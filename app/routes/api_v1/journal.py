from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import List, Optional
from datetime import datetime

from ...database import get_db
from ...models import PlayHistory, ListeningJournal, ChapterBookmark, Podcast
from ...schemas import (
    JournalEntryResponse,
    JournalEntryCreate,
    JournalEntryUpdate,
    BookmarkResponse,
    BookmarkCreate
)
from ...services.sync_service import handle_episode_listened
from ...services.feed_parser import clear_proxy_cache

router = APIRouter(prefix="/journal", tags=["API Listening Journal"])

def _format_entry(h: PlayHistory) -> JournalEntryResponse:
    bookmarks = [
        BookmarkResponse(
            id=b.id,
            journal_entry_id=b.journal_entry_id,
            timestamp_secs=b.timestamp_secs,
            label=b.label,
            created_at=b.created_at
        ) for b in (h.bookmarks or [])
    ]
    return JournalEntryResponse(
        id=h.id,
        podcast_id=h.podcast_id,
        episode_guid=h.episode_guid,
        episode_title=h.episode_title,
        completion_type=h.completion_type or ("skipped" if h.is_skipped else "finished"),
        is_skipped=h.is_skipped,
        episode_duration_secs=h.episode_duration_secs,
        time_listened_secs=h.time_listened_secs,
        rating=h.rating,
        personal_note=h.personal_note,
        played_at=h.played_at,
        created_at=h.created_at,
        updated_at=h.updated_at,
        podcast_title=h.podcast.title if h.podcast else None,
        podcast_artwork_url=h.podcast.artwork_url if h.podcast else None,
        bookmarks=bookmarks
    )

@router.get("", response_model=List[JournalEntryResponse])
def list_journal_entries(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    podcast_id: Optional[int] = None,
    completion_type: Optional[str] = None,
    q: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """Retrieve chronological listening journal entries with optional filters."""
    query = db.query(PlayHistory).join(Podcast, PlayHistory.podcast_id == Podcast.id)

    if podcast_id:
        query = query.filter(PlayHistory.podcast_id == podcast_id)
    if completion_type:
        query = query.filter(PlayHistory.completion_type == completion_type)
    if q and q.strip():
        term = f"%{q.strip()}%"
        query = query.filter(
            (PlayHistory.episode_title.ilike(term)) |
            (Podcast.title.ilike(term)) |
            (PlayHistory.personal_note.ilike(term))
        )

    offset = (page - 1) * page_size
    entries = query.order_by(desc(PlayHistory.played_at)).offset(offset).limit(page_size).all()

    return [_format_entry(e) for e in entries]

@router.post("", response_model=JournalEntryResponse, status_code=201)
def create_journal_entry(payload: JournalEntryCreate, db: Session = Depends(get_db)):
    """Record or update a listening event in the journal."""
    podcast = db.query(Podcast).filter(Podcast.id == payload.podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    comp_type = payload.completion_type or "finished"
    success = handle_episode_listened(
        podcast=podcast,
        episode_guid=payload.episode_guid,
        episode_title=payload.episode_title,
        completion_type=comp_type,
        episode_duration_secs=payload.episode_duration_secs,
        time_listened_secs=payload.time_listened_secs,
        rating=payload.rating,
        personal_note=payload.personal_note,
        db=db
    )
    if not success:
        raise HTTPException(status_code=500, detail="Failed to save listening journal entry")

    entry = db.query(PlayHistory).filter(
        PlayHistory.podcast_id == podcast.id,
        PlayHistory.episode_guid == payload.episode_guid.strip()
    ).first()

    if payload.played_at:
        entry.played_at = payload.played_at
        db.commit()

    return _format_entry(entry)

@router.get("/{entry_id}", response_model=JournalEntryResponse)
def get_journal_entry(entry_id: int, db: Session = Depends(get_db)):
    """Get single listening journal entry."""
    entry = db.query(PlayHistory).filter(PlayHistory.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Journal entry not found")
    return _format_entry(entry)

@router.patch("/{entry_id}", response_model=JournalEntryResponse)
def update_journal_entry(entry_id: int, payload: JournalEntryUpdate, db: Session = Depends(get_db)):
    """Update notes, star rating, or metadata of an existing journal entry."""
    entry = db.query(PlayHistory).filter(PlayHistory.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Journal entry not found")

    if payload.episode_title is not None:
        entry.episode_title = payload.episode_title
    if payload.completion_type is not None:
        entry.completion_type = payload.completion_type
        entry.is_skipped = (payload.completion_type == "skipped")
    if payload.episode_duration_secs is not None:
        entry.episode_duration_secs = payload.episode_duration_secs
    if payload.time_listened_secs is not None:
        entry.time_listened_secs = payload.time_listened_secs
    if payload.rating is not None:
        entry.rating = max(1, min(5, payload.rating))
    if payload.personal_note is not None:
        entry.personal_note = payload.personal_note
    if payload.played_at is not None:
        entry.played_at = payload.played_at

    entry.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(entry)
    clear_proxy_cache(entry.podcast_id)

    return _format_entry(entry)

@router.delete("/{entry_id}")
def delete_journal_entry(entry_id: int, db: Session = Depends(get_db)):
    """Remove an entry from the listening history."""
    entry = db.query(PlayHistory).filter(PlayHistory.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Journal entry not found")

    pod_id = entry.podcast_id
    db.delete(entry)
    db.commit()
    clear_proxy_cache(pod_id)

    return {"status": "ok", "message": "Journal entry deleted"}

# --- Bookmarks sub-routes ---

@router.get("/{entry_id}/bookmarks", response_model=List[BookmarkResponse])
def get_entry_bookmarks(entry_id: int, db: Session = Depends(get_db)):
    """List chapter bookmarks for a journal entry."""
    entry = db.query(PlayHistory).filter(PlayHistory.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Journal entry not found")

    bookmarks = db.query(ChapterBookmark).filter(
        ChapterBookmark.journal_entry_id == entry_id
    ).order_by(ChapterBookmark.timestamp_secs.asc()).all()

    return [
        BookmarkResponse(
            id=b.id,
            journal_entry_id=b.journal_entry_id,
            timestamp_secs=b.timestamp_secs,
            label=b.label,
            created_at=b.created_at
        ) for b in bookmarks
    ]

@router.post("/{entry_id}/bookmarks", response_model=BookmarkResponse, status_code=201)
def create_entry_bookmark(entry_id: int, payload: BookmarkCreate, db: Session = Depends(get_db)):
    """Add a chapter bookmark to a journal entry."""
    entry = db.query(PlayHistory).filter(PlayHistory.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Journal entry not found")

    bm = ChapterBookmark(
        journal_entry_id=entry_id,
        timestamp_secs=payload.timestamp_secs,
        label=payload.label.strip(),
        created_at=datetime.utcnow()
    )
    db.add(bm)
    db.commit()
    db.refresh(bm)

    return BookmarkResponse(
        id=bm.id,
        journal_entry_id=bm.journal_entry_id,
        timestamp_secs=bm.timestamp_secs,
        label=bm.label,
        created_at=bm.created_at
    )

@router.delete("/bookmarks/{bookmark_id}")
def delete_bookmark(bookmark_id: int, db: Session = Depends(get_db)):
    """Delete a chapter bookmark."""
    bm = db.query(ChapterBookmark).filter(ChapterBookmark.id == bookmark_id).first()
    if not bm:
        raise HTTPException(status_code=404, detail="Bookmark not found")

    db.delete(bm)
    db.commit()
    return {"status": "ok", "message": "Bookmark deleted"}
