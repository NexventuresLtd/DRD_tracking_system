from sqlalchemy import Column, String, DateTime, Boolean, Float, UUID
from sqlalchemy.sql import func
import uuid
from app.database import Base


class LiveSession(Base):
    __tablename__ = "live_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    room_id = Column(String(255), nullable=False, index=True)
    initiator_name = Column(String(255), default="Unknown")
    team_name = Column(String(255), default="")
    lat = Column(Float, nullable=True)
    lng = Column(Float, nullable=True)
    saved = Column(Boolean, default=False)
    duration_seconds = Column(Float, nullable=True)
    video_file_path = Column(String(500), nullable=True)
    started_at = Column(DateTime(timezone=True), server_default=func.now())
    ended_at = Column(DateTime(timezone=True), nullable=True)
