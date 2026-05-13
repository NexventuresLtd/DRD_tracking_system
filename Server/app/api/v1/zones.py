# app/api/v1/zones.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import Optional, List
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel, Field

from app.database import get_db
from app.models.user import User
from app.models.zone import Zone, ZoneCoordinate, ZoneAssignment
from app.models.team import Team
from app.middleware.auth import get_current_user, require_commander
from app.websocket.manager import manager
import asyncio

class ZoneCoordinateCreate(BaseModel):
    latitude: float
    longitude: float
    sequence_order: Optional[int] = None

class ZoneCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=255)
    zone_type: str = Field(..., min_length=2, max_length=50)
    color: str = "#ec4899"
    description: Optional[str] = None
    coordinates: List[ZoneCoordinateCreate] = []
    assigned_team_ids: List[UUID] = []
    assigned_user_ids: List[UUID] = []
    # Circle zone fields
    center_lat: Optional[float] = None
    center_lng: Optional[float] = None
    radius_m: Optional[float] = None

class ZoneUpdate(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None
    description: Optional[str] = None
    is_active: Optional[bool] = None

class ZoneCoordinateResponse(BaseModel):
    id: UUID
    sequence_order: int
    latitude: float
    longitude: float
    
    class Config:
        from_attributes = True

class ZoneResponse(BaseModel):
    id: UUID
    name: str
    zone_type: str
    color: str
    description: Optional[str]
    created_by: UUID
    is_active: bool
    created_at: datetime
    updated_at: datetime
    coordinates: List[ZoneCoordinateResponse] = []
    assigned_team_ids: List[UUID] = []
    assigned_user_ids: List[UUID] = []
    center_lat: Optional[float] = None
    center_lng: Optional[float] = None
    radius_m: Optional[float] = None

    class Config:
        from_attributes = True

class ZoneAssignmentCreate(BaseModel):
    team_id: Optional[UUID] = None
    user_id: Optional[UUID] = None

router = APIRouter(prefix="/zones", tags=["Zones"])

@router.get("/", response_model=List[ZoneResponse])
async def list_zones(
    zone_type: Optional[str] = None,
    is_active: Optional[bool] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List all zones"""
    query = select(Zone)
    
    if zone_type:
        query = query.where(Zone.zone_type == zone_type)
    if is_active is not None:
        query = query.where(Zone.is_active == is_active)
    
    query = query.order_by(Zone.created_at.desc())
    
    result = await db.execute(query)
    zones = result.scalars().all()
    
    response = []
    for zone in zones:
        # Get coordinates
        coords_result = await db.execute(
            select(ZoneCoordinate)
            .where(ZoneCoordinate.zone_id == zone.id)
            .order_by(ZoneCoordinate.sequence_order)
        )
        coordinates = coords_result.scalars().all()
        
        # Get assignments
        assignments_result = await db.execute(
            select(ZoneAssignment).where(ZoneAssignment.zone_id == zone.id)
        )
        assignments = assignments_result.scalars().all()
        
        response.append(ZoneResponse(
            id=zone.id,
            name=zone.name,
            zone_type=zone.zone_type,
            color=zone.color,
            description=zone.description,
            created_by=zone.created_by,
            is_active=zone.is_active,
            created_at=zone.created_at,
            updated_at=zone.updated_at,
            coordinates=[
                ZoneCoordinateResponse(
                    id=c.id,
                    sequence_order=c.sequence_order,
                    latitude=c.latitude,
                    longitude=c.longitude,
                )
                for c in coordinates
            ],
            assigned_team_ids=[a.team_id for a in assignments if a.team_id],
            assigned_user_ids=[a.user_id for a in assignments if a.user_id],
            center_lat=zone.center_lat,
            center_lng=zone.center_lng,
            radius_m=zone.radius_m,
        ))
    
    return response

@router.post("/", response_model=ZoneResponse, status_code=status.HTTP_201_CREATED)
async def create_zone(
    data: ZoneCreate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Create a new zone"""
    zone = Zone(
        name=data.name,
        zone_type=data.zone_type,
        color=data.color,
        description=data.description,
        created_by=current_user.id,
        center_lat=data.center_lat,
        center_lng=data.center_lng,
        radius_m=data.radius_m,
    )
    
    db.add(zone)
    await db.flush()
    
    # Add coordinates
    for i, coord_data in enumerate(data.coordinates):
        coord = ZoneCoordinate(
            zone_id=zone.id,
            sequence_order=coord_data.sequence_order if coord_data.sequence_order is not None else i,
            latitude=coord_data.latitude,
            longitude=coord_data.longitude,
        )
        db.add(coord)
    
    # Add assignments
    for team_id in data.assigned_team_ids:
        assignment = ZoneAssignment(
            zone_id=zone.id,
            team_id=team_id,
        )
        db.add(assignment)
    
    for user_id in data.assigned_user_ids:
        assignment = ZoneAssignment(
            zone_id=zone.id,
            user_id=user_id,
        )
        db.add(assignment)
    
    await db.commit()
    await db.refresh(zone)

    # Broadcast so connected commanders refresh their maps immediately
    try:
        asyncio.create_task(manager.broadcast_event({
            "event_type": "ZONE",
            "description": f"Zone created: {zone.name}",
            "id": str(zone.id),
        }))
    except Exception:
        pass

    # Get coordinates for response
    coords_result = await db.execute(
        select(ZoneCoordinate)
        .where(ZoneCoordinate.zone_id == zone.id)
        .order_by(ZoneCoordinate.sequence_order)
    )
    coordinates = coords_result.scalars().all()
    
    return ZoneResponse(
        id=zone.id,
        name=zone.name,
        zone_type=zone.zone_type,
        color=zone.color,
        description=zone.description,
        created_by=zone.created_by,
        is_active=zone.is_active,
        created_at=zone.created_at,
        updated_at=zone.updated_at,
        coordinates=[
            ZoneCoordinateResponse(
                id=c.id,
                sequence_order=c.sequence_order,
                latitude=c.latitude,
                longitude=c.longitude,
            )
            for c in coordinates
        ],
        assigned_team_ids=data.assigned_team_ids,
        assigned_user_ids=data.assigned_user_ids,
        center_lat=zone.center_lat,
        center_lng=zone.center_lng,
        radius_m=zone.radius_m,
    )

@router.delete("/{zone_id}", status_code=status.HTTP_200_OK)
async def delete_zone(
    zone_id: UUID,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")
    await db.delete(zone)
    await db.commit()
    try:
        asyncio.create_task(manager.broadcast_event({"event_type": "ZONE", "description": "Zone deleted", "id": str(zone_id)}))
    except Exception:
        pass
    return {"message": "Zone deleted"}

@router.get("/{zone_id}", response_model=ZoneResponse)
async def get_zone(
    zone_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get zone details"""
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    
    if not zone:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Zone not found"
        )
    
    # Get coordinates
    coords_result = await db.execute(
        select(ZoneCoordinate)
        .where(ZoneCoordinate.zone_id == zone.id)
        .order_by(ZoneCoordinate.sequence_order)
    )
    coordinates = coords_result.scalars().all()
    
    # Get assignments
    assignments_result = await db.execute(
        select(ZoneAssignment).where(ZoneAssignment.zone_id == zone.id)
    )
    assignments = assignments_result.scalars().all()
    
    return ZoneResponse(
        id=zone.id,
        name=zone.name,
        zone_type=zone.zone_type,
        color=zone.color,
        description=zone.description,
        created_by=zone.created_by,
        is_active=zone.is_active,
        created_at=zone.created_at,
        updated_at=zone.updated_at,
        coordinates=[
            ZoneCoordinateResponse(
                id=c.id,
                sequence_order=c.sequence_order,
                latitude=c.latitude,
                longitude=c.longitude,
            )
            for c in coordinates
        ],
        assigned_team_ids=[a.team_id for a in assignments if a.team_id],
        assigned_user_ids=[a.user_id for a in assignments if a.user_id],
    )

@router.put("/{zone_id}", response_model=ZoneResponse)
async def update_zone(
    zone_id: UUID,
    data: ZoneUpdate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Update zone"""
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    
    if not zone:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Zone not found"
        )
    
    if data.name is not None:
        zone.name = data.name
    if data.color is not None:
        zone.color = data.color
    if data.description is not None:
        zone.description = data.description
    if data.is_active is not None:
        zone.is_active = data.is_active
    
    await db.commit()
    await db.refresh(zone)
    
    return ZoneResponse(
        id=zone.id,
        name=zone.name,
        zone_type=zone.zone_type,
        color=zone.color,
        description=zone.description,
        created_by=zone.created_by,
        is_active=zone.is_active,
        created_at=zone.created_at,
        updated_at=zone.updated_at,
        coordinates=[],
        assigned_team_ids=[],
        assigned_user_ids=[],
    )

@router.delete("/{zone_id}")
async def delete_zone(
    zone_id: UUID,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Delete zone"""
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    
    if not zone:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Zone not found"
        )
    
    zone.is_active = False
    await db.commit()
    
    return {"message": "Zone deactivated successfully"}

@router.post("/{zone_id}/assign")
async def assign_to_zone(
    zone_id: UUID,
    data: ZoneAssignmentCreate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Assign team or user to zone"""
    # Check zone exists
    zone_result = await db.execute(select(Zone).where(Zone.id == zone_id))
    if not zone_result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Zone not found"
        )
    
    if data.team_id:
        # Check if already assigned
        existing = await db.execute(
            select(ZoneAssignment).where(
                ZoneAssignment.zone_id == zone_id,
                ZoneAssignment.team_id == data.team_id,
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Team already assigned to this zone"
            )
        
        assignment = ZoneAssignment(
            zone_id=zone_id,
            team_id=data.team_id,
        )
    elif data.user_id:
        existing = await db.execute(
            select(ZoneAssignment).where(
                ZoneAssignment.zone_id == zone_id,
                ZoneAssignment.user_id == data.user_id,
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="User already assigned to this zone"
            )
        
        assignment = ZoneAssignment(
            zone_id=zone_id,
            user_id=data.user_id,
        )
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Must specify team_id or user_id"
        )
    
    db.add(assignment)
    await db.commit()
    
    return {"message": "Assignment added to zone successfully"}