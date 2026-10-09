import time
import hashlib
import requests
from typing import Optional, Dict, Any, List
from ..core.config import PODCASTINDEX_API_KEY, PODCASTINDEX_API_SECRET
from ..core.logger import log_system_event

def get_podcastindex_headers(api_key: str = None, api_secret: str = None) -> Dict[str, str]:
    api_key = api_key or PODCASTINDEX_API_KEY
    api_secret = api_secret or PODCASTINDEX_API_SECRET
    api_header_time = str(int(time.time()))
    data_to_hash = api_key + api_secret + api_header_time
    sha_1 = hashlib.sha1(data_to_hash.encode("utf-8")).hexdigest()
    return {
        "User-Agent": "Polarr/2.0",
        "X-Auth-Key": api_key,
        "X-Auth-Date": api_header_time,
        "Authorization": sha_1
    }

def is_podcastindex_configured() -> bool:
    return bool(PODCASTINDEX_API_KEY and PODCASTINDEX_API_SECRET)

def search_podcasts(query: str) -> List[Dict[str, Any]]:
    """Search podcasts via PodcastIndex API."""
    if not is_podcastindex_configured() or not query.strip():
        return []
    try:
        url = f"https://api.podcastindex.org/api/1.0/search/byterm?q={requests.utils.quote(query)}"
        headers = get_podcastindex_headers()
        res = requests.get(url, headers=headers, timeout=10)
        if res.ok:
            data = res.json()
            return data.get("feeds", [])
        log_system_event("WARN", "Discover", f"PodcastIndex search returned HTTP {res.status_code}")
    except Exception as e:
        log_system_event("ERROR", "Discover", f"PodcastIndex search exception: {e}")
    return []

def get_podcast_by_feed_url(feed_url: str) -> Optional[Dict[str, Any]]:
    """Lookup podcast metadata by feed URL."""
    if not is_podcastindex_configured() or not feed_url:
        return None
    try:
        url = f"https://api.podcastindex.org/api/1.0/podcasts/byfeedurl?url={requests.utils.quote(feed_url)}"
        headers = get_podcastindex_headers()
        res = requests.get(url, headers=headers, timeout=10)
        if res.ok:
            data = res.json()
            return data.get("feed")
    except Exception as e:
        log_system_event("ERROR", "Discover", f"PodcastIndex byfeedurl exception: {e}")
    return None

def get_episodes_by_feed_id(feed_id: int, max_results: int = 1000) -> List[Dict[str, Any]]:
    """Lookup episodes by feed ID."""
    if not is_podcastindex_configured() or not feed_id:
        return []
    try:
        url = f"https://api.podcastindex.org/api/1.0/episodes/byfeedid?id={feed_id}&max={max_results}"
        headers = get_podcastindex_headers()
        res = requests.get(url, headers=headers, timeout=10)
        if res.ok:
            data = res.json()
            return data.get("items", [])
    except Exception as e:
        log_system_event("ERROR", "Discover", f"PodcastIndex episodes exception: {e}")
    return []
