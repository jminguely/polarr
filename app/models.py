from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from .database import Base

class Podcast(Base):
    __tablename__ = "podcasts"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    feed_url = Column(String, unique=True, index=True)
    abs_id = Column(String, unique=True, nullable=True)
    subscribed = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    history = relationship("PlayHistory", back_populates="podcast", cascade="all, delete-orphan")

class PlayHistory(Base):
    __tablename__ = "play_history"
    id = Column(Integer, primary_key=True, index=True)
    podcast_id = Column(Integer, ForeignKey("podcasts.id"))
    episode_guid = Column(String, index=True)
    episode_title = Column(String, nullable=True)
    played_at = Column(DateTime, default=datetime.utcnow)
    
    podcast = relationship("Podcast", back_populates="history")
