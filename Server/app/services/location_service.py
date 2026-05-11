# app/services/location_service.py
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func
from typing import Optional, List
from uuid import UUID
from datetime import datetime, timedelta, timezone

from app.models.location import Location, LocationHistory
from app.models.user import User
from app.models.team import Team
from app.schemas.location import LocationCreate, LocationBatchCreate, LocationResponse
from app.utils.geo_utils import is_within_geofence
from app.websocket.manager import manager
from app.services.route_follow_service import RouteFollowService
import asyncio

class LocationService:
    """Location tracking service"""
    
    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def update_location(self, data: LocationCreate) -> Location:
        """Update or create current location for user"""
        # Check if user exists
        user_result = await self.db.execute(
            select(User).where(User.id == data.user_id)
        )
        user = user_result.scalar_one_or_none()
        
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        # Find existing location record
        result = await self.db.execute(
                    select(Location)
                    .where(Location.user_id == data.user_id)
                    .order_by(Location.created_at.desc(), Location.id.desc())
                    .limit(1)
        )
        location = result.scalar_one_or_none()
        
        recorded_at = data.recorded_at or datetime.now(timezone.utc)
        
        if location:
            # Update existing
            location.latitude = data.latitude
            location.longitude = data.longitude
            location.altitude = data.altitude
            location.speed = data.speed
            location.heading = data.heading
            location.accuracy = data.accuracy
            location.battery_level = data.battery_level
            location.device_info = data.device_info
            location.team_id = data.team_id
            location.recorded_at = recorded_at
            
            # Update sensor data if provided
            if data.sensor_data:
                location.accel_x = data.sensor_data.accel_x
                location.accel_y = data.sensor_data.accel_y
                location.accel_z = data.sensor_data.accel_z
                location.gyro_x = data.sensor_data.gyro_x
                location.gyro_y = data.sensor_data.gyro_y
                location.gyro_z = data.sensor_data.gyro_z
            
            # Determine status based on time
            time_diff = (datetime.now(timezone.utc) - recorded_at).total_seconds()
            if time_diff > 90:
                location.status = "offline"
            elif time_diff > 30:
                location.status = "stale"
            else:
                location.status = "active"
        else:
            # Create new
            location = Location(
                user_id=data.user_id,
                team_id=data.team_id,
                latitude=data.latitude,
                longitude=data.longitude,
                altitude=data.altitude,
                speed=data.speed,
                heading=data.heading,
                accuracy=data.accuracy,
                battery_level=data.battery_level,
                device_info=data.device_info,
                recorded_at=recorded_at,
                status="active",
            )
            
            if data.sensor_data:
                location.accel_x = data.sensor_data.accel_x
                location.accel_y = data.sensor_data.accel_y
                location.accel_z = data.sensor_data.accel_z
                location.gyro_x = data.sensor_data.gyro_x
                location.gyro_y = data.sensor_data.gyro_y
                location.gyro_z = data.sensor_data.gyro_z
            
            self.db.add(location)
        
        # Also save to history
        history = LocationHistory(
            user_id=data.user_id,
            latitude=data.latitude,
            longitude=data.longitude,
            altitude=data.altitude,
            speed=data.speed,
            heading=data.heading,
            recorded_at=recorded_at,
        )
        
        if data.sensor_data:
            history.accel_x = data.sensor_data.accel_x
            history.accel_y = data.sensor_data.accel_y
            history.accel_z = data.sensor_data.accel_z
            history.gyro_x = data.sensor_data.gyro_x
            history.gyro_y = data.sensor_data.gyro_y
            history.gyro_z = data.sensor_data.gyro_z
        
        self.db.add(history)
        await self.db.commit()
        await self.db.refresh(location)

        # Attach this GPS update to any active route-follow session for the user.
        try:
            follow_service = RouteFollowService(self.db)
            session = await follow_service.record_location(user_id=data.user_id, location=location)
            if session:
                await follow_service.broadcast_session_update(session, "route_follow_progress")
        except Exception:
            pass

        # Broadcast the updated location to websocket clients
        try:
            # Resolve team name for the broadcast
            team_name: str | None = None
            if location.team_id:
                team_result = await self.db.execute(
                    select(Team).where(Team.id == location.team_id)
                )
                team_obj = team_result.scalar_one_or_none()
                if team_obj:
                    team_name = team_obj.name

            location_data = {
                "id": str(location.id),
                "user_id": str(location.user_id),
                "team_id": str(location.team_id) if location.team_id else None,
                "latitude": location.latitude,
                "longitude": location.longitude,
                "altitude": location.altitude,
                "speed": location.speed,
                "heading": location.heading,
                "accuracy": location.accuracy,
                "accel_x": location.accel_x,
                "accel_y": location.accel_y,
                "accel_z": location.accel_z,
                "gyro_x": location.gyro_x,
                "gyro_y": location.gyro_y,
                "gyro_z": location.gyro_z,
                "battery_level": location.battery_level,
                "status": location.status,
                "recorded_at": location.recorded_at.isoformat() if location.recorded_at else None,
                "created_at": location.created_at.isoformat() if location.created_at else None,
                "name": user.full_name or user.username,
                "team_name": team_name,
            }

            # fire-and-forget broadcast; don't block main flow
            try:
                # schedule broadcast without awaiting to avoid slowing API
                asyncio.create_task(manager.broadcast_location_update(location_data))
            except Exception:
                # fallback to awaiting if create_task not available
                import asyncio as _asyncio
                _asyncio.get_event_loop().create_task(manager.broadcast_location_update(location_data))
        except Exception:
            # ensure location saving is not affected by broadcast failures
            pass

        return location
    
    async def batch_update_locations(
        self, data: LocationBatchCreate
    ) -> List[Location]:
        """Batch update multiple locations"""
        results = []
        for loc_data in data.locations:
            location = await self.update_location(loc_data)
            results.append(location)
        return results
    
    async def get_active_locations(
        self,
        team_id: Optional[UUID] = None,
        user_ids: Optional[List[UUID]] = None,
    ) -> List[Location]:
        """Get all active locations"""
        query = select(Location)
        
        if team_id:
            query = query.where(Location.team_id == team_id)
        
        if user_ids:
            query = query.where(Location.user_id.in_(user_ids))
        
        result = await self.db.execute(query)
        return result.scalars().all()
    
    async def get_user_location(self, user_id: UUID) -> Optional[Location]:
        """Get specific user's current location"""
        result = await self.db.execute(
            select(Location)
            .where(Location.user_id == user_id)
            .order_by(Location.created_at.desc(), Location.id.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()
    
    async def get_location_history(
        self,
        user_id: UUID,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 100,
    ) -> List[LocationHistory]:
        """Get location history for a user"""
        query = select(LocationHistory).where(
            LocationHistory.user_id == user_id
        )
        
        if start_time:
            query = query.where(LocationHistory.recorded_at >= start_time)
        
        if end_time:
            query = query.where(LocationHistory.recorded_at <= end_time)
        
        query = query.order_by(LocationHistory.recorded_at.desc()).limit(limit)
        
        result = await self.db.execute(query)
        return result.scalars().all()
    
    async def get_locations_in_bounds(
        self,
        min_lat: float,
        max_lat: float,
        min_lng: float,
        max_lng: float,
        team_id: Optional[UUID] = None,
    ) -> List[Location]:
        """Get locations within geographic bounds"""
        query = select(Location).where(
            and_(
                Location.latitude >= min_lat,
                Location.latitude <= max_lat,
                Location.longitude >= min_lng,
                Location.longitude <= max_lng,
            )
        )
        
        if team_id:
            query = query.where(Location.team_id == team_id)
        
        result = await self.db.execute(query)
        return result.scalars().all()
    
    async def update_location_statuses(self):
        """Update status of all locations based on last update time"""
        now = datetime.now(timezone.utc)
        
        # Get all locations
        result = await self.db.execute(select(Location))
        locations = result.scalars().all()
        
        for location in locations:
            time_diff = (now - location.recorded_at).total_seconds()
            
            if time_diff > 90:
                location.status = "offline"
            elif time_diff > 30:
                location.status = "stale"
            else:
                location.status = "active"
        
        await self.db.commit()