# app/api/v1/admin.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import delete

from app.database import get_db
from app.models.user import User
from app.models.location import Location, LocationHistory
from app.models.message import Message
from app.models.event import Event
from app.models.team import Team, TeamMember
from app.models.route import Route, RouteWaypoint, RouteVisibility, RouteHistory
from app.models.route_follow import RouteFollowSession, RouteFollowPoint
from app.models.zone import Zone, ZoneCoordinate, ZoneAssignment
from app.models.poi import POI, POIVisibility
from app.models.live_session import LiveSession
from app.models.evidence import Evidence
from app.models.notification import Notification, UserFlag
from app.models.audit import AuditLog, UserSession
from app.middleware.auth import require_admin

router = APIRouter(prefix="/admin", tags=["Admin"])


@router.post("/reset-data", status_code=status.HTTP_200_OK)
async def reset_all_data(
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Delete all operational data while preserving user accounts.
    Restricted to admin and super_admin roles.
    """
    # Delete in dependency order (children before parents)
    await db.execute(delete(RouteFollowPoint))
    await db.execute(delete(RouteFollowSession))
    await db.execute(delete(RouteWaypoint))
    await db.execute(delete(RouteVisibility))
    await db.execute(delete(RouteHistory))
    await db.execute(delete(Route))
    await db.execute(delete(ZoneCoordinate))
    await db.execute(delete(ZoneAssignment))
    await db.execute(delete(Zone))
    await db.execute(delete(POIVisibility))
    await db.execute(delete(POI))
    await db.execute(delete(TeamMember))
    await db.execute(delete(Team))
    await db.execute(delete(LocationHistory))
    await db.execute(delete(Location))
    await db.execute(delete(Message))
    await db.execute(delete(Event))
    await db.execute(delete(LiveSession))
    await db.execute(delete(Evidence))
    await db.execute(delete(UserFlag))
    await db.execute(delete(Notification))
    await db.execute(delete(AuditLog))
    await db.execute(delete(UserSession))

    await db.commit()

    return {"message": "All operational data cleared. User accounts preserved."}
