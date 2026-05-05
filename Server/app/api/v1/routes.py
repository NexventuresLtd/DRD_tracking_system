# app/api/v1/routes.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload
from typing import Optional, List
from uuid import UUID
import asyncio

from app.database import get_db
from app.models.user import User, UserRole
from app.models.route import Route, RouteWaypoint, RouteVisibility, RouteHistory
from app.models.route_follow import RouteFollowSession
from app.models.team import Team, TeamMember
from app.schemas.route import RouteCreate, RouteUpdate, RouteResponse, RouteHistoryResponse, WaypointCreate, WaypointResponse
from app.middleware.auth import get_current_user, require_commander
from app.websocket.manager import manager

router = APIRouter(prefix="/routes", tags=["Routes"])


def _route_waypoints_payload(waypoints: List[RouteWaypoint]) -> list[dict]:
    return [
        {
            "id": str(wp.id),
            "sequence_order": wp.sequence_order,
            "latitude": wp.latitude,
            "longitude": wp.longitude,
            "label": wp.label,
            "poi_type": wp.poi_type,
        }
        for wp in waypoints
    ]


def _route_response(
    route: Route,
    *,
    creator_name: Optional[str] = None,
    assigned_team_name: Optional[str] = None,
    assigned_user_name: Optional[str] = None,
    route_status: Optional[str] = None,
    active_follow_count: int = 0,
) -> RouteResponse:
    waypoints = getattr(route, "waypoints", []) or []
    return RouteResponse(
        id=route.id,
        name=route.name,
        description=route.description,
        created_by=route.created_by,
        assigned_team_id=route.assigned_team_id,
        assigned_user_id=route.assigned_user_id,
        color=route.color,
        is_active=route.is_active,
        is_zone=route.is_zone,
        zone_type=route.zone_type,
        meeting_point=route.meeting_point,
        created_at=route.created_at,
        updated_at=route.updated_at,
        waypoints=[
            WaypointResponse(
                id=wp.id,
                sequence_order=wp.sequence_order,
                latitude=wp.latitude,
                longitude=wp.longitude,
                label=wp.label,
                poi_type=wp.poi_type,
            )
            for wp in waypoints
        ],
        created_by_name=creator_name,
        assigned_team_name=assigned_team_name,
        assigned_user_name=assigned_user_name,
        route_status=route_status,
        active_follow_count=active_follow_count,
    )


async def _broadcast_route_event(route: Route, current_user: User, description: str, waypoints: Optional[List[RouteWaypoint]] = None) -> None:
    payload_waypoints = waypoints or []
    event_data = {
        "id": str(route.id),
        "event_type": "ZONE" if route.is_zone else "ROUTE",
        "user_id": str(current_user.id),
        "team_id": str(route.assigned_team_id) if route.assigned_team_id else None,
        "description": description,
        "location_lat": payload_waypoints[0].latitude if payload_waypoints else None,
        "location_lng": payload_waypoints[0].longitude if payload_waypoints else None,
        "event_metadata": {
            "route_id": str(route.id),
            "assigned_team_id": str(route.assigned_team_id) if route.assigned_team_id else None,
            "assigned_user_id": str(route.assigned_user_id) if route.assigned_user_id else None,
            "is_zone": route.is_zone,
            "is_active": route.is_active,
        },
        "severity": "low",
        "created_at": route.created_at.isoformat() if route.created_at else None,
    }
    try:
        asyncio.create_task(manager.broadcast_event(event_data))
    except Exception:
        asyncio.get_event_loop().create_task(manager.broadcast_event(event_data))

@router.get("/", response_model=List[RouteResponse])
async def list_routes(
    team_id: Optional[UUID] = None,
    user_id: Optional[UUID] = None,
    is_active: Optional[bool] = None,
    is_zone: Optional[bool] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List all routes"""
    query = select(Route).options(
        selectinload(Route.waypoints),
        selectinload(Route.created_by_user),
        selectinload(Route.assigned_team),
        selectinload(Route.assigned_user),
    )
    
    if team_id:
        query = query.where(Route.assigned_team_id == team_id)
    if user_id:
        query = query.where(Route.assigned_user_id == user_id)
    if is_active is not None:
        query = query.where(Route.is_active == is_active)
    if is_zone is not None:
        query = query.where(Route.is_zone == is_zone)
    
    query = query.order_by(Route.created_at.desc())
    
    result = await db.execute(query)
    routes = result.scalars().all()

    deleted_route_ids_result = await db.execute(select(RouteHistory.route_id))
    deleted_route_ids = {row[0] for row in deleted_route_ids_result.all()}
    routes = [route for route in routes if route.id not in deleted_route_ids]

    privileged_roles = {
        UserRole.SUPER_ADMIN,
        UserRole.ADMIN,
        UserRole.COMMANDER,
        UserRole.OPERATOR,
    }

    visible_routes = routes
    if current_user.role not in privileged_roles:
        team_ids_result = await db.execute(
            select(TeamMember.team_id).where(
                TeamMember.user_id == current_user.id,
                TeamMember.is_active == True,
            )
        )
        team_ids = {row[0] for row in team_ids_result.all()}

        route_ids = [r.id for r in routes]
        vis_map: dict[UUID, list[RouteVisibility]] = {}
        if route_ids:
            vis_result = await db.execute(
                select(RouteVisibility).where(RouteVisibility.route_id.in_(route_ids))
            )
            for vis in vis_result.scalars().all():
                vis_map.setdefault(vis.route_id, []).append(vis)

        filtered: List[Route] = []
        for route in routes:
            vis_rows = vis_map.get(route.id, [])
            can_view = (
                route.created_by == current_user.id
                or route.assigned_user_id == current_user.id
                or (route.assigned_team_id in team_ids if route.assigned_team_id else False)
                or any(v.visible_to_all for v in vis_rows)
                or any(v.user_id == current_user.id for v in vis_rows)
                or any(v.team_id in team_ids for v in vis_rows if v.team_id is not None)
            )
            if can_view:
                filtered.append(route)
        visible_routes = filtered

    active_route_ids = [route.id for route in visible_routes]
    active_sessions_map: dict[UUID, list[RouteFollowSession]] = {}
    if active_route_ids:
        session_result = await db.execute(
            select(RouteFollowSession)
            .where(
                RouteFollowSession.route_id.in_(active_route_ids),
                RouteFollowSession.status == "active",
            )
            .order_by(RouteFollowSession.started_at.desc())
        )
        for session in session_result.scalars().all():
            active_sessions_map.setdefault(session.route_id, []).append(session)
    
    response = []
    for route in visible_routes:
        sessions = active_sessions_map.get(route.id, [])
        if sessions:
            route_status = "active"
        elif route.is_active:
            route_status = "assigned" if (route.assigned_team_id or route.assigned_user_id) else "available"
        else:
            route_status = "completed"

        response.append(
            _route_response(
                route,
                creator_name=route.created_by_user.full_name if route.created_by_user else None,
                assigned_team_name=route.assigned_team.name if route.assigned_team else None,
                assigned_user_name=route.assigned_user.full_name if route.assigned_user else None,
                route_status=route_status,
                active_follow_count=len(sessions),
            )
        )

    return response


@router.get("/history", response_model=List[RouteHistoryResponse])
async def list_route_history(
    team_id: Optional[UUID] = None,
    user_id: Optional[UUID] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List deleted/completed route snapshots."""
    query = select(RouteHistory)

    if team_id:
        query = query.where(RouteHistory.assigned_team_id == team_id)
    if user_id:
        query = query.where(RouteHistory.assigned_user_id == user_id)

    query = query.order_by(RouteHistory.deleted_at.desc())
    result = await db.execute(query)
    history_rows = result.scalars().all()

    response: list[RouteHistoryResponse] = []
    for row in history_rows:
        response.append(
            RouteHistoryResponse(
                route_id=row.route_id,
                id=row.id,
                name=row.name,
                description=row.description,
                created_by=row.created_by,
                assigned_team_id=row.assigned_team_id,
                assigned_user_id=row.assigned_user_id,
                color=row.color,
                is_active=row.is_active,
                is_zone=row.is_zone,
                zone_type=row.zone_type,
                meeting_point=row.meeting_point,
                created_at=row.deleted_at,
                updated_at=row.deleted_at,
                deleted_at=row.deleted_at,
                waypoints=[
                    WaypointResponse(
                        id=UUID(wp["id"]) if isinstance(wp.get("id"), str) else wp["id"],
                        sequence_order=wp["sequence_order"],
                        latitude=wp["latitude"],
                        longitude=wp["longitude"],
                        label=wp.get("label"),
                        poi_type=wp.get("poi_type"),
                    )
                    for wp in (row.waypoints or [])
                ],
            )
        )

    return response

@router.post("/", response_model=RouteResponse, status_code=status.HTTP_201_CREATED)
async def create_route(
    data: RouteCreate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Create a new route"""
    # Create route
    route = Route(
        name=data.name,
        description=data.description,
        created_by=current_user.id,
        assigned_team_id=data.assigned_team_id,
        assigned_user_id=data.assigned_user_id,
        color=data.color or "#3b82f6",
        is_zone=data.is_zone,
        zone_type=data.zone_type,
        meeting_point=data.meeting_point,
    )
    
    db.add(route)
    await db.flush()
    
    # Add waypoints
    for i, wp_data in enumerate(data.waypoints):
        waypoint = RouteWaypoint(
            route_id=route.id,
            sequence_order=wp_data.sequence_order if wp_data.sequence_order is not None else i,
            latitude=wp_data.latitude,
            longitude=wp_data.longitude,
            label=wp_data.label,
            poi_type=wp_data.poi_type,
        )
        db.add(waypoint)
    
    # Add visibility
    if data.visible_to_all:
        visibility = RouteVisibility(
            route_id=route.id,
            visible_to_all=True,
        )
        db.add(visibility)
    
    for team_id in data.visible_to_teams:
        visibility = RouteVisibility(
            route_id=route.id,
            team_id=team_id,
        )
        db.add(visibility)
    
    for user_id in data.visible_to_users:
        visibility = RouteVisibility(
            route_id=route.id,
            user_id=user_id,
        )
        db.add(visibility)
    
    await db.commit()
    await db.refresh(route)

    waypoints_result = await db.execute(
        select(RouteWaypoint)
        .where(RouteWaypoint.route_id == route.id)
        .order_by(RouteWaypoint.sequence_order)
    )
    waypoints = waypoints_result.scalars().all()

    # Broadcast route creation/update notification in real time
    try:
        await _broadcast_route_event(route, current_user, f"{'Zone' if route.is_zone else 'Route'} created: {route.name}", waypoints)
    except Exception:
        pass
    
    return RouteResponse(
        id=route.id,
        name=route.name,
        description=route.description,
        created_by=route.created_by,
        assigned_team_id=route.assigned_team_id,
        assigned_user_id=route.assigned_user_id,
        color=route.color,
        is_active=route.is_active,
        is_zone=route.is_zone,
        zone_type=route.zone_type,
        meeting_point=route.meeting_point,
        created_at=route.created_at,
        updated_at=route.updated_at,
        waypoints=[
            WaypointResponse(
                id=wp.id,
                sequence_order=wp.sequence_order,
                latitude=wp.latitude,
                longitude=wp.longitude,
                label=wp.label,
                poi_type=wp.poi_type,
            )
            for wp in waypoints
        ],
        created_by_name=current_user.full_name,
    )

@router.get("/{route_id}", response_model=RouteResponse)
async def get_route(
    route_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get route details"""
    result = await db.execute(select(Route).where(Route.id == route_id))
    route = result.scalar_one_or_none()
    
    if not route:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Route not found"
        )
    
    # Get waypoints
    waypoints_result = await db.execute(
        select(RouteWaypoint)
        .where(RouteWaypoint.route_id == route.id)
        .order_by(RouteWaypoint.sequence_order)
    )
    waypoints = waypoints_result.scalars().all()
    
    return RouteResponse(
        id=route.id,
        name=route.name,
        description=route.description,
        created_by=route.created_by,
        assigned_team_id=route.assigned_team_id,
        assigned_user_id=route.assigned_user_id,
        color=route.color,
        is_active=route.is_active,
        is_zone=route.is_zone,
        zone_type=route.zone_type,
        meeting_point=route.meeting_point,
        created_at=route.created_at,
        updated_at=route.updated_at,
        waypoints=[
            WaypointResponse(
                id=wp.id,
                sequence_order=wp.sequence_order,
                latitude=wp.latitude,
                longitude=wp.longitude,
                label=wp.label,
                poi_type=wp.poi_type,
            )
            for wp in waypoints
        ],
    )

@router.put("/{route_id}", response_model=RouteResponse)
async def update_route(
    route_id: UUID,
    data: RouteUpdate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Update route"""
    result = await db.execute(select(Route).where(Route.id == route_id))
    route = result.scalar_one_or_none()
    
    if not route:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Route not found"
        )
    
    if data.name is not None:
        route.name = data.name
    if data.description is not None:
        route.description = data.description
    if data.color is not None:
        route.color = data.color
    if data.is_active is not None:
        route.is_active = data.is_active
    if data.meeting_point is not None:
        route.meeting_point = data.meeting_point
    
    await db.commit()
    await db.refresh(route)

    waypoints_result = await db.execute(
        select(RouteWaypoint)
        .where(RouteWaypoint.route_id == route.id)
        .order_by(RouteWaypoint.sequence_order)
    )
    waypoints = waypoints_result.scalars().all()

    try:
        await _broadcast_route_event(
            route,
            current_user,
            f"{'Zone' if route.is_zone else 'Route'} updated: {route.name}",
            waypoints,
        )
    except Exception:
        pass
    
    return RouteResponse(
        id=route.id,
        name=route.name,
        description=route.description,
        created_by=route.created_by,
        assigned_team_id=route.assigned_team_id,
        assigned_user_id=route.assigned_user_id,
        color=route.color,
        is_active=route.is_active,
        is_zone=route.is_zone,
        zone_type=route.zone_type,
        meeting_point=route.meeting_point,
        created_at=route.created_at,
        updated_at=route.updated_at,
        waypoints=[
            WaypointResponse(
                id=wp.id,
                sequence_order=wp.sequence_order,
                latitude=wp.latitude,
                longitude=wp.longitude,
                label=wp.label,
                poi_type=wp.poi_type,
            )
            for wp in waypoints
        ],
    )

@router.post("/{route_id}/complete", response_model=RouteResponse)
async def complete_route(
    route_id: UUID,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Mark a route as completed."""
    result = await db.execute(select(Route).where(Route.id == route_id))
    route = result.scalar_one_or_none()

    if not route:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Route not found"
        )

    route.is_active = False
    await db.commit()
    await db.refresh(route)

    waypoints_result = await db.execute(
        select(RouteWaypoint)
        .where(RouteWaypoint.route_id == route.id)
        .order_by(RouteWaypoint.sequence_order)
    )
    waypoints = waypoints_result.scalars().all()

    try:
        await _broadcast_route_event(route, current_user, f"Route completed: {route.name}", waypoints)
    except Exception:
        pass

    return RouteResponse(
        id=route.id,
        name=route.name,
        description=route.description,
        created_by=route.created_by,
        assigned_team_id=route.assigned_team_id,
        assigned_user_id=route.assigned_user_id,
        color=route.color,
        is_active=route.is_active,
        is_zone=route.is_zone,
        zone_type=route.zone_type,
        meeting_point=route.meeting_point,
        created_at=route.created_at,
        updated_at=route.updated_at,
        waypoints=[
            WaypointResponse(
                id=wp.id,
                sequence_order=wp.sequence_order,
                latitude=wp.latitude,
                longitude=wp.longitude,
                label=wp.label,
                poi_type=wp.poi_type,
            )
            for wp in waypoints
        ],
    )

@router.delete("/{route_id}")
async def delete_route(
    route_id: UUID,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Soft delete route"""
    result = await db.execute(select(Route).where(Route.id == route_id))
    route = result.scalar_one_or_none()
    
    if not route:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Route not found"
        )

    waypoints_result = await db.execute(
        select(RouteWaypoint)
        .where(RouteWaypoint.route_id == route.id)
        .order_by(RouteWaypoint.sequence_order)
    )
    waypoints = waypoints_result.scalars().all()

    history = RouteHistory(
        route_id=route.id,
        name=route.name,
        description=route.description,
        created_by=route.created_by,
        assigned_team_id=route.assigned_team_id,
        assigned_user_id=route.assigned_user_id,
        color=route.color,
        is_zone=route.is_zone,
        zone_type=route.zone_type,
        meeting_point=route.meeting_point,
        is_active=False,
        waypoints=[
            {
                "id": str(wp.id),
                "sequence_order": wp.sequence_order,
                "latitude": wp.latitude,
                "longitude": wp.longitude,
                "label": wp.label,
                "poi_type": wp.poi_type,
            }
            for wp in waypoints
        ],
    )
    db.add(history)
    
    route.is_active = False
    await db.commit()

    try:
        await _broadcast_route_event(route, current_user, f"Route deactivated: {route.name}", waypoints)
    except Exception:
        pass
    
    return {"message": "Route deactivated successfully"}

@router.post("/{route_id}/waypoints", status_code=status.HTTP_201_CREATED)
async def add_waypoint(
    route_id: UUID,
    data: WaypointCreate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Add waypoint to route"""
    result = await db.execute(select(Route).where(Route.id == route_id))
    route = result.scalar_one_or_none()
    
    if not route:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Route not found"
        )
    
    # Get next sequence order
    max_seq_result = await db.execute(
        select(func.max(RouteWaypoint.sequence_order))
        .where(RouteWaypoint.route_id == route_id)
    )
    max_seq = max_seq_result.scalar() or -1
    
    waypoint = RouteWaypoint(
        route_id=route_id,
        sequence_order=max_seq + 1,
        latitude=data.latitude,
        longitude=data.longitude,
        label=data.label,
        poi_type=data.poi_type,
    )
    
    db.add(waypoint)
    await db.commit()
    await db.refresh(waypoint)
    
    return WaypointResponse(
        id=waypoint.id,
        sequence_order=waypoint.sequence_order,
        latitude=waypoint.latitude,
        longitude=waypoint.longitude,
        label=waypoint.label,
        poi_type=waypoint.poi_type,
    )