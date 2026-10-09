import os
import secrets

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///data/polarr.db")

ABS_URL = os.getenv("ABS_URL", "http://totoro:13378/audiobookshelf").rstrip("/")
ABS_TOKEN = os.getenv("ABS_TOKEN", "")
ABS_LIBRARY_ID = os.getenv("ABS_LIBRARY_ID", "")
ABS_FOLDER_ID = os.getenv("ABS_FOLDER_ID", "")

PODCASTINDEX_API_KEY = os.getenv("PODCASTINDEX_API_KEY", "")
PODCASTINDEX_API_SECRET = os.getenv("PODCASTINDEX_API_SECRET", "")

AUTH_ENABLED = os.getenv("AUTH_ENABLED", "false").lower() in ("true", "1", "yes")
AUTH_USERNAME = os.getenv("AUTH_USERNAME", "admin")
AUTH_PASSWORD = os.getenv("AUTH_PASSWORD", "polarr123")
POLARR_API_KEY = os.getenv("POLARR_API_KEY", secrets.token_hex(16))
SESSION_SECRET_KEY = os.getenv("SESSION_SECRET_KEY", secrets.token_hex(32))

PROXY_FEED_CACHE_TTL = int(os.getenv("PROXY_FEED_CACHE_TTL", "180")) # 3 minutes
FEED_CACHE_TTL = int(os.getenv("FEED_CACHE_TTL", "300"))             # 5 minutes
