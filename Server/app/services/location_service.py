import uuid
from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from app.models.location import Location, LocationHistory, LocationStatus


class LocationService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def update_location(
        self,
        user_id: uuid.UUID,
        latitude: float,
        longitude: float,
        altitude: Optional[float] = None,
        heading: Optional[float] = None,
        speed: Optional[float] = None,
        accuracy: Optional[float] = None,
    ) -> Location:
        result = await self.db.execute(select(Location).where(Location.user_id == user_id))
        location = result.scalar_one_or_none()

        if location:
            location.latitude = latitude
            location.longitude = longitude
            location.altitude = altitude
            location.heading = heading
            location.speed = speed
            location.accuracy = accuracy
            location.status = LocationStatus.active
            location.last_update = datetime.utcnow()
        else:
            location = Location(
                user_id=user_id,
                latitude=latitude,
                longitude=longitude,
                altitude=altitude,
                heading=heading,
                speed=speed,
                accuracy=accuracy,
                status=LocationStatus.active,
            )
            self.db.add(location)

        history = LocationHistory(
            user_id=user_id,
            latitude=latitude,
            longitude=longitude,
            altitude=altitude,
            heading=heading,
            speed=speed,
            accuracy=accuracy,
        )
        self.db.add(history)
        await self.db.commit()
        await self.db.refresh(location)
        return location

    async def get_all_live(self) -> list[Location]:
        result = await self.db.execute(select(Location))
        return result.scalars().all()

    async def get_user_location(self, user_id: uuid.UUID) -> Optional[Location]:
        result = await self.db.execute(select(Location).where(Location.user_id == user_id))
        return result.scalar_one_or_none()

    async def update_location_statuses(self) -> None:
        stale_threshold = datetime.utcnow() - timedelta(minutes=5)
        offline_threshold = datetime.utcnow() - timedelta(minutes=15)

        await self.db.execute(
            update(Location)
            .where(Location.last_update < stale_threshold, Location.status == LocationStatus.active)
            .values(status=LocationStatus.stale)
        )
        await self.db.execute(
            update(Location)
            .where(Location.last_update < offline_threshold)
            .values(status=LocationStatus.offline)
        )
        await self.db.commit()
