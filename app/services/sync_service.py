import asyncio
import time
from datetime import datetime
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from ..database import SessionLocal
from ..models import Podcast, PlayHistory, ListeningJournal, NewEpisode, QueueItem, AppSetting, SyncLog
from ..core.logger import log_system_event
from .feed_parser import clear_proxy_cache, fetch_feed_episodes, get_podcast_proxy_url

def handle_episode_listened(
    podcast: Podcast,
    episode_guid: str,
    episode_title: Optional[str] = None,
    completion_type: str = "finished",
    episode_duration_secs: Optional[int] = None,
    time_listened_secs: Optional[int] = None,
    rating: Optional[int] = None,
    personal_note: Optional[str] = None,
    abs_episode_id: Optional[str] = None,  # Legacy parameter, ignored safely
    db: Optional[Session] = None
) -> bool:
    """
    Mark an episode as listened/finished/skipped in ListeningJournal (PlayHistory).
    1. Persist/update to PlayHistory
    2. Dismiss or remove from NewEpisode inbox
    3. Remove from QueueItem queue
    4. Invalidate proxy feed cache
    """
    should_close_db = False
    if db is None:
        db = SessionLocal()
        should_close_db = True

    try:
        clean_guid = str(episode_guid).strip()
        existing = db.query(PlayHistory).filter(
            PlayHistory.podcast_id == podcast.id,
            PlayHistory.episode_guid == clean_guid
        ).first()

        # Fallback check by exact episode title
        if not existing and episode_title and not episode_title.startswith("Episode "):
            existing = db.query(PlayHistory).filter(
                PlayHistory.podcast_id == podcast.id,
                PlayHistory.episode_title == episode_title
            ).first()
            if existing and existing.episode_guid != clean_guid:
                existing.episode_guid = clean_guid
                db.commit()

        is_skip = completion_type == "skipped"

        if not existing:
            new_history = PlayHistory(
                podcast_id=podcast.id,
                episode_guid=clean_guid,
                episode_title=episode_title or f"Episode {clean_guid[:12]}",
                played_at=datetime.utcnow(),
                is_skipped=is_skip,
                completion_type=completion_type,
                episode_duration_secs=episode_duration_secs,
                time_listened_secs=time_listened_secs,
                rating=rating,
                personal_note=personal_note,
            )
            db.add(new_history)
            db.commit()
            log_system_event(
                "INFO",
                "Sync",
                f"Recorded journal entry: '{new_history.episode_title}' for '{podcast.title}' ({completion_type})"
            )
        else:
            if episode_title and (not existing.episode_title or existing.episode_title.startswith("Episode ")):
                existing.episode_title = episode_title
            existing.completion_type = completion_type
            existing.is_skipped = is_skip
            if episode_duration_secs is not None:
                existing.episode_duration_secs = episode_duration_secs
            if time_listened_secs is not None:
                existing.time_listened_secs = time_listened_secs
            if rating is not None:
                existing.rating = rating
            if personal_note is not None:
                existing.personal_note = personal_note
            existing.played_at = datetime.utcnow()
            db.commit()
            log_system_event(
                "DEBUG",
                "Sync",
                f"Updated journal entry: '{clean_guid}' for '{podcast.title}'"
            )

        # Remove from NewEpisode inbox if present
        db.query(NewEpisode).filter(
            NewEpisode.podcast_id == podcast.id,
            NewEpisode.episode_guid == clean_guid
        ).delete()

        # Remove from QueueItem if present
        db.query(QueueItem).filter(
            QueueItem.podcast_id == podcast.id,
            QueueItem.episode_guid == clean_guid
        ).delete()
        db.commit()

        # Invalidate proxy feed cache
        clear_proxy_cache(podcast.id)

        return True
    except Exception as e:
        log_system_event("ERROR", "Sync", f"Error in handle_episode_listened for {podcast.title}: {e}")
        return False
    finally:
        if should_close_db:
            db.close()


def handle_episode_unplayed(podcast: Podcast, episode_guid: str, db: Optional[Session] = None) -> bool:
    """Mark an episode as unplayed (remove from history and refresh cache)."""
    should_close_db = False
    if db is None:
        db = SessionLocal()
        should_close_db = True

    try:
        clean_guid = str(episode_guid).strip()
        record = db.query(PlayHistory).filter(
            PlayHistory.podcast_id == podcast.id,
            PlayHistory.episode_guid == clean_guid
        ).first()

        if record:
            db.delete(record)
            db.commit()
            clear_proxy_cache(podcast.id)
            log_system_event("INFO", "Sync", f"Removed episode '{clean_guid}' from history for '{podcast.title}'")
            return True
        return False
    except Exception as e:
        log_system_event("ERROR", "Sync", f"Error in handle_episode_unplayed: {e}")
        return False
    finally:
        if should_close_db:
            db.close()


def poll_podcast_for_new_episodes(podcast: Podcast, db: Session) -> int:
    """
    Fetch RSS feed for a podcast and populate NewEpisode table for episodes
    not yet listened to and not already in NewEpisode.
    Returns count of newly discovered episodes.
    """
    if not podcast.feed_url:
        return 0

    episodes, artwork = fetch_feed_episodes(podcast.feed_url)
    if artwork and not podcast.artwork_url:
        podcast.artwork_url = artwork
        db.commit()

    if not episodes:
        return 0

    # Collect known GUIDs
    played_guids = {
        row[0] for row in db.query(PlayHistory.episode_guid).filter(PlayHistory.podcast_id == podcast.id).all() if row[0]
    }
    existing_new_guids = {
        row[0] for row in db.query(NewEpisode.episode_guid).filter(NewEpisode.podcast_id == podcast.id).all() if row[0]
    }

    new_count = 0
    # Process episodes (typically RSS gives newest first)
    for ep in episodes:
        guid = ep["guid"]
        if not guid or guid in played_guids or guid in existing_new_guids:
            continue

        item = NewEpisode(
            podcast_id=podcast.id,
            episode_guid=guid,
            title=ep.get("title", "Untitled Episode"),
            description=ep.get("description", ""),
            enclosure_url=ep.get("enclosure_url", ""),
            duration_secs=ep.get("duration_secs"),
            pub_date=ep.get("pub_date"),
            is_dismissed=False,
            is_queued=False,
            discovered_at=datetime.utcnow(),
        )
        db.add(item)
        existing_new_guids.add(guid)
        new_count += 1

    if new_count > 0:
        db.commit()

    return new_count


def check_all_podcasts_sync(log_id: Optional[int] = None) -> None:
    """Synchronous worker that polls RSS feeds of all active subscriptions."""
    db = SessionLocal()
    sync_log = None
    try:
        if log_id:
            sync_log = db.query(SyncLog).filter(SyncLog.id == log_id).first()
        else:
            sync_log = SyncLog(status="running", details="Periodic feed check started...")
            db.add(sync_log)
            db.commit()

        subscribed = db.query(Podcast).filter(Podcast.subscribed == True).all()
        if not subscribed:
            if sync_log:
                sync_log.status = "success"
                sync_log.finished_at = datetime.utcnow()
                sync_log.details = "No active subscriptions to check."
                db.commit()
            return

        output_lines = []
        total_new = 0

        for pod in subscribed:
            try:
                new_found = poll_podcast_for_new_episodes(pod, db)
                total_new += new_found
                output_lines.append(f"[{pod.title}] Checked: {new_found} new episode(s)")
            except Exception as e:
                output_lines.append(f"[{pod.title}] Error: {e}")

        if sync_log:
            sync_log.status = "success"
            sync_log.finished_at = datetime.utcnow()
            sync_log.details = f"Total new episodes found: {total_new}\n" + "\n".join(output_lines)
            db.commit()

        log_system_event("INFO", "Sync", f"Feed check complete: {total_new} new episode(s) found across {len(subscribed)} podcasts")
    except Exception as e:
        db.rollback()
        if sync_log:
            sync_log.status = "error"
            sync_log.finished_at = datetime.utcnow()
            sync_log.details = f"Exception: {e}"
            db.commit()
        log_system_event("ERROR", "Sync", f"Exception in check_all_podcasts_sync: {e}")
    finally:
        db.close()


async def check_new_episodes_loop():
    """Periodic background loop checking for new episodes across subscribed feeds."""
    log_system_event("INFO", "System", "Starting periodic feed checking loop")
    while True:
        try:
            interval_minutes = 60
            db = SessionLocal()
            try:
                interval_setting = db.query(AppSetting).filter(AppSetting.key == "episode_check_interval").first()
                if interval_setting and interval_setting.value:
                    interval_minutes = int(interval_setting.value)
                interval_minutes = max(15, min(interval_minutes, 1440))
            finally:
                db.close()

            await asyncio.to_thread(check_all_podcasts_sync)
            await asyncio.sleep(interval_minutes * 60)
        except Exception as e:
            log_system_event("ERROR", "Sync", f"Exception in check_new_episodes_loop: {e}")
            await asyncio.sleep(300)


# Safe stubs for backward compatibility
async def sync_abs_progress_loop():
    """Deprecated: Audiobookshelf progress loop replaced by direct iOS app journal sync."""
    pass

def remove_episode_from_abs_and_sync(*args, **kwargs):
    """Deprecated: No-op."""
    pass

def perform_full_sync(log_id: int):
    """Refreshes all subscribed feeds."""
    check_all_podcasts_sync(log_id)

def sync_and_repair_play_history(log_id: Optional[int] = None):
    """Reconciles feed episode titles and durations with PlayHistory."""
    check_all_podcasts_sync(log_id)
