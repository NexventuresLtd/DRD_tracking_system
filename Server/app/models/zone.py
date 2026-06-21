# app/models/zone.py
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UUID, Float, Integer
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from app.database import Base

class Zone(Base):
    __tablename__ = "zones"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    zone_type = Column(String(50), nullable=False)
    color = Column(String(7), default="#ec4899")
    description = Column(String(500))
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    is_active = Column(Boolean, default=True)
    # Circle zone fields (null = polygon zone)
    center_lat = Column(Float, nullable=True)
    center_lng = Column(Float, nullable=True)
    radius_m = Column(Float, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    creator = relationship("User", back_populates="created_zones")
    coordinates = relationship("ZoneCoordinate", back_populates="zone", order_by="ZoneCoordinate.sequence_order")
    assignments = relationship("ZoneAssignment", back_populates="zone")
    posts = relationship("ZonePost", back_populates="zone", cascade="all, delete-orphan")

class ZoneCoordinate(Base):
    __tablename__ = "zone_coordinates"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    zone_id = Column(UUID(as_uuid=True), ForeignKey("zones.id"), nullable=False)
    sequence_order = Column(Integer, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    zone = relationship("Zone", back_populates="coordinates")

class ZoneAssignment(Base):
    __tablename__ = "zone_assignments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    zone_id = Column(UUID(as_uuid=True), ForeignKey("zones.id"), nullable=False)
    team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"))
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    assigned_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    zone = relationship("Zone", back_populates="assignments")
    team = relationship("Team", back_populates="zone_assignments")


class ZonePost(Base):
    """A named position point inside a zone where soldiers are posted."""
    __tablename__ = "zone_posts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    zone_id = Column(UUID(as_uuid=True), ForeignKey("zones.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(255), nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    description = Column(String(500))
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    zone = relationship("Zone", back_populates="posts")
    soldier_assignments = relationship("ZonePostAssignment", back_populates="post", cascade="all, delete-orphan")


class ZonePostAssignment(Base):
    """Which soldier is assigned to which zone post."""
    __tablename__ = "zone_post_assignments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    post_id = Column(UUID(as_uuid=True), ForeignKey("zone_posts.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    assigned_by = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    assigned_at = Column(DateTime(timezone=True), server_default=func.now())

    post = relationship("ZonePost", back_populates="soldier_assignments")
    user = relationship("User", foreign_keys=[user_id])
    assigner = relationship("User", foreign_keys=[assigned_by])