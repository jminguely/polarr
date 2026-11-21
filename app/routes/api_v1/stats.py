from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, or_
from typing import List, Optional
from datetime import datetime, timedelta

from ...database import get_db
from ...models import PlayHistory, Podcast
from ...schemas import (
    StatsOverviewResponse,
    PodcastStatsResponse,
    HeatmapCell,
    TopPodcastResponse,
    CompletionRateResponse
)
from ...services.feed_parser import fetch_feed_episodes

router = APIRouter(prefix="/stats", tags=["API Statistics"])

@router.get("/overview", response_model=StatsOverviewResponse)
def get_stats_overview(db: Session = Depends(get_db)):
    """Summary overview of all-time listening history and hours."""
    listened_count = db.query(PlayHistory).filter(
        or_(PlayHistory.completion_type == "finished", PlayHistory.is_skipped == False)
    ).count()

    skipped_count = db.query(PlayHistory).filter(
        or_(PlayHistory.completion_type == "skipped", PlayHistory.is_skipped == True)
    ).count()

    abandoned_count = db.query(PlayHistory).filter(
        PlayHistory.completion_type == "abandoned"
    ).count()

    podcasts_count = db.query(Podcast).count()

    first_record = db.query(PlayHistory).order_by(PlayHistory.played_at.asc()).first()
    first_date = first_record.played_at if first_record else None

    # Calculate total duration in hours
    all_finished = db.query(PlayHistory).filter(PlayHistory.is_skipped == False).all()
    total_secs = 0
    for row in all_finished:
        secs = row.time_listened_secs or row.episode_duration_secs or 0
        total_secs += secs

    return StatsOverviewResponse(
        total_episodes_listened=listened_count,
        total_episodes_skipped=skipped_count,
        total_episodes_abandoned=abandoned_count,
        total_hours_listened=round(total_secs / 3600.0, 1),
        total_podcasts_tracked=podcasts_count,
        first_listen_date=first_date
    )

@router.get("/by-podcast", response_model=List[PodcastStatsResponse])
def get_stats_by_podcast(db: Session = Depends(get_db)):
    """Listening metrics grouped by podcast."""
    podcasts = db.query(Podcast).order_by(Podcast.title.asc()).all()
    results = []

    for pod in podcasts:
        entries = db.query(PlayHistory).filter(PlayHistory.podcast_id == pod.id).all()
        listened = [e for e in entries if not e.is_skipped]
        skipped = [e for e in entries if e.is_skipped]

        total_secs = sum((e.time_listened_secs or e.episode_duration_secs or 0) for e in listened)
        ratings = [e.rating for e in entries if e.rating is not None]
        avg_rating = round(sum(ratings) / len(ratings), 1) if ratings else None

        results.append(PodcastStatsResponse(
            podcast_id=pod.id,
            title=pod.title,
            artwork_url=pod.artwork_url,
            listened_count=len(listened),
            skipped_count=len(skipped),
            hours_listened=round(total_secs / 3600.0, 1),
            average_rating=avg_rating
        ))

    # Sort by listened_count desc
    results.sort(key=lambda x: x.listened_count, reverse=True)
    return results

@router.get("/heatmap", response_model=List[HeatmapCell])
def get_listening_heatmap(db: Session = Depends(get_db)):
    """Listening distribution by day-of-week (0=Mon..6=Sun) and hour-of-day (0..23)."""
    entries = db.query(PlayHistory).filter(PlayHistory.is_skipped == False).all()

    # Matrix initialized to 0
    matrix = {}
    for dow in range(7):
        for hod in range(24):
            matrix[(dow, hod)] = 0

    for e in entries:
        if e.played_at:
            dow = e.played_at.weekday() # 0 = Monday, 6 = Sunday
            hod = e.played_at.hour
            matrix[(dow, hod)] = matrix.get((dow, hod), 0) + 1

    cells = [
        HeatmapCell(day_of_week=k[0], hour_of_day=k[1], listen_count=v)
        for k, v in matrix.items()
    ]
    return cells

@router.get("/top", response_model=List[TopPodcastResponse])
def get_top_podcasts(period: str = Query("all", pattern="^(month|year|all)$"), limit: int = 10, db: Session = Depends(get_db)):
    """Top podcasts by episode count within a given timeframe."""
    query = db.query(PlayHistory).filter(PlayHistory.is_skipped == False)

    now = datetime.utcnow()
    if period == "month":
        query = query.filter(PlayHistory.played_at >= now - timedelta(days=30))
    elif period == "year":
        query = query.filter(PlayHistory.played_at >= now - timedelta(days=365))

    entries = query.all()
    by_pod = {}
    for e in entries:
        by_pod.setdefault(e.podcast_id, []).append(e)

    results = []
    for pod_id, pod_entries in by_pod.items():
        pod = db.query(Podcast).filter(Podcast.id == pod_id).first()
        if not pod:
            continue
        total_secs = sum((x.time_listened_secs or x.episode_duration_secs or 0) for x in pod_entries)
        results.append(TopPodcastResponse(
            podcast_id=pod.id,
            title=pod.title,
            artwork_url=pod.artwork_url,
            listened_count=len(pod_entries),
            hours_listened=round(total_secs / 3600.0, 1)
        ))

    results.sort(key=lambda x: x.listened_count, reverse=True)
    return results[:limit]

@router.get("/completion-rates", response_model=List[CompletionRateResponse])
def get_completion_rates(db: Session = Depends(get_db)):
    """Completion rate for each active subscription."""
    podcasts = db.query(Podcast).filter(Podcast.subscribed == True).order_by(Podcast.title.asc()).all()
    results = []

    for pod in podcasts:
        feed_eps, _ = fetch_feed_episodes(pod.feed_url)
        total_feed = len(feed_eps)
        listened_count = db.query(PlayHistory).filter(
            PlayHistory.podcast_id == pod.id,
            PlayHistory.is_skipped == False
        ).count()

        pct = round((listened_count / total_feed * 100.0), 1) if total_feed > 0 else 0.0
        results.append(CompletionRateResponse(
            podcast_id=pod.id,
            title=pod.title,
            artwork_url=pod.artwork_url,
            total_feed_episodes=total_feed,
            listened_episodes=listened_count,
            completion_rate_pct=min(100.0, pct)
        ))

    results.sort(key=lambda x: x.completion_rate_pct, reverse=True)
    return results
