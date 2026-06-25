import uuid
from typing import Optional
from datetime import date
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, cast, Date
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.poi import POI
from app.models.evidence import Evidence
from app.websocket.manager import manager

router = APIRouter(prefix="/pois", tags=["POIs"])


def _poi_dict(poi: POI, creator: "User | None" = None) -> dict:
    return {
        "id": str(poi.id),
        "name": poi.name,
        "description": poi.description,
        "latitude": poi.latitude,
        "longitude": poi.longitude,
        "altitude": poi.altitude,
        "poi_type": poi.poi_type,
        "icon": poi.icon,
        "color": poi.color,
        "team_id": str(poi.team_id) if poi.team_id else None,
        "mission_id": str(poi.mission_id) if poi.mission_id else None,
        "created_by": str(poi.created_by) if poi.created_by else None,
        "creator_name": (creator.full_name or creator.username) if creator else None,
        "creator_username": creator.username if creator else None,
        "created_at": poi.created_at.isoformat() if poi.created_at else None,
    }


class POICreate(BaseModel):
    name: str
    description: Optional[str] = None
    latitude: float
    longitude: float
    altitude: Optional[float] = None
    poi_type: str = "general"
    icon: Optional[str] = None
    color: str = "#8b5cf6"
    team_id: Optional[uuid.UUID] = None
    mission_id: Optional[uuid.UUID] = None


@router.get("")
async def list_pois(
    my_marks: bool = Query(False, description="Only return marks created by the current user"),
    today_only: bool = Query(False, description="Only return marks created today"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = select(POI)
    if my_marks:
        q = q.where(POI.created_by == current_user.id)
    if today_only:
        q = q.where(cast(POI.created_at, Date) == func.current_date())
    result = await db.execute(q.order_by(POI.created_at.desc()))
    pois = result.scalars().all()
    creator_ids = list({p.created_by for p in pois if p.created_by})
    creators: dict = {}
    if creator_ids:
        u_result = await db.execute(select(User).where(User.id.in_(creator_ids)))
        creators = {u.id: u for u in u_result.scalars().all()}
    return [_poi_dict(p, creators.get(p.created_by)) for p in pois]


@router.post("", status_code=201)
async def create_poi(
    data: POICreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    poi = POI(**data.model_dump(), created_by=current_user.id)
    db.add(poi)
    await db.commit()
    await db.refresh(poi)
    await manager.broadcast({"type": "poi_created", "poi": _poi_dict(poi, current_user)}, room="events")
    return poi


@router.put("/{poi_id}")
async def update_poi(
    poi_id: uuid.UUID,
    data: POICreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(POI).where(POI.id == poi_id))
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")
    for k, v in data.model_dump(exclude_none=True).items():
        setattr(poi, k, v)
    await db.commit()
    await manager.broadcast({"type": "poi_updated", "poi": _poi_dict(poi)}, room="events")
    return poi


@router.delete("/{poi_id}")
async def delete_poi(
    poi_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(POI).where(POI.id == poi_id))
    poi = result.scalar_one_or_none()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")
    poi_id_str = str(poi.id)
    await db.delete(poi)
    await db.commit()
    await manager.broadcast({"type": "poi_deleted", "poi_id": poi_id_str}, room="events")
    return {"message": "Deleted"}


@router.get("/{poi_id}/evidence")
async def get_poi_evidence(
    poi_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return all evidence items linked to a specific map marker (POI)."""
    result = await db.execute(select(POI).where(POI.id == poi_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="POI not found")
    ev_result = await db.execute(
        select(Evidence).where(Evidence.poi_id == poi_id).order_by(Evidence.created_at.desc())
    )
    items = ev_result.scalars().all()
    return [
        {
            "id": str(e.id),
            "title": e.title,
            "description": e.description,
            "evidence_type": e.evidence_type,
            "file_url": e.file_url,
            "latitude": e.latitude,
            "longitude": e.longitude,
            "mission_id": str(e.mission_id) if e.mission_id else None,
            "created_by": str(e.created_by) if e.created_by else None,
            "approval_status": e.approval_status,
            "created_at": e.created_at.isoformat() if e.created_at else None,
        }
        for e in items
    ]
