import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from sqlalchemy.orm import selectinload
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user, require_coordinator, require_planning_or_above
from app.models.user import User, UserRole
from app.models.route import Route, RouteWaypoint, RouteType
from app.websocket.manager import manager

router = APIRouter(prefix="/routes", tags=["Routes"])

COORD = UserRole.operations_coordinator
PLANNING = UserRole.planning_officer


class WaypointIn(BaseModel):
    latitude: float
    longitude: float
    altitude: Optional[float] = None
    name: Optional[str] = None
    notes: Optional[str] = None


class RouteCreate(BaseModel):
    name: str
    description: Optional[str] = None
    route_type: RouteType = RouteType.patrol
    color: Optional[str] = "#3b82f6"
    mission_id: Optional[uuid.UUID] = None
    waypoints: list[WaypointIn] = []


def _route_dict(r: Route) -> dict:
    wps = sorted(r.waypoints or [], key=lambda w: w.order_index)
    return {
        "id": str(r.id),
        "name": r.name,
        "description": r.description,
        "route_type": r.route_type.value,
        "color": r.color,
        "created_by": str(r.created_by) if r.created_by else None,
        "waypoint_count": len(wps),
        "review_status": r.review_status,
        "created_at": r.created_at.isoformat(),
        "waypoints": [
            {"order": w.order_index, "latitude": w.latitude, "longitude": w.longitude, "name": w.name}
            for w in wps
        ],
    }


@router.get("")
async def list_routes(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = select(Route).options(selectinload(Route.waypoints)).where(Route.is_active == True)
    # Non-coordinators only see approved routes + their own pending
    if current_user.role != COORD:
        q = q.where(
            or_(
                Route.review_status == "approved",
                (Route.created_by == current_user.id),
            )
        )
    result = await db.execute(q)
    return [_route_dict(r) for r in result.scalars().all()]


@router.post("", status_code=201)
async def create_route(
    data: RouteCreate,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    # Planning officers submit for review; coordinators auto-approve
    review_status = "pending_review" if current_user.role == PLANNING else "approved"

    route = Route(
        name=data.name,
        description=data.description,
        route_type=data.route_type,
        color=data.color,
        created_by=current_user.id,
        mission_id=data.mission_id,
        review_status=review_status,
    )
    db.add(route)
    await db.flush()

    for i, wp in enumerate(data.waypoints):
        db.add(RouteWaypoint(
            route_id=route.id,
            order_index=i,
            latitude=wp.latitude,
            longitude=wp.longitude,
            altitude=wp.altitude,
            name=wp.name,
            notes=wp.notes,
        ))

    await db.commit()
    await db.refresh(route)

    # Notify all connected users of coordinator role when planning officer submits
    if current_user.role == PLANNING:
        await manager.broadcast({
            "type": "route_pending_review",
            "route_id": str(route.id),
            "route_name": route.name,
            "submitted_by": current_user.full_name,
        })

    return {"id": str(route.id), "name": route.name, "review_status": review_status}


@router.get("/{route_id}")
async def get_route(
    route_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Route).options(selectinload(Route.waypoints))
        .where(Route.id == route_id, Route.is_active == True)
    )
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    return {
        **_route_dict(route),
        "waypoints": [
            {"order": w.order_index, "latitude": w.latitude, "longitude": w.longitude, "name": w.name}
            for w in route.waypoints
        ],
    }


@router.post("/{route_id}/approve", status_code=200)
async def approve_route(
    route_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Route).where(Route.id == route_id, Route.is_active == True))
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    route.review_status = "approved"
    await db.commit()
    return {"id": str(route.id), "review_status": "approved"}


@router.post("/{route_id}/reject", status_code=200)
async def reject_route(
    route_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Route).where(Route.id == route_id, Route.is_active == True))
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    route.review_status = "rejected"
    await db.commit()
    return {"id": str(route.id), "review_status": "rejected"}


@router.delete("/{route_id}")
async def delete_route(
    route_id: uuid.UUID,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Route).where(Route.id == route_id))
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    # Planning officers can only delete their own routes
    if current_user.role == PLANNING and route.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Cannot delete another officer's route")
    route.is_active = False
    await db.commit()
    return {"message": "Route deleted"}
