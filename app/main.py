import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Query, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy import or_, desc

from .database import engine, get_db, init_db
from .models import Podcast, PlayHistory
from .core.logger import log_system_event
from .core.auth import is_authenticated
from .services.sync_service import sync_abs_progress_loop, check_new_episodes_loop

from .routes import auth, podcasts, webhooks, feeds, discover, history, settings, system_logs

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize database tables and columns
    init_db()
    
    # Load config into abs_client
    from .database import SessionLocal
    from .services.abs_client import abs_client
    with SessionLocal() as db:
        abs_client.reload_config(db)
        
    log_system_event("INFO", "System", "Polarr application starting up")
    
    # Start background synchronization loops
    progress_task = asyncio.create_task(sync_abs_progress_loop())
    check_task = asyncio.create_task(check_new_episodes_loop())
    
    yield
    
    # Shutdown
    progress_task.cancel()
    check_task.cancel()
    log_system_event("INFO", "System", "Polarr application shutting down")

app = FastAPI(title="Polarr", version="2.0", lifespan=lifespan)
templates = Jinja2Templates(directory="app/templates")

# Context processor for Jinja2 templates (auth state, current path)
@app.middleware("http")
async def add_auth_context(request: Request, call_next):
    # Pass authenticated state down
    request.state.is_authenticated = is_authenticated(request)
    response = await call_next(request)
    return response

# Mount pre-compiled static assets
app.mount("/static", StaticFiles(directory="app/static"), name="static")

# Live search endpoint (accessible globally for the topbar search input)
@app.get("/api/search")
def search(q: str = Query("", min_length=1), db: Session = Depends(get_db)):
    """Live search endpoint returning matching podcasts and episodes."""
    term = f"%{q}%"
    podcasts_list = db.query(Podcast).filter(
        or_(
            Podcast.title.ilike(term),
            Podcast.feed_url.ilike(term),
        )
    ).limit(6).all()

    episodes_list = db.query(PlayHistory).filter(
        PlayHistory.episode_title.ilike(term)
    ).order_by(desc(PlayHistory.played_at)).limit(6).all()

    return JSONResponse({
        "podcasts": [
            {"id": p.id, "title": p.title, "subscribed": p.subscribed}
            for p in podcasts_list
        ],
        "episodes": [
            {
                "podcast_id": e.podcast_id,
                "podcast_title": e.podcast.title if e.podcast else "Unknown",
                "episode_title": e.episode_title,
                "played_at": e.played_at.strftime("%Y-%m-%d") if e.played_at else None,
            }
            for e in episodes_list
        ],
    })

# Register Modular Routers
app.include_router(auth.router)
app.include_router(podcasts.router)
app.include_router(webhooks.router)
app.include_router(feeds.router)
app.include_router(discover.router)
app.include_router(history.router)
app.include_router(settings.router)
app.include_router(system_logs.router)
