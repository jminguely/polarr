import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import SessionLocal
from app.models import Podcast
import requests
from lxml import etree

db = SessionLocal()
podcast = db.query(Podcast).filter(Podcast.id == 205).first() # The Daily
if not podcast:
    print("Podcast not found")
    sys.exit(1)

# Fetch feed episodes to get a GUID
d = requests.get(podcast.feed_url).text
parser = etree.XMLParser(strip_cdata=False, recover=True)
root = etree.fromstring(d.encode('utf-8'), parser)
items = list(root.xpath('//item'))
print(f"Total items in feed: {len(items)}")

# Pick the 10th item from the end (oldest side)
# The oldest is items[-1]. So items[-10] is the 10th oldest.
start_after_item = items[-10]
guid = start_after_item.find('guid').text.strip()
title = start_after_item.find('title').text.strip()
print(f"Setting start after: {title} ({guid})")

podcast.sync_start_after_guid = guid
podcast.sync_order = "oldest_first"
podcast.sync_limit = 5
db.commit()

# Now simulate proxy_rss_feed
items_with_info = []
for item in root.xpath('//item'):
    guid_elem = item.find('guid')
    guid_text = guid_elem.text.strip() if guid_elem is not None and guid_elem.text else ""
    items_with_info.append({
        "element": item,
        "guid": guid_text,
    })

remaining_items = list(root.xpath('//item'))
start_idx = None
for i, item in enumerate(remaining_items):
    guid_elem = item.find('guid')
    guid_text = guid_elem.text.strip() if guid_elem is not None and guid_elem.text else ""
    if guid_text == podcast.sync_start_after_guid:
        start_idx = i
        break

print(f"Found start_idx: {start_idx}")

if start_idx is not None:
    for item in remaining_items[start_idx:]:
        item.getparent().remove(item)
    remaining_items = remaining_items[:start_idx]

print(f"Items remaining after start filter: {len(remaining_items)}")

# Apply order and limit
if podcast.sync_order == "oldest_first":
    if podcast.sync_limit and len(remaining_items) > podcast.sync_limit:
        for item in remaining_items[:-podcast.sync_limit]:
            item.getparent().remove(item)
        remaining_items = remaining_items[-podcast.sync_limit:]
else:
    if podcast.sync_limit and len(remaining_items) > podcast.sync_limit:
        for item in remaining_items[podcast.sync_limit:]:
            item.getparent().remove(item)
        remaining_items = remaining_items[:podcast.sync_limit]

print("Final items in feed:")
for i, item in enumerate(remaining_items):
    print(f"  {i+1}: {item.find('title').text}")

