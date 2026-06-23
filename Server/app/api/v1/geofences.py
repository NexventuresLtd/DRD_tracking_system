import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user, require_leader_or_above
from app.models.user import User
from app.models.geofence import Geofence, GeofenceZoneType

router = APIRouter(prefix="/geofences", tags=["Geofences"])


class GeofenceCreate(BaseModel):
    name: str
    description: Optional[str] = None
    zone_type: GeofenceZoneType = GeofenceZoneType.circle
    center_lat: Optional[float] = None
    center_lng: Optional[float] = None
    radius: Optional[float] = None
    polygon_points: Optional[list] = None
    color: str = "#6366f1"
    is_active: bool = True


@router.get("")
async def list_geofences(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Geofence).where(Geofence.is_active == True))
    return [
        {
            "id": str(g.id),
            "name": g.name,
            "description": g.description,
            "zone_type": g.zone_type.value,
            "center_lat": g.center_lat,
            "center_lng": g.center_lng,
            "radius": g.radius,
            "color": g.color if hasattr(g, "color") else "#6366f1",
            "is_active": g.is_active,
            "created_at": g.created_at.isoformat(),
        }
        for g in result.scalars().all()
    ]


@router.post("", status_code=201)
async def create_geofence(
    data: GeofenceCreate,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    fence = Geofence(
        name=data.name,
        description=data.description,
        zone_type=data.zone_type,
        center_lat=data.center_lat,
        center_lng=data.center_lng,
        radius=data.radius,
        is_active=data.is_active,
        created_by=current_user.id,
    )
    db.add(fence)
    await db.commit()
    await db.refresh(fence)
    return {"id": str(fence.id), "name": fence.name}


@router.delete("/{fence_id}")
async def delete_geofence(
    fence_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Geofence).where(Geofence.id == fence_id))
    fence = result.scalar_one_or_none()
    if not fence:
        raise HTTPException(status_code=404, detail="Geofence not found")
    fence.is_active = False
    await db.commit()
    return {"message": "Deleted"}
