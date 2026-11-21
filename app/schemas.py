from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List, Dict, Any
from datetime import datetime

# --- Podcasts Schemas ---
class PodcastBase(BaseModel):
    title: Optional[str] = None
    feed_url: str
    artwork_url: Optional[str] = None
    sync_order: Optional[str] = "oldest_first"
    sync_limit: Optional[int] = 5
    sync_start_after_guid: Optional[str] = None

class PodcastCreate(PodcastBase):
    pass

class PodcastUpdate(BaseModel):
    title: Optional[str] = None
    feed_url: Optional[str] = None
    artwork_url: Optional[str] = None
    sync_order: Optional[str] = None
    sync_limit: Optional[int] = None
    sync_start_after_guid: Optional[str] = None
    subscribed: Optional[bool] = None

class PodcastResponse(PodcastBase):
    id: int
    subscribed: bool
    created_at: Optional[datetime] = None
    listened_count: int = 0

    model_config = ConfigDict(from_attributes=True)

# --- Episode Schemas ---
class EpisodeResponse(BaseModel):
    guid: str
    title: str
    description: Optional[str] = ""
    pub_date: Optional[datetime] = None
    link: Optional[str] = ""
    enclosure_url: Optional[str] = ""
    duration_secs: Optional[int] = None
    played: bool = False
    skipped: bool = False
    completion_type: Optional[str] = None
    played_at: Optional[datetime] = None
    rating: Optional[int] = None
    is_queued: bool = False

class NewEpisodeResponse(BaseModel):
    id: int
    podcast_id: int
    podcast_title: Optional[str] = None
    podcast_artwork_url: Optional[str] = None
    episode_guid: str
    title: str
    description: Optional[str] = None
    enclosure_url: Optional[str] = None
    duration_secs: Optional[int] = None
    pub_date: Optional[datetime] = None
    is_dismissed: bool
    is_queued: bool
    discovered_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

# --- Journal & Bookmark Schemas ---
class BookmarkBase(BaseModel):
    timestamp_secs: int
    label: str

class BookmarkCreate(BookmarkBase):
    pass

class BookmarkResponse(BookmarkBase):
    id: int
    journal_entry_id: int
    created_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

class JournalEntryBase(BaseModel):
    podcast_id: int
    episode_guid: str
    episode_title: Optional[str] = None
    completion_type: Optional[str] = "finished"  # finished, skipped, abandoned
    episode_duration_secs: Optional[int] = None
    time_listened_secs: Optional[int] = None
    rating: Optional[int] = None                  # 1-5
    personal_note: Optional[str] = None
    played_at: Optional[datetime] = None

class JournalEntryCreate(JournalEntryBase):
    pass

class JournalEntryUpdate(BaseModel):
    episode_title: Optional[str] = None
    completion_type: Optional[str] = None
    episode_duration_secs: Optional[int] = None
    time_listened_secs: Optional[int] = None
    rating: Optional[int] = None
    personal_note: Optional[str] = None
    played_at: Optional[datetime] = None

class JournalEntryResponse(JournalEntryBase):
    id: int
    is_skipped: bool = False
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    podcast_title: Optional[str] = None
    podcast_artwork_url: Optional[str] = None
    bookmarks: List[BookmarkResponse] = []

    model_config = ConfigDict(from_attributes=True)

# --- Queue Schemas ---
class QueueItemBase(BaseModel):
    podcast_id: int
    episode_guid: str
    episode_title: str
    enclosure_url: Optional[str] = None
    duration_secs: Optional[int] = None

class QueueItemCreate(QueueItemBase):
    position: Optional[int] = None
    progress_secs: Optional[int] = 0

class QueueItemResponse(QueueItemBase):
    id: int
    position: int
    progress_secs: int
    added_at: Optional[datetime] = None
    podcast_title: Optional[str] = None
    podcast_artwork_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

class QueueProgressUpdate(BaseModel):
    progress_secs: int

class QueueReorderRequest(BaseModel):
    item_ids: List[int]

# --- Sync Schemas ---
class DeviceRegisterRequest(BaseModel):
    device_id: str
    device_name: Optional[str] = None

class SyncPushRequest(BaseModel):
    device_id: str
    journal_entries: List[JournalEntryCreate] = []
    queue_items: Optional[List[QueueItemCreate]] = None

class SyncPullResponse(BaseModel):
    sync_token: str
    journal_entries: List[JournalEntryResponse] = []
    subscriptions: List[PodcastResponse] = []
    queue_items: List[QueueItemResponse] = []

# --- Stats Schemas ---
class StatsOverviewResponse(BaseModel):
    total_episodes_listened: int
    total_episodes_skipped: int
    total_episodes_abandoned: int
    total_hours_listened: float
    total_podcasts_tracked: int
    first_listen_date: Optional[datetime] = None

class PodcastStatsResponse(BaseModel):
    podcast_id: int
    title: str
    artwork_url: Optional[str] = None
    listened_count: int
    skipped_count: int
    hours_listened: float
    average_rating: Optional[float] = None

class HeatmapCell(BaseModel):
    day_of_week: int  # 0=Monday, 6=Sunday
    hour_of_day: int  # 0..23
    listen_count: int

class TopPodcastResponse(BaseModel):
    podcast_id: int
    title: str
    artwork_url: Optional[str] = None
    listened_count: int
    hours_listened: float

class CompletionRateResponse(BaseModel):
    podcast_id: int
    title: str
    artwork_url: Optional[str] = None
    total_feed_episodes: int
    listened_episodes: int
    completion_rate_pct: float
