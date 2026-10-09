import asyncio
from fastapi import APIRouter, Request, BackgroundTasks, Depends
from sqlalchemy.orm import Session
from ..database import get_db
from ..models import Podcast
from ..core.auth import get_auth_settings
from ..core.logger import log_system_event
from ..services.abs_client import abs_client
from ..services.sync_service import handle_episode_listened

router = APIRouter(tags=["webhooks"])

@router.post("/webhook/abs")
async def abs_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """Receives and processes playback webhooks from Audiobookshelf."""
    # Check API key if auth is configured
    auth_settings = get_auth_settings(db)
    if auth_settings["auth_enabled"]:
        key = request.headers.get("X-Api-Key") or request.query_params.get("apikey")
        if key != auth_settings["api_key"]:
            log_system_event("WARN", "Webhook", "Rejected ABS webhook: invalid API key")
            return {"status": "unauthorized"}

    try:
        payload = await request.json()
    except Exception as e:
        log_system_event("WARN", "Webhook", f"Invalid webhook JSON payload: {e}")
        return {"status": "bad_request"}

    event_name = payload.get("event")
    log_system_event("DEBUG", "Webhook", f"Received ABS webhook event: '{event_name}'", str(payload))

    # We process item_finished and finished progress_update events
    if event_name not in ["item_finished", "progress_update"]:
        return {"status": "ignored", "reason": f"unhandled_event_{event_name}"}

    is_finished = payload.get("progress", {}).get("isFinished", False)
    if event_name == "progress_update" and not is_finished:
        return {"status": "ignored", "reason": "not_finished"}

    library_item_id = payload.get("libraryItemId")
    episode_id = payload.get("episodeId")

    if not library_item_id or not episode_id:
        log_system_event("WARN", "Webhook", "Webhook payload missing libraryItemId or episodeId")
        return {"status": "ignored", "reason": "missing_ids"}

    podcast = db.query(Podcast).filter(Podcast.abs_id == library_item_id).first()
    if not podcast:
        log_system_event("WARN", "Webhook", f"No Polarr subscription matches ABS library item ID '{library_item_id}'")
        return {"status": "ignored", "reason": "podcast_not_found"}

    # Fetch episode info from ABS to resolve RSS GUID and episode title
    ep_data = await asyncio.to_thread(abs_client.get_episode, library_item_id, episode_id)
    guid = ep_data.get("guid", episode_id) if ep_data else episode_id
    title = ep_data.get("title", f"Episode {episode_id}") if ep_data else f"Episode {episode_id}"

    # Execute full listen state sync + ABS file cleanup + ABS checknew auto-download
    background_tasks.add_task(
        handle_episode_listened,
        podcast=podcast,
        episode_guid=guid,
        episode_title=title,
        abs_episode_id=episode_id
    )

    log_system_event("INFO", "Webhook", f"Processed finish event for '{title}' on '{podcast.title}'")
    return {"status": "success", "action": "logged_cleaned_and_synced"}
