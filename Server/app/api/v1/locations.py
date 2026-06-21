# app/api/v1/locations.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional, List
from uuid import UUID
from datetime import datetime

from app.database import get_db
from app.models.location import Location
from app.models.user import User, UserRole
from app.models.team import Team, TeamMember
from app.schemas.location import (
    LocationCreate, LocationBatchCreate,
    LocationResponse, LocationHistoryResponse,
    GeofenceQuery,
)
from app.services.location_service import LocationService
from app.middleware.auth import get_current_user, require_operator
from app.websocket.manager import manager
import asyncio

router = APIRouter(prefix="/locations", tags=["Locations"])


@router.post("/offline", status_code=status.HTTP_200_OK)
async def mark_offline(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Immediately mark the current user as offline (called when app closes)."""
    result = await db.execute(
        select(Location)
        .where(Location.user_id == current_user.id)
        .order_by(Location.created_at.desc())
        .limit(1)
    )
    location = result.scalar_one_or_none()
    if location:
        location.status = "offline"
        await db.commit()
        # Broadcast status change so the web dashboard updates immediately
        try:
            asyncio.create_task(manager.broadcast_location_update({
                "user_id": str(current_user.id),
                "latitude": location.latitude,
                "longitude": location.longitude,
                "status": "offline",
                "recorded_at": location.recorded_at.isoformat() if location.recorded_at else None,
                "name": current_user.full_name or current_user.username,
            }))
        except Exception:
            pass
    return {"status": "offline"}


@router.post("/", response_model=LocationResponse, status_code=status.HTTP_201_CREATED)
async def update_location(
    data: LocationCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update current location"""
    # Field units can only update their own location
    if current_user.role.value == "field_unit" and data.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only update your own location"
        )
    
    location_service = LocationService(db)
    location = await location_service.update_location(data)
    
    return LocationResponse(
        id=location.id,
        user_id=location.user_id,
        team_id=location.team_id,
        latitude=location.latitude,
        longitude=location.longitude,
        altitude=location.altitude,
        speed=location.speed,
        heading=location.heading,
        accuracy=location.accuracy,
        accel_x=location.accel_x,
        accel_y=location.accel_y,
        accel_z=location.accel_z,
        gyro_x=location.gyro_x,
        gyro_y=location.gyro_y,
        gyro_z=location.gyro_z,
        battery_level=location.battery_level,
        status=location.status,
        recorded_at=location.recorded_at,
        created_at=location.created_at,
    )

@router.post("/batch", response_model=List[LocationResponse])
async def batch_update_locations(
    data: LocationBatchCreate,
    current_user: User = Depends(require_operator),
    db: AsyncSession = Depends(get_db)
):
    """Batch update multiple locations (for operators/commanders)"""
    location_service = LocationService(db)
    locations = await location_service.batch_update_locations(data)
    
    return [
        LocationResponse(
            id=loc.id,
            user_id=loc.user_id,
            team_id=loc.team_id,
            latitude=loc.latitude,
            longitude=loc.longitude,
            altitude=loc.altitude,
            speed=loc.speed,
            heading=loc.heading,
            accuracy=loc.accuracy,
            accel_x=loc.accel_x,
            accel_y=loc.accel_y,
            accel_z=loc.accel_z,
            gyro_x=loc.gyro_x,
            gyro_y=loc.gyro_y,
            gyro_z=loc.gyro_z,
            battery_level=loc.battery_level,
            status=loc.status,
            recorded_at=loc.recorded_at,
            created_at=loc.created_at,
        )
        for loc in locations
    ]

async def _get_field_unit_team(user_id, db: AsyncSession):
    """Return (team_id, is_lead) for a field_unit, or (None, False) if not in a team."""
    result = await db.execute(
        select(TeamMember).where(TeamMember.user_id == user_id, TeamMember.is_active == True)
    )
    member = result.scalar_one_or_none()
    if member:
        return member.team_id, member.role == "lead"
    return None, False


@router.get("/", response_model=List[LocationResponse])
async def get_active_locations(
    team_id: Optional[UUID] = None,
    start_time: Optional[datetime] = None,
    end_time: Optional[datetime] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get active locations. When start_time/end_time are provided, returns the last
    known position of each user within that historical window instead of live data.

    Role-scoped:
    - Operator and above: all locations
    - Field unit (team lead): own team only
    - Field unit (plain member): own location only
    """
    location_service = LocationService(db)
    own_only = False

    if current_user.role == UserRole.FIELD_UNIT:
        member_team_id, is_lead = await _get_field_unit_team(current_user.id, db)
        if is_lead and member_team_id:
            team_id = member_team_id  # override caller-supplied team_id
        else:
            own_only = True

    if own_only:
        # Return only the current user's location
        location = await location_service.get_user_location(current_user.id)
        if not location:
            return []
        user_result = await db.execute(select(User).where(User.id == current_user.id))
        u = user_result.scalar_one_or_none()
        return [LocationResponse(
            id=location.id,
            user_id=location.user_id,
            team_id=getattr(location, "team_id", None),
            latitude=location.latitude,
            longitude=location.longitude,
            altitude=location.altitude,
            speed=location.speed,
            heading=location.heading,
            accuracy=getattr(location, "accuracy", None),
            accel_x=location.accel_x,
            accel_y=location.accel_y,
            accel_z=location.accel_z,
            gyro_x=location.gyro_x,
            gyro_y=location.gyro_y,
            gyro_z=location.gyro_z,
            battery_level=getattr(location, "battery_level", None),
            status=getattr(location, "status", None) or "offline",
            recorded_at=location.recorded_at,
            created_at=getattr(location, "created_at", None) or location.recorded_at,
            name=u.full_name or u.username if u else None,
        )]

    if start_time or end_time:
        locations = await location_service.get_historical_snapshot(
            team_id=team_id, start_time=start_time, end_time=end_time
        )
    else:
        locations = await location_service.get_active_locations(team_id=team_id)

    # Bulk-fetch user names and team names to avoid N+1 queries
    # Use getattr with defaults: LocationHistory objects lack team_id/status/accuracy/battery_level
    user_ids = list({loc.user_id for loc in locations})
    team_ids = list({getattr(loc, "team_id", None) for loc in locations if getattr(loc, "team_id", None)})
    user_map: dict = {}
    team_map: dict = {}
    if user_ids:
        user_result = await db.execute(select(User).where(User.id.in_(user_ids)))
        for u in user_result.scalars().all():
            user_map[u.id] = u.full_name or u.username
    if team_ids:
        team_result = await db.execute(select(Team).where(Team.id.in_(team_ids)))
        for t in team_result.scalars().all():
            team_map[t.id] = t.name

    return [
        LocationResponse(
            id=loc.id,
            user_id=loc.user_id,
            team_id=getattr(loc, "team_id", None),
            latitude=loc.latitude,
            longitude=loc.longitude,
            altitude=loc.altitude,
            speed=loc.speed,
            heading=loc.heading,
            accuracy=getattr(loc, "accuracy", None),
            accel_x=loc.accel_x,
            accel_y=loc.accel_y,
            accel_z=loc.accel_z,
            gyro_x=loc.gyro_x,
            gyro_y=loc.gyro_y,
            gyro_z=loc.gyro_z,
            battery_level=getattr(loc, "battery_level", None),
            status=getattr(loc, "status", None) or "offline",
            recorded_at=loc.recorded_at,
            created_at=getattr(loc, "created_at", None) or loc.recorded_at,
            name=user_map.get(loc.user_id),
            team_name=team_map.get(getattr(loc, "team_id", None)) if getattr(loc, "team_id", None) else None,
        )
        for loc in locations
    ]

@router.get("/{user_id}", response_model=LocationResponse)
async def get_user_location(
    user_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get specific user's current location"""
    location_service = LocationService(db)
    location = await location_service.get_user_location(user_id)
    
    if not location:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Location not found for this user"
        )
    
    return LocationResponse(
        id=location.id,
        user_id=location.user_id,
        team_id=location.team_id,
        latitude=location.latitude,
        longitude=location.longitude,
        altitude=location.altitude,
        speed=location.speed,
        heading=location.heading,
        accuracy=location.accuracy,
        accel_x=location.accel_x,
        accel_y=location.accel_y,
        accel_z=location.accel_z,
        gyro_x=location.gyro_x,
        gyro_y=location.gyro_y,
        gyro_z=location.gyro_z,
        battery_level=location.battery_level,
        status=location.status,
        recorded_at=location.recorded_at,
        created_at=location.created_at,
    )

@router.get("/{user_id}/history", response_model=List[LocationHistoryResponse])
async def get_location_history(
    user_id: UUID,
    start_time: Optional[datetime] = None,
    end_time: Optional[datetime] = None,
    limit: int = Query(100, le=1000),
    current_user: User = Depends(require_operator),
    db: AsyncSession = Depends(get_db)
):
    """Get location history for a user"""
    location_service = LocationService(db)
    history = await location_service.get_location_history(
        user_id=user_id,
        start_time=start_time,
        end_time=end_time,
        limit=limit,
    )
    
    return [
        LocationHistoryResponse(
            id=h.id,
            user_id=h.user_id,
            latitude=h.latitude,
            longitude=h.longitude,
            altitude=h.altitude,
            speed=h.speed,
            heading=h.heading,
            accel_x=h.accel_x,
            accel_y=h.accel_y,
            accel_z=h.accel_z,
            gyro_x=h.gyro_x,
            gyro_y=h.gyro_y,
            gyro_z=h.gyro_z,
            recorded_at=h.recorded_at,
        )
        for h in history
    ]

@router.post("/geofence", response_model=List[LocationResponse])
async def get_locations_in_bounds(
    query: GeofenceQuery,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get locations within geographic bounds"""
    location_service = LocationService(db)
    locations = await location_service.get_locations_in_bounds(
        min_lat=query.min_lat,
        max_lat=query.max_lat,
        min_lng=query.min_lng,
        max_lng=query.max_lng,
        team_id=query.team_id,
    )
    
    return [
        LocationResponse(
            id=loc.id,
            user_id=loc.user_id,
            team_id=loc.team_id,
            latitude=loc.latitude,
            longitude=loc.longitude,
            altitude=loc.altitude,
            speed=loc.speed,
            heading=loc.heading,
            accuracy=loc.accuracy,
            accel_x=loc.accel_x,
            accel_y=loc.accel_y,
            accel_z=loc.accel_z,
            gyro_x=loc.gyro_x,
            gyro_y=loc.gyro_y,
            gyro_z=loc.gyro_z,
            battery_level=loc.battery_level,
            status=loc.status,
            recorded_at=loc.recorded_at,
            created_at=loc.created_at,
        )
        for loc in locations
    ]