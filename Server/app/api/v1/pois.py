import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.poi import POI

router = APIRouter(prefix="/pois", tags=["POIs"])


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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(POI))
    return result.scalars().all()


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
    await db.delete(poi)
    await db.commit()
    return {"message": "Deleted"}
