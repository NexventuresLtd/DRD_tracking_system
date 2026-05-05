# app/schemas/team.py
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from uuid import UUID

class TeamBase(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    code: str = Field(..., min_length=2, max_length=50)
    color: Optional[str] = "#3b82f6"
    description: Optional[str] = None

class TeamCreate(TeamBase):
    lead_id: Optional[UUID] = None

class TeamUpdate(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None
    description: Optional[str] = None
    lead_id: Optional[UUID] = None
    is_active: Optional[bool] = None

class TeamMemberCreate(BaseModel):
    user_id: UUID
    role: str = "support"  # lead, medic, scout, support, sniper

class TeamMemberResponse(BaseModel):
    id: UUID
    user_id: UUID
    user_name: str
    role: str
    joined_at: datetime
    is_active: bool
    
    class Config:
        from_attributes = True

class TeamResponse(TeamBase):
    id: UUID
    lead_id: Optional[UUID]
    is_active: bool
    created_at: datetime
    updated_at: datetime
    members: List[TeamMemberResponse] = []
    member_count: int = 0
    
    class Config:
        from_attributes = True