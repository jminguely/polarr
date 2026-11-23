from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime
from .database import Base

class Podcast(Base):
    __tablename__ = "podcasts"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    feed_url = Column(String, unique=True, index=True)
    artwork_url = Column(String, nullable=True)
    abs_id = Column(String, unique=True, nullable=True)  # Kept for backward compatibility, deprecated
    subscribed = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Sync settings
    sync_order = Column(String, default="oldest_first")   # "oldest_first" or "newest_first"
    sync_limit = Column(Integer, default=5)                # Number of episodes to keep in feed
    sync_start_after_guid = Column(String, nullable=True)  # Episode GUID to start syncing after

    history = relationship("PlayHistory", back_populates="podcast", cascade="all, delete-orphan")
    new_episodes = relationship("NewEpisode", back_populates="podcast", cascade="all, delete-orphan")
    queue_items = relationship("QueueItem", back_populates="podcast", cascade="all, delete-orphan")

class PlayHistory(Base):
    __tablename__ = "play_history"
    id = Column(Integer, primary_key=True, index=True)
    podcast_id = Column(Integer, ForeignKey("podcasts.id"))
    episode_guid = Column(String, index=True)
    episode_title = Column(String, nullable=True)
    played_at = Column(DateTime, default=datetime.utcnow)
    is_skipped = Column(Boolean, default=False)
    
    # Enriched listening journal fields
    completion_type = Column(String, default="finished")  # "finished", "skipped", "abandoned"
    episode_duration_secs = Column(Integer, nullable=True)
    time_listened_secs = Column(Integer, nullable=True)
    rating = Column(Integer, nullable=True)                # 1-5 stars
    personal_note = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    podcast = relationship("Podcast", back_populates="history")
    bookmarks = relationship("ChapterBookmark", back_populates="journal_entry", cascade="all, delete-orphan")

# Alias for domain clarity
ListeningJournal = PlayHistory

class ChapterBookmark(Base):
    __tablename__ = "chapter_bookmarks"
    id = Column(Integer, primary_key=True, index=True)
    journal_entry_id = Column(Integer, ForeignKey("play_history.id"), index=True)
    timestamp_secs = Column(Integer, nullable=False)
    label = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    journal_entry = relationship("PlayHistory", back_populates="bookmarks")

class NewEpisode(Base):
    __tablename__ = "new_episodes"
    id = Column(Integer, primary_key=True, index=True)
    podcast_id = Column(Integer, ForeignKey("podcasts.id"), index=True)
    episode_guid = Column(String, index=True)
    title = Column(String)
    description = Column(Text, nullable=True)
    enclosure_url = Column(String, nullable=True)
    duration_secs = Column(Integer, nullable=True)
    pub_date = Column(DateTime, nullable=True)
    is_dismissed = Column(Boolean, default=False, index=True)
    is_queued = Column(Boolean, default=False, index=True)
    discovered_at = Column(DateTime, default=datetime.utcnow)

    podcast = relationship("Podcast", back_populates="new_episodes")

class QueueItem(Base):
    __tablename__ = "queue_items"
    id = Column(Integer, primary_key=True, index=True)
    podcast_id = Column(Integer, ForeignKey("podcasts.id"), index=True)
    episode_guid = Column(String, index=True)
    episode_title = Column(String)
    enclosure_url = Column(String, nullable=True)
    duration_secs = Column(Integer, nullable=True)
    position = Column(Integer, default=0, index=True)
    progress_secs = Column(Integer, default=0)
    added_at = Column(DateTime, default=datetime.utcnow)

    podcast = relationship("Podcast", back_populates="queue_items")

class DeviceSync(Base):
    __tablename__ = "device_syncs"
    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(String, unique=True, index=True)
    device_name = Column(String, nullable=True)
    last_sync_at = Column(DateTime, default=datetime.utcnow)
    sync_token = Column(String, nullable=True)

class AppSetting(Base):
    __tablename__ = "app_settings"
    key = Column(String, primary_key=True, index=True)
    value = Column(String)

class SyncLog(Base):
    __tablename__ = "sync_logs"
    id = Column(Integer, primary_key=True, index=True)
    started_at = Column(DateTime, default=datetime.utcnow)
    finished_at = Column(DateTime, nullable=True)
    status = Column(String, default="running") # "running", "success", "error"
    details = Column(Text, nullable=True)      # Detailed text log of what happened

class SystemLog(Base):
    __tablename__ = "system_logs"
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, index=True)
    level = Column(String, default="INFO", index=True)      # DEBUG, INFO, WARN, ERROR
    source = Column(String, default="System", index=True)   # Webhook, Sync, Feed, ABS, Auth, Discover, System
    message = Column(String)
    details = Column(Text, nullable=True)                  # JSON payload, traceback, or raw text

class Playlist(Base):
    __tablename__ = "playlists"
    id = Column(Integer, primary_key=True, index=True)
    uuid = Column(String(36), unique=True, index=True, nullable=False)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    is_smart = Column(Boolean, default=False)
    smart_rules = Column(Text, nullable=True)  # JSON formatted rules
    auto_remove_finished = Column(Boolean, default=False)
    last_played_episode_guid = Column(String, nullable=True)
    last_played_position_secs = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    episodes = relationship("PlaylistEpisode", back_populates="playlist", cascade="all, delete-orphan", order_by="PlaylistEpisode.position")

class PlaylistEpisode(Base):
    __tablename__ = "playlist_episodes"
    id = Column(Integer, primary_key=True, index=True)
    playlist_id = Column(Integer, ForeignKey("playlists.id", ondelete="CASCADE"), index=True, nullable=False)
    episode_guid = Column(String, index=True, nullable=False)
    episode_title = Column(String, nullable=False)
    podcast_id = Column(Integer, ForeignKey("podcasts.id"), nullable=True)
    podcast_title = Column(String, nullable=False)
    podcast_artwork_url = Column(String, nullable=True)
    enclosure_url = Column(String, nullable=True)
    duration_secs = Column(Integer, nullable=True)
    position = Column(Integer, default=0, index=True)
    is_completed = Column(Boolean, default=False)
    added_at = Column(DateTime, default=datetime.utcnow)

    playlist = relationship("Playlist", back_populates="episodes")

