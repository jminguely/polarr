import pytest
from datetime import datetime
from app.models import Podcast, Playlist, PlaylistEpisode, NewEpisode

def test_playlist_crud_and_episodes(client, db_session):
    pod = Podcast(
        title="Test Podcast",
        feed_url="https://example.com/feed.xml",
        artwork_url="https://example.com/art.jpg",
        subscribed=True
    )
    db_session.add(pod)
    db_session.commit()
    db_session.refresh(pod)

    # 1. Create a manual playlist
    create_res = client.post(
        "/api/v1/playlists",
        json={
            "title": "Morning Commute",
            "description": "Daily tech & news",
            "is_smart": False,
            "auto_remove_finished": True
        }
    )
    assert create_res.status_code == 201
    pl_data = create_res.json()
    assert pl_data["title"] == "Morning Commute"
    assert pl_data["auto_remove_finished"] is True
    assert pl_data["is_smart"] is False
    pl_uuid = pl_data["uuid"]

    # 2. Add an episode
    add_ep_res = client.post(
        f"/api/v1/playlists/{pl_uuid}/episodes",
        json={
            "episode_guid": "guid-ep-1",
            "episode_title": "Episode 1: Tech Trends",
            "podcast_id": pod.id,
            "podcast_title": "Test Podcast",
            "podcast_artwork_url": "https://example.com/art.jpg",
            "enclosure_url": "https://example.com/ep1.mp3",
            "duration_secs": 1800
        }
    )
    assert add_ep_res.status_code == 201
    ep_data = add_ep_res.json()
    assert ep_data["episode_guid"] == "guid-ep-1"
    assert ep_data["position"] == 0

    # 3. Add second episode
    client.post(
        f"/api/v1/playlists/{pl_uuid}/episodes",
        json={
            "episode_guid": "guid-ep-2",
            "episode_title": "Episode 2: Deep Dive",
            "podcast_id": pod.id,
            "podcast_title": "Test Podcast",
            "enclosure_url": "https://example.com/ep2.mp3",
            "duration_secs": 2400
        }
    )

    # 4. Fetch playlist detail
    get_res = client.get(f"/api/v1/playlists/{pl_uuid}")
    assert get_res.status_code == 200
    detail = get_res.json()
    assert len(detail["episodes"]) == 2
    assert detail["episode_count"] == 2

    # 5. Reorder episodes
    reorder_res = client.put(
        f"/api/v1/playlists/{pl_uuid}/episodes/reorder",
        json={"episode_guids": ["guid-ep-2", "guid-ep-1"]}
    )
    assert reorder_res.status_code == 200
    reordered = reorder_res.json()
    assert reordered["episodes"][0]["episode_guid"] == "guid-ep-2"
    assert reordered["episodes"][1]["episode_guid"] == "guid-ep-1"

    # 6. Update progress memory
    prog_res = client.post(
        f"/api/v1/playlists/{pl_uuid}/progress",
        json={
            "last_played_episode_guid": "guid-ep-2",
            "last_played_position_secs": 420.5
        }
    )
    assert prog_res.status_code == 200
    assert prog_res.json()["last_played_episode_guid"] == "guid-ep-2"
    assert prog_res.json()["last_played_position_secs"] == 420.5

    # 7. Complete episode with auto_remove_finished=True
    comp_res = client.post(
        f"/api/v1/playlists/{pl_uuid}/episodes/guid-ep-2/complete"
    )
    assert comp_res.status_code == 200
    comp_data = comp_res.json()
    # guid-ep-2 was deleted because auto_remove_finished=True
    assert len(comp_data["episodes"]) == 1
    assert comp_data["episodes"][0]["episode_guid"] == "guid-ep-1"
    # Auto-advanced to next episode
    assert comp_data["last_played_episode_guid"] == "guid-ep-1"

    # 8. Delete playlist
    del_res = client.delete(f"/api/v1/playlists/{pl_uuid}")
    assert del_res.status_code == 204
