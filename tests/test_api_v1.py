import pytest
from datetime import datetime, timedelta
from app.models import Podcast, PlayHistory, NewEpisode, QueueItem, ChapterBookmark

def test_podcasts_crud(client, db_session):
    # 1. Create podcast
    res = client.post("/api/v1/podcasts", json={
        "title": "Tech Talk",
        "feed_url": "https://example.com/feed.xml",
        "artwork_url": "https://example.com/art.jpg",
        "sync_order": "newest_first",
        "sync_limit": 10
    })
    assert res.status_code == 201
    data = res.json()
    assert data["title"] == "Tech Talk"
    assert data["subscribed"] is True
    pod_id = data["id"]

    # 2. List podcasts
    res = client.get("/api/v1/podcasts")
    assert res.status_code == 200
    pods = res.json()
    assert len(pods) == 1
    assert pods[0]["id"] == pod_id

    # 3. Get single podcast
    res = client.get(f"/api/v1/podcasts/{pod_id}")
    assert res.status_code == 200
    assert res.json()["title"] == "Tech Talk"

    # 4. Update podcast
    res = client.patch(f"/api/v1/podcasts/{pod_id}", json={
        "sync_limit": 20,
        "sync_order": "oldest_first"
    })
    assert res.status_code == 200
    assert res.json()["sync_limit"] == 20
    assert res.json()["sync_order"] == "oldest_first"

    # 5. Delete podcast (soft delete)
    res = client.delete(f"/api/v1/podcasts/{pod_id}")
    assert res.status_code == 200
    res = client.get(f"/api/v1/podcasts/{pod_id}")
    assert res.json()["subscribed"] is False


def test_inbox_flow(client, db_session):
    # Setup podcast
    pod = Podcast(title="News Daily", feed_url="https://example.com/news.xml", subscribed=True)
    db_session.add(pod)
    db_session.commit()
    db_session.refresh(pod)

    # Add inbox items
    ep1 = NewEpisode(
        podcast_id=pod.id,
        episode_guid="guid-101",
        title="Episode 101: Morning Brief",
        description="Daily news update",
        enclosure_url="https://example.com/ep101.mp3",
        duration_secs=900,
        pub_date=datetime.utcnow() - timedelta(hours=2)
    )
    ep2 = NewEpisode(
        podcast_id=pod.id,
        episode_guid="guid-102",
        title="Episode 102: Evening Brief",
        description="Evening summary",
        enclosure_url="https://example.com/ep102.mp3",
        duration_secs=1200,
        pub_date=datetime.utcnow() - timedelta(hours=1)
    )
    db_session.add_all([ep1, ep2])
    db_session.commit()

    # 1. Fetch inbox
    res = client.get("/api/v1/inbox")
    assert res.status_code == 200
    items = res.json()
    assert len(items) == 2
    assert items[0]["title"] == "Episode 102: Evening Brief"  # newest first

    # 2. Dismiss item
    res = client.post(f"/api/v1/inbox/{ep1.id}/dismiss")
    assert res.status_code == 200
    res = client.get("/api/v1/inbox")
    items = res.json()
    assert len(items) == 1
    assert items[0]["id"] == ep2.id

    # 3. Queue item from inbox
    res = client.post(f"/api/v1/inbox/{ep2.id}/queue")
    assert res.status_code == 200
    q_data = res.json()
    assert q_data["episode_guid"] == "guid-102"
    assert q_data["position"] == 0

    # Verify queue contains it
    q_res = client.get("/api/v1/queue")
    assert q_res.status_code == 200
    assert len(q_res.json()) == 1


def test_journal_and_bookmarks(client, db_session):
    pod = Podcast(title="Science Weekly", feed_url="https://example.com/science.xml", subscribed=True)
    db_session.add(pod)
    db_session.commit()
    db_session.refresh(pod)

    # 1. Create journal entry
    res = client.post("/api/v1/journal", json={
        "podcast_id": pod.id,
        "episode_guid": "sci-42",
        "episode_title": "Quantum Physics Explained",
        "completion_type": "finished",
        "episode_duration_secs": 3600,
        "time_listened_secs": 3550,
        "rating": 5,
        "personal_note": "Fascinating discussion on entanglement."
    })
    assert res.status_code == 201
    entry = res.json()
    assert entry["episode_guid"] == "sci-42"
    assert entry["rating"] == 5
    entry_id = entry["id"]

    # 2. Add bookmark
    bm_res = client.post(f"/api/v1/journal/{entry_id}/bookmarks", json={
        "timestamp_secs": 1420,
        "label": "Great explanation of Bell's theorem"
    })
    assert bm_res.status_code == 201
    bm = bm_res.json()
    assert bm["timestamp_secs"] == 1420
    bm_id = bm["id"]

    # 3. Get entry with bookmarks
    get_res = client.get(f"/api/v1/journal/{entry_id}")
    assert get_res.status_code == 200
    assert len(get_res.json()["bookmarks"]) == 1

    # 4. Update entry
    patch_res = client.patch(f"/api/v1/journal/{entry_id}", json={
        "personal_note": "Updated note: will re-listen."
    })
    assert patch_res.status_code == 200
    assert patch_res.json()["personal_note"] == "Updated note: will re-listen."

    # 5. Delete bookmark
    del_bm = client.delete(f"/api/v1/journal/bookmarks/{bm_id}")
    assert del_bm.status_code == 200

    # 6. Delete journal entry
    del_entry = client.delete(f"/api/v1/journal/{entry_id}")
    assert del_entry.status_code == 200


def test_queue_management(client, db_session):
    pod = Podcast(title="History Cast", feed_url="https://example.com/hist.xml", subscribed=True)
    db_session.add(pod)
    db_session.commit()
    db_session.refresh(pod)

    # Add 3 items to queue
    q1 = client.post("/api/v1/queue", json={
        "podcast_id": pod.id,
        "episode_guid": "h-1",
        "episode_title": "Rome Pt 1",
        "duration_secs": 1800
    }).json()

    q2 = client.post("/api/v1/queue", json={
        "podcast_id": pod.id,
        "episode_guid": "h-2",
        "episode_title": "Rome Pt 2",
        "duration_secs": 1900
    }).json()

    q3 = client.post("/api/v1/queue", json={
        "podcast_id": pod.id,
        "episode_guid": "h-3",
        "episode_title": "Rome Pt 3",
        "duration_secs": 2000
    }).json()

    # Verify positions
    queue = client.get("/api/v1/queue").json()
    assert len(queue) == 3
    assert [x["position"] for x in queue] == [0, 1, 2]

    # Update progress on item 1
    prog_res = client.patch(f"/api/v1/queue/{q1['id']}/progress", json={"progress_secs": 500})
    assert prog_res.status_code == 200
    assert prog_res.json()["progress_secs"] == 500

    # Reorder queue (swap 1 and 3)
    reorder_res = client.patch("/api/v1/queue/reorder", json={
        "item_ids": [q3["id"], q2["id"], q1["id"]]
    })
    assert reorder_res.status_code == 200
    reordered = reorder_res.json()
    assert reordered[0]["id"] == q3["id"]
    assert reordered[2]["id"] == q1["id"]

    # Clear queue
    clear_res = client.post("/api/v1/queue/clear")
    assert clear_res.status_code == 200
    assert len(client.get("/api/v1/queue").json()) == 0


def test_sync_push_and_pull(client, db_session):
    pod = Podcast(title="Sync Podcast", feed_url="https://example.com/sync.xml", subscribed=True)
    db_session.add(pod)
    db_session.commit()
    db_session.refresh(pod)

    # Register device
    reg_res = client.post("/api/v1/sync/register", json={
        "device_id": "iphone-15-pro-xyz",
        "device_name": "Julien's iPhone"
    })
    assert reg_res.status_code == 200
    assert reg_res.json()["device_id"] == "iphone-15-pro-xyz"

    # Push batch
    push_res = client.post("/api/v1/sync/push", json={
        "device_id": "iphone-15-pro-xyz",
        "journal_entries": [
            {
                "podcast_id": pod.id,
                "episode_guid": "sync-ep-1",
                "episode_title": "Sync Episode 1",
                "completion_type": "finished",
                "episode_duration_secs": 1800,
                "time_listened_secs": 1800,
                "rating": 4
            }
        ],
        "queue_items": [
            {
                "podcast_id": pod.id,
                "episode_guid": "sync-ep-2",
                "episode_title": "Sync Episode 2",
                "duration_secs": 2400
            }
        ]
    })
    assert push_res.status_code == 200
    assert push_res.json()["synced_journal_entries"] == 1

    # Pull
    pull_res = client.get("/api/v1/sync/pull")
    assert pull_res.status_code == 200
    pull_data = pull_res.json()
    assert len(pull_data["journal_entries"]) == 1
    assert len(pull_data["subscriptions"]) == 1
    assert len(pull_data["queue_items"]) == 1


def test_stats_endpoints(client, db_session):
    pod = Podcast(title="Data Stories", feed_url="https://example.com/data.xml", subscribed=True)
    db_session.add(pod)
    db_session.commit()
    db_session.refresh(pod)

    h1 = PlayHistory(
        podcast_id=pod.id,
        episode_guid="d-1",
        episode_title="Data Ep 1",
        is_skipped=False,
        completion_type="finished",
        time_listened_secs=3600,
        rating=5,
        played_at=datetime.utcnow() - timedelta(days=2)
    )
    h2 = PlayHistory(
        podcast_id=pod.id,
        episode_guid="d-2",
        episode_title="Data Ep 2",
        is_skipped=True,
        completion_type="skipped",
        time_listened_secs=120,
        played_at=datetime.utcnow() - timedelta(days=1)
    )
    db_session.add_all([h1, h2])
    db_session.commit()

    # Overview
    ov_res = client.get("/api/v1/stats/overview")
    assert ov_res.status_code == 200
    ov = ov_res.json()
    assert ov["total_episodes_listened"] == 1
    assert ov["total_episodes_skipped"] == 1
    assert ov["total_hours_listened"] == 1.0

    # By-podcast
    bp_res = client.get("/api/v1/stats/by-podcast")
    assert bp_res.status_code == 200
    bp = bp_res.json()
    assert len(bp) == 1
    assert bp[0]["listened_count"] == 1
    assert bp[0]["average_rating"] == 5.0

    # Heatmap
    hm_res = client.get("/api/v1/stats/heatmap")
    assert hm_res.status_code == 200
    assert len(hm_res.json()) == 7 * 24

    # Top podcasts
    top_res = client.get("/api/v1/stats/top?period=all")
    assert top_res.status_code == 200
    assert len(top_res.json()) == 1
