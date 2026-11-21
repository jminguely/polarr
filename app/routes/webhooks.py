from fastapi import APIRouter, Request, Depends
from sqlalchemy.orm import Session
from ..database import get_db
from ..core.logger import log_system_event

router = APIRouter(tags=["webhooks"])

@router.post("/webhook/abs")
async def abs_webhook(request: Request, db: Session = Depends(get_db)):
    """Deprecated: Audiobookshelf webhook kept as safe no-op."""
    log_system_event("DEBUG", "Webhook", "Received legacy ABS webhook call; ignored as standalone player mode is active.")
    return {"status": "deprecated", "message": "Audiobookshelf webhook is deprecated in Polarr standalone mode"}
