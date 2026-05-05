# app/models/team.py
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from app.database import Base

class Team(Base):
    __tablename__ = "teams"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(100), unique=True, nullable=False)
    code = Column(String(50), unique=True, nullable=False)
    color = Column(String(7), default="#3b82f6")
    description = Column(String(500))
    is_active = Column(Boolean, default=True)
    lead_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    lead = relationship("User", foreign_keys=[lead_id])
    members = relationship("TeamMember", back_populates="team")
    assigned_routes = relationship("Route", back_populates="assigned_team", foreign_keys="Route.assigned_team_id")
    locations = relationship("Location", back_populates="team")
    zone_assignments = relationship("ZoneAssignment", back_populates="team")
    poi_visibility = relationship("POIVisibility", back_populates="team")
    route_visibility = relationship("RouteVisibility", back_populates="team")

class TeamMember(Base):
    __tablename__ = "team_members"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    role = Column(String(50))  # lead, medic, scout, support, sniper
    joined_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True)
    
    # Relationships
    team = relationship("Team", back_populates="members")
    user = relationship("User", back_populates="team_memberships")