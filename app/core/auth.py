import hmac
import hashlib
import time
from typing import Optional
from fastapi import Request, HTTPException, Depends
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session
from .config import (
    AUTH_ENABLED as ENV_AUTH_ENABLED,
    AUTH_USERNAME as ENV_AUTH_USERNAME,
    AUTH_PASSWORD as ENV_AUTH_PASSWORD,
    POLARR_API_KEY as ENV_POLARR_API_KEY,
    SESSION_SECRET_KEY,
)
from ..database import get_db
from ..models import AppSetting
from .logger import log_system_event

COOKIE_NAME = "polarr_session"
SESSION_MAX_AGE = 30 * 24 * 3600  # 30 days


def get_auth_settings(db: Session = None):
    """Get active auth settings, checking DB first then falling back to env."""
    auth_enabled = ENV_AUTH_ENABLED
    username = ENV_AUTH_USERNAME
    password = ENV_AUTH_PASSWORD
    api_key = ENV_POLARR_API_KEY

    if db:
        try:
            ae = db.query(AppSetting).filter(AppSetting.key == "auth_enabled").first()
            if ae:
                auth_enabled = ae.value.lower() in ("true", "1", "yes")
            u = db.query(AppSetting).filter(AppSetting.key == "auth_username").first()
            if u:
                username = u.value
            p = db.query(AppSetting).filter(AppSetting.key == "auth_password").first()
            if p:
                password = p.value
            k = db.query(AppSetting).filter(AppSetting.key == "polarr_api_key").first()
            if k:
                api_key = k.value
        except Exception:
            pass

    return {
        "auth_enabled": auth_enabled,
        "username": username,
        "password": password,
        "api_key": api_key,
    }


def _sign_data(data: str) -> str:
    h = hmac.new(SESSION_SECRET_KEY.encode(), data.encode(), hashlib.sha256).hexdigest()
    return f"{data}:{h}"


def _verify_signature(signed_data: str) -> Optional[str]:
    try:
        parts = signed_data.rsplit(":", 1)
        if len(parts) != 2:
            return None
        data, sig = parts
        expected = hmac.new(SESSION_SECRET_KEY.encode(), data.encode(), hashlib.sha256).hexdigest()
        if hmac.compare_digest(sig, expected):
            return data
    except Exception:
        pass
    return None


def create_session_cookie(response, username: str):
    timestamp = str(int(time.time()))
    payload = f"{username}|{timestamp}"
    signed = _sign_data(payload)
    response.set_cookie(
        key=COOKIE_NAME,
        value=signed,
        max_age=SESSION_MAX_AGE,
        httponly=True,
        samesite="lax",
    )


def clear_session_cookie(response):
    response.delete_cookie(key=COOKIE_NAME)


def is_authenticated(request: Request, db: Session = None) -> bool:
    settings = get_auth_settings(db)
    if not settings["auth_enabled"]:
        return True

    cookie = request.cookies.get(COOKIE_NAME)
    if not cookie:
        return False

    verified = _verify_signature(cookie)
    if not verified:
        return False

    try:
        username, ts = verified.split("|", 1)
        # Check session age
        if time.time() - int(ts) > SESSION_MAX_AGE:
            return False
        return username == settings["username"]
    except Exception:
        return False


def require_auth(request: Request, db: Session = Depends(get_db)):
    """FastAPI route dependency ensuring user is authenticated."""
    if not is_authenticated(request, db):
        # If API or AJAX request, return 401
        if "application/json" in request.headers.get("accept", "") or request.url.path.startswith("/api/"):
            raise HTTPException(status_code=401, detail="Unauthorized")
        # Otherwise redirect to login
        next_url = request.url.path
        if request.url.query:
            next_url += f"?{request.url.query}"
        return RedirectResponse(url=f"/login?next={next_url}", status_code=303)
    return True


def verify_api_key_or_auth(request: Request, db: Session = Depends(get_db)):
    """Verify either valid session cookie OR X-Api-Key / ?apikey= param."""
    settings = get_auth_settings(db)
    if not settings["auth_enabled"]:
        return True

    # 1. Check API Key in header or query
    req_api_key = request.headers.get("X-Api-Key") or request.query_params.get("apikey")
    if req_api_key and hmac.compare_digest(req_api_key, settings["api_key"]):
        return True

    # 2. Check session cookie
    if is_authenticated(request, db):
        return True

    log_system_event("WARN", "Auth", f"Unauthorized request to {request.url.path}")
    raise HTTPException(status_code=401, detail="Invalid API Key or unauthorized session")
