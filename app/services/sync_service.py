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

        # If not found by GUID, check if a record exists by the same clean title
        if not existing and episode_title and not episode_title.startswith("Episode "):
            existing = db.query(PlayHistory).filter(
                PlayHistory.podcast_id == podcast.id,
                PlayHistory.episode_title == episode_title
            ).first()
            if existing and existing.episode_guid != clean_guid:
                existing.episode_guid = clean_guid
                db.commit()

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
            # Upgrade placeholder title if we have a better title now
            if episode_title and (not existing.episode_title or existing.episode_title.startswith("Episode ")):
                existing.episode_title = episode_title
                db.commit()
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

            from ..core.config import POLARR_EXTERNAL_URL
            polarr_ext = (POLARR_EXTERNAL_URL or "http://localhost:8080").rstrip("/")
            proxy_feed_url = f"{polarr_ext}/feed/{pod.id}"
            new_abs_id = abs_client.create_podcast(proxy_feed_url)
            if new_abs_id:
                pod.abs_id = new_abs_id
                db.commit()
                details.append(f"Synced '{pod.title}' -> ABS ID: {new_abs_id}")
            else:
                details.append(f"Failed to sync '{pod.title}' to ABS.")
            time.sleep(1)

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


def sync_and_repair_play_history(log_id: Optional[int] = None):
    """
    One-time / on-demand reconciliation of PlayHistory with Audiobookshelf and RSS feeds:
    1. Reconciles generic 'Episode <id>' titles by mapping ABS episode IDs to real RSS GUIDs and titles.
    2. Imports finished playback sessions and mediaProgress from ABS.
    3. Cleans duplicate records and clears proxy feed caches so all views update in lockstep.
    """
    import html, re
    import requests
    from .feed_parser import fetch_feed_episodes

    def norm_title(t):
        if not t:
            return ""
        t = html.unescape(t)
        t = t.replace('\xa0', ' ').replace('’', "'").replace('“', '"').replace('”', '"')
        return re.sub(r'\s+', ' ', t).strip().lower()

    db = SessionLocal()
    log_entry = db.query(SyncLog).filter(SyncLog.id == log_id).first() if log_id else None
    details = ["Starting Playback History & Audiobookshelf reconciliation..."]

    try:
        abs_episodes_map = {}
        if abs_client.is_configured():
            lib_res = requests.get(f"{abs_client.base_url}/api/libraries/{abs_client.library_id}/items?limit=0", headers=abs_client.headers, timeout=15)
            if lib_res.ok:
                items = lib_res.json().get("results", [])
                for it in items:
                    lib_id = it.get("id")
                    full_res = requests.get(f"{abs_client.base_url}/api/items/{lib_id}", headers=abs_client.headers, timeout=10)
                    if full_res.ok:
                        episodes = full_res.json().get("media", {}).get("episodes", [])
                        for ep in episodes:
                            eid = ep.get("id")
                            abs_episodes_map[(lib_id, eid)] = {
                                "guid": ep.get("guid") or eid,
                                "title": ep.get("title"),
                                "enclosure": ep.get("enclosure", {}).get("url") if ep.get("enclosure") else None
                            }

        details.append(f"Loaded {len(abs_episodes_map)} episode mappings from Audiobookshelf.")

        # Reconcile existing PlayHistory records
        podcasts = db.query(Podcast).filter(Podcast.subscribed == True).all()
        repaired_titles = 0
        repaired_guids = 0
        deduped_count = 0

        for pod in podcasts:
            histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == pod.id).all()
            if not histories:
                continue

            rss_eps, _ = fetch_feed_episodes(pod.feed_url)
            rss_by_guid = {ep["guid"].strip(): ep for ep in rss_eps}
            rss_by_norm_title = {norm_title(ep["title"]): ep for ep in rss_eps}
            rss_by_enclosure = {ep.get("enclosure_url"): ep for ep in rss_eps if ep.get("enclosure_url")}

            for h in histories:
                # A. Check ABS mapping
                if pod.abs_id and (pod.abs_id, h.episode_guid) in abs_episodes_map:
                    mapping = abs_episodes_map[(pod.abs_id, h.episode_guid)]
                    if mapping.get("guid") and mapping["guid"] != h.episode_guid:
                        h.episode_guid = mapping["guid"]
                        repaired_guids += 1
                    if mapping.get("title") and (not h.episode_title or h.episode_title.startswith("Episode ")):
                        h.episode_title = mapping["title"]
                        repaired_titles += 1

                clean_guid = str(h.episode_guid).strip()

                # B. Check RSS match by GUID
                if clean_guid in rss_by_guid:
                    real_ep = rss_by_guid[clean_guid]
                    if not h.episode_title or h.episode_title.startswith("Episode "):
                        h.episode_title = real_ep["title"]
                        repaired_titles += 1

                # C. Check RSS match by Enclosure URL
                if clean_guid in rss_by_enclosure:
                    real_ep = rss_by_enclosure[clean_guid]
                    if h.episode_guid != real_ep["guid"]:
                        h.episode_guid = real_ep["guid"]
                        repaired_guids += 1
                    if not h.episode_title or h.episode_title.startswith("Episode "):
                        h.episode_title = real_ep["title"]
                        repaired_titles += 1

                # D. Check RSS match by Title
                if h.episode_title and not h.episode_title.startswith("Episode "):
                    nt = norm_title(h.episode_title)
                    if nt in rss_by_norm_title:
                        real_ep = rss_by_norm_title[nt]
                        if h.episode_guid != real_ep["guid"]:
                            h.episode_guid = real_ep["guid"]
                            repaired_guids += 1
                        if h.episode_title != real_ep["title"]:
                            h.episode_title = real_ep["title"]
                            repaired_titles += 1

            # Deduplicate history records for this podcast
            seen_guids = set()
            for h in sorted(histories, key=lambda x: x.played_at or datetime.min, reverse=True):
                guid_key = str(h.episode_guid).strip()
                if guid_key in seen_guids:
                    db.delete(h)
                    deduped_count += 1
                else:
                    seen_guids.add(guid_key)

        details.append(f"Reconciled existing records: {repaired_titles} titles updated, {repaired_guids} GUIDs aligned, {deduped_count} duplicates removed.")

        # Import finished sessions and mediaProgress from ABS
        imported_count = 0
        if abs_client.is_configured():
            r_sess = requests.get(f"{abs_client.base_url}/api/me/listening-sessions?limit=100", headers=abs_client.headers, timeout=12)
            if r_sess.ok:
                for s in r_sess.json().get("sessions", []):
                    lib_id = s.get("libraryItemId")
                    display_title = s.get("displayTitle")
                    pod = db.query(Podcast).filter(Podcast.abs_id == lib_id).first()
                    if pod and display_title:
                        rss_eps, _ = fetch_feed_episodes(pod.feed_url)
                        target_guid = s.get("episodeId")
                        target_title = display_title
                        norm_disp = norm_title(display_title)
                        for rep in rss_eps:
                            norm_rep = norm_title(rep["title"])
                            if norm_disp == norm_rep or norm_disp in norm_rep or norm_rep in norm_disp:
                                target_guid = rep["guid"]
                                target_title = rep["title"]
                                break
                        
                        exists = db.query(PlayHistory).filter(
                            PlayHistory.podcast_id == pod.id,
                            (PlayHistory.episode_guid == target_guid) | (PlayHistory.episode_title == target_title)
                        ).first()
                        if not exists:
                            ts = s.get("updatedAt") / 1000 if s.get("updatedAt") else None
                            dt = datetime.fromtimestamp(ts) if ts else datetime.utcnow()
                            db.add(PlayHistory(
                                podcast_id=pod.id,
                                episode_guid=target_guid,
                                episode_title=target_title,
                                played_at=dt
                            ))
                            imported_count += 1

            # Check mediaProgress
            r_me = requests.get(f"{abs_client.base_url}/api/me", headers=abs_client.headers, timeout=12)
            if r_me.ok:
                for mp in r_me.json().get("mediaProgress", []):
                    if mp.get("isFinished") or mp.get("progress", 0) > 0.95:
                        lib_id = mp.get("libraryItemId")
                        ep_id = mp.get("episodeId")
                        pod = db.query(Podcast).filter(Podcast.abs_id == lib_id).first()
                        if pod and ep_id:
                            ep_data = abs_client.get_episode(lib_id, ep_id)
                            eguid = ep_data.get("guid", ep_id) if ep_data else ep_id
                            etitle = ep_data.get("title", f"Episode {ep_id}") if ep_data else f"Episode {ep_id}"
                            exists = db.query(PlayHistory).filter(
                                PlayHistory.podcast_id == pod.id,
                                (PlayHistory.episode_guid == eguid) | (PlayHistory.episode_title == etitle)
                            ).first()
                            if not exists:
                                db.add(PlayHistory(
                                    podcast_id=pod.id,
                                    episode_guid=eguid,
                                    episode_title=etitle,
                                    played_at=datetime.utcnow()
                                ))
                                imported_count += 1

        details.append(f"Imported {imported_count} finished playback records from Audiobookshelf.")
        db.commit()
        clear_proxy_cache()

        if log_entry:
            log_entry.status = "success"
            log_entry.finished_at = datetime.utcnow()
            log_entry.details = "\n".join(details)
            db.commit()

        log_system_event("INFO", "Sync", f"PlayHistory reconciliation completed ({repaired_titles} titles, {repaired_guids} GUIDs, {imported_count} imported)")
    except Exception as e:
        if log_entry:
            log_entry.status = "error"
            log_entry.finished_at = datetime.utcnow()
            log_entry.details = "\n".join(details) + f"\n\nError: {e}"
            db.commit()
        log_system_event("ERROR", "Sync", f"PlayHistory reconciliation failed: {e}")
    finally:
        db.close()

