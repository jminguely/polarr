import json
import traceback
from datetime import datetime
from sqlalchemy import desc
from sqlalchemy.orm import Session
from ..database import SessionLocal
from ..models import SystemLog

MAX_LOGS_RETENTION = 1000

def log_system_event(level: str, source: str, message: str, details: str = None):
    """
    Persist structured log event to SQLite SystemLog table and output to stdout.
    Automatically prunes entries beyond MAX_LOGS_RETENTION.
    """
    level_normalized = level.upper()
    print(f"[{datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')}] [{level_normalized}] [{source}] {message}")
    
    db: Session = SessionLocal()
    try:
        new_log = SystemLog(
            timestamp=datetime.utcnow(),
            level=level_normalized,
            source=source,
            message=message,
            details=details
        )
        db.add(new_log)
        db.commit()

        # Prune oldest if exceeding retention
        count = db.query(SystemLog).count()
        if count > MAX_LOGS_RETENTION:
            excess = count - MAX_LOGS_RETENTION
            oldest_ids = [
                row[0] for row in db.query(SystemLog.id)
                .order_by(SystemLog.id.asc())
                .limit(excess)
                .all()
            ]
            if oldest_ids:
                db.query(SystemLog).filter(SystemLog.id.in_(oldest_ids)).delete(synchronize_session=False)
                db.commit()
    except Exception as e:
        print(f"Failed to record SystemLog: {e}")
    finally:
        db.close()


def get_system_logs(
    db: Session,
    level: str = None,
    source: str = None,
    query: str = None,
    limit: int = 100,
    offset: int = 0
):
    """Retrieve filtered system logs from DB."""
    q = db.query(SystemLog)
    if level and level.upper() != "ALL":
        q = q.filter(SystemLog.level == level.upper())
    if source and source.upper() != "ALL":
        q = q.filter(SystemLog.source == source)
    if query:
        pattern = f"%{query}%"
        q = q.filter((SystemLog.message.ilike(pattern)) | (SystemLog.details.ilike(pattern)))
    
    total = q.count()
    logs = q.order_by(desc(SystemLog.timestamp)).offset(offset).limit(limit).all()
    return logs, total


def clear_system_logs(db: Session):
    """Clear all entries from system_logs."""
    db.query(SystemLog).delete()
    db.commit()
