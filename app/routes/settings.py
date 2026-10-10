import secrets
from fastapi import APIRouter, Request, Depends, Form, BackgroundTasks
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc
from ..database import get_db
from ..models import AppSetting, SyncLog, SystemLog
from ..core.auth import require_auth, get_auth_settings
from ..core.logger import log_system_event, get_system_logs
from ..services.sync_service import perform_full_sync
from .podcasts import flash_redirect

router = APIRouter(tags=["settings"], dependencies=[Depends(require_auth)])

@router.get("/settings", response_class=HTMLResponse)
def settings_page(request: Request, db: Session = Depends(get_db)):
    from ..main import templates

    sync_order_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_order").first()
    sync_limit_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_limit").first()
    check_interval_setting = db.query(AppSetting).filter(AppSetting.key == "episode_check_interval").first()

    default_sync_order = sync_order_setting.value if sync_order_setting else "oldest_first"
    default_sync_limit = int(sync_limit_setting.value) if sync_limit_setting else 5
    episode_check_interval = int(check_interval_setting.value) if check_interval_setting else 60

    auth_info = get_auth_settings(db)
    
    # Audiobookshelf Settings
    abs_url_setting = db.query(AppSetting).filter(AppSetting.key == "abs_url").first()
    abs_token_setting = db.query(AppSetting).filter(AppSetting.key == "abs_token").first()
    abs_lib_setting = db.query(AppSetting).filter(AppSetting.key == "abs_library_id").first()
    abs_folder_setting = db.query(AppSetting).filter(AppSetting.key == "abs_folder_id").first()
    
    abs_settings = {
        "url": abs_url_setting.value if abs_url_setting else "",
        "token": abs_token_setting.value if abs_token_setting else "",
        "library_id": abs_lib_setting.value if abs_lib_setting else "",
        "folder_id": abs_folder_setting.value if abs_folder_setting else "",
    }

    sync_logs = db.query(SyncLog).order_by(desc(SyncLog.started_at)).limit(15).all()
    recent_system_logs, total_logs = get_system_logs(db, limit=50)

    return templates.TemplateResponse(request=request, name="settings.html", context={
        "request": request,
        "default_sync_order": default_sync_order,
        "default_sync_limit": default_sync_limit,
        "episode_check_interval": episode_check_interval,
        "auth_settings": auth_info,
        "abs_settings": abs_settings,
        "sync_logs": sync_logs,
        "system_logs": recent_system_logs,
        "total_logs": total_logs,
    })

@router.post("/settings")
def save_settings(
    request: Request,
    default_sync_order: str = Form("oldest_first"),
    default_sync_limit: int = Form(5),
    episode_check_interval: int = Form(60),
    auth_enabled: str = Form("false"),
    auth_protect_feeds: str = Form("false"),
    auth_username: str = Form("admin"),
    auth_password: str = Form(""),
    abs_url: str = Form(""),
    abs_token: str = Form(""),
    abs_library_id: str = Form(""),
    abs_folder_id: str = Form(""),
    db: Session = Depends(get_db)
):
    episode_check_interval = max(30, min(episode_check_interval, 1440))
    is_auth_enabled = "true" if auth_enabled.lower() in ("true", "1", "on") else "false"
    is_protect_feeds = "true" if auth_protect_feeds.lower() in ("true", "1", "on") else "false"

    settings_to_update = [
        ("default_sync_order", default_sync_order),
        ("default_sync_limit", str(default_sync_limit)),
        ("episode_check_interval", str(episode_check_interval)),
        ("auth_enabled", is_auth_enabled),
        ("auth_protect_feeds", is_protect_feeds),
        ("auth_username", auth_username.strip() or "admin"),
        ("abs_url", abs_url.strip()),
        ("abs_token", abs_token.strip()),
        ("abs_library_id", abs_library_id.strip()),
        ("abs_folder_id", abs_folder_id.strip()),
    ]

    if auth_password.strip():
        settings_to_update.append(("auth_password", auth_password.strip()))

    for key, value in settings_to_update:
        setting = db.query(AppSetting).filter(AppSetting.key == key).first()
        if setting:
            setting.value = value
        else:
            db.add(AppSetting(key=key, value=value))

    db.commit()
    
    from ..services.abs_client import abs_client
    abs_client.reload_config(db)
    
    log_system_event("INFO", "Settings", "Updated application and security settings")
    return flash_redirect("/settings", "Settings saved successfully.")

@router.post("/settings/regenerate-api-key")
def regenerate_api_key(db: Session = Depends(get_db)):
    new_key = secrets.token_hex(16)
    setting = db.query(AppSetting).filter(AppSetting.key == "polarr_api_key").first()
    if setting:
        setting.value = new_key
    else:
        db.add(AppSetting(key="polarr_api_key", value=new_key))
    db.commit()
    log_system_event("INFO", "Auth", "Regenerated Polarr API Key")
    return flash_redirect("/settings", "API Key regenerated successfully.")

@router.post("/settings/check-new")
def trigger_check_new(background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    from ..services.abs_client import abs_client
    from ..models import Podcast

    if not abs_client.is_configured():
        return flash_redirect("/settings", "Audiobookshelf is not configured in .env", "error")

    subscribed = db.query(Podcast).filter(Podcast.subscribed == True, Podcast.abs_id.isnot(None)).all()
    new_log = SyncLog(status="running", details=f"Manual check for {len(subscribed)} podcasts started...")
    db.add(new_log)
    db.commit()

    def run_check():
        from ..database import SessionLocal
        local_db = SessionLocal()
        lines = []
        for pod in subscribed:
            abs_client.reset_media_check(pod.abs_id)
            ok = abs_client.checknew_podcast(pod.abs_id)
            lines.append(f"[{pod.title}] Check triggered: {'Success' if ok else 'Failed'}")
        
        log_rec = local_db.query(SyncLog).filter(SyncLog.id == new_log.id).first()
        if log_rec:
            from datetime import datetime
            log_rec.status = "success"
            log_rec.finished_at = datetime.utcnow()
            log_rec.details = "\n".join(lines)
            local_db.commit()
        local_db.close()

    background_tasks.add_task(run_check)
    return flash_redirect("/settings", "Manual episode check started.")

@router.post("/settings/sync-all")
def trigger_full_resync(background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    from ..services.abs_client import abs_client

    if not abs_client.is_configured():
        return flash_redirect("/settings", "Audiobookshelf is not configured in .env", "error")

    new_log = SyncLog(status="running", details="Starting complete library wipe and resync...")
    db.add(new_log)
    db.commit()

    background_tasks.add_task(perform_full_sync, new_log.id)
    return flash_redirect("/settings", "Full resync started in background.")

@router.post("/settings/sync-history-from-abs")
def trigger_sync_history_from_abs(background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    from ..services.abs_client import abs_client
    from ..services.sync_service import sync_and_repair_play_history

    if not abs_client.is_configured():
        return flash_redirect("/settings", "Audiobookshelf is not configured in .env", "error")

    new_log = SyncLog(status="running", details="Starting Playback History & Audiobookshelf reconciliation...")
    db.add(new_log)
    db.commit()

    background_tasks.add_task(sync_and_repair_play_history, new_log.id)
    return flash_redirect("/settings", "History reconciliation started in background.")

