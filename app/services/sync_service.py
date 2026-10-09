import asyncio
import time
from datetime import datetime
from typing import Optional
from sqlalchemy.orm import Session
from ..database import SessionLocal
from ..models import Podcast, PlayHistory, AppSetting, SyncLog
from ..core.logger import log_system_event
from .abs_client import abs_client
from .feed_parser import clear_proxy_cache

def handle_episode_listened(
    podcast: Podcast,
    episode_guid: str,
    episode_title: Optional[str] = None,
    abs_episode_id: Optional[str] = None,
    db: Optional[Session] = None
) -> bool:
    """
    Mark an episode as listened:
    1. Persist to PlayHistory
    2. Clear proxy feed cache
    3. Delete listened audio file from Audiobookshelf
    4. Trigger ABS checknew to auto-download the next episode in line
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

        if not existing:
            new_history = PlayHistory(
                podcast_id=podcast.id,
                episode_guid=clean_guid,
                episode_title=episode_title or f"Episode {clean_guid[:12]}",
                played_at=datetime.utcnow()
            )
            db.add(new_history)
            db.commit()
            log_system_event(
                "INFO",
                "Sync",
                f"Marked listened: '{new_history.episode_title}' for podcast '{podcast.title}'"
            )
        else:
            log_system_event(
                "DEBUG",
                "Sync",
                f"Episode '{clean_guid}' was already in PlayHistory"
            )

        # Invalidate proxy feed cache so the listened episode is filtered out
        clear_proxy_cache(podcast.id)

        # Delete audio file from ABS and trigger replacement download if podcast has ABS ID
        if podcast.abs_id:
            target_abs_ep_id = abs_episode_id
            
            # If we don't have the ABS episode ID directly, look it up in ABS item metadata
            if not target_abs_ep_id:
                abs_item = abs_client.get_podcast(podcast.abs_id)
                if abs_item:
                    episodes = abs_item.get("media", {}).get("episodes", [])
                    for ep in episodes:
                        if ep.get("guid") == clean_guid or (episode_title and ep.get("title") == episode_title):
                            target_abs_ep_id = ep.get("id")
                            break

            if target_abs_ep_id:
                abs_client.delete_episode(podcast.abs_id, target_abs_ep_id)
            
            # Trigger ABS to immediately scan the proxy feed and download the replacement episode
            abs_client.reset_media_check(podcast.abs_id)
            abs_client.checknew_podcast(podcast.abs_id)
            log_system_event(
                "INFO",
                "Sync",
                f"Triggered ABS checknew for '{podcast.title}' to download next sync episode"
            )

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

            if podcast.abs_id:
                abs_client.reset_media_check(podcast.abs_id)
                abs_client.checknew_podcast(podcast.abs_id)
            return True
        return False
    except Exception as e:
        log_system_event("ERROR", "Sync", f"Error in handle_episode_unplayed: {e}")
        return False
    finally:
        if should_close_db:
            db.close()


async def sync_abs_progress_loop():
    """Background task running every 5 minutes polling ABS /api/me for finished items."""
    log_system_event("INFO", "System", "Starting background ABS progress synchronization loop")
    while True:
        try:
            if abs_client.is_configured():
                data = await asyncio.to_thread(abs_client.get_me)
                if data:
                    media_progress = data.get("mediaProgress", [])
                    db = SessionLocal()
                    try:
                        for mp in media_progress:
                            if mp.get("isFinished") or mp.get("progress", 0) > 0.95:
                                lib_item_id = mp.get("libraryItemId")
                                ep_id = mp.get("episodeId")
                                if not lib_item_id or not ep_id:
                                    continue

                                pod = db.query(Podcast).filter(Podcast.abs_id == lib_item_id).first()
                                if pod:
                                    # Fetch episode metadata from ABS to obtain true RSS GUID & Title
                                    ep_data = await asyncio.to_thread(abs_client.get_episode, lib_item_id, ep_id)
                                    guid = ep_data.get("guid", ep_id) if ep_data else ep_id
                                    title = ep_data.get("title", f"Episode {ep_id}") if ep_data else f"Episode {ep_id}"

                                    handle_episode_listened(
                                        podcast=pod,
                                        episode_guid=guid,
                                        episode_title=title,
                                        abs_episode_id=ep_id,
                                        db=db
                                    )
                    finally:
                        db.close()
        except Exception as e:
            log_system_event("ERROR", "Sync", f"Exception in sync_abs_progress_loop: {e}")

        # Sleep 5 minutes
        await asyncio.sleep(300)


async def check_new_episodes_loop():
    """Periodic background check for new episodes on ABS."""
    log_system_event("INFO", "System", "Starting periodic check new episodes background loop")
    while True:
        try:
            db = SessionLocal()
            interval_setting = db.query(AppSetting).filter(AppSetting.key == "episode_check_interval").first()
            interval_minutes = int(interval_setting.value) if interval_setting else 60
            interval_minutes = max(30, min(interval_minutes, 1440))

            if abs_client.is_configured():
                subscribed = db.query(Podcast).filter(Podcast.subscribed == True, Podcast.abs_id.isnot(None)).all()
                if subscribed:
                    sync_log = SyncLog(status="running", details=f"Periodic check for {len(subscribed)} podcasts started...")
                    db.add(sync_log)
                    db.commit()

                    output_lines = []
                    for pod in subscribed:
                        abs_client.reset_media_check(pod.abs_id)
                        ok = abs_client.checknew_podcast(pod.abs_id)
                        output_lines.append(f"[{pod.title}] Check triggered: {'Success' if ok else 'Failed'}")

                    sync_log.status = "success"
                    sync_log.finished_at = datetime.utcnow()
                    sync_log.details = "\n".join(output_lines)
                    db.commit()
                    log_system_event("INFO", "Sync", f"Periodic episode check completed for {len(subscribed)} podcasts")

            db.close()
            await asyncio.sleep(interval_minutes * 60)
        except Exception as e:
            log_system_event("ERROR", "Sync", f"Exception in check_new_episodes_loop: {e}")
            await asyncio.sleep(300)


def perform_full_sync(log_id: int):
    """Background task to wipe ABS library and re-sync all active podcasts."""
    db = SessionLocal()
    log_entry = db.query(SyncLog).filter(SyncLog.id == log_id).first()

    if not abs_client.is_configured():
        if log_entry:
            log_entry.status = "error"
            log_entry.details = "Audiobookshelf configuration missing in .env"
            log_entry.finished_at = datetime.utcnow()
            db.commit()
        db.close()
        return

    details = []
    try:
        details.append(f"Clearing library {abs_client.library_id} on ABS...")
        lib_data = abs_client.get_library_items(abs_client.library_id) or {}
        items = lib_data.get("results", [])
        for item in items:
            if item.get("mediaType") == "podcast":
                abs_client.delete_podcast(item.get("id"))
                details.append(f"Removed item {item.get('id')} from ABS.")

        active_podcasts = db.query(Podcast).filter(Podcast.subscribed == True).all()
        details.append(f"\nResyncing {len(active_podcasts)} active subscriptions...")

        for pod in active_podcasts:
            pod.abs_id = None
            db.commit()

            polarr_ext = abs_client.base_url  # fallback
            proxy_feed_url = f"{polarr_ext}/feed/{pod.id}"
            new_abs_id = abs_client.create_podcast(proxy_feed_url)
            if new_abs_id:
                pod.abs_id = new_abs_id
                db.commit()
                details.append(f"Synced '{pod.title}' -> ABS ID: {new_abs_id}")
            else:
                details.append(f"Failed to sync '{pod.title}' to ABS.")

        if log_entry:
            log_entry.status = "success"
            log_entry.finished_at = datetime.utcnow()
            log_entry.details = "\n".join(details)
            db.commit()
        log_system_event("INFO", "Sync", f"Full ABS resync completed ({len(active_podcasts)} podcasts)")
    except Exception as e:
        if log_entry:
            log_entry.status = "error"
            log_entry.finished_at = datetime.utcnow()
            log_entry.details = "\n".join(details) + f"\n\nError: {e}"
            db.commit()
        log_system_event("ERROR", "Sync", f"Full resync failed: {e}")
    finally:
        db.close()
