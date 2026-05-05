from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.route import WaypointResponse


class RouteFollowStartRequest(BaseModel):
    route_id: UUID
    current_latitude: Optional[float] = Field(None, ge=-90, le=90)
    current_longitude: Optional[float] = Field(None, ge=-180, le=180)


class RouteFollowStopRequest(BaseModel):
    completion_note: Optional[str] = None


class RouteFollowCompleteRequest(BaseModel):
    completion_note: Optional[str] = None


class RouteFollowSessionResponse(BaseModel):
    id: UUID
    route_id: UUID
    user_id: UUID
    team_id: Optional[UUID]
    status: str
    route_name_snapshot: str
    route_description_snapshot: Optional[str]
    route_color_snapshot: str
    waypoints_snapshot: list[dict]
    start_latitude: Optional[float]
    start_longitude: Optional[float]
    last_latitude: Optional[float]
    last_longitude: Optional[float]
    current_waypoint_index: int
    progress_percent: float
    distance_to_destination_m: Optional[float]
    eta_seconds: Optional[int]
    last_recorded_at: Optional[datetime]
    started_at: datetime
    updated_at: datetime
    ended_at: Optional[datetime]
    completion_note: Optional[str]

    class Config:
        from_attributes = True


class RouteFollowSessionDetailResponse(RouteFollowSessionResponse):
    waypoints: list[WaypointResponse] = []


class RouteFollowUpdateResponse(BaseModel):
    session: RouteFollowSessionResponse
    route_id: UUID
    user_id: UUID
    team_id: Optional[UUID]
    latitude: float
    longitude: float
    progress_percent: float
    current_waypoint_index: int
    distance_to_destination_m: Optional[float]
    eta_seconds: Optional[int]
    recorded_at: datetime
