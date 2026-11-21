from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import List

from ...database import get_db
from ...models import NewEpisode, Podcast, QueueItem
from ...schemas import NewEpisodeResponse, QueueItemResponse
from ...services.sync_service import check_all_podcasts_sync

router = APIRouter(prefix="/inbox", tags=["API Inbox"])

@router.get("", response_model=List[NewEpisodeResponse])
def get_inbox_episodes(limit: int = 50, db: Session = Depends(get_db)):
    """Get newly released unplayed episodes across all subscribed podcasts."""
    items = (
        db.query(NewEpisode)
        .join(Podcast, NewEpisode.podcast_id == Podcast.id)
        .filter(Podcast.subscribed == True, NewEpisode.is_dismissed == False)
        .order_by(desc(NewEpisode.pub_date), desc(NewEpisode.discovered_at))
        .limit(limit)
        .all()
    )

    results = []
    for it in items:
        results.append(NewEpisodeResponse(
            id=it.id,
            podcast_id=it.podcast_id,
            podcast_title=it.podcast.title if it.podcast else None,
            podcast_artwork_url=it.podcast.artwork_url if it.podcast else None,
            episode_guid=it.episode_guid,
            title=it.title,
            description=it.description,
            enclosure_url=it.enclosure_url,
            duration_secs=it.duration_secs,
            pub_date=it.pub_date,
            is_dismissed=it.is_dismissed,
            is_queued=it.is_queued,
            discovered_at=it.discovered_at
        ))
    return results

@router.post("/{episode_id}/dismiss")
def dismiss_inbox_episode(episode_id: int, db: Session = Depends(get_db)):
    """Dismiss a new episode from the inbox."""
    episode = db.query(NewEpisode).filter(NewEpisode.id == episode_id).first()
    if not episode:
        raise HTTPException(status_code=404, detail="Episode not found in inbox")

    episode.is_dismissed = True
    db.commit()
    return {"status": "ok", "message": "Episode dismissed from inbox"}

@router.post("/{episode_id}/queue", response_model=QueueItemResponse)
def queue_inbox_episode(episode_id: int, db: Session = Depends(get_db)):
    """Add a new inbox episode directly into the playback queue."""
    episode = db.query(NewEpisode).filter(NewEpisode.id == episode_id).first()
    if not episode:
        raise HTTPException(status_code=404, detail="Episode not found in inbox")

    # Check if already queued
    existing_queue = db.query(QueueItem).filter(
        QueueItem.podcast_id == episode.podcast_id,
        QueueItem.episode_guid == episode.episode_guid
    ).first()

    if existing_queue:
        episode.is_queued = True
        db.commit()
        return QueueItemResponse(
            id=existing_queue.id,
            podcast_id=existing_queue.podcast_id,
            podcast_title=episode.podcast.title if episode.podcast else None,
            podcast_artwork_url=episode.podcast.artwork_url if episode.podcast else None,
            episode_guid=existing_queue.episode_guid,
            episode_title=existing_queue.episode_title,
            enclosure_url=existing_queue.enclosure_url,
            duration_secs=existing_queue.duration_secs,
            position=existing_queue.position,
            progress_secs=existing_queue.progress_secs,
            added_at=existing_queue.added_at
        )

    # Determine next position
    last_item = db.query(QueueItem).order_by(desc(QueueItem.position)).first()
    next_pos = (last_item.position + 1) if last_item else 0

    queue_item = QueueItem(
        podcast_id=episode.podcast_id,
        episode_guid=episode.episode_guid,
        episode_title=episode.title,
        enclosure_url=episode.enclosure_url,
        duration_secs=episode.duration_secs,
        position=next_pos,
        progress_secs=0
    )
    db.add(queue_item)
    episode.is_queued = True
    db.commit()
    db.refresh(queue_item)

    return QueueItemResponse(
        id=queue_item.id,
        podcast_id=queue_item.podcast_id,
        podcast_title=episode.podcast.title if episode.podcast else None,
        podcast_artwork_url=episode.podcast.artwork_url if episode.podcast else None,
        episode_guid=queue_item.episode_guid,
        episode_title=queue_item.episode_title,
        enclosure_url=queue_item.enclosure_url,
        duration_secs=queue_item.duration_secs,
        position=queue_item.position,
        progress_secs=queue_item.progress_secs,
        added_at=queue_item.added_at
    )

@router.post("/refresh")
def refresh_inbox(background_tasks: BackgroundTasks):
    """Trigger background check across all subscribed podcasts for new episodes."""
    background_tasks.add_task(check_all_podcasts_sync)
    return {"status": "ok", "message": "Background feed refresh started"}
