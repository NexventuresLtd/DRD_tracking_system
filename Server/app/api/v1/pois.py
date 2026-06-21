# app/api/v1/pois.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import Optional, List
from uuid import UUID
import asyncio

from app.database import get_db
from app.models.user import User, UserRole
from app.models.poi import POI, POIVisibility
from app.models.team import TeamMember
from app.middleware.auth import get_current_user, require_any_user, require_commander
from pydantic import BaseModel, Field
from datetime import datetime
from app.websocket.manager import manager

# Schemas for POI
class POICreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = None
    poi_type: str = Field(..., min_length=2, max_length=50)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    tactical_shape: str = "diamond"
    status: str = "active"
    visible_to_all: bool = True
    visible_to_teams: List[UUID] = []
    visible_to_users: List[UUID] = []

class POIUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    tactical_shape: Optional[str] = None
    visible_to_all: Optional[bool] = None

class POIResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str]
    poi_type: str
    latitude: float
    longitude: float
    tactical_shape: Optional[str] = "diamond"
    status: Optional[str] = "active"
    created_by: Optional[UUID]
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    visible_to_all: bool = False

    class Config:
        from_attributes = True

class POIVisibilityUpdate(BaseModel):
    visible_to_all: bool = False
    team_ids: List[UUID] = []
    user_ids: List[UUID] = []

router = APIRouter(prefix="/pois", tags=["POIs"])

@router.get("/", response_model=List[POIResponse])
async def list_pois(
    poi_type: Optional[str] = None,
    status: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List all POIs"""
    query = select(POI)
    
    if poi_type:
        query = query.where(POI.poi_type == poi_type)
    if status:
        query = query.where(POI.status == status)
    
    query = query.order_by(POI.created_at.desc())
    
    result = await db.execute(query)
    pois = result.scalars().all()

    privileged_roles = {
        UserRole.SUPER_ADMIN,
        UserRole.ADMIN,
        UserRole.COMMANDER,
        UserRole.OPERATOR,
    }

    visible_pois = pois
    if current_user.role not in privileged_roles:
        team_ids_result = await db.execute(
            select(TeamMember.team_id).where(
                TeamMember.user_id == current_user.id,
                TeamMember.is_active == True,
            )
        )
        team_ids = {row[0] for row in team_ids_result.all()}

        poi_ids = [p.id for p in pois]
        vis_map: dict[UUID, list[POIVisibility]] = {}
        if poi_ids:
            vis_result = await db.execute(
                select(POIVisibility).where(POIVisibility.poi_id.in_(poi_ids))
            )
            for vis in vis_result.scalars().all():
                vis_map.setdefault(vis.poi_id, []).append(vis)

        filtered: List[POI] = []
        for poi in pois:
            vis_rows = vis_map.get(poi.id, [])
            can_view = (
                poi.created_by == current_user.id
                or any(v.visible_to_all for v in vis_rows)
                or any(v.user_id == current_user.id for v in vis_rows)
                or any(v.team_id in team_ids for v in vis_rows if v.team_id is not None)
            )
            if can_view:
                filtered.append(poi)
        visible_pois = filtered
    
    response = []
    for poi in visible_pois:
        # Check if visible to all
        vis_result = await db.execute(
            select(POIVisibility).where(
                POIVisibility.poi_id == poi.id,
                POIVisibility.visible_to_all == True,
            )
        )
        visible_to_all = vis_result.scalar_one_or_none() is not None
        
        response.append(POIResponse(
            id=poi.id,
            name=poi.name,
            description=poi.description,
            poi_type=poi.poi_type,
            latitude=poi.latitude,
            longitude=poi.longitude,
            tactical_shape=poi.tactical_shape,
            status=poi.status,
            created_by=poi.created_by,
            created_at=poi.created_at,
            updated_at=poi.updated_at,
            visible_to_all=visible_to_all,
        ))
    
    return response

@router.post("/", response_model=POIResponse, status_code=status.HTTP_201_CREATED)
async def create_poi(
    data: POICreate,
    current_user: User = Depends(require_any_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new POI"""
    poi = POI(
        name=data.name,
        description=data.description,
        poi_type=data.poi_type,
        latitude=data.latitude,
        longitude=data.longitude,
        tactical_shape=data.tactical_shape,
        status=data.status,
        created_by=current_user.id,
    )
    
    db.add(poi)
    await db.flush()
    
    # Set visibility
    if data.visible_to_all:
        visibility = POIVisibility(
            poi_id=poi.id,
            visible_to_all=True,
        )
        db.add(visibility)
    
    for team_id in data.visible_to_teams:
        visibility = POIVisibility(
            poi_id=poi.id,
            team_id=team_id,
        )
        db.add(visibility)
    
    for user_id in data.visible_to_users:
        visibility = POIVisibility(
            poi_id=poi.id,
            user_id=user_id,
        )
        db.add(visibility)
    
    await db.commit()
    await db.refresh(poi)

    # Broadcast POI creation/update notification in real time
    try:
        event_data = {
            "id": str(poi.id),
            "event_type": "POI",
            "user_id": str(current_user.id),
            "team_id": None,
            "description": f"POI created: {poi.name}",
            "location_lat": poi.latitude,
            "location_lng": poi.longitude,
            "event_metadata": {
                "poi_id": str(poi.id),
                "poi_type": poi.poi_type,
                "status": poi.status,
            },
            "severity": "low",
            "created_at": poi.created_at.isoformat() if poi.created_at else None,
        }
        try:
            asyncio.create_task(manager.broadcast_event(event_data))
        except Exception:
            asyncio.get_event_loop().create_task(manager.broadcast_event(event_data))
    except Exception:
        pass
    
    return POIResponse(
        id=poi.id,
        name=poi.name,
        description=poi.description,
        poi_type=poi.poi_type,
        latitude=poi.latitude,
        longitude=poi.longitude,
        tactical_shape=poi.tactical_shape,
        status=poi.status,
        created_by=poi.created_by,
        created_at=poi.created_at,
        updated_at=poi.updated_at,
        visible_to_all=data.visible_to_all,
    )

@router.get("/{poi_id}", response_model=POIResponse)
async def get_poi(
    poi_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get POI details"""
    result = await db.execute(select(POI).where(POI.id == poi_id))
    poi = result.scalar_one_or_none()
    
    if not poi:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="POI not found"
        )
    
    return POIResponse(
        id=poi.id,
        name=poi.name,
        description=poi.description,
        poi_type=poi.poi_type,
        latitude=poi.latitude,
        longitude=poi.longitude,
        tactical_shape=poi.tactical_shape,
        status=poi.status,
        created_by=poi.created_by,
        created_at=poi.created_at,
        updated_at=poi.updated_at,
    )

@router.put("/{poi_id}", response_model=POIResponse)
async def update_poi(
    poi_id: UUID,
    data: POIUpdate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Update POI"""
    result = await db.execute(select(POI).where(POI.id == poi_id))
    poi = result.scalar_one_or_none()
    
    if not poi:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="POI not found"
        )
    
    if data.name is not None:
        poi.name = data.name
    if data.description is not None:
        poi.description = data.description
    if data.status is not None:
        poi.status = data.status
    if data.tactical_shape is not None:
        poi.tactical_shape = data.tactical_shape
    
    await db.commit()
    await db.refresh(poi)
    
    return POIResponse(
        id=poi.id,
        name=poi.name,
        description=poi.description,
        poi_type=poi.poi_type,
        latitude=poi.latitude,
        longitude=poi.longitude,
        tactical_shape=poi.tactical_shape,
        status=poi.status,
        created_by=poi.created_by,
        created_at=poi.created_at,
        updated_at=poi.updated_at,
    )

@router.delete("/{poi_id}")
async def delete_poi(
    poi_id: UUID,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Permanently delete a POI and its visibility records"""
    result = await db.execute(select(POI).where(POI.id == poi_id))
    poi = result.scalar_one_or_none()

    if not poi:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="POI not found"
        )

    # Delete child visibility records first to avoid FK constraint errors
    vis_result = await db.execute(select(POIVisibility).where(POIVisibility.poi_id == poi_id))
    for vis in vis_result.scalars().all():
        await db.delete(vis)

    await db.delete(poi)
    await db.commit()

    return {"message": "POI deleted successfully"}

@router.put("/{poi_id}/visibility")
async def update_poi_visibility(
    poi_id: UUID,
    data: POIVisibilityUpdate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Update POI visibility settings"""
    # Delete existing visibility
    await db.execute(
        select(POIVisibility).where(POIVisibility.poi_id == poi_id)
    )
    
    # Add new visibility
    if data.visible_to_all:
        vis = POIVisibility(poi_id=poi_id, visible_to_all=True)
        db.add(vis)
    
    for team_id in data.team_ids:
        vis = POIVisibility(poi_id=poi_id, team_id=team_id)
        db.add(vis)
    
    for user_id in data.user_ids:
        vis = POIVisibility(poi_id=poi_id, user_id=user_id)
        db.add(vis)
    
    await db.commit()
    
    return {"message": "POI visibility updated successfully"}