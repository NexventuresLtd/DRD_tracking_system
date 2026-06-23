import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user, require_leader_or_above
from app.models.user import User
from app.models.zone import Zone
from app.websocket.manager import manager

router = APIRouter(prefix="/zones", tags=["Zones"])


class ZoneCreate(BaseModel):
    name: str
    description: Optional[str] = None
    zone_type: str = "operational"
    color: str = "#6366f1"
    fill_color: Optional[str] = None
    polygon_points: Optional[dict] = None
    center_lat: Optional[float] = None
    center_lng: Optional[float] = None
    radius: Optional[float] = None
    is_circle: bool = False
    mission_id: Optional[uuid.UUID] = None


@router.get("")
async def list_zones(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Zone).where(Zone.is_active == True))
    return result.scalars().all()


@router.post("", status_code=201)
async def create_zone(
    data: ZoneCreate,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    zone = Zone(**data.model_dump(), created_by=current_user.id)
    db.add(zone)
    await db.commit()
    await db.refresh(zone)
    await manager.broadcast({"type": "zone_created", "zone_id": str(zone.id), "name": zone.name})
    return zone


@router.put("/{zone_id}")
async def update_zone(
    zone_id: uuid.UUID,
    data: ZoneCreate,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=404, detail="Zone not found")
    for k, v in data.model_dump(exclude_none=True).items():
        setattr(zone, k, v)
    await db.commit()
    return zone


@router.delete("/{zone_id}")
async def delete_zone(
    zone_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=404, detail="Zone not found")
    zone.is_active = False
    await db.commit()
    await manager.broadcast({"type": "zone_deleted", "zone_id": str(zone_id)})
    return {"message": "Zone deleted"}
