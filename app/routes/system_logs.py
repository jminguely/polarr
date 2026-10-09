from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from ..database import get_db
from ..models import SystemLog
from ..core.auth import require_auth
from ..core.logger import get_system_logs, clear_system_logs

router = APIRouter(prefix="/api/system-logs", tags=["system-logs"], dependencies=[Depends(require_auth)])

@router.get("", response_class=JSONResponse)
def list_logs(
    level: str = Query("ALL"),
    source: str = Query("ALL"),
    q: str = Query(""),
    limit: int = Query(50, le=200),
    offset: int = Query(0),
    db: Session = Depends(get_db)
):
    logs, total = get_system_logs(
        db,
        level=level if level != "ALL" else None,
        source=source if source != "ALL" else None,
        query=q if q.strip() else None,
        limit=limit,
        offset=offset
    )

    data = []
    for l in logs:
        data.append({
            "id": l.id,
            "timestamp": l.timestamp.strftime("%Y-%m-%d %H:%M:%S"),
            "level": l.level,
            "source": l.source,
            "message": l.message,
            "has_details": bool(l.details),
        })

    return {
        "logs": data,
        "total": total,
        "offset": offset,
        "limit": limit
    }

@router.get("/{log_id}", response_class=JSONResponse)
def get_log_details(log_id: int, db: Session = Depends(get_db)):
    log = db.query(SystemLog).filter(SystemLog.id == log_id).first()
    if not log:
        raise HTTPException(status_code=404, detail="Log entry not found")

    return {
        "id": log.id,
        "timestamp": log.timestamp.strftime("%Y-%m-%d %H:%M:%S"),
        "level": log.level,
        "source": log.source,
        "message": log.message,
        "details": log.details or ""
    }

@router.post("/clear", response_class=JSONResponse)
def clear_logs(db: Session = Depends(get_db)):
    clear_system_logs(db)
    return {"status": "ok", "message": "All system logs cleared."}
