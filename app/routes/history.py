from fastapi import APIRouter, Request, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc
from ..database import get_db
from ..models import PlayHistory
from ..core.auth import require_auth
from ..core.logger import log_system_event
from .podcasts import flash_redirect

router = APIRouter(tags=["history"], dependencies=[Depends(require_auth)])

@router.get("/history", response_class=HTMLResponse)
def history_page(request: Request, db: Session = Depends(get_db)):
    from ..main import templates
    history = db.query(PlayHistory).order_by(desc(PlayHistory.played_at)).limit(100).all()

    return templates.TemplateResponse(request=request, name="history.html", context={
        "request": request,
        "history": history
    })

@router.post("/history/{history_id}/delete")
def delete_history_item(history_id: int, db: Session = Depends(get_db)):
    item = db.query(PlayHistory).filter(PlayHistory.id == history_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="History entry not found")

    title = item.episode_title or "Episode"
    db.delete(item)
    db.commit()
    log_system_event("INFO", "Sync", f"Deleted history entry '{title}'")
    return flash_redirect("/history", f"Removed '{title}' from history.")
