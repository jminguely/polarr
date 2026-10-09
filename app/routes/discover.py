from fastapi import APIRouter, Request, Depends, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from ..database import get_db
from ..models import Podcast, AppSetting
from ..core.auth import require_auth
from ..core.logger import log_system_event
from ..services.podcastindex import search_podcasts
from .podcasts import flash_redirect

router = APIRouter(tags=["discover"], dependencies=[Depends(require_auth)])

@router.get("/discover", response_class=HTMLResponse)
def discover_page(request: Request, q: str = "", db: Session = Depends(get_db)):
    from ..main import templates
    results = []
    if q.strip():
        results = search_podcasts(q.strip())
        log_system_event("INFO", "Discover", f"Searched for '{q.strip()}', found {len(results)} results")

    return templates.TemplateResponse(request=request, name="discover.html", context={
        "request": request,
        "query": q,
        "results": results,
    })

@router.post("/discover/add")
def discover_add(
    request: Request,
    title: str = Form(...),
    feed_url: str = Form(...),
    artwork_url: str = Form(None),
    db: Session = Depends(get_db)
):
    existing = db.query(Podcast).filter(Podcast.feed_url == feed_url).first()
    if existing:
        return flash_redirect(f"/podcast/{existing.id}", "Podcast already exists in your library.")

    sync_order_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_order").first()
    sync_limit_setting = db.query(AppSetting).filter(AppSetting.key == "default_sync_limit").first()

    default_sync_order = sync_order_setting.value if sync_order_setting else "oldest_first"
    default_sync_limit = int(sync_limit_setting.value) if sync_limit_setting else 5

    pod = Podcast(
        title=title,
        feed_url=feed_url,
        artwork_url=artwork_url or None,
        subscribed=False,
        sync_order=default_sync_order,
        sync_limit=default_sync_limit
    )
    db.add(pod)
    db.commit()
    db.refresh(pod)

    log_system_event("INFO", "Discover", f"Added '{title}' to library from Discover")
    return flash_redirect(f"/podcast/{pod.id}", f"'{title}' added. You can now configure it and subscribe.")
