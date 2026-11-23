import uuid
import json
from datetime import datetime
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import desc

from ...database import get_db
from ...models import Playlist, PlaylistEpisode, NewEpisode, Podcast
from ...schemas import (
    PlaylistCreate,
    PlaylistUpdate,
    PlaylistResponse,
    PlaylistDetailResponse,
    PlaylistEpisodeCreate,
    PlaylistEpisodeResponse,
    PlaylistProgressUpdate,
    PlaylistReorderRequest
)

router = APIRouter(prefix="/playlists", tags=["API Playlists"])


def _format_playlist_response(pl: Playlist) -> PlaylistResponse:
    return PlaylistResponse(
        id=pl.id,
        uuid=pl.uuid,
        title=pl.title,
        description=pl.description,
        is_smart=pl.is_smart,
        smart_rules=pl.smart_rules,
        auto_remove_finished=pl.auto_remove_finished,
        last_played_episode_guid=pl.last_played_episode_guid,
        last_played_position_secs=pl.last_played_position_secs or 0.0,
        episode_count=len(pl.episodes),
        created_at=pl.created_at,
        updated_at=pl.updated_at
    )


def _format_playlist_detail_response(pl: Playlist) -> PlaylistDetailResponse:
    ep_responses = [
        PlaylistEpisodeResponse(
            id=ep.id,
            playlist_id=ep.playlist_id,
            episode_guid=ep.episode_guid,
            episode_title=ep.episode_title,
            podcast_id=ep.podcast_id,
            podcast_title=ep.podcast_title,
            podcast_artwork_url=ep.podcast_artwork_url,
            enclosure_url=ep.enclosure_url,
            duration_secs=ep.duration_secs,
            position=ep.position,
            is_completed=ep.is_completed,
            added_at=ep.added_at
        )
        for ep in sorted(pl.episodes, key=lambda x: x.position)
    ]
    return PlaylistDetailResponse(
        id=pl.id,
        uuid=pl.uuid,
        title=pl.title,
        description=pl.description,
        is_smart=pl.is_smart,
        smart_rules=pl.smart_rules,
        auto_remove_finished=pl.auto_remove_finished,
        last_played_episode_guid=pl.last_played_episode_guid,
        last_played_position_secs=pl.last_played_position_secs or 0.0,
        episode_count=len(pl.episodes),
        created_at=pl.created_at,
        updated_at=pl.updated_at,
        episodes=ep_responses
    )


def _refresh_smart_playlist(playlist: Playlist, db: Session):
    if not playlist.is_smart or not playlist.smart_rules:
        return
    try:
        rules = json.loads(playlist.smart_rules)
    except Exception:
        return

    podcast_ids = rules.get("podcast_ids", [])
    limit = rules.get("limit", 25)

    query = db.query(NewEpisode).filter(NewEpisode.is_dismissed == False)
    if podcast_ids:
        query = query.filter(NewEpisode.podcast_id.in_(podcast_ids))

    new_eps = query.order_by(NewEpisode.pub_date.desc()).limit(limit).all()
    existing_guids = {ep.episode_guid for ep in playlist.episodes}
    pos = len(playlist.episodes)

    for ep in new_eps:
        if ep.episode_guid not in existing_guids:
            pe = PlaylistEpisode(
                playlist_id=playlist.id,
                episode_guid=ep.episode_guid,
                episode_title=ep.title,
                podcast_id=ep.podcast_id,
                podcast_title=ep.podcast.title if ep.podcast else "Podcast",
                podcast_artwork_url=ep.podcast.artwork_url if ep.podcast else None,
                enclosure_url=ep.enclosure_url,
                duration_secs=ep.duration_secs,
                position=pos,
                is_completed=False,
                added_at=datetime.utcnow()
            )
            db.add(pe)
            pos += 1
            existing_guids.add(ep.episode_guid)
    db.commit()
    db.refresh(playlist)


@router.get("", response_model=List[PlaylistResponse])
def list_playlists(db: Session = Depends(get_db)):
    """List all playlists with their episode counts."""
    playlists = db.query(Playlist).order_by(desc(Playlist.updated_at)).all()
    return [_format_playlist_response(p) for p in playlists]


@router.post("", response_model=PlaylistDetailResponse, status_code=status.HTTP_201_CREATED)
def create_playlist(payload: PlaylistCreate, db: Session = Depends(get_db)):
    """Create a new manual or smart playlist."""
    pl_uuid = payload.uuid or str(uuid.uuid4())
    existing = db.query(Playlist).filter(Playlist.uuid == pl_uuid).first()
    if existing:
        return _format_playlist_detail_response(existing)

    pl = Playlist(
        uuid=pl_uuid,
        title=payload.title.strip(),
        description=payload.description.strip() if payload.description else None,
        is_smart=payload.is_smart,
        smart_rules=payload.smart_rules,
        auto_remove_finished=payload.auto_remove_finished,
        last_played_episode_guid=None,
        last_played_position_secs=0.0,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow()
    )
    db.add(pl)
    db.commit()
    db.refresh(pl)

    if pl.is_smart:
        _refresh_smart_playlist(pl, db)

    return _format_playlist_detail_response(pl)


@router.get("/{playlist_uuid}", response_model=PlaylistDetailResponse)
def get_playlist(playlist_uuid: str, db: Session = Depends(get_db)):
    """Get a playlist and its episodes by UUID."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    if pl.is_smart:
        _refresh_smart_playlist(pl, db)

    return _format_playlist_detail_response(pl)


@router.patch("/{playlist_uuid}", response_model=PlaylistResponse)
def update_playlist(playlist_uuid: str, payload: PlaylistUpdate, db: Session = Depends(get_db)):
    """Update playlist properties."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    if payload.title is not None:
        pl.title = payload.title.strip()
    if payload.description is not None:
        pl.description = payload.description.strip()
    if payload.is_smart is not None:
        pl.is_smart = payload.is_smart
    if payload.smart_rules is not None:
        pl.smart_rules = payload.smart_rules
    if payload.auto_remove_finished is not None:
        pl.auto_remove_finished = payload.auto_remove_finished

    pl.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(pl)

    if pl.is_smart:
        _refresh_smart_playlist(pl, db)

    return _format_playlist_response(pl)


@router.delete("/{playlist_uuid}", status_code=status.HTTP_204_NO_CONTENT)
def delete_playlist(playlist_uuid: str, db: Session = Depends(get_db)):
    """Delete a playlist."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    db.delete(pl)
    db.commit()
    return None


@router.post("/{playlist_uuid}/episodes", response_model=PlaylistEpisodeResponse, status_code=status.HTTP_201_CREATED)
def add_episode_to_playlist(playlist_uuid: str, payload: PlaylistEpisodeCreate, db: Session = Depends(get_db)):
    """Add an episode to a playlist."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    # Check if episode is already in playlist
    existing = db.query(PlaylistEpisode).filter(
        PlaylistEpisode.playlist_id == pl.id,
        PlaylistEpisode.episode_guid == payload.episode_guid
    ).first()

    if existing:
        return existing

    # Determine position
    pos = payload.position
    if pos is None:
        last = db.query(PlaylistEpisode).filter(PlaylistEpisode.playlist_id == pl.id).order_by(desc(PlaylistEpisode.position)).first()
        pos = (last.position + 1) if last else 0

    ep = PlaylistEpisode(
        playlist_id=pl.id,
        episode_guid=payload.episode_guid.strip(),
        episode_title=payload.episode_title.strip(),
        podcast_id=payload.podcast_id,
        podcast_title=payload.podcast_title.strip(),
        podcast_artwork_url=payload.podcast_artwork_url,
        enclosure_url=payload.enclosure_url,
        duration_secs=payload.duration_secs,
        position=pos,
        is_completed=False,
        added_at=datetime.utcnow()
    )
    db.add(ep)
    pl.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(ep)
    return ep


@router.delete("/{playlist_uuid}/episodes/{episode_guid}", status_code=status.HTTP_204_NO_CONTENT)
def remove_episode_from_playlist(playlist_uuid: str, episode_guid: str, db: Session = Depends(get_db)):
    """Remove an episode from a playlist."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    ep = db.query(PlaylistEpisode).filter(
        PlaylistEpisode.playlist_id == pl.id,
        PlaylistEpisode.episode_guid == episode_guid
    ).first()

    if ep:
        db.delete(ep)
        if pl.last_played_episode_guid == episode_guid:
            pl.last_played_episode_guid = None
            pl.last_played_position_secs = 0.0
        pl.updated_at = datetime.utcnow()
        db.commit()

    return None


@router.put("/{playlist_uuid}/episodes/reorder", response_model=PlaylistDetailResponse)
def reorder_playlist_episodes(playlist_uuid: str, payload: PlaylistReorderRequest, db: Session = Depends(get_db)):
    """Reorder episodes in a playlist according to the provided list of GUIDs."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    episodes = {ep.episode_guid: ep for ep in pl.episodes}
    for new_idx, guid in enumerate(payload.episode_guids):
        if guid in episodes:
            episodes[guid].position = new_idx

    pl.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(pl)
    return _format_playlist_detail_response(pl)


@router.post("/{playlist_uuid}/progress", response_model=PlaylistResponse)
def update_playlist_progress(playlist_uuid: str, payload: PlaylistProgressUpdate, db: Session = Depends(get_db)):
    """Record the independent playback progress for this playlist."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    pl.last_played_episode_guid = payload.last_played_episode_guid
    pl.last_played_position_secs = payload.last_played_position_secs
    pl.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(pl)
    return _format_playlist_response(pl)


@router.post("/{playlist_uuid}/episodes/{episode_guid}/complete", response_model=PlaylistDetailResponse)
def complete_playlist_episode(playlist_uuid: str, episode_guid: str, db: Session = Depends(get_db)):
    """Mark an episode as completed, or auto-remove it if auto_remove_finished is enabled."""
    pl = db.query(Playlist).filter(Playlist.uuid == playlist_uuid).first()
    if not pl:
        raise HTTPException(status_code=404, detail="Playlist not found")

    ep = db.query(PlaylistEpisode).filter(
        PlaylistEpisode.playlist_id == pl.id,
        PlaylistEpisode.episode_guid == episode_guid
    ).first()

    if ep:
        if pl.auto_remove_finished:
            db.delete(ep)
        else:
            ep.is_completed = True

        # Find next uncompleted episode in playlist
        remaining = [e for e in sorted(pl.episodes, key=lambda x: x.position) if e.episode_guid != episode_guid and not e.is_completed]
        if remaining:
            pl.last_played_episode_guid = remaining[0].episode_guid
            pl.last_played_position_secs = 0.0
        else:
            pl.last_played_episode_guid = None
            pl.last_played_position_secs = 0.0

        pl.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(pl)

    return _format_playlist_detail_response(pl)
