# app/models/message.py
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UUID, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from app.database import Base

class Message(Base):
    __tablename__ = "messages"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    from_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    to_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"))
    to_team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"))
    to_all = Column(Boolean, default=False)
    content = Column(Text, nullable=False)
    priority = Column(String(20), default="normal")
    is_read = Column(Boolean, default=False)
    read_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    sender = relationship("User", back_populates="sent_messages", foreign_keys=[from_user_id])
    recipient = relationship("User", back_populates="received_messages", foreign_keys=[to_user_id])