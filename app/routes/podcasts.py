import os
from urllib.parse import quote
import feedparser
from fastapi import APIRouter, Request, Depends, HTTPException, Form, BackgroundTasks
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from sqlalchemy.orm import Session
from ..database import get_db
from ..models import Podcast, PlayHistory, AppSetting
from ..core.auth import require_auth
from ..core.logger import log_system_event
from ..services.abs_client import abs_client
from ..services.feed_parser import fetch_feed_episodes, clear_proxy_cache
from ..services.podcastindex import is_podcastindex_configured, get_podcast_by_feed_url, get_episodes_by_feed_id
from ..services.sync_service import handle_episode_listened, handle_episode_unplayed

router = APIRouter(tags=["podcasts"], dependencies=[Depends(require_auth)])

def flash_redirect(url: str, message: str, level: str = "success") -> RedirectResponse:
    separator = "&" if "?" in url else "?"
    return RedirectResponse(
        url=f"{url}{separator}_toast={quote(message)}&_toast_level={level}",
        status_code=303
    )

@router.get("/", response_class=HTMLResponse)
def index_page(request: Request, db: Session = Depends(get_db)):
    from ..main import templates
    active_podcasts = db.query(Podcast).filter(Podcast.subscribed == True).order_by(Podcast.title.asc()).all()
    archived_podcasts = db.query(Podcast).filter(Podcast.subscribed == False).order_by(Podcast.title.asc()).all()

    # Precalculate listen stats for active podcasts
    active_items = []
    for p in active_podcasts:
        listened_count = len(p.history)
        active_items.append({
            "podcast": p,
            "listened_count": listened_count,
        })

    archived_items = []
    for p in archived_podcasts:
        archived_items.append({
            "podcast": p,
            "listened_count": len(p.history),
        })

    return templates.TemplateResponse(request=request, name="index.html", context={
        "request": request,
        "active_podcasts": active_items,
        "archived_podcasts": archived_items,
    })

@router.get("/podcast/{podcast_id}", response_class=HTMLResponse)
def podcast_detail(request: Request, podcast_id: int, db: Session = Depends(get_db)):
    from ..main import templates
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    history_records = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast_id).order_by(PlayHistory.played_at.desc()).all()

    return templates.TemplateResponse(request=request, name="podcast_detail.html", context={
        "request": request,
        "podcast": podcast,
        "played_count": len(history_records),
        "history_records": history_records,
    })

@router.get("/podcast/{podcast_id}/episodes", response_class=JSONResponse)
def podcast_episodes(request: Request, podcast_id: int, db: Session = Depends(get_db)):
    from ..main import templates
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    history_records = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast_id).all()
    played_map = {str(h.episode_guid).strip(): h for h in history_records if h.episode_guid}
    played_titles = {str(h.episode_title).strip().lower(): h for h in history_records if h.episode_title}

    feed_episodes, artwork_url = fetch_feed_episodes(podcast.feed_url)
    if artwork_url and not podcast.artwork_url:
        podcast.artwork_url = artwork_url
        db.commit()

    episodes = []
    start_after_found = False
    for ep in feed_episodes:
        guid = ep["guid"]
        title = ep["title"]
        # Match played state either by GUID or Title
        play_record = played_map.get(guid) or played_titles.get(title.strip().lower())
        is_start_after = bool(podcast.sync_start_after_guid and guid == podcast.sync_start_after_guid)
        if is_start_after:
            start_after_found = True

        episodes.append({
            "guid": guid,
            "title": title,
            "description": ep.get("description", ""),
            "pub_date": ep["pub_date"],
            "played": play_record is not None,
            "played_at": play_record.played_at if play_record else None,
            "is_start_after": is_start_after,
        })

    # Determine which episodes are currently exposed in the proxy feed
    unplayed_eps = [ep for ep in episodes if not ep["played"]]
    if podcast.sync_start_after_guid:
        start_idx = None
        for i, ep in enumerate(unplayed_eps):
            if ep["guid"] == podcast.sync_start_after_guid:
                start_idx = i
                break
        if start_idx is not None:
            unplayed_eps = unplayed_eps[:start_idx]

    synced_eps = []
    if podcast.sync_order == "oldest_first":
        if podcast.sync_limit and len(unplayed_eps) > podcast.sync_limit:
            synced_eps = unplayed_eps[-podcast.sync_limit:]
        else:
            synced_eps = unplayed_eps
    else:
        if podcast.sync_limit and len(unplayed_eps) > podcast.sync_limit:
            synced_eps = unplayed_eps[:podcast.sync_limit]
        else:
            synced_eps = unplayed_eps

    synced_guids = {ep["guid"] for ep in synced_eps}
    for ep in episodes:
        ep["is_synced"] = ep["guid"] in synced_guids

    html_content = templates.get_template("podcast_episodes.html").render({
        "request": request,
        "podcast": podcast,
        "episodes": episodes,
        "played_count": len(history_records),
        "total_count": len(episodes),
    })

    return {
        "html": html_content,
        "played_count": len(history_records),
        "total_count": len(episodes)
    }

@router.post("/podcast/{podcast_id}/episode/{guid}/toggle-played", response_class=JSONResponse)
def toggle_episode_played(
    podcast_id: int,
    guid: str,
    background_tasks: BackgroundTasks,
    title: str = Form(None),
    db: Session = Depends(get_db)
):
    """1-Click toggle to mark an episode listened or unplayed directly from Polarr UI."""
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    clean_guid = str(guid).strip()
    existing = db.query(PlayHistory).filter(
        PlayHistory.podcast_id == podcast_id,
        PlayHistory.episode_guid == clean_guid
    ).first()

    if existing:
        # Mark unplayed
        handle_episode_unplayed(podcast, clean_guid, db=db)
        return {"status": "ok", "played": False, "message": "Marked as unplayed"}
    else:
        # Mark listened and trigger auto-download pipeline in background
        background_tasks.add_task(
            handle_episode_listened,
            podcast=podcast,
            episode_guid=clean_guid,
            episode_title=title
        )
        return {"status": "ok", "played": True, "message": "Marked as listened & sync triggered"}

@router.post("/podcast/{podcast_id}/settings")
def save_podcast_settings(
    podcast_id: int,
    sync_order: str = Form("oldest_first"),
    sync_limit: int = Form(5),
    sync_start_after_guid: str = Form(None),
    db: Session = Depends(get_db)
):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    podcast.sync_order = sync_order
    podcast.sync_limit = max(1, min(sync_limit, 999))
    podcast.sync_start_after_guid = sync_start_after_guid.strip() if sync_start_after_guid else None
    db.commit()
    clear_proxy_cache(podcast.id)

    log_system_event("INFO", "Sync", f"Updated sync settings for '{podcast.title}' (order={sync_order}, limit={sync_limit})")
    return flash_redirect(f"/podcast/{podcast_id}", "Sync settings updated.")

@router.post("/podcast/{podcast_id}/set-start-after", response_class=JSONResponse)
def set_start_after(
    podcast_id: int,
    episode_guid: str = Form(""),
    db: Session = Depends(get_db)
):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    podcast.sync_start_after_guid = episode_guid.strip() if episode_guid else None
    db.commit()
    clear_proxy_cache(podcast.id)
    return {"status": "ok", "start_after": podcast.sync_start_after_guid}

@router.post("/podcast/{podcast_id}/toggle")
def toggle_podcast(podcast_id: int, source: str = None, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    was_subscribed = podcast.subscribed
    podcast.subscribed = not was_subscribed
    redirect_target = "/" if source == "index" else f"/podcast/{podcast_id}"

    if was_subscribed:
        # Unsubscribe: remove from ABS
        if podcast.abs_id:
            abs_client.delete_podcast(podcast.abs_id)
            podcast.abs_id = None
        db.commit()
        clear_proxy_cache(podcast.id)
        log_system_event("INFO", "Sync", f"Unsubscribed '{podcast.title}' and removed from Audiobookshelf")
        return flash_redirect(redirect_target, f"Unsubscribed from '{podcast.title}'.")
    else:
        # Re-subscribe
        db.commit()
        clear_proxy_cache(podcast.id)
        log_system_event("INFO", "Sync", f"Re-subscribed to '{podcast.title}'")
        return flash_redirect(redirect_target, f"Re-subscribed to '{podcast.title}'.")

@router.post("/podcast/{podcast_id}/resync")
def resync_podcast(podcast_id: int, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    if podcast.abs_id:
        abs_client.reset_media_check(podcast.abs_id)
        abs_client.checknew_podcast(podcast.abs_id)

    clear_proxy_cache(podcast.id)
    log_system_event("INFO", "Sync", f"Force resync initiated for '{podcast.title}'")
    return flash_redirect(f"/podcast/{podcast_id}", f"Resync triggered for '{podcast.title}'.")

@router.post("/podcast/{podcast_id}/automatch")
def automatch_podcast(podcast_id: int, provider: str = "podcastindex", db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    if provider == "rss":
        d = feedparser.parse(podcast.feed_url)
        if hasattr(d, "feed") and "title" in d.feed:
            podcast.title = d.feed.title
            if "image" in d.feed and "href" in d.feed.image:
                podcast.artwork_url = d.feed.image.href
            elif "itunes_image" in d.feed:
                podcast.artwork_url = d.feed.itunes_image
            db.commit()
            log_system_event("INFO", "Discover", f"Automatch updated title for '{podcast.title}' via RSS")
            return flash_redirect(f"/podcast/{podcast_id}", f"Title updated from RSS: {podcast.title}")
        return flash_redirect(f"/podcast/{podcast_id}", "Could not read RSS feed.", "error")

    # PodcastIndex provider
    feed_data = get_podcast_by_feed_url(podcast.feed_url)
    if feed_data and feed_data.get("title"):
        podcast.title = feed_data["title"]
        if feed_data.get("artwork") or feed_data.get("image"):
            podcast.artwork_url = feed_data.get("artwork") or feed_data.get("image")
        db.commit()
        log_system_event("INFO", "Discover", f"Automatch updated '{podcast.title}' via PodcastIndex")
        return flash_redirect(f"/podcast/{podcast_id}", f"Updated from PodcastIndex: {podcast.title}")

    return flash_redirect(f"/podcast/{podcast_id}", "No match found on PodcastIndex.", "error")
