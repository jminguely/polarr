import os
import sys

# Setup imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import SessionLocal, Base, engine
from app.models import Podcast

Base.metadata.create_all(bind=engine)

db = SessionLocal()
pod = Podcast(title="The Daily", feed_url="https://feeds.simplecast.com/54nAGcIl", subscribed=True, sync_order="oldest_first", sync_limit=5)
db.add(pod)
db.commit()
db.refresh(pod)
print(f"Added podcast {pod.id}")
