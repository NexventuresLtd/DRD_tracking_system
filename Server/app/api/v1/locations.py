# app/api/v1/locations.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional, List
from uuid import UUID
from datetime import datetime

from app.database import get_db
from app.models.user import User
from app.schemas.location import (
    LocationCreate, LocationBatchCreate,
    LocationResponse, LocationHistoryResponse,
    GeofenceQuery,
)
from app.services.location_service import LocationService
from app.middleware.auth import get_current_user, require_operator

router = APIRouter(prefix="/locations", tags=["Locations"])

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

@router.get("/", response_model=List[LocationResponse])
async def get_active_locations(
    team_id: Optional[UUID] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get all active locations"""
    location_service = LocationService(db)
    locations = await location_service.get_active_locations(team_id=team_id)
    
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