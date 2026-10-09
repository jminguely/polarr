from fastapi import APIRouter, Request, Form, Depends, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from ..database import get_db
from ..core.auth import get_auth_settings, create_session_cookie, clear_session_cookie, is_authenticated
from ..core.logger import log_system_event

router = APIRouter(tags=["auth"])

@router.get("/login", response_class=HTMLResponse)
def login_page(request: Request, next: str = "/", db: Session = Depends(get_db)):
    if is_authenticated(request, db):
        return RedirectResponse(url=next, status_code=303)
    
    from ..main import templates
    return templates.TemplateResponse(request=request, name="login.html", context={
        "request": request,
        "next": next,
        "error": None
    })

@router.post("/login", response_class=HTMLResponse)
def login_submit(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    next: str = Form("/"),
    db: Session = Depends(get_db)
):
    settings = get_auth_settings(db)
    from ..main import templates

    if username == settings["username"] and password == settings["password"]:
        log_system_event("INFO", "Auth", f"User '{username}' logged in successfully")
        response = RedirectResponse(url=next or "/", status_code=303)
        create_session_cookie(response, username)
        return response
    
    log_system_event("WARN", "Auth", f"Failed login attempt for user '{username}'")
    return templates.TemplateResponse(request=request, name="login.html", context={
        "request": request,
        "next": next,
        "error": "Invalid username or password. Please try again."
    }, status_code=401)

@router.get("/logout")
@router.post("/logout")
def logout(request: Request):
    response = RedirectResponse(url="/login", status_code=303)
    clear_session_cookie(response)
    log_system_event("INFO", "Auth", "User logged out")
    return response
