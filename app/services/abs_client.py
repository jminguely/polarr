import requests
import json
from typing import Optional, Dict, Any, List
from ..core.config import ABS_URL, ABS_TOKEN, ABS_LIBRARY_ID, ABS_FOLDER_ID
from ..core.logger import log_system_event

class AudiobookshelfClient:
    def __init__(self):
        self.base_url = ABS_URL.rstrip("/")
        self.token = ABS_TOKEN
        self.library_id = ABS_LIBRARY_ID
        self.folder_id = ABS_FOLDER_ID

    @property
    def headers(self) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }

    def is_configured(self) -> bool:
        return bool(self.base_url and self.token and self.library_id)

    def get_me(self) -> Optional[Dict[str, Any]]:
        """Fetch user info and media progress."""
        if not self.is_configured():
            return None
        try:
            res = requests.get(f"{self.base_url}/api/me", headers=self.headers, timeout=10)
            if res.ok:
                return res.json()
            log_system_event("WARN", "ABS", f"GET /api/me failed with status {res.status_code}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Error connecting to ABS /api/me: {e}")
        return None

    def get_library_items(self, library_id: Optional[str] = None, limit: int = 0) -> Optional[Dict[str, Any]]:
        """Fetch all items in an ABS library (limit=0 fetches all without pagination limit)."""
        if not self.is_configured():
            return None
        target_lib = library_id or self.library_id
        try:
            url = f"{self.base_url}/api/libraries/{target_lib}/items?limit={limit}"
            res = requests.get(url, headers=self.headers, timeout=15)
            if res.ok:
                return res.json()
            log_system_event("WARN", "ABS", f"GET /api/libraries/{target_lib}/items failed with status {res.status_code}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Error fetching library items for {target_lib}: {e}")
        return None

    def get_podcast(self, abs_id: str) -> Optional[Dict[str, Any]]:
        """Get full podcast item details from ABS including episodes."""
        if not self.is_configured() or not abs_id:
            return None
        try:
            res = requests.get(f"{self.base_url}/api/items/{abs_id}", headers=self.headers, timeout=10)
            if res.ok:
                return res.json()
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Error fetching podcast {abs_id}: {e}")
        return None

    def get_episode(self, abs_id: str, episode_id: str) -> Optional[Dict[str, Any]]:
        """Fetch metadata for a specific podcast episode."""
        if not self.is_configured() or not abs_id or not episode_id:
            return None
        try:
            res = requests.get(f"{self.base_url}/api/podcasts/{abs_id}/episode/{episode_id}", headers=self.headers, timeout=10)
            if res.ok:
                return res.json()
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Error fetching episode {episode_id} for podcast {abs_id}: {e}")
        return None

    def delete_episode(self, abs_id: str, episode_id: str) -> bool:
        """Hard delete an episode file from ABS to reclaim disk space."""
        if not self.is_configured() or not abs_id or not episode_id:
            return False
        try:
            url = f"{self.base_url}/api/podcasts/{abs_id}/episode/{episode_id}?hard=1"
            res = requests.delete(url, headers=self.headers, timeout=10)
            if res.ok:
                log_system_event("INFO", "ABS", f"Deleted listened episode file {episode_id} from ABS")
                return True
            log_system_event("WARN", "ABS", f"Failed deleting episode {episode_id}: HTTP {res.status_code}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Exception deleting episode {episode_id} from ABS: {e}")
        return False

    def checknew_podcast(self, abs_id: str) -> bool:
        """Trigger ABS to check for new episodes on this podcast's RSS feed."""
        if not self.is_configured() or not abs_id:
            return False
        try:
            url = f"{self.base_url}/api/podcasts/{abs_id}/checknew"
            res = requests.get(url, headers=self.headers, timeout=10)
            if res.ok:
                log_system_event("INFO", "ABS", f"Triggered feed checknew for podcast {abs_id}")
                return True
            log_system_event("WARN", "ABS", f"checknew for {abs_id} failed: HTTP {res.status_code}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Exception triggering checknew for {abs_id}: {e}")
        return False

    def reset_media_check(self, abs_id: str) -> bool:
        """Reset media check timestamp on ABS to force fresh fetch."""
        if not self.is_configured() or not abs_id:
            return False
        try:
            url = f"{self.base_url}/api/items/{abs_id}/media"
            res = requests.patch(url, headers=self.headers, json={"metadata": {"lastCheck": 0}}, timeout=10)
            return res.ok
        except Exception as e:
            log_system_event("WARN", "ABS", f"Error resetting media check for {abs_id}: {e}")
            return False

    def delete_podcast(self, abs_id: str) -> bool:
        """Hard-delete an entire podcast and all its files from ABS."""
        if not self.is_configured() or not abs_id:
            return False
        try:
            url = f"{self.base_url}/api/items/{abs_id}?hard=1"
            res = requests.delete(url, headers=self.headers, timeout=15)
            if res.ok:
                log_system_event("INFO", "ABS", f"Hard deleted podcast {abs_id} from ABS")
                return True
            log_system_event("WARN", "ABS", f"Failed deleting podcast {abs_id}: HTTP {res.status_code}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Exception deleting podcast {abs_id}: {e}")
        return False

    def create_podcast(self, feed_url: str, folder_id: Optional[str] = None) -> Optional[str]:
        """Create a podcast in ABS and return its created libraryItemId (abs_id)."""
        if not self.is_configured():
            return None
        folder_id = folder_id or self.folder_id
        try:
            # 1. Parse feed on ABS
            feed_res = requests.post(f"{self.base_url}/api/podcasts/feed", headers=self.headers, json={"url": feed_url}, timeout=15)
            if not feed_res.ok:
                log_system_event("ERROR", "ABS", f"Failed to parse feed on ABS: {feed_res.status_code}")
                return None
            
            feed_data = feed_res.json()
            payload = {
                "media": feed_data.get("podcast", {}),
                "folderId": folder_id
            }
            # 2. Create in library
            create_res = requests.post(f"{self.base_url}/api/podcasts", headers=self.headers, json=payload, timeout=15)
            if create_res.ok:
                created = create_res.json()
                item_id = created.get("id") or created.get("libraryItem", {}).get("id")
                log_system_event("INFO", "ABS", f"Created podcast on ABS with ID {item_id}")
                return item_id
            log_system_event("ERROR", "ABS", f"Failed creating podcast on ABS: HTTP {create_res.status_code}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Exception creating podcast on ABS: {e}")
        return None

abs_client = AudiobookshelfClient()
