import os
import time
import requests
import feedparser
from datetime import datetime
from typing import List, Dict, Any, Tuple, Optional, Set
from lxml import etree
from ..core.config import PROXY_FEED_CACHE_TTL, FEED_CACHE_TTL
from ..core.logger import log_system_event

PROXY_FEED_CACHE: Dict[int, Tuple[bytes, float]] = {}
FEED_CACHE: Dict[str, Tuple[List[Dict[str, Any]], float, Optional[str]]] = {}

def clear_proxy_cache(podcast_id: Optional[int] = None):
    """Clear cached proxy RSS feed for a podcast, or all if podcast_id is None."""
    if podcast_id:
        PROXY_FEED_CACHE.pop(podcast_id, None)
    else:
        PROXY_FEED_CACHE.clear()

def fetch_feed_episodes(feed_url: str) -> Tuple[List[Dict[str, Any]], Optional[str]]:
    """
    Fetch and parse all episodes from an RSS feed.
    Returns (episodes_list, feed_artwork_url).
    """
    now = time.time()
    if feed_url in FEED_CACHE:
        cached_data, timestamp, artwork = FEED_CACHE[feed_url]
        if now - timestamp < FEED_CACHE_TTL:
            return cached_data, artwork

    try:
        r = requests.get(feed_url, headers={"User-Agent": "Polarr/2.0"}, timeout=12)
        r.raise_for_status()
        d = feedparser.parse(r.content)

        # Extract feed artwork
        artwork_url = None
        if hasattr(d, "feed"):
            if "image" in d.feed and "href" in d.feed.image:
                artwork_url = d.feed.image.href
            elif "itunes_image" in d.feed:
                artwork_url = d.feed.itunes_image

        episodes = []
        for entry in d.entries:
            guid = entry.get("id") or entry.get("guid") or ""
            pub_date = None
            if hasattr(entry, "published_parsed") and entry.published_parsed:
                pub_date = datetime(*entry.published_parsed[:6])
            elif hasattr(entry, "updated_parsed") and entry.updated_parsed:
                pub_date = datetime(*entry.updated_parsed[:6])

            episodes.append({
                "guid": str(guid).strip(),
                "title": entry.get("title", "Untitled Episode"),
                "description": entry.get("summary", ""),
                "pub_date": pub_date,
                "link": entry.get("link", ""),
            })

        FEED_CACHE[feed_url] = (episodes, now, artwork_url)
        return episodes, artwork_url
    except Exception as e:
        log_system_event("ERROR", "Feed", f"Error fetching RSS feed '{feed_url}': {e}")
        return [], None

def generate_proxy_feed_xml(podcast, played_guids: Set[str]) -> Optional[bytes]:
    """
    Fetch upstream RSS feed and filter out played episodes based on sync settings.
    Returns cleaned XML bytes ready for response.
    """
    now = time.time()
    if podcast.id in PROXY_FEED_CACHE:
        cached_content, cached_ts = PROXY_FEED_CACHE[podcast.id]
        if now - cached_ts < PROXY_FEED_CACHE_TTL:
            return cached_content

    try:
        r = requests.get(podcast.feed_url, headers={"User-Agent": "Polarr/2.0"}, timeout=15)
        r.raise_for_status()

        parser = etree.XMLParser(strip_cdata=False, recover=True)
        root = etree.fromstring(r.content, parser)

        # Collect items with metadata
        items_with_info = []
        for item in root.xpath("//item"):
            guid_elem = item.find("guid")
            link_elem = item.find("link")
            guid_text = guid_elem.text.strip() if guid_elem is not None and guid_elem.text else None
            link_text = link_elem.text.strip() if link_elem is not None and link_elem.text else None

            is_played = (guid_text in played_guids) if guid_text else ((link_text in played_guids) if link_text else False)
            items_with_info.append({
                "element": item,
                "guid": guid_text or link_text or "",
                "is_played": is_played,
            })

        # 1. Remove played items
        removed = 0
        for info in items_with_info:
            if info["is_played"]:
                parent = info["element"].getparent()
                if parent is not None:
                    parent.remove(info["element"])
                    removed += 1

        remaining_items = list(root.xpath("//item"))

        # 2. Apply start-after filter
        if podcast.sync_start_after_guid and remaining_items:
            start_idx = None
            for i, item in enumerate(remaining_items):
                guid_elem = item.find("guid")
                link_elem = item.find("link")
                guid_text = guid_elem.text.strip() if guid_elem is not None and guid_elem.text else ""
                link_text = link_elem.text.strip() if link_elem is not None and link_elem.text else ""
                if guid_text == podcast.sync_start_after_guid or link_text == podcast.sync_start_after_guid:
                    start_idx = i
                    break

            if start_idx is not None:
                for item in remaining_items[start_idx:]:
                    parent = item.getparent()
                    if parent is not None:
                        parent.remove(item)
                remaining_items = remaining_items[:start_idx]

        # 3. Apply sync order and limit
        if podcast.sync_order == "oldest_first":
            if podcast.sync_limit and len(remaining_items) > podcast.sync_limit:
                for item in remaining_items[:-podcast.sync_limit]:
                    parent = item.getparent()
                    if parent is not None:
                        parent.remove(item)
        else:
            if podcast.sync_limit and len(remaining_items) > podcast.sync_limit:
                for item in remaining_items[podcast.sync_limit:]:
                    parent = item.getparent()
                    if parent is not None:
                        parent.remove(item)

        # 4. Replace atom:link self URL to point to proxy feed
        polarr_ext = os.getenv("POLARR_EXTERNAL_URL", "http://localhost:8080").rstrip("/")
        proxy_url = f"{polarr_ext}/feed/{podcast.id}"
        ns = {
            "atom": "http://www.w3.org/2005/Atom",
            "itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd",
        }
        for atom_link in root.xpath('//channel/atom:link[@rel="self"]', namespaces=ns):
            atom_link.set("href", proxy_url)
        for new_feed in root.xpath('//channel/itunes:new-feed-url', namespaces=ns):
            parent = new_feed.getparent()
            if parent is not None:
                parent.remove(new_feed)

        xml_bytes = etree.tostring(root, encoding="utf-8", xml_declaration=True)
        PROXY_FEED_CACHE[podcast.id] = (xml_bytes, now)
        log_system_event(
            "INFO",
            "Feed",
            f"Generated proxy feed for '{podcast.title}': {removed} played hidden, {len(root.xpath('//item'))} active exposed"
        )
        return xml_bytes
    except Exception as e:
        log_system_event("ERROR", "Feed", f"Error generating proxy feed for podcast {podcast.id}: {e}")
        return None
