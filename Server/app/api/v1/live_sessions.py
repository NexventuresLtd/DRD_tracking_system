import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.live_session import LiveSession

router = APIRouter(prefix="/live-sessions", tags=["Live Sessions"])


@router.get("")
async def list_sessions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveSession).where(LiveSession.is_active == True))
    return result.scalars().all()


@router.post("", status_code=201)
async def start_session(
    title: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    room_id = str(uuid.uuid4()).replace("-", "")
    session = LiveSession(title=title, host_id=current_user.id, room_id=room_id)
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return {"session_id": str(session.id), "room_id": room_id}


@router.post("/{session_id}/end")
async def end_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from datetime import datetime
    result = await db.execute(select(LiveSession).where(LiveSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session.is_active = False
    session.ended_at = datetime.utcnow()
    await db.commit()
    return {"message": "Session ended"}
