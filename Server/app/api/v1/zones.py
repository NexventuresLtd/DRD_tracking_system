# app/api/v1/zones.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import Optional, List
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel, Field
import math

from app.database import get_db
from app.models.user import User
from app.models.location import Location
from app.models.zone import Zone, ZoneCoordinate, ZoneAssignment, ZonePost, ZonePostAssignment
from app.models.team import Team, TeamMember
from app.middleware.auth import get_current_user, require_commander
from app.websocket.manager import manager
import asyncio


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Return distance in metres between two GPS coordinates."""
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

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

class ZonePostSummary(BaseModel):
    id: UUID
    name: str
    latitude: float
    longitude: float
    description: Optional[str]
    soldier_count: int = 0

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
    posts: List[ZonePostSummary] = []

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

        # Get posts with assignment counts
        posts_result = await db.execute(
            select(ZonePost).where(ZonePost.zone_id == zone.id)
        )
        zone_posts = posts_result.scalars().all()
        post_summaries = []
        for zp in zone_posts:
            count_result = await db.execute(
                select(func.count(ZonePostAssignment.id))
                .where(ZonePostAssignment.post_id == zp.id)
            )
            soldier_count = count_result.scalar() or 0
            post_summaries.append(ZonePostSummary(
                id=zp.id, name=zp.name, latitude=zp.latitude,
                longitude=zp.longitude, description=zp.description,
                soldier_count=soldier_count,
            ))

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
            posts=post_summaries,
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


# ─── Zone Posts ────────────────────────────────────────────────────────────────

class ZonePostCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    latitude: float
    longitude: float
    description: Optional[str] = None


class ZonePostAssignRequest(BaseModel):
    user_ids: List[UUID]


class SoldierAtPost(BaseModel):
    user_id: UUID
    name: str
    status: str
    distance_m: Optional[float] = None
    at_post: bool


class ZonePostResponse(BaseModel):
    id: UUID
    zone_id: UUID
    name: str
    latitude: float
    longitude: float
    description: Optional[str]
    soldiers: List[SoldierAtPost] = []

    class Config:
        from_attributes = True


async def _require_commander_or_lead(current_user: User, db: AsyncSession) -> User:
    """Allow commander/admin/super_admin or a team lead (field_unit with lead role)."""
    if current_user.role.value in ("commander", "admin", "super_admin"):
        return current_user
    # Check team lead
    result = await db.execute(
        select(TeamMember).where(
            TeamMember.user_id == current_user.id,
            TeamMember.role == "lead",
            TeamMember.is_active == True,
        )
    )
    if result.scalar_one_or_none():
        return current_user
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Commander or team lead required")


@router.post("/{zone_id}/posts", response_model=ZonePostResponse, status_code=status.HTTP_201_CREATED)
async def create_zone_post(
    zone_id: UUID,
    data: ZonePostCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a named position point inside a zone."""
    await _require_commander_or_lead(current_user, db)

    zone_result = await db.execute(select(Zone).where(Zone.id == zone_id))
    if not zone_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Zone not found")

    post = ZonePost(
        zone_id=zone_id,
        name=data.name,
        latitude=data.latitude,
        longitude=data.longitude,
        description=data.description,
        created_by=current_user.id,
    )
    db.add(post)
    await db.commit()
    await db.refresh(post)

    try:
        asyncio.create_task(manager.broadcast_event({
            "event_type": "ZONE",
            "description": f"Post '{data.name}' added to zone",
            "zone_id": str(zone_id),
        }))
    except Exception:
        pass

    return ZonePostResponse(id=post.id, zone_id=post.zone_id, name=post.name,
                            latitude=post.latitude, longitude=post.longitude,
                            description=post.description, soldiers=[])


@router.get("/{zone_id}/posts", response_model=List[ZonePostResponse])
async def list_zone_posts(
    zone_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all posts in a zone with assigned soldiers and proximity status."""
    posts_result = await db.execute(
        select(ZonePost).where(ZonePost.zone_id == zone_id)
    )
    posts = posts_result.scalars().all()

    # Bulk-fetch all user locations once
    assignments_result = await db.execute(
        select(ZonePostAssignment).where(
            ZonePostAssignment.post_id.in_([p.id for p in posts])
        )
    )
    all_assignments = assignments_result.scalars().all()

    user_ids = list({a.user_id for a in all_assignments})
    loc_map: dict = {}
    name_map: dict = {}
    status_map: dict = {}

    if user_ids:
        users_result = await db.execute(select(User).where(User.id.in_(user_ids)))
        for u in users_result.scalars().all():
            name_map[u.id] = u.full_name or u.username

        locs_result = await db.execute(select(Location).where(Location.user_id.in_(user_ids)))
        for loc in locs_result.scalars().all():
            loc_map[loc.user_id] = loc
            status_map[loc.user_id] = loc.status

    response = []
    for post in posts:
        soldiers = []
        for a in all_assignments:
            if a.post_id != post.id:
                continue
            loc = loc_map.get(a.user_id)
            distance_m: Optional[float] = None
            at_post = False
            if loc and loc.latitude and loc.longitude:
                distance_m = _haversine_m(post.latitude, post.longitude, loc.latitude, loc.longitude)
                at_post = distance_m <= 100
            soldiers.append(SoldierAtPost(
                user_id=a.user_id,
                name=name_map.get(a.user_id, "Unknown"),
                status=status_map.get(a.user_id, "offline"),
                distance_m=round(distance_m, 1) if distance_m is not None else None,
                at_post=at_post,
            ))
        response.append(ZonePostResponse(
            id=post.id,
            zone_id=post.zone_id,
            name=post.name,
            latitude=post.latitude,
            longitude=post.longitude,
            description=post.description,
            soldiers=soldiers,
        ))
    return response


@router.post("/{zone_id}/posts/{post_id}/assign", status_code=status.HTTP_200_OK)
async def assign_soldiers_to_post(
    zone_id: UUID,
    post_id: UUID,
    data: ZonePostAssignRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Assign one or more soldiers to a zone post. Existing assignments are kept."""
    await _require_commander_or_lead(current_user, db)

    post_result = await db.execute(
        select(ZonePost).where(ZonePost.id == post_id, ZonePost.zone_id == zone_id)
    )
    if not post_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Post not found")

    existing_result = await db.execute(
        select(ZonePostAssignment.user_id).where(ZonePostAssignment.post_id == post_id)
    )
    existing_ids = {row[0] for row in existing_result.all()}

    for uid in data.user_ids:
        if uid in existing_ids:
            continue
        db.add(ZonePostAssignment(post_id=post_id, user_id=uid, assigned_by=current_user.id))

    await db.commit()

    try:
        asyncio.create_task(manager.broadcast_event({
            "event_type": "ZONE",
            "description": "Soldiers assigned to post",
            "zone_id": str(zone_id),
            "post_id": str(post_id),
        }))
    except Exception:
        pass

    return {"message": "Soldiers assigned"}


@router.delete("/{zone_id}/posts/{post_id}/assign/{user_id}", status_code=status.HTTP_200_OK)
async def unassign_soldier_from_post(
    zone_id: UUID,
    post_id: UUID,
    user_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove a soldier from a zone post."""
    await _require_commander_or_lead(current_user, db)

    result = await db.execute(
        select(ZonePostAssignment).where(
            ZonePostAssignment.post_id == post_id,
            ZonePostAssignment.user_id == user_id,
        )
    )
    assignment = result.scalar_one_or_none()
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found")

    await db.delete(assignment)
    await db.commit()
    return {"message": "Soldier unassigned"}


@router.delete("/{zone_id}/posts/{post_id}", status_code=status.HTTP_200_OK)
async def delete_zone_post(
    zone_id: UUID,
    post_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a zone post (and all its assignments)."""
    await _require_commander_or_lead(current_user, db)

    result = await db.execute(
        select(ZonePost).where(ZonePost.id == post_id, ZonePost.zone_id == zone_id)
    )
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    await db.delete(post)
    await db.commit()
    return {"message": "Post deleted"}