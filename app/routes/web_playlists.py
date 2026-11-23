from fastapi import APIRouter, Request, Depends, HTTPException, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc
import uuid
from datetime import datetime

from ..database import get_db
from ..models import Playlist, PlaylistEpisode, Podcast
from ..core.auth import require_auth
from ..core.logger import log_system_event
from .podcasts import flash_redirect

router = APIRouter(tags=["web_playlists"], dependencies=[Depends(require_auth)])


@router.get("/playlists", response_class=HTMLResponse)
def playlists_page(request: Request, db: Session = Depends(get_db)):
    from ..main import templates
    playlists = db.query(Playlist).order_by(desc(Playlist.updated_at)).all()
    podcasts = db.query(Podcast).filter(Podcast.subscribed == True).order_by(Podcast.title.asc()).all()

    return templates.TemplateResponse(request=request, name="playlists.html", context={
        "request": request,
        "playlists": playlists,
        "podcasts": podcasts
    })


@router.post("/playlists/create")
def create_playlist_web(
    title: str = Form(...),
    description: str = Form(""),
    is_smart: bool = Form(False),
    auto_remove_finished: bool = Form(False),
    db: Session = Depends(get_db)
):
    pl = Playlist(
        uuid=str(uuid.uuid4()),
        title=title.strip(),
        description=description.strip() if description else None,
        is_smart=is_smart,
        auto_remove_finished=auto_remove_finished,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow()
    )
    db.add(pl)
    db.commit()
    log_system_event("INFO", "System", f"Created playlist '{pl.title}' via Web UI")
    return flash_redirect("/playlists", f"Playlist '{pl.title}' created.")


@router.post("/playlists/{playlist_uuid}/delete")
def delete_playlist_web(playlist_uuid: str, db: Session = Depends(get_db)):
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    title = pl.title
    db.delete(pl)
    db.commit()
    log_system_event("INFO", "System", f"Deleted playlist '{title}'")
    return flash_redirect("/playlists", f"Playlist '{title}' deleted.")


@router.post("/playlists/{playlist_uuid}/episodes/{episode_guid}/delete")
def remove_playlist_episode_web(playlist_uuid: str, episode_guid: str, db: Session = Depends(get_db)):
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    ep = db.query(PlaylistEpisode).filter(
        PlaylistEpisode.playlist_id == pl.id,
        PlaylistEpisode.episode_guid == episode_guid
    ).first()

    if ep:
        db.delete(ep)
        pl.updated_at = datetime.utcnow()
        db.commit()

    return flash_redirect("/playlists", f"Episode removed from '{pl.title}'.")
