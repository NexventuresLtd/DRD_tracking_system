import uuid
import enum
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Enum, ForeignKey, Text, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class MessageChannel(str, enum.Enum):
    global_chat = "global"
    team = "team"
    mission = "mission"
    dm = "dm"
    emergency = "emergency"


class MessageType(str, enum.Enum):
    text = "text"
    file = "file"
    location = "location"
    route = "route"
    voice = "voice"
    image = "image"


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    channel_type: Mapped[MessageChannel] = mapped_column(Enum(MessageChannel), nullable=False, index=True)
    channel_id: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    sender_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    content: Mapped[str | None] = mapped_column(Text, nullable=True)
    message_type: Mapped[MessageType] = mapped_column(Enum(MessageType), default=MessageType.text)
    reply_to_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="SET NULL"), nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, index=True)

    reads: Mapped[list["MessageRead"]] = relationship("MessageRead", back_populates="message", cascade="all, delete-orphan")
    attachments: Mapped[list["MessageAttachment"]] = relationship("MessageAttachment", back_populates="message", cascade="all, delete-orphan")


class MessageRead(Base):
    __tablename__ = "message_reads"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    read_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    message: Mapped["Message"] = relationship("Message", back_populates="reads")


class MessageAttachment(Base):
    __tablename__ = "message_attachments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    file_url: Mapped[str] = mapped_column(String(1000), nullable=False)
    file_type: Mapped[str | None] = mapped_column(String(100), nullable=True)
    file_name: Mapped[str | None] = mapped_column(String(500), nullable=True)
    file_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    message: Mapped["Message"] = relationship("Message", back_populates="attachments")
