from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import List

from ...database import get_db
from ...models import QueueItem, Podcast
from ...schemas import (
    QueueItemResponse,
    QueueItemCreate,
    QueueProgressUpdate,
    QueueReorderRequest
)

router = APIRouter(prefix="/queue", tags=["API Queue"])

def _format_queue_item(item: QueueItem) -> QueueItemResponse:
    return QueueItemResponse(
        id=item.id,
        podcast_id=item.podcast_id,
        podcast_title=item.podcast.title if item.podcast else None,
        podcast_artwork_url=item.podcast.artwork_url if item.podcast else None,
        episode_guid=item.episode_guid,
        episode_title=item.episode_title,
        enclosure_url=item.enclosure_url,
        duration_secs=item.duration_secs,
        position=item.position,
        progress_secs=item.progress_secs,
        added_at=item.added_at
    )

@router.get("", response_model=List[QueueItemResponse])
def get_queue(db: Session = Depends(get_db)):
    """Get all queued episodes ordered by playback position."""
    items = db.query(QueueItem).join(Podcast, QueueItem.podcast_id == Podcast.id).order_by(QueueItem.position.asc()).all()
    return [_format_queue_item(it) for it in items]

@router.post("", response_model=QueueItemResponse, status_code=201)
def add_to_queue(payload: QueueItemCreate, db: Session = Depends(get_db)):
    """Add an episode to the queue."""
    podcast = db.query(Podcast).filter(Podcast.id == payload.podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    # If position not provided, place at the end of queue
    pos = payload.position
    if pos is None:
        last = db.query(QueueItem).order_by(desc(QueueItem.position)).first()
        pos = (last.position + 1) if last else 0

    item = QueueItem(
        podcast_id=payload.podcast_id,
        episode_guid=payload.episode_guid.strip(),
        episode_title=payload.episode_title.strip(),
        enclosure_url=payload.enclosure_url,
        duration_secs=payload.duration_secs,
        position=pos,
        progress_secs=payload.progress_secs or 0
    )
    db.add(item)
    db.commit()
    db.refresh(item)

    return _format_queue_item(item)

@router.patch("/reorder", response_model=List[QueueItemResponse])
def reorder_queue(payload: QueueReorderRequest, db: Session = Depends(get_db)):
    """Reorder queue items based on the provided list of IDs."""
    for idx, item_id in enumerate(payload.item_ids):
        item = db.query(QueueItem).filter(QueueItem.id == item_id).first()
        if item:
            item.position = idx
    db.commit()

    items = db.query(QueueItem).join(Podcast, QueueItem.podcast_id == Podcast.id).order_by(QueueItem.position.asc()).all()
    return [_format_queue_item(it) for it in items]

@router.patch("/{item_id}/progress", response_model=QueueItemResponse)
def update_queue_progress(item_id: int, payload: QueueProgressUpdate, db: Session = Depends(get_db)):
    """Update current listening playback position (seconds) for a queued episode."""
    item = db.query(QueueItem).filter(QueueItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")

    item.progress_secs = max(0, payload.progress_secs)
    db.commit()
    db.refresh(item)

    return _format_queue_item(item)

@router.delete("/{item_id}")
def delete_queue_item(item_id: int, db: Session = Depends(get_db)):
    """Remove an item from the queue."""
    item = db.query(QueueItem).filter(QueueItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")

    db.delete(item)
    db.commit()
    return {"status": "ok", "message": "Item removed from queue"}

@router.post("/clear")
def clear_queue(db: Session = Depends(get_db)):
    """Clear all items from playback queue."""
    db.query(QueueItem).delete()
    db.commit()
    return {"status": "ok", "message": "Queue cleared"}
