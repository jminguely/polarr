from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_, desc
from typing import Optional
from datetime import datetime

from ...database import get_db
from ...models import DeviceSync, PlayHistory, Podcast, QueueItem
from ...schemas import (
    DeviceRegisterRequest,
    SyncPushRequest,
    SyncPullResponse,
    JournalEntryResponse,
    PodcastResponse,
    QueueItemResponse
)
from ...services.sync_service import handle_episode_listened
from .journal import _format_entry
from .queue import _format_queue_item

router = APIRouter(prefix="/sync", tags=["API Sync"])

@router.post("/register")
def register_device(payload: DeviceRegisterRequest, db: Session = Depends(get_db)):
    """Register or heartbeat an iOS device for cloud synchronization."""
    device = db.query(DeviceSync).filter(DeviceSync.device_id == payload.device_id).first()
    now = datetime.utcnow()
    if not device:
        device = DeviceSync(
            device_id=payload.device_id,
            device_name=payload.device_name or "iPhone",
            last_sync_at=now,
            sync_token=now.isoformat()
        )
        db.add(device)
    else:
        if payload.device_name:
            device.device_name = payload.device_name
        device.last_sync_at = now
    db.commit()
    db.refresh(device)

    return {
        "status": "ok",
        "device_id": device.device_id,
        "sync_token": device.sync_token,
        "last_sync_at": device.last_sync_at.isoformat()
    }

@router.post("/push")
def sync_push(payload: SyncPushRequest, db: Session = Depends(get_db)):
    """Push local journal entries and queue updates from iOS device to cloud."""
    # Update device heartbeat
    dev = db.query(DeviceSync).filter(DeviceSync.device_id == payload.device_id).first()
    if dev:
        dev.last_sync_at = datetime.utcnow()

    synced_journal = 0
    for entry in payload.journal_entries:
        podcast = db.query(Podcast).filter(Podcast.id == entry.podcast_id).first()
        if not podcast:
            continue

        handle_episode_listened(
            podcast=podcast,
            episode_guid=entry.episode_guid,
            episode_title=entry.episode_title,
            completion_type=entry.completion_type or "finished",
            episode_duration_secs=entry.episode_duration_secs,
            time_listened_secs=entry.time_listened_secs,
            rating=entry.rating,
            personal_note=entry.personal_note,
            db=db
        )

        # Set specific played_at if provided
        if entry.played_at:
            rec = db.query(PlayHistory).filter(
                PlayHistory.podcast_id == podcast.id,
                PlayHistory.episode_guid == entry.episode_guid.strip()
            ).first()
            if rec:
                rec.played_at = entry.played_at
                db.commit()
        synced_journal += 1

    # If full queue replacement is sent
    if payload.queue_items is not None:
        db.query(QueueItem).delete()
        for idx, q in enumerate(payload.queue_items):
            item = QueueItem(
                podcast_id=q.podcast_id,
                episode_guid=q.episode_guid.strip(),
                episode_title=q.episode_title.strip(),
                enclosure_url=q.enclosure_url,
                duration_secs=q.duration_secs,
                position=q.position if q.position is not None else idx,
                progress_secs=q.progress_secs or 0
            )
            db.add(item)
        db.commit()

    return {
        "status": "ok",
        "synced_journal_entries": synced_journal,
        "new_sync_token": datetime.utcnow().isoformat()
    }

@router.get("/pull", response_model=SyncPullResponse)
def sync_pull(
    since: Optional[str] = None,
    limit: Optional[int] = Query(None, description="Max entries to return; defaults to all for full sync or 200 for incremental"),
    db: Session = Depends(get_db)
):
    """Pull incremental journal entries, all subscriptions, and active queue."""
    now_token = datetime.utcnow().isoformat()

    # 1. Fetch journal entries
    journal_query = db.query(PlayHistory).join(Podcast, PlayHistory.podcast_id == Podcast.id)
    if since:
        try:
            since_dt = datetime.fromisoformat(since)
            journal_query = journal_query.filter(
                or_(
                    PlayHistory.played_at >= since_dt,
                    PlayHistory.updated_at >= since_dt,
                    PlayHistory.created_at >= since_dt
                )
            )
        except ValueError:
            pass

    journal_query = journal_query.order_by(desc(PlayHistory.played_at))
    if limit is not None:
        entries = journal_query.limit(limit).all()
    elif since:
        entries = journal_query.limit(200).all()
    else:
        entries = journal_query.all()

    formatted_entries = [_format_entry(e) for e in entries]

    # 2. Fetch subscriptions
    podcasts = db.query(Podcast).filter(Podcast.subscribed == True).order_by(Podcast.title.asc()).all()
    formatted_subs = []
    for p in podcasts:
        l_cnt = db.query(PlayHistory).filter(PlayHistory.podcast_id == p.id, PlayHistory.is_skipped == False).count()
        formatted_subs.append(PodcastResponse(
            id=p.id,
            title=p.title,
            feed_url=p.feed_url,
            artwork_url=p.artwork_url,
            subscribed=p.subscribed,
            sync_order=p.sync_order,
            sync_limit=p.sync_limit,
            sync_start_after_guid=p.sync_start_after_guid,
            created_at=p.created_at,
            listened_count=l_cnt
        ))

    # 3. Fetch queue
    queue_items = db.query(QueueItem).join(Podcast, QueueItem.podcast_id == Podcast.id).order_by(QueueItem.position.asc()).all()
    formatted_queue = [_format_queue_item(q) for q in queue_items]

    return SyncPullResponse(
        sync_token=now_token,
        journal_entries=formatted_entries,
        subscriptions=formatted_subs,
        queue_items=formatted_queue
    )
