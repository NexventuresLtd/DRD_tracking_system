import uuid
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.location import LocationHistory

router = APIRouter(prefix="/playback", tags=["Playback"])


@router.get("/users")
async def list_trackable_users(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LocationHistory.user_id).distinct())
    user_ids = [str(r[0]) for r in result.all()]
    return {"user_ids": user_ids, "count": len(user_ids)}


@router.get("/trail/{user_id}")
async def get_trail(
    user_id: uuid.UUID,
    start: Optional[str] = Query(None, description="ISO8601 start time"),
    end: Optional[str]   = Query(None, description="ISO8601 end time"),
    limit: int           = Query(500, le=2000),
    current_user: User   = Depends(get_current_user),
    db: AsyncSession     = Depends(get_db),
):
    filters = [LocationHistory.user_id == user_id]
    if start:
        filters.append(LocationHistory.timestamp >= datetime.fromisoformat(start))
    if end:
        filters.append(LocationHistory.timestamp <= datetime.fromisoformat(end))

    result = await db.execute(
        select(LocationHistory)
        .where(and_(*filters))
        .order_by(LocationHistory.timestamp.asc())
        .limit(limit)
    )
    locs = result.scalars().all()
    return {
        "user_id": str(user_id),
        "points": [
            {
                "lat": loc.latitude,
                "lng": loc.longitude,
                "alt": loc.altitude,
                "speed": loc.speed,
                "heading": loc.heading,
                "ts": loc.timestamp.isoformat() if loc.timestamp else None,
            }
            for loc in locs
        ],
        "count": len(locs),
    }


@router.get("/snapshot")
async def get_snapshot(
    at: str            = Query(..., description="ISO8601 timestamp"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession   = Depends(get_db),
):
    """Return the last known position of every user at or before the given time."""
    ts = datetime.fromisoformat(at)

    subq = (
        select(LocationHistory.user_id, func.max(LocationHistory.timestamp).label("max_ts"))
        .where(LocationHistory.timestamp <= ts)
        .group_by(LocationHistory.user_id)
        .subquery()
    )
    result = await db.execute(
        select(LocationHistory)
        .join(subq, and_(LocationHistory.user_id == subq.c.user_id, LocationHistory.timestamp == subq.c.max_ts))
    )
    locs = result.scalars().all()
    return {
        "at": at,
        "positions": [
            {"user_id": str(loc.user_id), "lat": loc.latitude, "lng": loc.longitude, "ts": loc.timestamp.isoformat()}
            for loc in locs
        ],
    }
