import uuid
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.location import Location, LocationHistory
from app.services.location_service import LocationService
from app.websocket.manager import manager

router = APIRouter(prefix="/locations", tags=["Locations"])


class LocationUpdate(BaseModel):
    latitude: float
    longitude: float
    altitude: Optional[float] = None
    heading: Optional[float] = None
    speed: Optional[float] = None
    accuracy: Optional[float] = None


@router.post("")
async def submit_location(
    data: LocationUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = LocationService(db)
    loc = await svc.update_location(
        user_id=current_user.id,
        latitude=data.latitude,
        longitude=data.longitude,
        altitude=data.altitude,
        heading=data.heading,
        speed=data.speed,
        accuracy=data.accuracy,
    )
    await manager.broadcast({
        "type": "location_update",
        "user_id": str(current_user.id),
        "latitude": loc.latitude,
        "longitude": loc.longitude,
        "altitude": loc.altitude,
        "heading": loc.heading,
        "speed": loc.speed,
        "status": loc.status.value,
        "last_updated": loc.last_update.isoformat() if loc.last_update else None,
        "user": {
            "id": str(current_user.id),
            "full_name": current_user.full_name,
            "username": current_user.username,
            "role": current_user.role.value,
            "avatar_url": current_user.avatar_url,
        },
    }, room="locations")
    return {"status": "updated"}


@router.get("/live")
async def get_live_locations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models.team import Team, TeamMember

    role = current_user.role.value

    # Fetch all live locations joined with user info
    rows = await db.execute(
        select(Location, User).join(User, Location.user_id == User.id)
    )
    all_pairs: list[tuple[Location, User]] = rows.all()

    if role not in ("operations_coordinator", "planning_officer"):
        membership_q = await db.execute(
            select(TeamMember).where(TeamMember.user_id == current_user.id)
        )
        memberships = membership_q.scalars().all()
        team_ids = [m.team_id for m in memberships]

        visible_ids: set = {current_user.id}
        for team_id in team_ids:
            team = await db.get(Team, team_id)
            if not team:
                continue
            if team.location_sharing or role == "team_leader":
                members_q = await db.execute(
                    select(TeamMember).where(TeamMember.team_id == team_id)
                )
                for member in members_q.scalars().all():
                    visible_ids.add(member.user_id)

        all_pairs = [(loc, u) for loc, u in all_pairs if loc.user_id in visible_ids]

    # Build a map of user_id → first team name for popup display
    user_team_map: dict[str, str] = {}
    all_user_ids = [u.id for _, u in all_pairs]
    if all_user_ids:
        tm_rows = await db.execute(
            select(TeamMember, Team)
            .join(Team, TeamMember.team_id == Team.id)
            .where(TeamMember.user_id.in_(all_user_ids), Team.is_active == True)
        )
        for tm, t in tm_rows.all():
            uid = str(tm.user_id)
            if uid not in user_team_map:
                user_team_map[uid] = t.name

    def _fmt(loc: Location, u: User) -> dict:
        uid = str(u.id)
        return {
            "user_id": str(loc.user_id),
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "altitude": loc.altitude,
            "heading": loc.heading,
            "speed": loc.speed,
            "status": loc.status.value,
            "last_updated": loc.last_update.isoformat() if loc.last_update else None,
            "user": {
                "id": uid,
                "full_name": u.full_name,
                "username": u.username,
                "role": u.role.value,
                "email": u.email,
                "avatar_url": u.avatar_url,
                "team": user_team_map.get(uid),
            },
        }

    return [_fmt(loc, u) for loc, u in all_pairs]


@router.get("/{user_id}")
async def get_user_location(
    user_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = LocationService(db)
    loc = await svc.get_user_location(user_id)
    if not loc:
        return {"status": "no_location"}
    return {
        "user_id": str(loc.user_id),
        "latitude": loc.latitude,
        "longitude": loc.longitude,
        "altitude": loc.altitude,
        "heading": loc.heading,
        "speed": loc.speed,
        "status": loc.status.value,
        "last_update": loc.last_update.isoformat() if loc.last_update else None,
    }


@router.get("/{user_id}/history")
async def get_location_history(
    user_id: uuid.UUID,
    limit: int = Query(100, ge=1, le=1000),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(LocationHistory)
        .where(LocationHistory.user_id == user_id)
        .order_by(LocationHistory.timestamp.desc())
        .limit(limit)
    )
    history = result.scalars().all()
    return [
        {
            "latitude": h.latitude,
            "longitude": h.longitude,
            "altitude": h.altitude,
            "heading": h.heading,
            "speed": h.speed,
            "timestamp": h.timestamp.isoformat(),
        }
        for h in history
    ]
