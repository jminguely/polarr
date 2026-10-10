import os
import secrets
from pathlib import Path

# Load .env file from project root if present
_env_path = Path(__file__).resolve().parent.parent.parent / ".env"
if _env_path.exists():
    try:
        with open(_env_path, "r", encoding="utf-8") as _f:
            for _line in _f:
                _line = _line.strip()
                if not _line or _line.startswith("#") or "=" not in _line:
                    continue
                _k, _v = _line.split("=", 1)
                _k = _k.strip()
                _v = _v.strip().strip("'\"")
                if _k and _k not in os.environ:
                    os.environ[_k] = _v
    except Exception:
        pass

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///data/polarr.db")



PODCASTINDEX_API_KEY = os.getenv("PODCASTINDEX_API_KEY", "")
PODCASTINDEX_API_SECRET = os.getenv("PODCASTINDEX_API_SECRET", "")

AUTH_ENABLED = os.getenv("AUTH_ENABLED", "false").lower() in ("true", "1", "yes")
AUTH_PROTECT_FEEDS = os.getenv("AUTH_PROTECT_FEEDS", "false").lower() in ("true", "1", "yes")
AUTH_USERNAME = os.getenv("AUTH_USERNAME", "admin")
AUTH_PASSWORD = os.getenv("AUTH_PASSWORD", "polarr123")
AUTH_POLARR_API_KEY = os.getenv("POLARR_API_KEY", secrets.token_hex(16))
POLARR_API_KEY = AUTH_POLARR_API_KEY
_secret_file = Path(__file__).resolve().parent.parent.parent / "data" / ".session_secret"
if "SESSION_SECRET_KEY" in os.environ:
    SESSION_SECRET_KEY = os.environ["SESSION_SECRET_KEY"]
elif _secret_file.exists():
    try:
        SESSION_SECRET_KEY = _secret_file.read_text(encoding="utf-8").strip()
    except Exception:
        SESSION_SECRET_KEY = secrets.token_hex(32)
else:
    SESSION_SECRET_KEY = secrets.token_hex(32)
    try:
        _secret_file.parent.mkdir(parents=True, exist_ok=True)
        _secret_file.write_text(SESSION_SECRET_KEY, encoding="utf-8")
    except Exception:
        pass

PROXY_FEED_CACHE_TTL = int(os.getenv("PROXY_FEED_CACHE_TTL", "180")) # 3 minutes
FEED_CACHE_TTL = int(os.getenv("FEED_CACHE_TTL", "300"))             # 5 minutes
POLARR_EXTERNAL_URL = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
