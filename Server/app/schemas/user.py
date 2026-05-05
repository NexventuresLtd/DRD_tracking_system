# app/schemas/user.py
from pydantic import BaseModel, EmailStr, Field
from typing import Optional, List
from datetime import datetime
from uuid import UUID

class UserBase(BaseModel):
    email: EmailStr
    username: str
    full_name: Optional[str] = None
    phone: Optional[str] = None
    role: Optional[str] = "field_unit"

class UserCreate(UserBase):
    password: str = Field(..., min_length=8)
    team_id: Optional[UUID] = None
    team_role: Optional[str] = None  # lead, medic, scout, support, sniper

class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None

class UserResponse(UserBase):
    id: UUID
    is_active: bool
    is_verified: bool
    last_login: Optional[datetime]
    created_at: datetime
    updated_at: datetime
    team: Optional[dict] = None
    team_role: Optional[str] = None
    
    class Config:
        from_attributes = True

class UserListResponse(BaseModel):
    total: int
    items: List[UserResponse]
    page: int
    size: int