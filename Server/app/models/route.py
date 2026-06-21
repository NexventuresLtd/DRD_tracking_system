# app/models/route.py
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UUID, Integer, Float, Text, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from app.database import Base

class Route(Base):
    __tablename__ = "routes"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    assigned_team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"))
    assigned_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    color = Column(String(7), default="#3b82f6")
    is_active = Column(Boolean, default=True)
    proposed_status = Column(String(20), nullable=False, default="approved", server_default="approved")
    is_zone = Column(Boolean, default=False)
    zone_type = Column(String(50))
    meeting_point = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships
    created_by_user = relationship("User", back_populates="created_routes", foreign_keys=[created_by])
    assigned_user = relationship("User", back_populates="assigned_routes", foreign_keys=[assigned_user_id])
    assigned_team = relationship("Team", back_populates="assigned_routes", foreign_keys=[assigned_team_id])
    waypoints = relationship("RouteWaypoint", back_populates="route", order_by="RouteWaypoint.sequence_order")
    visibility = relationship("RouteVisibility", back_populates="route")

class RouteWaypoint(Base):
    __tablename__ = "route_waypoints"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id"), nullable=False)
    sequence_order = Column(Integer, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    label = Column(String(100))
    poi_type = Column(String(50))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    route = relationship("Route", back_populates="waypoints")

class RouteVisibility(Base):
    __tablename__ = "route_visibility"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"))
    visible_to_all = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    route = relationship("Route", back_populates="visibility")
    team = relationship("Team", back_populates="route_visibility")


class RouteHistory(Base):
    __tablename__ = "route_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    assigned_team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"))
    assigned_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    color = Column(String(7), default="#3b82f6")
    is_zone = Column(Boolean, default=False)
    zone_type = Column(String(50))
    meeting_point = Column(Boolean, default=False)
    is_active = Column(Boolean, default=False)
    waypoints = Column(JSON, nullable=False)
    deleted_at = Column(DateTime(timezone=True), server_default=func.now())

    created_by_user = relationship("User", foreign_keys=[created_by])
    assigned_user = relationship("User", foreign_keys=[assigned_user_id])
    assigned_team = relationship("Team", foreign_keys=[assigned_team_id])