from fastapi import APIRouter, Request, Response, HTTPException, Depends
from sqlalchemy.orm import Session
from ..database import get_db
from ..models import Podcast, PlayHistory
from ..core.auth import get_auth_settings
from ..core.logger import log_system_event
from ..services.feed_parser import generate_proxy_feed_xml

router = APIRouter(tags=["feeds"])

@router.get("/feed/{podcast_id}")
def get_proxy_feed(podcast_id: int, request: Request, db: Session = Depends(get_db)):
    """Serve the dynamically filtered proxy RSS feed for a podcast."""
    # Check auth / API key if feed protection is explicitly enabled
    auth_settings = get_auth_settings(db)
    if auth_settings.get("auth_protect_feeds"):
        key = request.headers.get("X-Api-Key") or request.query_params.get("apikey")
        if key != auth_settings["api_key"]:
            from ..core.auth import is_authenticated
            if not is_authenticated(request, db):
                log_system_event("WARN", "Feed", f"Unauthorized feed access request for podcast {podcast_id}")
                raise HTTPException(status_code=401, detail="Unauthorized feed access: missing or invalid API Key")

    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")

    histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
    played_guids = {str(h.episode_guid).strip() for h in histories if h.episode_guid}

    xml_bytes = generate_proxy_feed_xml(podcast, played_guids)
    if xml_bytes is None:
        return Response("Error fetching or parsing upstream RSS feed", status_code=502)

    return Response(content=xml_bytes, media_type="application/rss+xml")
