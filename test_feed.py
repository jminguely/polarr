import requests
from app.database import SessionLocal
from app.models import Podcast

db = SessionLocal()
pod = Podcast(title="Test", feed_url="https://feeds.simplecast.com/54nAGcIl", subscribed=True, sync_order="oldest_first", sync_limit=5)
db.add(pod)
db.commit()
db.refresh(pod)
print(f"Added podcast {pod.id}")
