# app/schemas/route.py
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from uuid import UUID

class WaypointCreate(BaseModel):
    latitude: float
    longitude: float
    label: Optional[str] = None
    poi_type: Optional[str] = None
    sequence_order: Optional[int] = None

class WaypointResponse(BaseModel):
    id: UUID
    sequence_order: int
    latitude: float
    longitude: float
    label: Optional[str]
    poi_type: Optional[str]
    
    class Config:
        from_attributes = True

class RouteCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    assigned_team_id: Optional[UUID] = None
    assigned_user_id: Optional[UUID] = None
    color: Optional[str] = "#3b82f6"
    is_zone: bool = False
    zone_type: Optional[str] = None  # perimeter, sector, corridor, extraction
    meeting_point: bool = False
    waypoints: List[WaypointCreate]
    visible_to_all: bool = True
    visible_to_teams: List[UUID] = []
    visible_to_users: List[UUID] = []

class RouteUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None
    is_active: Optional[bool] = None
    meeting_point: Optional[bool] = None

class RouteResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str]
    created_by: UUID
    assigned_team_id: Optional[UUID]
    assigned_user_id: Optional[UUID]
    color: str
    is_active: bool
    is_zone: bool
    zone_type: Optional[str]
    meeting_point: bool
    created_at: datetime
    updated_at: datetime
    waypoints: List[WaypointResponse] = []
    created_by_name: Optional[str] = None
    assigned_team_name: Optional[str] = None
    assigned_user_name: Optional[str] = None
    route_status: Optional[str] = None
    active_follow_count: int = 0
    
    class Config:
        from_attributes = True


class RouteHistoryResponse(RouteResponse):
    route_id: UUID
    deleted_at: datetime

    class Config:
        from_attributes = True