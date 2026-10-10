import requests
import json
import re
import time
from typing import Optional, Dict, Any, List, Tuple
from ..core.config import ABS_URL, ABS_TOKEN, ABS_LIBRARY_ID, ABS_FOLDER_ID
from ..core.logger import log_system_event

class AudiobookshelfClient:
    def __init__(self):
        self.base_url = ""
        self.token = ""
        self.library_id = ""
        self.folder_id = ""
        self._cached_folder_info: Optional[Tuple[Optional[str], Optional[str]]] = None

    def reload_config(self, db) -> None:
        from ..models import AppSetting
        
        url_setting = db.query(AppSetting).filter(AppSetting.key == "abs_url").first()
        token_setting = db.query(AppSetting).filter(AppSetting.key == "abs_token").first()
        lib_setting = db.query(AppSetting).filter(AppSetting.key == "abs_library_id").first()
        folder_setting = db.query(AppSetting).filter(AppSetting.key == "abs_folder_id").first()
        
        self.base_url = (url_setting.value or "").rstrip("/") if url_setting else ""
        self.token = token_setting.value if token_setting else ""
        self.library_id = lib_setting.value if lib_setting else ""
        self.folder_id = folder_setting.value if folder_setting else ""
        self._cached_folder_info = None

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

    def get_default_folder(self) -> Tuple[Optional[str], Optional[str]]:
        """Retrieve default folder ID and full path from ABS library."""
        if not self.is_configured():
            return None, None
        if self._cached_folder_info is not None:
            return self._cached_folder_info
        try:
            res = requests.get(f"{self.base_url}/api/libraries/{self.library_id}", headers=self.headers, timeout=10)
            if res.ok:
                folders = res.json().get("folders", [])
                if folders:
                    target_folder = folders[0]
                    if self.folder_id:
                        for f in folders:
                            if f.get("id") == self.folder_id:
                                target_folder = f
                                break
                    self._cached_folder_info = (target_folder.get("id"), target_folder.get("fullPath", "/podcasts"))
                    return self._cached_folder_info
        except Exception as e:
            log_system_event("WARN", "ABS", f"Could not fetch library folder info: {e}")
        return self.folder_id, "/podcasts"

    def create_podcast(self, feed_url: str, folder_id: Optional[str] = None) -> Optional[str]:
        """Create a podcast in ABS and return its created libraryItemId (abs_id)."""
        if not self.is_configured():
            return None
        try:
            # 1. Parse feed on ABS (ABS API expects {"rssFeed": url})
            feed_res = requests.post(
                f"{self.base_url}/api/podcasts/feed",
                headers=self.headers,
                json={"rssFeed": feed_url},
                timeout=20
            )
            if not feed_res.ok:
                log_system_event("ERROR", "ABS", f"Failed to parse feed on ABS ({feed_res.status_code}): {feed_res.text[:120]}")
                return None
            
            feed_data = feed_res.json()
            pod_media = feed_data.get("podcast", {})
            title = pod_media.get("metadata", {}).get("title") or "Podcast"
            pod_media["autoDownloadEpisodes"] = True

            # 2. Resolve target folder info
            fid, fpath = self.get_default_folder()
            fid = folder_id or fid
            fpath = fpath or "/podcasts"

            clean_title = re.sub(r'[\\/*?:"<>|]', "", title).strip() or f"Podcast_{int(time.time())}"
            item_path = f"{fpath.rstrip('/')}/{clean_title}"

            payload = {
                "media": pod_media,
                "libraryId": self.library_id,
                "folderId": fid,
                "path": item_path
            }
            # 3. Create in library
            create_res = requests.post(f"{self.base_url}/api/podcasts", headers=self.headers, json=payload, timeout=20)
            if create_res.ok:
                created = create_res.json()
                item_id = created.get("id") or created.get("libraryItem", {}).get("id")
                log_system_event("INFO", "ABS", f"Created podcast '{title}' on ABS with ID {item_id}")
                
                # 4. Force download existing episodes immediately
                episodes = pod_media.get("episodes", [])
                if episodes:
                    dl_res = requests.post(f"{self.base_url}/api/podcasts/{item_id}/download-episodes", headers=self.headers, json=episodes, timeout=20)
                    if dl_res.ok:
                        log_system_event("INFO", "ABS", f"Queued {len(episodes)} episodes for download")
                
                return item_id
            log_system_event("ERROR", "ABS", f"Failed creating podcast '{title}' on ABS (HTTP {create_res.status_code}): {create_res.text[:120]}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Exception creating podcast on ABS: {e}")
        return None

    def force_download_episodes(self, abs_id: str, proxy_feed_url: str) -> bool:
        """Fetch the feed and force ABS to download all episodes in it, bypassing lastEpisodeCheck."""
        if not self.is_configured():
            return False
        try:
            feed_res = requests.post(
                f"{self.base_url}/api/podcasts/feed",
                headers=self.headers,
                json={"rssFeed": proxy_feed_url},
                timeout=20
            )
            if not feed_res.ok:
                return False
            
            episodes = feed_res.json().get("podcast", {}).get("episodes", [])
            if not episodes:
                return True
                
            download_res = requests.post(
                f"{self.base_url}/api/podcasts/{abs_id}/download-episodes",
                headers=self.headers,
                json=episodes,
                timeout=20
            )
            if download_res.ok:
                log_system_event("INFO", "ABS", f"Triggered download of {len(episodes)} episodes for podcast {abs_id}")
                return True
            log_system_event("ERROR", "ABS", f"Failed to trigger downloads for {abs_id}: HTTP {download_res.status_code}")
        except Exception as e:
            log_system_event("ERROR", "ABS", f"Exception forcing downloads for {abs_id}: {e}")
        return False

abs_client = AudiobookshelfClient()
