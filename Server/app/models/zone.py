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
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    creator = relationship("User", back_populates="created_zones")
    coordinates = relationship("ZoneCoordinate", back_populates="zone", order_by="ZoneCoordinate.sequence_order")
    assignments = relationship("ZoneAssignment", back_populates="zone")

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