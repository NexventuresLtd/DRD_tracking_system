import uuid
import enum
from datetime import datetime
from sqlalchemy import String, DateTime, Enum, ForeignKey, Text, Float, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class DrawingType(str, enum.Enum):
    line = "line"
    polygon = "polygon"
    circle = "circle"
    arrow = "arrow"
    boundary = "boundary"
    area = "area"
    search_zone = "search_zone"
    freehand = "freehand"


class Drawing(Base):
    __tablename__ = "drawings"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    drawing_type: Mapped[DrawingType] = mapped_column(Enum(DrawingType), nullable=False)
    color: Mapped[str] = mapped_column(String(7), default="#ef4444")
    fill_color: Mapped[str | None] = mapped_column(String(7), nullable=True)
    stroke_width: Mapped[float] = mapped_column(Float, default=2.0)
    opacity: Mapped[float] = mapped_column(Float, default=1.0)
    radius: Mapped[float | None] = mapped_column(Float, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    mission_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="SET NULL"), nullable=True)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    points: Mapped[list["DrawingPoint"]] = relationship("DrawingPoint", back_populates="drawing", cascade="all, delete-orphan", order_by="DrawingPoint.order_index")


class DrawingPoint(Base):
    __tablename__ = "drawing_points"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    drawing_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("drawings.id", ondelete="CASCADE"), nullable=False, index=True)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)

    drawing: Mapped["Drawing"] = relationship("Drawing", back_populates="points")
