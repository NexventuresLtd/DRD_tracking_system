import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user, require_leader_or_above
from app.models.user import User
from app.models.route import Route, RouteWaypoint, RouteAssignment, RouteType

router = APIRouter(prefix="/routes", tags=["Routes"])


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


@router.get("")
async def list_routes(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Route).options(selectinload(Route.waypoints)).where(Route.is_active == True)
    )
    routes = result.scalars().all()
    return [
        {
            "id": str(r.id),
            "name": r.name,
            "description": r.description,
            "route_type": r.route_type.value,
            "color": r.color,
            "created_by": str(r.created_by),
            "waypoint_count": len(r.waypoints),
            "created_at": r.created_at.isoformat(),
        }
        for r in routes
    ]


@router.post("", status_code=201)
async def create_route(
    data: RouteCreate,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    route = Route(
        name=data.name,
        description=data.description,
        route_type=data.route_type,
        color=data.color,
        created_by=current_user.id,
        mission_id=data.mission_id,
    )
    db.add(route)
    await db.flush()

    for i, wp in enumerate(data.waypoints):
        waypoint = RouteWaypoint(
            route_id=route.id,
            order_index=i,
            latitude=wp.latitude,
            longitude=wp.longitude,
            altitude=wp.altitude,
            name=wp.name,
            notes=wp.notes,
        )
        db.add(waypoint)

    await db.commit()
    await db.refresh(route)
    return {"id": str(route.id), "name": route.name}


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
        "id": str(route.id),
        "name": route.name,
        "description": route.description,
        "route_type": route.route_type.value,
        "color": route.color,
        "created_at": route.created_at.isoformat(),
        "waypoints": [
            {"order": w.order_index, "latitude": w.latitude, "longitude": w.longitude, "name": w.name}
            for w in route.waypoints
        ],
    }


@router.delete("/{route_id}")
async def delete_route(
    route_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Route).where(Route.id == route_id))
    route = result.scalar_one_or_none()
    if not route:
        raise HTTPException(status_code=404, detail="Route not found")
    route.is_active = False
    await db.commit()
    return {"message": "Route deleted"}
