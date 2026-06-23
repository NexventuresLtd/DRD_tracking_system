import uuid
import enum
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Enum, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class CallType(str, enum.Enum):
    voice = "voice"
    video = "video"


class CallStatus(str, enum.Enum):
    pending = "pending"
    active = "active"
    ended = "ended"
    missed = "missed"
    declined = "declined"


class Call(Base):
    __tablename__ = "calls"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    call_type: Mapped[CallType] = mapped_column(Enum(CallType), nullable=False)
    initiator_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    channel_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    channel_type: Mapped[str | None] = mapped_column(String(50), nullable=True)
    status: Mapped[CallStatus] = mapped_column(Enum(CallStatus), default=CallStatus.pending)
    room_id: Mapped[str] = mapped_column(String(255), nullable=False, default=lambda: str(uuid.uuid4()))
    recording_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    participants: Mapped[list["CallParticipant"]] = relationship("CallParticipant", back_populates="call", cascade="all, delete-orphan")


class CallParticipant(Base):
    __tablename__ = "call_participants"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    call_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("calls.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    is_muted: Mapped[bool] = mapped_column(Boolean, default=False)
    is_video_on: Mapped[bool] = mapped_column(Boolean, default=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    left_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    call: Mapped["Call"] = relationship("Call", back_populates="participants")
