# app/models/event.py
from sqlalchemy import Column, String, DateTime, ForeignKey, UUID, Float, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from app.database import Base

class Event(Base):
    __tablename__ = "events"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_type = Column(String(50), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"))
    description = Column(String(500))
    location_lat = Column(Float)
    location_lng = Column(Float)
    event_metadata = Column(JSON)
    severity = Column(String(20), default="low")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # No back_populates needed for Event - use simple relationships
    user = relationship("User")
    team = relationship("Team")