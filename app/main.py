import os
import requests
import feedparser
from datetime import datetime

from fastapi import FastAPI, Depends, Request, Form, BackgroundTasks, HTTPException, Response
from lxml import etree

from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from sqlalchemy import desc
from .database import engine, Base, get_db
from .models import Podcast, PlayHistory

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Polarr")
templates = Jinja2Templates(directory="app/templates")
templates.env.cache = None

ABS_URL = os.getenv("ABS_URL", "http://totoro:13378/audiobookshelf").rstrip("/")
ABS_TOKEN = os.getenv("ABS_TOKEN", "")
ABS_LIBRARY_ID = os.getenv("ABS_LIBRARY_ID", "")
ABS_FOLDER_ID = os.getenv("ABS_FOLDER_ID", "") # We need this to create podcasts

def delete_episode_from_abs(abs_id: str, episode_id: str):
    """Deletes an episode from Audiobookshelf to free up space"""
    if not ABS_TOKEN:
        return
    url = f"{ABS_URL}/api/podcasts/{abs_id}/episode/{episode_id}"
    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    try:
        # hard=1 tells ABS to delete the actual file
        requests.delete(f"{url}?hard=1", headers=headers, timeout=10)
    except Exception as e:
        print(f"Failed to delete episode from ABS: {e}")

@app.get("/", response_class=HTMLResponse)
def index(request: Request, db: Session = Depends(get_db)):
    active_podcasts = db.query(Podcast).filter(Podcast.subscribed == True).order_by(Podcast.title).all()
    archived_podcasts = db.query(Podcast).filter(Podcast.subscribed == False).order_by(Podcast.title).all()
    return templates.TemplateResponse(request=request, name="index.html", context={"request": request, "active_podcasts": active_podcasts, "archived_podcasts": archived_podcasts})

@app.get("/history", response_class=HTMLResponse)
def history(request: Request, db: Session = Depends(get_db)):
    # Get last 100 played episodes
    history_records = db.query(PlayHistory).order_by(desc(PlayHistory.played_at)).limit(100).all()
    return templates.TemplateResponse(request=request, name="history.html", context={"request": request, "history": history_records})

@app.post("/webhook/abs")
async def abs_webhook(request: Request, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """Receives webhooks from Audiobookshelf"""
    payload = await request.json()
    
    # We only care when an item is finished
    event_name = payload.get("event")
    if event_name not in ["item_finished", "progress_update"]:
        return {"status": "ignored"}
    
    # Check if it's finished
    is_finished = payload.get("progress", {}).get("isFinished", False)
    if event_name == "progress_update" and not is_finished:
        return {"status": "ignored"}

    library_item_id = payload.get("libraryItemId")
    episode_id = payload.get("episodeId")
    
    if not library_item_id or not episode_id:
        return {"status": "ignored", "reason": "missing_ids"}
        
    podcast = db.query(Podcast).filter(Podcast.abs_id == library_item_id).first()
    if not podcast:
        return {"status": "ignored", "reason": "podcast_not_found_in_polarr"}
        
    # Get episode info from ABS to save title/guid
    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    try:
        res = requests.get(f"{ABS_URL}/api/podcasts/{library_item_id}/episode/{episode_id}", headers=headers, timeout=10)
        res.raise_for_status()
        ep_data = res.json()
        guid = ep_data.get("guid", episode_id)
        title = ep_data.get("title", "Unknown Episode")
    except Exception:
        guid = episode_id
        title = f"Episode {episode_id}"

    # Log to history
    existing = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id, PlayHistory.episode_guid == guid).first()
    if not existing:
        new_history = PlayHistory(podcast_id=podcast.id, episode_guid=guid, episode_title=title)
        db.add(new_history)
        db.commit()
    
    # Tell ABS to delete the file to free up space!
    background_tasks.add_task(delete_episode_from_abs, library_item_id, episode_id)
    
    return {"status": "success", "action": "logged_and_deletion_queued"}

@app.get("/podcast/{podcast_id}", response_class=HTMLResponse)
def podcast_detail(request: Request, podcast_id: int, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        raise HTTPException(status_code=404, detail="Podcast not found")
    history_records = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast_id).order_by(desc(PlayHistory.played_at)).all()
    return templates.TemplateResponse(request=request, name="podcast_detail.html", context={"request": request, "podcast": podcast, "history": history_records})

import hashlib
import time

def get_podcastindex_headers(api_key, api_secret):
    api_header_time = str(int(time.time()))
    data_to_hash = api_key + api_secret + api_header_time
    sha_1 = hashlib.sha1(data_to_hash.encode('utf-8')).hexdigest()
    return {
        "User-Agent": "Polarr/1.0",
        "X-Auth-Key": api_key,
        "X-Auth-Date": api_header_time,
        "Authorization": sha_1
    }

@app.post("/podcast/{podcast_id}/automatch")
def automatch_podcast(request: Request, podcast_id: int, provider: str = "podcastindex", db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        return HTMLResponse("Podcast non trouvé", status_code=404)

    if provider == "rss":
        try:
            import feedparser
            d = feedparser.parse(podcast.feed_url)
            if hasattr(d, "feed") and "title" in d.feed:
                podcast.title = d.feed.title
                
                history = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
                for h in history:
                    for entry in d.entries:
                        guid = entry.get("id") or entry.get("guid") or ""
                        if h.episode_guid == guid:
                            h.episode_title = entry.get("title", h.episode_title)
                            break
                db.commit()
                return RedirectResponse(url=f"/podcast/{podcast_id}", status_code=303)
            return HTMLResponse("<script>alert('Impossible de lire le flux RSS direct. Lien probablement mort.'); window.history.back();</script>")
        except Exception as e:
            return HTMLResponse(f"<script>alert('Erreur RSS: {e}'); window.history.back();</script>")
            
    # Sinon, PodcastIndex
    api_key = os.getenv("PODCASTINDEX_API_KEY")
    api_secret = os.getenv("PODCASTINDEX_API_SECRET")
    
    if not api_key or not api_secret:
        return HTMLResponse("<script>alert('Veuillez ajouter PODCASTINDEX_API_KEY et SECRET dans votre .env !'); window.history.back();</script>")
        
    url = f"https://api.podcastindex.org/api/1.0/podcasts/byfeedurl?url={podcast.feed_url}"
    headers = get_podcastindex_headers(api_key, api_secret)
    
    try:
        res = requests.get(url, headers=headers, timeout=10)
        data = res.json()
        if data.get("feed") and data["feed"].get("title"):
            new_title = data["feed"]["title"]
            podcast.title = new_title
            
            feed_id = data["feed"].get("id")
            if feed_id:
                ep_url = f"https://api.podcastindex.org/api/1.0/episodes/byfeedid?id={feed_id}&max=1000"
                try:
                    ep_res = requests.get(ep_url, headers=headers, timeout=10)
                    if ep_res.ok:
                        ep_data = ep_res.json()
                        items = ep_data.get("items", [])
                        
                        ep_map = {}
                        for item in items:
                            if item.get("guid"):
                                ep_map[str(item["guid"]).strip()] = item.get("title")
                            if item.get("link"):
                                ep_map[str(item["link"]).strip()] = item.get("title")
                        
                        histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
                        for h in histories:
                            guid = str(h.episode_guid).strip()
                            if guid in ep_map and h.episode_title.startswith("Episode "):
                                h.episode_title = ep_map[guid]
                except Exception as e:
                    pass
                    
            db.commit()
            return RedirectResponse(url=f"/podcast/{podcast_id}", status_code=303)
    except Exception as e:
        pass
        
    return HTMLResponse("<script>alert('Aucune correspondance trouvée sur PodcastIndex pour cette URL (elle est probablement définitivement morte).'); window.history.back();</script>")


@app.get("/feed/{podcast_id}")
def proxy_rss_feed(podcast_id: int, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        return Response("Podcast non trouvé", status_code=404)
        
    try:
        r = requests.get(podcast.feed_url, headers={"User-Agent": "Polarr/1.0"}, timeout=15)
        r.raise_for_status()
        
        parser = etree.XMLParser(strip_cdata=False, recover=True)
        root = etree.fromstring(r.content, parser)
        
        histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
        played_guids = {str(h.episode_guid).strip() for h in histories if h.episode_guid}
        
        removed = 0
        for item in root.xpath('//item'):
            guid_elem = item.find('guid')
            if guid_elem is not None and guid_elem.text:
                if guid_elem.text.strip() in played_guids:
                    item.getparent().remove(item)
                    removed += 1
            else:
                # Check link as fallback
                link_elem = item.find('link')
                if link_elem is not None and link_elem.text:
                    if link_elem.text.strip() in played_guids:
                        item.getparent().remove(item)
                        removed += 1
                        
        print(f"Proxy Feed {podcast_id}: {removed} épisodes déjà écoutés masqués.")
        return Response(content=etree.tostring(root, encoding='utf-8', xml_declaration=True), media_type="application/rss+xml")
    except Exception as e:
        print(f"Erreur proxy_rss_feed: {e}")
        return Response("Erreur lors de la récupération du flux", status_code=502)

@app.post("/podcast/{podcast_id}/toggle")
def toggle_podcast(request: Request, podcast_id: int, source: str = None, db: Session = Depends(get_db)):
    podcast = db.query(Podcast).filter(Podcast.id == podcast_id).first()
    if not podcast:
        return HTMLResponse("Podcast non trouvé", status_code=404)
        
    ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
    ABS_TOKEN = os.getenv("ABS_TOKEN", "")
    ABS_LIBRARY_ID = os.getenv("ABS_LIBRARY_ID", "")
    headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
    
    if podcast.subscribed:
        if podcast.abs_id:
            try:
                requests.delete(f"{ABS_URL}/api/items/{podcast.abs_id}?hard=1", headers=headers, timeout=10)
            except:
                pass
        podcast.subscribed = False
        podcast.abs_id = None
    else:
        try:
            res = requests.get(f"{ABS_URL}/api/libraries/{ABS_LIBRARY_ID}", headers=headers, timeout=10)
            if res.ok:
                folders = res.json().get("folders", [])
                if folders:
                    folder_id = folders[0]["id"]
                    folder_path = folders[0].get("fullPath") or folders[0].get("path") or ""
                    safe_title = "".join(c for c in podcast.title if c.isalnum() or c in (' ', '-', '_')).strip()
                    
                    feed_res = requests.post(f"{ABS_URL}/api/podcasts/feed", json={"rssFeed": podcast.feed_url}, headers=headers, timeout=10)
                    if feed_res.ok:
                        podcast_media = feed_res.json().get("podcast")
                        if podcast_media:
                            payload = {
                                "path": os.path.join(folder_path, safe_title),
                                "folderId": folder_id,
                                "libraryId": ABS_LIBRARY_ID,
                                "media": podcast_media,
                                "autoDownloadEpisodes": True
                            }
                            r = requests.post(f"{ABS_URL}/api/podcasts", json=payload, headers=headers, timeout=10)
                            if r.ok:
                                podcast.abs_id = r.json().get("id")
                                
                                # Marquer l'historique comme terminé
                                histories = db.query(PlayHistory).filter(PlayHistory.podcast_id == podcast.id).all()
                                played_guids = {str(h.episode_guid).strip() for h in histories if h.episode_guid}
                                if "episodes" in podcast_media:
                                    for ep in podcast_media["episodes"]:
                                        if str(ep.get("id")) in played_guids or str(ep.get("enclosureUrl")) in played_guids:
                                            requests.patch(f"{ABS_URL}/api/me/progress/{podcast.abs_id}", json={"isFinished": True, "progress": 1, "episodeId": ep.get("id"), "hideFromContinueListening": True}, headers=headers)

                                # Forcer le scan de tous les anciens épisodes
                                requests.patch(f"{ABS_URL}/api/items/{podcast.abs_id}/media", json={"lastEpisodeCheck": 0}, headers=headers, timeout=10)
                                requests.get(f"{ABS_URL}/api/podcasts/{podcast.abs_id}/checknew?limit=9999", headers=headers, timeout=10)

        except Exception as e:
            print("Erreur:", e)
        podcast.subscribed = True

    db.commit()
    return RedirectResponse(url="/" if source == "index" else f"/podcast/{podcast_id}", status_code=303)

import asyncio

async def sync_abs_progress():
    while True:
        try:
            ABS_URL = os.getenv("ABS_URL", "").rstrip("/")
            ABS_TOKEN = os.getenv("ABS_TOKEN", "")
            if not ABS_URL or not ABS_TOKEN:
                await asyncio.sleep(300)
                continue
                
            headers = {"Authorization": f"Bearer {ABS_TOKEN}"}
            db = SessionLocal()
            
            # Fetch user progress
            res = requests.get(f"{ABS_URL}/api/me", headers=headers, timeout=10)
            if res.ok:
                data = res.json()
                media_progress = data.get("mediaProgress", [])
                
                for mp in media_progress:
                    # Si l'utilisateur a fini l'épisode (ou écouté à plus de 95%)
                    if mp.get("isFinished") or mp.get("progress", 0) > 0.95:
                        lib_item_id = mp.get("libraryItemId")
                        ep_id = mp.get("episodeId")
                        
                        pod = db.query(Podcast).filter(Podcast.abs_id == lib_item_id).first()
                        if pod and ep_id:
                            # Vérifie s'il est déjà archivé
                            exists = db.query(PlayHistory).filter(PlayHistory.podcast_id == pod.id, PlayHistory.episode_guid == ep_id).first()
                            
                            if not exists:
                                # On a besoin du titre de l'épisode
                                ep_title = f"Episode {ep_id}"
                                item_res = requests.get(f"{ABS_URL}/api/library/items/{lib_item_id}", headers=headers, timeout=10)
                                if item_res.ok:
                                    item_data = item_res.json()
                                    episodes = item_data.get("media", {}).get("episodes", [])
                                    for e in episodes:
                                        if e.get("id") == ep_id:
                                            ep_title = e.get("title", ep_title)
                                            break
                                            
                                # Ajout à l'historique
                                ph = PlayHistory(
                                    podcast_id=pod.id,
                                    episode_guid=ep_id,
                                    episode_title=ep_title,
                                    played_at=datetime.utcnow()
                                )
                                db.add(ph)
                                db.commit()
                                print(f"🎧 NOUVELLE ÉCOUTE ARCHIVÉE : {ep_title}")
                                
                                # On ordonne à ABS de supprimer le fichier pour faire de la place
                                # ABS API: DELETE /api/library/items/{itemId}/episode/{episodeId}
                                # Mais l'API ABS pour supprimer un épisode spécifique est complexe.
                                # L'astuce est de faire un appel DELETE sur l'épisode.
                                try:
                                    requests.delete(f"{ABS_URL}/api/podcasts/{lib_item_id}/episode/{ep_id}?hard=1", headers=headers, timeout=10)
                                    print(f"🗑️ Fichier supprimé d'ABS avec succès.")
                                except:
                                    pass
            db.close()
        except Exception as e:
            print(f"Erreur Sync Progress: {e}")
            
        # Attendre 5 minutes
        await asyncio.sleep(300)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(sync_abs_progress())
