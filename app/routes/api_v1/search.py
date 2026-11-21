from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_, desc
from typing import List, Dict, Any

from ...database import get_db
from ...models import Podcast, PlayHistory
from ...services.podcastindex import search_podcasts, is_podcastindex_configured

router = APIRouter(prefix="/search", tags=["API Search"])

@router.get("")
def search_directory(q: str = Query(..., min_length=1), db: Session = Depends(get_db)):
    """Search podcast directory (PodcastIndex) and indicate if already subscribed."""
    if not is_podcastindex_configured():
        return {
            "configured": False,
            "message": "PodcastIndex API keys not configured on server",
            "results": []
        }

    feeds = search_podcasts(q.strip())
    existing_urls = {
        p.feed_url.rstrip("/") for p in db.query(Podcast.feed_url).all() if p.feed_url
    }

    formatted = []
    for f in feeds:
        feed_url = f.get("url") or ""
        clean_url = feed_url.rstrip("/")
        is_sub = clean_url in existing_urls

        formatted.append({
            "id": f.get("id"),
            "title": f.get("title"),
            "feed_url": feed_url,
            "description": f.get("description"),
            "artwork_url": f.get("artwork") or f.get("image"),
            "author": f.get("author"),
            "episode_count": f.get("episodeCount"),
            "subscribed": is_sub,
        })

    return {
        "configured": True,
        "query": q,
        "count": len(formatted),
        "results": formatted
    }

@router.get("/local")
def search_local(q: str = Query(..., min_length=1), db: Session = Depends(get_db)):
    """Live search across locally subscribed podcasts and listening journal history."""
    term = f"%{q.strip()}%"
    podcasts_list = db.query(Podcast).filter(
        or_(
            Podcast.title.ilike(term),
            Podcast.feed_url.ilike(term),
        )
    ).limit(10).all()

    episodes_list = db.query(PlayHistory).filter(
        or_(
            PlayHistory.episode_title.ilike(term),
            PlayHistory.personal_note.ilike(term),
        )
    ).order_by(desc(PlayHistory.played_at)).limit(15).all()

    return {
        "podcasts": [
            {
                "id": p.id,
                "title": p.title,
                "feed_url": p.feed_url,
                "artwork_url": p.artwork_url,
                "subscribed": p.subscribed
            } for p in podcasts_list
        ],
        "journal_entries": [
            {
                "id": e.id,
                "podcast_id": e.podcast_id,
                "podcast_title": e.podcast.title if e.podcast else None,
                "episode_title": e.episode_title,
                "played_at": e.played_at.isoformat() if e.played_at else None,
                "completion_type": e.completion_type or ("skipped" if e.is_skipped else "finished"),
                "rating": e.rating
            } for e in episodes_list
        ]
    }
