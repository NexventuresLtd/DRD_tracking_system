import uuid
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.sos import SOSEvent, SOSStatus
from app.websocket.manager import manager

router = APIRouter(prefix="/sos", tags=["SOS"])


class SOSTrigger(BaseModel):
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    altitude: Optional[float] = None
    message: Optional[str] = None


@router.post("", status_code=201)
async def trigger_sos(
    data: SOSTrigger,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    event = SOSEvent(
        triggered_by=current_user.id,
        latitude=data.latitude,
        longitude=data.longitude,
        altitude=data.altitude,
        message=data.message,
        status=SOSStatus.active,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)

    await manager.broadcast_to_room(
        "events",
        {
            "type": "sos_alert",
            "sos_id": str(event.id),
            "triggered_by": str(current_user.id),
            "user_name": current_user.full_name,
            "latitude": data.latitude,
            "longitude": data.longitude,
            "message": data.message,
            "status": "active",
            "created_at": event.created_at.isoformat(),
        },
    )
    return {"id": str(event.id), "status": "active"}


@router.get("")
async def list_sos(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(SOSEvent).order_by(SOSEvent.created_at.desc()).limit(50)
    )
    events = result.scalars().all()
    return [
        {
            "id": str(e.id),
            "triggered_by": str(e.triggered_by),
            "latitude": e.latitude,
            "longitude": e.longitude,
            "message": e.message,
            "status": e.status.value,
            "acknowledged_by": str(e.acknowledged_by) if e.acknowledged_by else None,
            "acknowledged_at": e.acknowledged_at.isoformat() if e.acknowledged_at else None,
            "resolved_at": e.resolved_at.isoformat() if e.resolved_at else None,
            "created_at": e.created_at.isoformat(),
        }
        for e in events
    ]


@router.put("/{sos_id}/acknowledge")
async def acknowledge_sos(
    sos_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(SOSEvent).where(SOSEvent.id == sos_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="SOS not found")
    if event.status != SOSStatus.active:
        raise HTTPException(status_code=400, detail="SOS is not active")

    event.status = SOSStatus.acknowledged
    event.acknowledged_by = current_user.id
    event.acknowledged_at = datetime.now(timezone.utc)
    await db.commit()

    await manager.broadcast_to_room(
        "events",
        {"type": "sos_acknowledged", "sos_id": str(sos_id), "acknowledged_by": current_user.full_name},
    )
    return {"status": "acknowledged"}


@router.put("/{sos_id}/resolve")
async def resolve_sos(
    sos_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(SOSEvent).where(SOSEvent.id == sos_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="SOS not found")

    event.status = SOSStatus.resolved
    event.resolved_by = current_user.id
    event.resolved_at = datetime.now(timezone.utc)
    await db.commit()

    await manager.broadcast_to_room(
        "events",
        {"type": "sos_resolved", "sos_id": str(sos_id), "resolved_by": current_user.full_name},
    )
    return {"status": "resolved"}
