import pytest
from app.models import Podcast, PlayHistory

def test_web_pages_render_without_abs(client, db_session):
    # Create sample podcast and history
    pod = Podcast(title="Web Test Podcast", feed_url="https://example.com/web.xml", subscribed=True)
    db_session.add(pod)
    db_session.commit()
    db_session.refresh(pod)

    h = PlayHistory(podcast_id=pod.id, episode_guid="ep-web-1", episode_title="Web Ep 1")
    db_session.add(h)
    db_session.commit()

    # Index page
    res = client.get("/")
    assert res.status_code == 200
    assert "Web Test Podcast" in res.text

    # History page
    res = client.get("/history")
    assert res.status_code == 200
    assert "Web Ep 1" in res.text

    # Settings page
    res = client.get("/settings")
    assert res.status_code == 200

    # Discover page
    res = client.get("/discover")
    assert res.status_code == 200

    # Podcast detail page
    res = client.get(f"/podcast/{pod.id}")
    assert res.status_code == 200
    assert "Web Test Podcast" in res.text
