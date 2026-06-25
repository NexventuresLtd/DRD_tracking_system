import uuid
from datetime import datetime
from pydantic import BaseModel
from typing import Optional
from app.schemas.user import UserResponse


class TeamCreate(BaseModel):
    name: str
    description: Optional[str] = None
    color: Optional[str] = "#3b82f6"
    icon: Optional[str] = None


class TeamUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None
    icon: Optional[str] = None
    leader_id: Optional[uuid.UUID] = None
    location_sharing: Optional[bool] = None


class TeamMemberResponse(BaseModel):
    id: uuid.UUID
    team_id: uuid.UUID
    user_id: uuid.UUID
    role_in_team: str
    joined_at: datetime
    user: Optional[UserResponse] = None

    model_config = {"from_attributes": True}


class TeamResponse(BaseModel):
    id: uuid.UUID
    name: str
    description: Optional[str] = None
    leader_id: Optional[uuid.UUID] = None
    color: str
    icon: Optional[str] = None
    location_sharing: bool = False
    is_active: bool
    created_at: datetime
    member_count: Optional[int] = None

    model_config = {"from_attributes": True}


class TeamDetailResponse(TeamResponse):
    members: list[TeamMemberResponse] = []


class AddMemberRequest(BaseModel):
    user_id: uuid.UUID
    role_in_team: Optional[str] = "member"


class UpdateMemberRequest(BaseModel):
    role_in_team: str
