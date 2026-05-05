# app/models/user.py
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, UUID, Enum as SQLEnum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from app.database import Base
import enum

class UserRole(str, enum.Enum):
    SUPER_ADMIN = "super_admin"
    ADMIN = "admin"
    COMMANDER = "commander"
    OPERATOR = "operator"
    VIEWER = "viewer"
    FIELD_UNIT = "field_unit"

class User(Base):
    __tablename__ = "users"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    username = Column(String(100), unique=True, nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(200))
    role = Column(SQLEnum(UserRole), default=UserRole.FIELD_UNIT)
    phone = Column(String(20))
    is_active = Column(Boolean, default=True)
    is_verified = Column(Boolean, default=False)
    last_login = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # Relationships - use string references to avoid circular imports
    team_memberships = relationship("TeamMember", back_populates="user")
    locations = relationship("Location", back_populates="user")
    location_history = relationship("LocationHistory", back_populates="user")
    created_routes = relationship("Route", back_populates="created_by_user", foreign_keys="Route.created_by")
    assigned_routes = relationship("Route", back_populates="assigned_user", foreign_keys="Route.assigned_user_id")
    sent_messages = relationship("Message", back_populates="sender", foreign_keys="Message.from_user_id")
    received_messages = relationship("Message", back_populates="recipient", foreign_keys="Message.to_user_id")
    created_pois = relationship("POI", back_populates="creator")
    created_zones = relationship("Zone", back_populates="creator")
    user_flags = relationship("UserFlag", back_populates="user", foreign_keys="UserFlag.user_id")
    notifications = relationship("Notification", back_populates="user")
    audit_logs = relationship("AuditLog", back_populates="user")