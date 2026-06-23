import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.route import RouteFollowSession

router = APIRouter(prefix="/route-follow-sessions", tags=["Route Follow Sessions"])


@router.post("/{route_id}/start", status_code=201)
async def start_session(
    route_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    session = RouteFollowSession(route_id=route_id, user_id=current_user.id)
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return {"session_id": str(session.id)}


@router.put("/{session_id}")
async def update_session(
    session_id: uuid.UUID,
    waypoint_index: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(RouteFollowSession).where(
            RouteFollowSession.id == session_id,
            RouteFollowSession.user_id == current_user.id,
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session.current_waypoint_index = waypoint_index
    await db.commit()
    return {"status": "updated"}


@router.post("/{session_id}/complete")
async def complete_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from datetime import datetime
    result = await db.execute(
        select(RouteFollowSession).where(
            RouteFollowSession.id == session_id,
            RouteFollowSession.user_id == current_user.id,
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session.is_active = False
    session.completed_at = datetime.utcnow()
    await db.commit()
    return {"status": "completed"}
