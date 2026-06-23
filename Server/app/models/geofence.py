import uuid
import enum
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Enum, ForeignKey, Text, Float
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, JSONB
from app.database import Base


class GeofenceZoneType(str, enum.Enum):
    circle = "circle"
    polygon = "polygon"
    rectangle = "rectangle"


class GeofenceEventType(str, enum.Enum):
    entered = "entered"
    exited = "exited"


class Geofence(Base):
    __tablename__ = "geofences"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    zone_type: Mapped[GeofenceZoneType] = mapped_column(Enum(GeofenceZoneType), default=GeofenceZoneType.circle)
    center_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    center_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    radius: Mapped[float | None] = mapped_column(Float, nullable=True)
    polygon_points: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    color: Mapped[str] = mapped_column(String(7), default="#f59e0b")
    alert_on_enter: Mapped[bool] = mapped_column(Boolean, default=True)
    alert_on_exit: Mapped[bool] = mapped_column(Boolean, default=True)
    is_restricted: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    events: Mapped[list["GeofenceEvent"]] = relationship("GeofenceEvent", back_populates="geofence", cascade="all, delete-orphan")


class GeofenceEvent(Base):
    __tablename__ = "geofence_events"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    geofence_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("geofences.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    event_type: Mapped[GeofenceEventType] = mapped_column(Enum(GeofenceEventType), nullable=False)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, index=True)

    geofence: Mapped["Geofence"] = relationship("Geofence", back_populates="events")
