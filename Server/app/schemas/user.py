import uuid
from datetime import datetime
from pydantic import BaseModel, EmailStr
from typing import Optional
from app.models.user import UserRole


class UserBase(BaseModel):
    email: EmailStr
    username: str
    full_name: str
    phone: Optional[str] = None


class UserResponse(BaseModel):
    id: uuid.UUID
    email: str
    username: str
    full_name: str
    role: UserRole
    phone: Optional[str] = None
    avatar_url: Optional[str] = None
    is_active: bool
    is_verified: bool
    last_seen: Optional[datetime] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    username: Optional[str] = None


class UserRoleUpdate(BaseModel):
    role: UserRole


class UserListResponse(BaseModel):
    users: list[UserResponse]
    total: int
    page: int
    page_size: int
