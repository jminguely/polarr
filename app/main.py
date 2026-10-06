import os
import hashlib
import time
import asyncio
import requests
import feedparser
from datetime import datetime
from urllib.parse import quote

from fastapi import FastAPI, Depends, Request, Form, BackgroundTasks, HTTPException, Response, Query
from lxml import etree

from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from sqlalchemy import desc, or_
from .database import engine, Base, get_db, SessionLocal
from .models import Podcast, PlayHistory, AppSetting, SyncLog

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Polarr")
templates = Jinja2Templates(directory="app/templates")
templates.env.cache = None

ABS_URL = os.getenv("ABS_URL", "http://totoro:13378/audiobookshelf").rstrip("/")
ABS_TOKEN = os.getenv("ABS_TOKEN", "")
ABS_LIBRARY_ID = os.getenv("ABS_LIBRARY_ID", "")
ABS_FOLDER_ID = os.getenv("ABS_FOLDER_ID", "") # We need this to create podcasts


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def flash_redirect(url: str, message: str, level: str = "success") -> RedirectResponse:
    """Redirect with a toast message encoded in the query string."""
    separator = "&" if "?" in url else "?"
    return RedirectResponse(
        url=f"{url}{separator}_toast={quote(message)}&_toast_level={level}",
        status_code=303
    )


def get_podcastindex_headers(api_key, api_secret):
    api_header_time = str(int(time.time()))
    data_to_hash = api_key + api_secret + api_header_time
    sha_1 = hashlib.sha1(data_to_hash.encode('utf-8')).hexdigest()
    return {
        "User-Agent": "Polarr/1.0",
        "X-Auth-Key": api_key,
        "X-Auth-Date": api_header_time,
        "Authorization": sha_1
    }


FEED_CACHE = {}
FEED_CACHE_TTL = 300  # 5 minutes

def fetch_feed_episodes(feed_url: str):
    """Fetch and parse all episodes from an RSS feed. Returns a list of dicts."""
    now = time.time()
    if feed_url in FEED_CACHE:
        cached_data, timestamp = FEED_CACHE[feed_url]
        if now - timestamp < FEED_CACHE_TTL:
            return cached_data

    try:
        r = requests.get(feed_url, headers={"User-Agent": "Polarr/1.0"}, timeout=10)
        r.raise_for_status()
        d = feedparser.parse(r.content)
        episodes = []
        for entry in d.entries:
            guid = entry.get("id") or entry.get("guid") or ""
            pub_date = None
            if hasattr(entry, "published_parsed") and entry.published_parsed:
                pub_date = datetime(*entry.published_parsed[:6])
            elif hasattr(entry, "updated_parsed") and entry.updated_parsed:
                pub_date = datetime(*entry.updated_parsed[:6])

            episodes.append({
                "guid": str(guid).strip(),
                "title": entry.get("title", "Untitled"),
                "description": entry.get("summary", ""),
                "pub_date": pub_date,
                "link": entry.get("link", ""),
            })
        FEED_CACHE[feed_url] = (episodes, now)
        return episodes
    except Exception as e:
        print(f"Error fetching feed: {e}")
        return []


def delete_episode_from_abs(abs_id: str, episode_id: str):
    """Deletes an episode from Audiobookshelf to free up space"""
    if not ABS_TOKEN:
        return
    url = f"{ABS_URL}/api/podcasts/{abs_id}/episode/{episode_id}"
    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    try:
        # hard=1 tells ABS to delete the actual file
        requests.delete(f"{url}?hard=1", headers=headers, timeout=10)
    except Exception as e:
        print(f"Failed to delete episode from ABS: {e}")


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
def index(request: Request, db: Session = Depends(get_db)):
    active_podcasts = db.query(Podcast).filter(Podcast.subscribed == True).order_by(Podcast.title).all()
    archived_podcasts = db.query(Podcast).filter(Podcast.subscribed == False).order_by(Podcast.title).all()
    return templates.TemplateResponse(request=request, name="index.html", context={
        "request": request,
        "active_podcasts": active_podcasts,
        "archived_podcasts": archived_podcasts,
    })


@app.get("/history", response_class=HTMLResponse)
def history(request: Request, db: Session = Depends(get_db)):
    # Get last 100 played episodes
    history_records = db.query(PlayHistory).order_by(desc(PlayHistory.played_at)).limit(100).all()
    return templates.TemplateResponse(request=request, name="history.html", context={
        "request": request,
        "history": history_records,
    })


@app.get("/podcast/{podcast_id}", response_class=HTMLResponse)
def podcast_detail(request: Request, podcast_id: int, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    # Get play history for this podcast
    history_records = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast_id).all()
    played_map = {}
    for h in history_records:
        played_map[str(h.episode_guid).strip()] = h

    return templates.TemplateResponse(request=request, name="podcast_detail.html", context={
        "request": request,
        "podcast": podcast,
        "played_count": len(history_records),
        "total_count": "?",
    })

@app.get("/podcast/{podcast_id}/episodes", response_class=JSONResponse)
def podcast_episodes(request: Request, podcast_id: int, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    # Get play history for this podcast
    history_records = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast_id).all()
    played_map = {}
    for h in history_records:
        played_map[str(h.episode_guid).strip()] = h

    # Fetch all episodes from the RSS feed
    feed_episodes = fetch_feed_episodes(podcast.feed_url)

    # Build enriched episode list
    episodes = []
    start_after_found = False
    for ep in feed_episodes:
        guid = ep["guid"]
        play_record = played_map.get(guid)
        is_start_after = (podcast.sync_start_after_guid and guid == podcast.sync_start_after_guid)
        if is_start_after:
            start_after_found = True

        episodes.append({
            "guid": guid,
            "title": ep["title"],
            "description": ep.get("description", ""),
            "pub_date": ep["pub_date"],
            "played": play_record is not None,
            "played_at": play_record.played_at if play_record else None,
            "is_start_after": is_start_after,
        })

    # --- Determine which episodes are currently synced to ABS ---
    unplayed_eps = [ep for ep in episodes if not ep["played"]]
    
    if podcast.sync_start_after_guid:
        start_idx = None
        for i, ep in enumerate(unplayed_eps):
            if ep["guid"] == podcast.sync_start_after_guid:
                start_idx = i
                break
        if start_idx is not None:
            # Newest-first: elements before start_idx are newer
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
    # -----------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Search API
# ---------------------------------------------------------------------------

@app.get("/api/search")
def search(q: str = Query("", min_length=1), db: Session = Depends(get_db)):
    """Live search endpoint returning matching podcasts and episodes as JSON."""
    term = f"%{q}%"

    podcasts = db.query(Podcast).filter(
        or_(
            Podcast.title.ilike(term),
            Podcast.feed_url.ilike(term),
        )
    ).limit(5).all()

    episodes = db.query(PlayHistory).filter(
        PlayHistory.episode_title.ilike(term)
    ).order_by(desc(PlayHistory.played_at)).limit(5).all()

    return JSONResponse({
        "podcasts": [
            {"id": p.id, "title": p.title, "subscribed": p.subscribed}
            for p in podcasts
        ],
        "episodes": [
            {
                "podcast_id": e.podcast_id,
                "podcast_title": e.podcast.title if e.podcast else "Unknown",
                "episode_title": e.episode_title,
                "played_at": e.played_at.strftime("%Y-%m-%d") if e.played_at else None,
            }
            for e in episodes
        ],
    })


# ---------------------------------------------------------------------------
# Subscription settings
# ---------------------------------------------------------------------------

@app.post("/podcast/{podcast_id}/settings")
def save_podcast_settings(
    request: Request,
    podcast_id: int,
    sync_order: str = Form("oldest_first"),
    sync_limit: int = Form(5),
    sync_start_after_guid: str = Form(""),
    db: Session = Depends(get_db),
):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    podcast.sync_order = sync_order
    podcast.sync_limit = max(1, min(sync_limit, 999))
    podcast.sync_start_after_guid = sync_start_after_guid if sync_start_after_guid else None
    db.commit()

    return flash_redirect(f"/podcast/{podcast_id}", "Sync settings saved successfully.")


@app.post("/podcast/{podcast_id}/set-start-after")
def set_start_after(
    podcast_id: int,
    episode_guid: str = Form(""),
    db: Session = Depends(get_db),
):
    """Set the start-after episode via an AJAX call from the episode table."""
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        return JSONResponse({"error": "Podcast not found"}, status_code=404)

    podcast.sync_start_after_guid = episode_guid if episode_guid else None
    db.commit()
    return JSONResponse({"status": "ok", "guid": episode_guid})


# ---------------------------------------------------------------------------
# Webhook
# ---------------------------------------------------------------------------

@app.post("/webhook/abs")
async def abs_webhook(request: Request, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """Receives webhooks from Audiobookshelf"""
    payload = await request.json()
    
    # We only care when an item is finished
    event_name = payload.get("event")
    if event_name not in ["item_finished", "progress_update"]:
        return {"status": "ignored"}
    
    # Check if it's finished
    is_finished = payload.get("progress", {}).get("isFinished", False)
    if event_name == "progress_update" and not is_finished:
        return {"status": "ignored"}

    library_item_id = payload.get("libraryItemId")
    episode_id = payload.get("episodeId")
    
    if not library_item_id or not episode_id:
        return {"status": "ignored", "reason": "missing_ids"}
        
    podcast = db.query(Podcast).filter(Podcast.abs_id == library_item_id).first()
    if not podcast:
        return {"status": "ignored", "reason": "podcast_not_found_in_polarr"}
        
    # Get episode info from ABS to save title/guid
    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    try:
        res = await asyncio.to_thread(requests.get, f"{ABS_URL}/api/podcasts/{library_item_id}/episode/{episode_id}", headers=headers, timeout=10)
        res.raise_for_status()
        ep_data = res.json()
        guid = ep_data.get("guid", episode_id)
        title = ep_data.get("title", "Unknown Episode")
    except Exception:
        guid = episode_id
        title = f"Episode {episode_id}"

    # Log to history
    existing = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id, PlayHistory.episode_guid == guid).first()
    if not existing:
        new_history = PlayHistory(podcast_id=podcast.id, episode_guid=guid, episode_title=title)
        db.add(new_history)
        db.commit()
    
    # Tell ABS to delete the file to free up space!
    background_tasks.add_task(delete_episode_from_abs, library_item_id, episode_id)
    
    return {"status": "success", "action": "logged_and_deletion_queued"}


# ---------------------------------------------------------------------------
# Automatch (metadata enrichment)
# ---------------------------------------------------------------------------

@app.post("/podcast/{podcast_id}/automatch")
def automatch_podcast(request: Request, podcast_id: int, provider: str = "podcastindex", db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        return flash_redirect(f"/podcast/{podcast_id}", "Podcast not found.", "error")

    if provider == "rss":
        try:
            d = feedparser.parse(podcast.feed_url)
            if hasattr(d, "feed") and "title" in d.feed:
                podcast.title = d.feed.title
                
                history = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
                for h in history:
                    for entry in d.entries:
                        guid = entry.get("id") or entry.get("guid") or ""
                        if h.episode_guid == guid:
                            h.episode_title = entry.get("title", h.episode_title)
                            break
                db.commit()
                return flash_redirect(f"/podcast/{podcast_id}", f"Title updated from RSS: {podcast.title}")
            return flash_redirect(f"/podcast/{podcast_id}", "Could not read the RSS feed. The link may be dead.", "error")
        except Exception as e:
            return flash_redirect(f"/podcast/{podcast_id}", f"RSS error: {e}", "error")
            
    # PodcastIndex provider
    api_key = os.getenv("PODCASTINDEX_API_KEY")
    api_secret = os.getenv("PODCASTINDEX_API_SECRET")
    
    if not api_key or not api_secret:
        return flash_redirect(f"/podcast/{podcast_id}", "Please add PODCASTINDEX_API_KEY and SECRET to your .env file.", "error")
        
    url = f"https://api.podcastindex.org/api/1.0/podcasts/byfeedurl?url={podcast.feed_url}"
    headers = get_podcastindex_headers(api_key, api_secret)
    
    try:
        res = requests.get(url, headers=headers, timeout=10)
        data = res.json()
        if data.get("feed") and data["feed"].get("title"):
            new_title = data["feed"]["title"]
            podcast.title = new_title
            
            feed_id = data["feed"].get("id")
            if feed_id:
                ep_url = f"https://api.podcastindex.org/api/1.0/episodes/byfeedid?id={feed_id}&max=1000"
                try:
                    ep_res = requests.get(ep_url, headers=headers, timeout=10)
                    if ep_res.ok:
                        ep_data = ep_res.json()
                        items = ep_data.get("items", [])
                        
                        ep_map = {}
                        for item in items:
                            if item.get("guid"):
                                ep_map[str(item["guid"]).strip()] = item.get("title")
                            if item.get("link"):
                                ep_map[str(item["link"]).strip()] = item.get("title")
                        
                        histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
                        for h in histories:
                            guid = str(h.episode_guid).strip()
                            if guid in ep_map and h.episode_title.startswith("Episode "):
                                h.episode_title = ep_map[guid]
                except Exception:
                    pass
                    
            db.commit()
            return flash_redirect(f"/podcast/{podcast_id}", f"Title updated from PodcastIndex: {new_title}")
    except Exception:
        pass
        
    return flash_redirect(f"/podcast/{podcast_id}", "No match found on PodcastIndex for this URL.", "error")


# ---------------------------------------------------------------------------
# Proxy RSS Feed
# ---------------------------------------------------------------------------

@app.get("/feed/{podcast_id}")
def proxy_rss_feed(podcast_id: int, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        return Response("Podcast not found", status_code=404)
        
    try:
        r = requests.get(podcast.feed_url, headers={"User-Agent": "Polarr/1.0"}, timeout=15)
        r.raise_for_status()
        
        parser = etree.XMLParser(strip_cdata=False, recover=True)
        root = etree.fromstring(r.content, parser)
        
        histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
        played_guids = {str(h.episode_guid).strip() for h in histories if h.episode_guid}
        
        # Collect all items with their GUIDs for filtering
        items_with_info = []
        for item in root.xpath('//item'):
            guid_elem = item.find('guid')
            link_elem = item.find('link')
            guid_text = guid_elem.text.strip() if guid_elem is not None and guid_elem.text else None
            link_text = link_elem.text.strip() if link_elem is not None and link_elem.text else None
            
            is_played = (guid_text in played_guids) if guid_text else ((link_text in played_guids) if link_text else False)
            items_with_info.append({
                "element": item,
                "guid": guid_text or link_text or "",
                "is_played": is_played,
            })

        # Apply sync settings
        # 1. Remove played episodes
        removed = 0
        for info in items_with_info:
            if info["is_played"]:
                info["element"].getparent().remove(info["element"])
                removed += 1

        # Re-collect remaining items after removing played ones
        remaining_items = list(root.xpath('//item'))

        # 2. Apply start-after filter: remove all episodes published before the start-after episode
        if podcast.sync_start_after_guid and remaining_items:
            start_idx = None
            for i, item in enumerate(remaining_items):
                guid_elem = item.find('guid')
                link_elem = item.find('link')
                guid_text = guid_elem.text.strip() if guid_elem is not None and guid_elem.text else ""
                link_text = link_elem.text.strip() if link_elem is not None and link_elem.text else ""
                if guid_text == podcast.sync_start_after_guid or link_text == podcast.sync_start_after_guid:
                    start_idx = i
                    break

            if start_idx is not None:
                # RSS items are typically newest-first. The start-after episode and everything
                # after it (older) should be removed.
                for item in remaining_items[start_idx:]:
                    item.getparent().remove(item)
                remaining_items = remaining_items[:start_idx]

        # 3. Apply order and limit
        if podcast.sync_order == "oldest_first":
            # RSS is newest-first by default. To get oldest first, we keep the LAST N items
            if podcast.sync_limit and len(remaining_items) > podcast.sync_limit:
                for item in remaining_items[:-podcast.sync_limit]:
                    item.getparent().remove(item)
        else:
            # newest_first: keep the FIRST N items
            if podcast.sync_limit and len(remaining_items) > podcast.sync_limit:
                for item in remaining_items[podcast.sync_limit:]:
                    item.getparent().remove(item)

        # 4. Replace self-referencing feed URLs so ABS stores our proxy URL
        POLARR_EXTERNAL_URL = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
        proxy_url = f"{POLARR_EXTERNAL_URL}/feed/{podcast.id}"
        ns = {
            "atom": "http://www.w3.org/2005/Atom",
            "itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd",
        }
        for atom_link in root.xpath('//channel/atom:link[@rel="self"]', namespaces=ns):
            atom_link.set("href", proxy_url)
        for new_feed in root.xpath('//channel/itunes:new-feed-url', namespaces=ns):
            new_feed.getparent().remove(new_feed)
                        
        print(f"Proxy Feed {podcast_id}: {removed} played episodes hidden, sync_order={podcast.sync_order}, sync_limit={podcast.sync_limit}")
        return Response(content=etree.tostring(root, encoding='utf-8', xml_declaration=True), media_type="application/rss+xml")
    except Exception as e:
        print(f"Error proxy_rss_feed: {e}")
        return Response("Error fetching the feed", status_code=502)


# ---------------------------------------------------------------------------
# Subscribe / Unsubscribe toggle
# ---------------------------------------------------------------------------

@app.post("/podcast/{podcast_id}/toggle")
def toggle_podcast(request: Request, podcast_id: int, source: str = None, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")
        
    ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
    ABS_TOKEN = os.getenv("ABS_TOKEN", "")
    ABS_LIBRARY_ID = os.getenv("ABS_LIBRARY_ID", "")
    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    
    if podcast.subscribed:
        if podcast.abs_id:
            try:
                requests.delete(f"{ABS_URL}/api/items/{podcast.abs_id}?hard=1", headers=headers, timeout=10)
            except:
                pass
        podcast.subscribed = False
        podcast.abs_id = None
        db.commit()
        redirect_url = "/" if source == "index" else f"/podcast/{podcast_id}"
        return flash_redirect(redirect_url, f"{podcast.title} unsubscribed and removed from ABS.")
    else:
        try:
            res = requests.get(f"{ABS_URL}/api/libraries/{ABS_LIBRARY_ID}", headers=headers, timeout=10)
            if res.ok:
                folders = res.json().get("folders", [])
                if folders:
                    folder_id = folders[0]["id"]
                    folder_path = folders[0].get("fullPath") or folders[0].get("path") or ""
                    safe_title = "".join(c for c in podcast.title if c.isalnum() or c in (' ', '-', '_')).strip()
                    
                    POLARR_EXTERNAL_URL = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
                    proxy_url = f"{POLARR_EXTERNAL_URL}/feed/{podcast.id}"
                    
                    feed_res = requests.post(f"{ABS_URL}/api/podcasts/feed", json={"rssFeed": proxy_url}, headers=headers, timeout=10)
                    if feed_res.ok:
                        podcast_media = feed_res.json().get("podcast")
                        if podcast_media:
                            # Override feedUrl so ABS uses the proxy feed for checknew
                            if "metadata" in podcast_media:
                                podcast_media["metadata"]["feedUrl"] = proxy_url
                            payload = {
                                "path": os.path.join(folder_path, safe_title),
                                "folderId": folder_id,
                                "libraryId": ABS_LIBRARY_ID,
                                "media": podcast_media,
                                "autoDownloadEpisodes": True
                            }
                            r = requests.post(f"{ABS_URL}/api/podcasts", json=payload, headers=headers, timeout=10)
                            if r.ok:
                                podcast.abs_id = r.json().get("id")
                                
                                # Mark history as finished in ABS
                                histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
                                played_guids = {str(h.episode_guid).strip() for h in histories if h.episode_guid}
                                if "episodes" in podcast_media:
                                    for ep in podcast_media["episodes"]:
                                        if str(ep.get("id")) in played_guids or str(ep.get("enclosureUrl")) in played_guids:
                                            requests.patch(f"{ABS_URL}/api/me/progress/{podcast.abs_id}", json={"isFinished": True, "progress": 1, "episodeId": ep.get("id"), "hideFromContinueListening": True}, headers=headers)

                                # Force scan of all old episodes
                                requests.patch(f"{ABS_URL}/api/items/{podcast.abs_id}/media", json={"lastEpisodeCheck": 0}, headers=headers, timeout=10)
                                requests.get(f"{ABS_URL}/api/podcasts/{podcast.abs_id}/checknew?limit=9999", headers=headers, timeout=10)

        except Exception as e:
            print("Error:", e)
        podcast.subscribed = True
        db.commit()
        redirect_url = "/" if source == "index" else f"/podcast/{podcast_id}"
        return flash_redirect(redirect_url, f"{podcast.title} subscribed and synced to ABS.")


@app.post("/podcast/{podcast_id}/resync")
def resync_podcast(request: Request, podcast_id: int, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast or not podcast.subscribed or not podcast.abs_id:
        raise HTTPException(status_code=404, detail="Podcast not found or not synced to ABS")
        
    ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
    ABS_TOKEN = os.getenv("ABS_TOKEN", "")
    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    
    POLARR_EXTERNAL_URL = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
    proxy_url = f"{POLARR_EXTERNAL_URL}/feed/{podcast.id}"
    
    try:
        # 1. Fetch what the proxy feed says SHOULD be there
        valid_enclosures = set()
        feed_res = requests.post(f"{ABS_URL}/api/podcasts/feed", json={"rssFeed": proxy_url}, headers=headers, timeout=10)
        if feed_res.ok:
            podcast_media = feed_res.json().get("podcast")
            if podcast_media and "episodes" in podcast_media:
                for ep in podcast_media["episodes"]:
                    valid_enclosures.add(ep.get("enclosureUrl"))
        else:
            return flash_redirect(f"/podcast/{podcast_id}", "Failed to fetch proxy feed during resync.", "error")
            
        # 2. Fetch what is CURRENTLY in ABS
        res = requests.get(f"{ABS_URL}/api/items/{podcast.abs_id}", headers=headers, timeout=10)
        if res.ok:
            abs_item = res.json()
            abs_episodes = abs_item.get("media", {}).get("episodes", [])
            
            # 3. Delete episodes from ABS that shouldn't be there
            deleted_count = 0
            for ep in abs_episodes:
                if ep.get("enclosureUrl") not in valid_enclosures:
                    requests.delete(f"{ABS_URL}/api/podcasts/{podcast.abs_id}/episode/{ep.get('id')}?hard=1", headers=headers, timeout=10)
                    deleted_count += 1
            
            # 4. Update feed URL in ABS to proxy URL and trigger scan for new episodes
            requests.patch(f"{ABS_URL}/api/items/{podcast.abs_id}/media", json={"metadata": {"feedUrl": proxy_url}}, headers=headers, timeout=10)
            requests.patch(f"{ABS_URL}/api/items/{podcast.abs_id}/media", json={"lastEpisodeCheck": 0}, headers=headers, timeout=10)
            requests.get(f"{ABS_URL}/api/podcasts/{podcast.abs_id}/checknew?limit=9999", headers=headers, timeout=10)
            
            return flash_redirect(f"/podcast/{podcast_id}", f"Resync successful! {deleted_count} old episodes removed. ABS is scanning for new episodes.")
        else:
            # If ABS returns 404, the podcast was deleted manually in ABS
            if res.status_code == 404:
                podcast.abs_id = None
                podcast.subscribed = False
                db.commit()
                return flash_redirect(f"/podcast/{podcast_id}", "Podcast was not found in Audiobookshelf. It has been unsubscribed in Polarr.", "error")
            return flash_redirect(f"/podcast/{podcast_id}", "Failed to fetch podcast from ABS.", "error")
            
    except Exception as e:
        print("Error during resync:", e)
        return flash_redirect(f"/podcast/{podcast_id}", f"Error during resync: {e}", "error")

# ---------------------------------------------------------------------------
# Discover Podcasts
# ---------------------------------------------------------------------------
from urllib.parse import quote

@app.get("/discover", response_class=HTMLResponse)
def discover_page(request: Request, q: str = ""):
    results = []
    if q:
        PODCASTINDEX_API_KEY = os.getenv("PODCASTINDEX_API_KEY", "")
        PODCASTINDEX_API_SECRET = os.getenv("PODCASTINDEX_API_SECRET", "")
        if PODCASTINDEX_API_KEY and PODCASTINDEX_API_SECRET:
            import time
            import hashlib
            api_header_time = str(int(time.time()))
            data_to_hash = PODCASTINDEX_API_KEY + PODCASTINDEX_API_SECRET + api_header_time
            sha_1 = hashlib.sha1(data_to_hash.encode()).hexdigest()
            headers = {
                "X-Auth-Date": api_header_time,
                "X-Auth-Key": PODCASTINDEX_API_KEY,
                "Authorization": sha_1,
                "User-Agent": "Polarr/1.0"
            }
            url = f"https://api.podcastindex.org/api/1.0/search/byterm?q={quote(q)}"
            try:
                res = requests.get(url, headers=headers, timeout=10)
                if res.ok:
                    data = res.json()
                    results = data.get("feeds", [])
            except Exception as e:
                print("Discover error:", e)
    
    return templates.TemplateResponse(request=request, name="discover.html", context={
        "request": request,
        "query": q,
        "results": results
    })

@app.post("/discover/add")
def discover_add(request: Request, title: str = Form(...), feed_url: str = Form(...), db: Session = Depends(get_db)):
    existing = db.query(Podcast).filter(Podcast.feed_url == feed_url).first()
    if existing:
        return flash_redirect(f"/podcast/{existing.id}", "Podcast already exists in your library.")
        
    sync_order_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_order").first()
    sync_limit_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_limit").first()
    
    default_sync_order = sync_order_setting.value if sync_order_setting else "oldest_first"
    default_sync_limit = int(sync_limit_setting.value) if sync_limit_setting else 5

    pod = Podcast(
        title=title,
        feed_url=feed_url,
        subscribed=False,
        sync_order=default_sync_order,
        sync_limit=default_sync_limit
    )
    db.add(pod)
    db.commit()
    db.refresh(pod)
    return flash_redirect(f"/podcast/{pod.id}", f"'{title}' added. You can now configure it and subscribe.")

# ---------------------------------------------------------------------------
# Settings & Global Sync
# ---------------------------------------------------------------------------

@app.get("/settings", response_class=HTMLResponse)
def settings_page(request: Request, db: Session = Depends(get_db)):
    # Get settings or defaults
    sync_order_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_order").first()
    sync_limit_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_limit").first()
    check_interval_setting = db.query(AppSetting).filter(AppSetting.key == "episode_check_interval").first()
    
    default_sync_order = sync_order_setting.value if sync_order_setting else "oldest_first"
    default_sync_limit = int(sync_limit_setting.value) if sync_limit_setting else 5
    episode_check_interval = int(check_interval_setting.value) if check_interval_setting else 60

    # Get recent sync logs
    logs = db.query(SyncLog).order_by(desc(SyncLog.started_at)).limit(10).all()

    return templates.TemplateResponse(request=request, name="settings.html", context={
        "request": request,
        "default_sync_order": default_sync_order,
        "default_sync_limit": default_sync_limit,
        "episode_check_interval": episode_check_interval,
        "logs": logs
    })

@app.post("/settings")
def save_settings(
    request: Request,
    default_sync_order: str = Form("oldest_first"),
    default_sync_limit: int = Form(5),
    episode_check_interval: int = Form(60),
    db: Session = Depends(get_db)
):
    # Clamp interval between 30 and 1440 minutes (24h)
    episode_check_interval = max(30, min(episode_check_interval, 1440))
    for key, value in [
        ("default_sync_order", default_sync_order),
        ("default_sync_limit", str(default_sync_limit)),
        ("episode_check_interval", str(episode_check_interval)),
    ]:
        setting = db.query(AppSetting).filter(AppSetting.key == key).first()
        if setting:
            setting.value = value
        else:
            db.add(AppSetting(key=key, value=value))
    
    db.commit()
    return flash_redirect("/settings", "Global settings saved successfully.")

def perform_full_sync(log_id: int):
    """Background task to sync all active podcasts to ABS"""
    db = SessionLocal()
    log_entry = db.query(SyncLog).filter(SyncLog.id == log_id).first()
    
    ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
    ABS_TOKEN = os.getenv("ABS_TOKEN", "")
    ABS_LIBRARY_ID = os.getenv("ABS_LIBRARY_ID", "")
    
    if not ABS_URL or not ABS_TOKEN or not ABS_LIBRARY_ID:
        log_entry.status = "error"
        log_entry.details = "Missing ABS configuration in .env"
        log_entry.finished_at = datetime.utcnow()
        db.commit()
        db.close()
        return

    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    details = []
    
    try:
        # 1. Clear out ABS library
        details.append(f"Clearing all podcasts in ABS library {ABS_LIBRARY_ID}...")
        res = requests.get(f"{ABS_URL}/api/libraries/{ABS_LIBRARY_ID}/items?limit=1000", headers=headers, timeout=10)
        if res.ok:
            items = res.json().get("results", [])
            for item in items:
                if item.get("mediaType") == "podcast":
                    item_id = item.get("id")
                    requests.delete(f"{ABS_URL}/api/podcasts/{item_id}?hard=1", headers=headers, timeout=10)
                    requests.delete(f"{ABS_URL}/api/library/items/{item_id}?hard=1", headers=headers, timeout=10)
            details.append("Old podcasts cleared.")
        else:
            raise Exception("Could not connect to ABS or library ID is incorrect.")

        requests.post(f"{ABS_URL}/api/libraries/{ABS_LIBRARY_ID}/scan", headers=headers, timeout=10)
        time.sleep(2)

        # 2. Get folder info
        res = requests.get(f"{ABS_URL}/api/libraries/{ABS_LIBRARY_ID}", headers=headers, timeout=10)
        folders = res.json().get("folders", [])
        if not folders:
            raise Exception("No folders found in the ABS library.")

        folder_id = folders[0]["id"]
        folder_path = folders[0].get("fullPath") or folders[0].get("path") or ""

        # 3. Iterate through subscribed podcasts
        active_podcasts = db.query(Podcast).filter(Podcast.subscribed == True).all()
        details.append(f"Syncing {len(active_podcasts)} active subscriptions...")
        
        success_count = 0
        for pod in active_podcasts:
            safe_title = "".join(c for c in pod.title if c.isalnum() or c in (' ', '-', '_')).strip()
            
            POLARR_EXTERNAL_URL = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
            proxy_url = f"{POLARR_EXTERNAL_URL}/feed/{pod.id}"
            
            # Self-check: Can Polarr reach its own proxy URL?
            try:
                self_test = requests.get(proxy_url, timeout=10)
                if not self_test.ok:
                    details.append(f"❌ Self-test failed for {pod.title}: Polarr returned HTTP {self_test.status_code}")
                    log_entry.details = "\n".join(details)
                    db.commit()
                    continue
            except Exception as e:
                details.append(f"❌ Self-test failed for {pod.title}: Could not connect to {proxy_url} ({e})")
                log_entry.details = "\n".join(details)
                db.commit()
                continue
            
            feed_res = requests.post(f"{ABS_URL}/api/podcasts/feed", json={"rssFeed": proxy_url}, headers=headers, timeout=10)
            
            if feed_res.ok:
                podcast_media = feed_res.json().get("podcast")
                if podcast_media:
                    payload = {
                        "path": os.path.join(folder_path, safe_title),
                        "folderId": folder_id,
                        "libraryId": ABS_LIBRARY_ID,
                        "media": podcast_media,
                        "autoDownloadEpisodes": True
                    }
                    
                    r = requests.post(f"{ABS_URL}/api/podcasts", json=payload, headers=headers, timeout=10)
                    if r.ok:
                        pod.abs_id = r.json().get("id")
                        
                        histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == pod.id).all()
                        played_guids = {str(h.episode_guid).strip() for h in histories if h.episode_guid}
                        
                        if "episodes" in podcast_media:
                            for ep in podcast_media["episodes"]:
                                if str(ep.get("id")) in played_guids or str(ep.get("enclosureUrl")) in played_guids:
                                    requests.patch(
                                        f"{ABS_URL}/api/me/progress/{pod.abs_id}", 
                                        json={"isFinished": True, "progress": 1, "episodeId": ep.get("id"), "hideFromContinueListening": True}, 
                                        headers=headers
                                    )
                        
                        requests.patch(f"{ABS_URL}/api/items/{pod.abs_id}/media", json={"lastEpisodeCheck": 0}, headers=headers, timeout=10)
                        requests.get(f"{ABS_URL}/api/podcasts/{pod.abs_id}/checknew?limit=9999", headers=headers, timeout=10)
                        db.commit()
                        details.append(f"✅ {pod.title} synced.")
                        success_count += 1
                    else:
                        details.append(f"❌ Failed to create {pod.title} in ABS (HTTP {r.status_code}: {r.text}).")
            else:
                details.append(f"❌ Failed to parse feed for {pod.title} (HTTP {feed_res.status_code}: {feed_res.text}).")
            
            # Update log periodically
            log_entry.details = "\n".join(details)
            db.commit()
            time.sleep(1)

        details.append(f"\nSync complete. {success_count}/{len(active_podcasts)} podcasts synced successfully.")
        log_entry.status = "success"
        
    except Exception as e:
        log_entry.status = "error"
        details.append(f"\n❌ Error: {str(e)}")
        
    log_entry.details = "\n".join(details)
    log_entry.finished_at = datetime.utcnow()
    db.commit()
    db.close()


@app.post("/settings/sync-all")
def trigger_full_sync(background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    # Check if a sync is already running
    running_sync = db.query(SyncLog).filter(SyncLog.status == "running").first()
    if running_sync:
        return flash_redirect("/settings", "A synchronization is already in progress.", "info")

    new_log = SyncLog(status="running", details="Starting background sync...")
    db.add(new_log)
    db.commit()
    db.refresh(new_log)
    
    background_tasks.add_task(perform_full_sync, new_log.id)
    
    return flash_redirect("/settings", "Full synchronization started in the background.")

@app.post("/settings/check-new")
def trigger_check_new(background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """Trigger an immediate check for new episodes across all subscribed podcasts."""
    ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
    ABS_TOKEN = os.getenv("ABS_TOKEN", "")
    POLARR_EXTERNAL_URL = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
    if not ABS_URL or not ABS_TOKEN:
        return flash_redirect("/settings", "ABS is not configured.", "error")

    def do_check():
        headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
        sess = SessionLocal()
        podcasts = sess.query(Podcast).filter(Podcast.subscribed == True, Podcast.abs_id != None).all()
        checked = 0
        for pod in podcasts:
            try:
                proxy_url = f"{POLARR_EXTERNAL_URL}/feed/{pod.id}"
                # Update feed URL to proxy
                requests.patch(
                    f"{ABS_URL}/api/items/{pod.abs_id}/media",
                    json={"metadata": {"feedUrl": proxy_url}},
                    headers=headers, timeout=30
                )
                # Reset lastEpisodeCheck to force ABS to scan immediately
                requests.patch(
                    f"{ABS_URL}/api/items/{pod.abs_id}/media",
                    json={"lastEpisodeCheck": 0},
                    headers=headers, timeout=30
                )
                # Fire-and-forget: trigger checknew without waiting for download
                try:
                    requests.get(
                        f"{ABS_URL}/api/podcasts/{pod.abs_id}/checknew?limit=9999",
                        headers=headers, timeout=60
                    )
                except requests.exceptions.ReadTimeout:
                    pass  # ABS is downloading episodes, that's fine
                checked += 1
                time.sleep(3)  # Space out requests to avoid overloading ABS
            except Exception as e:
                print(f"⚠️ check-new error for {pod.title}: {e}")
        sess.close()
        print(f"🔄 Manual episode check complete: {checked}/{len(podcasts)} podcasts checked")

    background_tasks.add_task(do_check)
    count = db.query(Podcast).filter(Podcast.subscribed == True, Podcast.abs_id != None).count()
    return flash_redirect("/settings", f"Checking new episodes for {count} podcasts in the background...")


# ---------------------------------------------------------------------------
# Background sync
# ---------------------------------------------------------------------------

async def sync_abs_progress():
    # Wait for ABS to start up before beginning the loop
    await asyncio.sleep(30)
    while True:
        try:
            ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
            ABS_TOKEN = os.getenv("ABS_TOKEN", "")
            if not ABS_URL or not ABS_TOKEN:
                await asyncio.sleep(300)
                continue
                
            headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
            db = SessionLocal()
            
            # Fetch user progress
            res = await asyncio.to_thread(requests.get, f"{ABS_URL}/api/me", headers=headers, timeout=10)
            if res.ok:
                data = res.json()
                media_progress = data.get("mediaProgress", [])
                
                for mp in media_progress:
                    # If the user has finished the episode (or listened >95%)
                    if mp.get("isFinished") or mp.get("progress", 0) > 0.95:
                        lib_item_id = mp.get("libraryItemId")
                        ep_id = mp.get("episodeId")
                        
                        pod = db.query(Podcast).filter(Podcast.abs_id == lib_item_id).first()
                        if pod and ep_id:
                            # Check if already archived
                            exists = db.query(PlayHistory).filter(PlayHistory.podcast_id == pod.id, PlayHistory.episode_guid == ep_id).first()
                            
                            if not exists:
                                # We need the episode title
                                ep_title = f"Episode {ep_id}"
                                item_res = await asyncio.to_thread(requests.get, f"{ABS_URL}/api/library/items/{lib_item_id}", headers=headers, timeout=10)
                                if item_res.ok:
                                    item_data = item_res.json()
                                    episodes = item_data.get("media", {}).get("episodes", [])
                                    for e in episodes:
                                        if e.get("id") == ep_id:
                                            ep_title = e.get("title", ep_title)
                                            break
                                            
                                # Add to history
                                ph = PlayHistory(
                                    podcast_id=pod.id,
                                    episode_guid=ep_id,
                                    episode_title=ep_title,
                                    played_at=datetime.utcnow()
                                )
                                db.add(ph)
                                db.commit()
                                print(f"🎧 NEW LISTEN ARCHIVED: {ep_title}")
                                
                                # Delete the file from ABS to save space
                                try:
                                    await asyncio.to_thread(requests.delete, f"{ABS_URL}/api/podcasts/{lib_item_id}/episode/{ep_id}?hard=1", headers=headers, timeout=10)
                                    print(f"🗑️ File deleted from ABS.")
                                except:
                                    pass
            db.close()
        except Exception as e:
            print(f"Sync Progress Error: {e}")
            
        # Wait 5 minutes
        await asyncio.sleep(300)

async def check_new_episodes():
    """Periodically update feed URLs in ABS to proxy and trigger checknew for all subscribed podcasts."""
    # Wait for ABS to start up before beginning the loop
    await asyncio.sleep(30)
    while True:
        try:
            ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
            ABS_TOKEN = os.getenv("ABS_TOKEN", "")
            POLARR_EXTERNAL_URL = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
            if not ABS_URL or not ABS_TOKEN:
                await asyncio.sleep(3600)
                continue

            headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
            db = SessionLocal()

            podcasts = db.query(Podcast).filter(Podcast.subscribed == True, Podcast.abs_id != None).all()
            updated = 0
            for pod in podcasts:
                try:
                    proxy_url = f"{POLARR_EXTERNAL_URL}/feed/{pod.id}"
                    # Update feed URL to proxy
                    await asyncio.to_thread(
                        requests.patch,
                        f"{ABS_URL}/api/items/{pod.abs_id}/media",
                        json={"metadata": {"feedUrl": proxy_url}},
                        headers=headers, timeout=30
                    )
                    # Reset lastEpisodeCheck to force ABS to scan immediately
                    await asyncio.to_thread(
                        requests.patch,
                        f"{ABS_URL}/api/items/{pod.abs_id}/media",
                        json={"lastEpisodeCheck": 0},
                        headers=headers, timeout=30
                    )
                    # Trigger episode check — tolerate timeout since ABS may be downloading
                    try:
                        await asyncio.to_thread(
                            requests.get,
                            f"{ABS_URL}/api/podcasts/{pod.abs_id}/checknew?limit=9999",
                            headers=headers, timeout=60
                        )
                    except requests.exceptions.ReadTimeout:
                        pass  # ABS is downloading episodes, that's fine
                    updated += 1
                except Exception as e:
                    print(f"⚠️ check_new_episodes error for {pod.title}: {e}")
                # Space out requests to avoid overloading ABS
                await asyncio.sleep(5)

            # Read configurable interval from settings (default: 60 min)
            interval_setting = db.query(AppSetting).filter(AppSetting.key == "episode_check_interval").first()
            interval_minutes = int(interval_setting.value) if interval_setting else 60
            interval_minutes = max(30, min(interval_minutes, 1440))
            db.close()
            print(f"🔄 Episode check complete: {updated}/{len(podcasts)} podcasts checked. Next check in {interval_minutes} min.")
        except Exception as e:
            print(f"check_new_episodes error: {e}")
            interval_minutes = 60

        await asyncio.sleep(interval_minutes * 60)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(sync_abs_progress())
    asyncio.create_task(check_new_episodes())
