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
    Base.metadata.create_all(bind=engine)
    # Check if podcasts table needs artwork_url column
    try:
        with engine.connect() as conn:
            if engine.dialect.name == "sqlite":
                result = conn.execute(text("PRAGMA table_info(podcasts)"))
                columns = [row[1] for row in result.fetchall()]
                if columns and "artwork_url" not in columns:
                    conn.execute(text("ALTER TABLE podcasts ADD COLUMN artwork_url VARCHAR"))
                    conn.commit()
    except Exception as e:
        print(f"DB migration notice: {e}")


