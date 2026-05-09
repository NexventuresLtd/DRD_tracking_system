from __future__ import annotations

from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user, require_commander
from app.models.user import User
from app.schemas.route import WaypointResponse
from app.schemas.route_follow import (
    RouteFollowCompleteRequest,
    RouteFollowSessionDetailResponse,
    RouteFollowSessionResponse,
    RouteFollowStartRequest,
    RouteFollowStopRequest,
)
from app.services.route_follow_service import RouteFollowService

router = APIRouter(prefix="/route-follow-sessions", tags=["Route Follow Sessions"])


def _serialize_session(session) -> RouteFollowSessionResponse:
    return RouteFollowSessionResponse(
        id=session.id,
        route_id=session.route_id,
        user_id=session.user_id,
        team_id=session.team_id,
        status=session.status,
        route_name_snapshot=session.route_name_snapshot,
        route_description_snapshot=session.route_description_snapshot,
        route_color_snapshot=session.route_color_snapshot,
        waypoints_snapshot=session.waypoints_snapshot or [],
        start_latitude=session.start_latitude,
        start_longitude=session.start_longitude,
        last_latitude=session.last_latitude,
        last_longitude=session.last_longitude,
        current_waypoint_index=session.current_waypoint_index or 0,
        progress_percent=float(session.progress_percent or 0.0),
        distance_to_destination_m=session.distance_to_destination_m,
        eta_seconds=session.eta_seconds,
        last_recorded_at=session.last_recorded_at,
        started_at=session.started_at,
        updated_at=session.updated_at,
        ended_at=session.ended_at,
        completion_note=session.completion_note,
    )


@router.get("", response_model=List[RouteFollowSessionResponse], include_in_schema=False)
@router.get("/", response_model=List[RouteFollowSessionResponse])
async def list_follow_sessions(
    status: Optional[str] = Query(None),
    team_id: Optional[UUID] = None,
    route_id: Optional[UUID] = None,
    user_id: Optional[UUID] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = RouteFollowService(db)
    sessions = await service.list_sessions(
        status=status or "active",
        route_id=route_id,
        user_id=user_id,
        team_id=team_id,
    )
    return [_serialize_session(session) for session in sessions]


@router.get("/me/", include_in_schema=False)
@router.get("/me")
async def get_my_active_session(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Returns the active session or null — never raises 404 so the mobile never crashes on no-session."""
    service = RouteFollowService(db)
    session = await service.get_active_session_for_user(current_user.id)
    if not session:
        return None
    return _serialize_session(session)


@router.get("/{session_id}/", response_model=RouteFollowSessionDetailResponse, include_in_schema=False)
@router.get("/{session_id}", response_model=RouteFollowSessionDetailResponse)
async def get_follow_session(
    session_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = RouteFollowService(db)
    session = await service.get_session_by_id(session_id)
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Follow session not found")

    serialized = _serialize_session(session)
    return RouteFollowSessionDetailResponse(
        **serialized.model_dump(),
        waypoints=[WaypointResponse(**waypoint) for waypoint in (session.waypoints_snapshot or [])],
    )


@router.post("/start/", response_model=RouteFollowSessionResponse, status_code=status.HTTP_201_CREATED, include_in_schema=False)
@router.post("/start", response_model=RouteFollowSessionResponse, status_code=status.HTTP_201_CREATED)
async def start_follow_session(
    data: RouteFollowStartRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = RouteFollowService(db)
    session = await service.start_follow(
        route_id=data.route_id,
        current_user=current_user,
        current_latitude=data.current_latitude,
        current_longitude=data.current_longitude,
    )
    await service.broadcast_session_update(session, "route_follow_started")
    return _serialize_session(session)


@router.post("/{session_id}/stop/", response_model=RouteFollowSessionResponse, include_in_schema=False)
@router.post("/{session_id}/stop", response_model=RouteFollowSessionResponse)
async def stop_follow_session(
    session_id: UUID,
    data: RouteFollowStopRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = RouteFollowService(db)
    session = await service.stop_follow(session_id, current_user, note=data.completion_note)
    await service.broadcast_session_update(session, "route_follow_stopped")
    return _serialize_session(session)


@router.post("/{session_id}/complete/", response_model=RouteFollowSessionResponse, include_in_schema=False)
@router.post("/{session_id}/complete", response_model=RouteFollowSessionResponse)
async def complete_follow_session(
    session_id: UUID,
    data: RouteFollowCompleteRequest,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db),
):
    service = RouteFollowService(db)
    session = await service.complete_follow(session_id, current_user, note=data.completion_note)
    await service.broadcast_session_update(session, "route_follow_completed")
    return _serialize_session(session)
