import uuid
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.location import Location, LocationHistory
from app.services.location_service import LocationService
from app.websocket.manager import manager

router = APIRouter(prefix="/locations", tags=["Locations"])


class LocationUpdate(BaseModel):
    latitude: float
    longitude: float
    altitude: Optional[float] = None
    heading: Optional[float] = None
    speed: Optional[float] = None
    accuracy: Optional[float] = None


@router.post("")
async def submit_location(
    data: LocationUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = LocationService(db)
    loc = await svc.update_location(
        user_id=current_user.id,
        latitude=data.latitude,
        longitude=data.longitude,
        altitude=data.altitude,
        heading=data.heading,
        speed=data.speed,
        accuracy=data.accuracy,
    )
    await manager.broadcast({
        "type": "location_update",
        "user_id": str(current_user.id),
        "latitude": loc.latitude,
        "longitude": loc.longitude,
        "heading": loc.heading,
        "speed": loc.speed,
        "status": loc.status.value,
        "timestamp": loc.last_update.isoformat() if loc.last_update else None,
    })
    return {"status": "updated"}


@router.get("/live")
async def get_live_locations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = LocationService(db)
    locations = await svc.get_all_live()
    return [
        {
            "user_id": str(loc.user_id),
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "altitude": loc.altitude,
            "heading": loc.heading,
            "speed": loc.speed,
            "status": loc.status.value,
            "last_update": loc.last_update.isoformat() if loc.last_update else None,
        }
        for loc in locations
    ]


@router.get("/{user_id}")
async def get_user_location(
    user_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = LocationService(db)
    loc = await svc.get_user_location(user_id)
    if not loc:
        return {"status": "no_location"}
    return {
        "user_id": str(loc.user_id),
        "latitude": loc.latitude,
        "longitude": loc.longitude,
        "altitude": loc.altitude,
        "heading": loc.heading,
        "speed": loc.speed,
        "status": loc.status.value,
        "last_update": loc.last_update.isoformat() if loc.last_update else None,
    }


@router.get("/{user_id}/history")
async def get_location_history(
    user_id: uuid.UUID,
    limit: int = Query(100, ge=1, le=1000),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(LocationHistory)
        .where(LocationHistory.user_id == user_id)
        .order_by(LocationHistory.timestamp.desc())
        .limit(limit)
    )
    history = result.scalars().all()
    return [
        {
            "latitude": h.latitude,
            "longitude": h.longitude,
            "altitude": h.altitude,
            "heading": h.heading,
            "speed": h.speed,
            "timestamp": h.timestamp.isoformat(),
        }
        for h in history
    ]
