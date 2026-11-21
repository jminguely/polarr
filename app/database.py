from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import declarative_base, sessionmaker
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///data/polarr.db")
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False, "timeout": 15})

@event.listens_for(Engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    if DATABASE_URL.startswith("sqlite"):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db():
    from . import models  # Ensure all models are registered
    Base.metadata.create_all(bind=engine)
    
    # Run lightweight schema migrations for existing SQLite databases
    try:
        with engine.connect() as conn:
            if engine.dialect.name == "sqlite":
                # Check podcasts columns
                pod_cols = [row[1] for row in conn.execute(text("PRAGMA table_info(podcasts)")).fetchall()]
                if pod_cols and "artwork_url" not in pod_cols:
                    conn.execute(text("ALTER TABLE podcasts ADD COLUMN artwork_url VARCHAR"))
                    conn.commit()

                # Check play_history columns
                hist_cols = [row[1] for row in conn.execute(text("PRAGMA table_info(play_history)")).fetchall()]
                if hist_cols:
                    columns_to_add = [
                        ("completion_type", "VARCHAR DEFAULT 'finished'"),
                        ("episode_duration_secs", "INTEGER"),
                        ("time_listened_secs", "INTEGER"),
                        ("rating", "INTEGER"),
                        ("personal_note", "TEXT"),
                        ("created_at", "DATETIME"),
                        ("updated_at", "DATETIME"),
                    ]
                    for col_name, col_type in columns_to_add:
                        if col_name not in hist_cols:
                            conn.execute(text(f"ALTER TABLE play_history ADD COLUMN {col_name} {col_type}"))
                            conn.commit()

                    # Normalize any records where is_skipped = 1 but completion_type != 'skipped'
                    conn.execute(text("UPDATE play_history SET completion_type = 'skipped' WHERE is_skipped = 1 AND completion_type != 'skipped'"))
                    conn.commit()

                # Check device_syncs columns
                dev_cols = [row[1] for row in conn.execute(text("PRAGMA table_info(device_syncs)")).fetchall()]
                if dev_cols:
                    if "device_name" not in dev_cols:
                        conn.execute(text("ALTER TABLE device_syncs ADD COLUMN device_name VARCHAR"))
                    if "last_sync_at" not in dev_cols:
                        conn.execute(text("ALTER TABLE device_syncs ADD COLUMN last_sync_at DATETIME"))
                    if "sync_token" not in dev_cols:
                        conn.execute(text("ALTER TABLE device_syncs ADD COLUMN sync_token VARCHAR"))
                    conn.commit()
    except Exception as e:
        print(f"DB migration notice: {e}")
