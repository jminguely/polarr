from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from ...database import get_db
from ...models import Podcast, PlayHistory, QueueItem, AppSetting
from ...schemas import PodcastResponse, PodcastCreate, PodcastUpdate, EpisodeResponse
from ...services.feed_parser import fetch_feed_episodes, clear_proxy_cache
from ...services.sync_service import poll_podcast_for_new_episodes

router = APIRouter(prefix="/podcasts", tags=["API Podcasts"])

@router.get("", response_model=List[PodcastResponse])
def list_podcasts(subscribed_only: bool = False, db: Session = Depends(get_db)):
    """List all podcasts with play history counts."""
    query = db.query(Podcast)
    if subscribed_only:
        query = query.filter(Podcast.subscribed == True)
    podcasts = query.order_by(Podcast.title.asc()).all()

    results = []
    for p in podcasts:
        listened_count = db.query(PlayHistory).filter(
            PlayHistory.podcast_id == p.id,
            PlayHistory.is_skipped == False
        ).count()
        results.append(PodcastResponse(
            id=p.id,
            title=p.title,
            feed_url=p.feed_url,
            artwork_url=p.artwork_url,
            subscribed=p.subscribed,
            sync_order=p.sync_order,
            sync_limit=p.sync_limit,
            sync_start_after_guid=p.sync_start_after_guid,
            created_at=p.created_at,
            listened_count=listened_count
        ))
    return results

@router.post("", response_model=PodcastResponse, status_code=201)
def create_podcast(
    payload: PodcastCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """Subscribe to a new podcast by feed URL."""
    feed_url = payload.feed_url.strip()
    existing = db.query(Podcast).filter(Podcast.feed_url == feed_url).first()
    if existing:
        if not existing.subscribed:
            existing.subscribed = True
            db.commit()
            background_tasks.add_task(poll_podcast_for_new_episodes, existing, db)
        return PodcastResponse(
            id=existing.id,
            title=existing.title,
            feed_url=existing.feed_url,
            artwork_url=existing.artwork_url,
            subscribed=existing.subscribed,
            sync_order=existing.sync_order,
            sync_limit=existing.sync_limit,
            sync_start_after_guid=existing.sync_start_after_guid,
            created_at=existing.created_at,
            listened_count=0
        )

    title = payload.title
    artwork_url = payload.artwork_url

    # If title or artwork not provided, parse upstream RSS feed
    if not title or not artwork_url:
        feed_eps, feed_art = fetch_feed_episodes(feed_url)
        if feed_art and not artwork_url:
            artwork_url = feed_art
        if not title:
            # Fallback title from feed
            import feedparser
            d = feedparser.parse(feed_url)
            if hasattr(d, "feed") and "title" in d.feed:
                title = d.feed.title
            else:
                title = "New Podcast"

    sync_order_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_order").first()
    sync_limit_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_limit").first()

    default_sync_order = payload.sync_order or (sync_order_setting.value if sync_order_setting else "oldest_first")
    default_sync_limit = payload.sync_limit or (int(sync_limit_setting.value) if sync_limit_setting else 5)

    podcast = Podcast(
        title=title,
        feed_url=feed_url,
        artwork_url=artwork_url,
        subscribed=True,
        sync_order=default_sync_order,
        sync_limit=default_sync_limit,
        sync_start_after_guid=payload.sync_start_after_guid,
        created_at=datetime.utcnow()
    )
    db.add(podcast)
    db.commit()
    db.refresh(podcast)

    background_tasks.add_task(poll_podcast_for_new_episodes, podcast, db)

    return PodcastResponse(
        id=podcast.id,
        title=podcast.title,
        feed_url=podcast.feed_url,
        artwork_url=podcast.artwork_url,
        subscribed=podcast.subscribed,
        sync_order=podcast.sync_order,
        sync_limit=podcast.sync_limit,
        sync_start_after_guid=podcast.sync_start_after_guid,
        created_at=podcast.created_at,
        listened_count=0
    )

@router.get("/{podcast_id}", response_model=PodcastResponse)
def get_podcast(podcast_id: int, db: Session = Depends(get_db)):
    """Get single podcast detail with stats."""
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    listened_count = db.query(PlayHistory).filter(
        PlayHistory.podcast_id == podcast.id,
        PlayHistory.is_skipped == False
    ).count()

    return PodcastResponse(
        id=podcast.id,
        title=podcast.title,
        feed_url=podcast.feed_url,
        artwork_url=podcast.artwork_url,
        subscribed=podcast.subscribed,
        sync_order=podcast.sync_order,
        sync_limit=podcast.sync_limit,
        sync_start_after_guid=podcast.sync_start_after_guid,
        created_at=podcast.created_at,
        listened_count=listened_count
    )

@router.patch("/{podcast_id}", response_model=PodcastResponse)
def update_podcast(podcast_id: int, payload: PodcastUpdate, db: Session = Depends(get_db)):
    """Update podcast configuration and subscription status."""
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    if payload.title is not None:
        podcast.title = payload.title.strip()
    if payload.feed_url is not None:
        podcast.feed_url = payload.feed_url.strip()
    if payload.artwork_url is not None:
        podcast.artwork_url = payload.artwork_url.strip()
    if payload.sync_order is not None:
        podcast.sync_order = payload.sync_order
    if payload.sync_limit is not None:
        podcast.sync_limit = payload.sync_limit
    if payload.sync_start_after_guid is not None:
        podcast.sync_start_after_guid = payload.sync_start_after_guid.strip() if payload.sync_start_after_guid else None
    if payload.subscribed is not None:
        podcast.subscribed = payload.subscribed

    db.commit()
    clear_proxy_cache(podcast.id)

    listened_count = db.query(PlayHistory).filter(
        PlayHistory.podcast_id == podcast.id,
        PlayHistory.is_skipped == False
    ).count()

    return PodcastResponse(
        id=podcast.id,
        title=podcast.title,
        feed_url=podcast.feed_url,
        artwork_url=podcast.artwork_url,
        subscribed=podcast.subscribed,
        sync_order=podcast.sync_order,
        sync_limit=podcast.sync_limit,
        sync_start_after_guid=podcast.sync_start_after_guid,
        created_at=podcast.created_at,
        listened_count=listened_count
    )

@router.delete("/{podcast_id}")
def delete_podcast(podcast_id: int, hard: bool = False, db: Session = Depends(get_db)):
    """Unsubscribe (soft delete) or remove podcast completely."""
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    clear_proxy_cache(podcast.id)
    if hard:
        db.delete(podcast)
        db.commit()
        return {"status": "ok", "message": f"Podcast '{podcast.title}' permanently deleted."}
    else:
        podcast.subscribed = False
        db.commit()
        return {"status": "ok", "message": f"Unsubscribed from '{podcast.title}'."}

@router.get("/{podcast_id}/episodes", response_model=List[EpisodeResponse])
def get_podcast_episodes(podcast_id: int, db: Session = Depends(get_db)):
    """Fetch feed episodes cross-referenced with PlayHistory and QueueItem."""
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    feed_episodes, artwork = fetch_feed_episodes(podcast.feed_url)
    if artwork and not podcast.artwork_url:
        podcast.artwork_url = artwork
        db.commit()

    # Load history for this podcast
    history_records = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast_id).all()
    history_by_guid = {h.episode_guid: h for h in history_records if h.episode_guid}

    # Load queue items for this podcast
    queue_guids = {
        row[0] for row in db.query(QueueItem.episode_guid).filter(QueueItem.podcast_id == podcast_id).all() if row[0]
    }

    results = []
    for ep in feed_episodes:
        guid = ep["guid"]
        h = history_by_guid.get(guid)
        results.append(EpisodeResponse(
            guid=guid,
            title=ep.get("title", "Untitled Episode"),
            description=ep.get("description", ""),
            pub_date=ep.get("pub_date"),
            link=ep.get("link", ""),
            enclosure_url=ep.get("enclosure_url", ""),
            duration_secs=ep.get("duration_secs"),
            played=h is not None and not h.is_skipped,
            skipped=h is not None and h.is_skipped,
            completion_type=h.completion_type if h else None,
            played_at=h.played_at if h else None,
            rating=h.rating if h else None,
            is_queued=guid in queue_guids
        ))
    return results
