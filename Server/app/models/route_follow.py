from __future__ import annotations

import uuid

from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, JSON, String, Text, UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class RouteFollowSession(Base):
    __tablename__ = "route_follow_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"), index=True)

    status = Column(String(20), nullable=False, default="active", index=True)
    route_name_snapshot = Column(String(255), nullable=False)
    route_description_snapshot = Column(Text)
    route_color_snapshot = Column(String(7), nullable=False, default="#3b82f6")
    waypoints_snapshot = Column(JSON, nullable=False)

    start_latitude = Column(Float)
    start_longitude = Column(Float)
    last_latitude = Column(Float)
    last_longitude = Column(Float)
    current_waypoint_index = Column(Integer, default=0)
    progress_percent = Column(Float, default=0.0)
    distance_to_destination_m = Column(Float)
    eta_seconds = Column(Integer)
    last_recorded_at = Column(DateTime(timezone=True))
    completion_note = Column(Text)

    started_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    ended_at = Column(DateTime(timezone=True))

    route = relationship("Route")
    user = relationship("User")
    team = relationship("Team")
    points = relationship(
        "RouteFollowPoint",
        back_populates="session",
        order_by="RouteFollowPoint.recorded_at",
        cascade="all, delete-orphan",
    )


class RouteFollowPoint(Base):
    __tablename__ = "route_follow_points"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(UUID(as_uuid=True), ForeignKey("route_follow_sessions.id"), nullable=False, index=True)
    route_id = Column(UUID(as_uuid=True), ForeignKey("routes.id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    altitude = Column(Float)
    speed = Column(Float)
    heading = Column(Float)
    accuracy = Column(Float)
    battery_level = Column(Integer)
    recorded_at = Column(DateTime(timezone=True), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    session = relationship("RouteFollowSession", back_populates="points")
