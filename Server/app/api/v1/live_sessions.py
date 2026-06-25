import uuid
from typing import Optional, List
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.live_session import LiveSession
from app.services.notification_service import NotificationService
from app.websocket.manager import manager

router = APIRouter(prefix="/live-sessions", tags=["Live Sessions"])


def _session_dict(s: LiveSession) -> dict:
    return {
        "id": str(s.id),
        "title": s.title,
        "host_id": str(s.host_id),
        "room_id": s.room_id,
        "is_active": s.is_active,
        "mission_id": str(s.mission_id) if s.mission_id else None,
        "team_id": str(s.team_id) if s.team_id else None,
        "is_recording": getattr(s, "is_recording", False),
        "invite_list": getattr(s, "invite_list", []) or [],
        "viewer_count": s.viewer_count,
        "started_at": s.started_at.isoformat() if s.started_at else None,
        "ended_at": s.ended_at.isoformat() if s.ended_at else None,
        "created_at": s.started_at.isoformat() if s.started_at else None,
    }


class StartSessionBody(BaseModel):
    title: str
    mission_id: Optional[str] = None
    team_id: Optional[str] = None
    invite_team_ids: List[str] = []
    invite_user_ids: List[str] = []


@router.get("")
async def list_sessions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveSession).where(LiveSession.is_active == True))
    sessions = result.scalars().all()
    user_id_str = str(current_user.id)
    visible = [
        s for s in sessions
        if s.host_id == current_user.id
        or user_id_str in (getattr(s, "invite_list", []) or [])
        or not (getattr(s, "invite_list", []) or [])
    ]
    return [_session_dict(s) for s in visible]


@router.post("", status_code=201)
async def start_session(
    body: StartSessionBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models.team import TeamMember

    invited_user_ids: list[str] = list(body.invite_user_ids)
    for team_id in body.invite_team_ids:
        q = select(TeamMember).where(TeamMember.team_id == uuid.UUID(team_id))
        res = await db.execute(q)
        for tm in res.scalars().all():
            uid = str(tm.user_id)
            if uid not in invited_user_ids:
                invited_user_ids.append(uid)

    room_id = str(uuid.uuid4()).replace("-", "")
    session = LiveSession(
        title=body.title,
        host_id=current_user.id,
        room_id=room_id,
        mission_id=uuid.UUID(body.mission_id) if body.mission_id else None,
        team_id=uuid.UUID(body.team_id) if body.team_id else None,
    )
    if hasattr(session, "invite_list"):
        session.invite_list = invited_user_ids
    db.add(session)
    await db.commit()
    await db.refresh(session)

    notif_svc = NotificationService(db)
    for uid_str in invited_user_ids:
        try:
            uid = uuid.UUID(uid_str)
            await notif_svc.create_and_send(
                user_id=uid,
                type="call_incoming",
                title=f"📞 INCOMING CALL: {body.title}",
                body=f"{current_user.full_name or current_user.username} is calling — tap to join",
                ref_id=str(session.id),
                ref_type="live_session",
                priority="high",
            )
            # Send direct WS invite so online users see the banner immediately
            await manager.send_to(uid_str, {
                "type": "live_session_invite",
                "session": _session_dict(session),
            })
        except Exception:
            pass

    data = _session_dict(session)
    await manager.broadcast({"type": "live_session_started", "session": data})
    return data


@router.get("/past")
async def list_past_sessions(
    mission_id: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = select(LiveSession).where(LiveSession.is_active == False)
    if mission_id:
        q = q.where(LiveSession.mission_id == uuid.UUID(mission_id))
    result = await db.execute(q.order_by(LiveSession.started_at.desc()).limit(50))
    return [_session_dict(s) for s in result.scalars().all()]


class InviteBody(BaseModel):
    user_ids: List[str] = []
    team_ids: List[str] = []


@router.post("/{session_id}/invite")
async def invite_to_session(
    session_id: uuid.UUID,
    body: InviteBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models.team import TeamMember

    result = await db.execute(select(LiveSession).where(LiveSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if not session.is_active:
        raise HTTPException(status_code=400, detail="Session is no longer active")

    # Collect user IDs from direct invites + team members
    invited: list[str] = list(body.user_ids)
    for team_id in body.team_ids:
        res = await db.execute(select(TeamMember).where(TeamMember.team_id == uuid.UUID(team_id)))
        for tm in res.scalars().all():
            uid = str(tm.user_id)
            if uid not in invited:
                invited.append(uid)

    # Update invite_list on session
    if hasattr(session, "invite_list"):
        existing = list(session.invite_list or [])
        for uid in invited:
            if uid not in existing:
                existing.append(uid)
        session.invite_list = existing
        await db.commit()

    notif_svc = NotificationService(db)
    session_data = _session_dict(session)
    for uid_str in invited:
        try:
            await notif_svc.create_and_send(
                user_id=uuid.UUID(uid_str),
                type="live_session_invite",
                title=f"LIVE BRIEFING: {session.title}",
                body=f"{current_user.full_name or current_user.username} invited you to join a live session",
                ref_id=str(session.id),
                ref_type="live_session",
                priority="high",
            )
            # Also broadcast invite event on WS so the mobile app can auto-open the session
            await manager.send_to(uid_str, {
                "type": "live_session_invite",
                "session": session_data,
            })
        except Exception:
            pass

    return {"invited": invited, "session_id": str(session_id)}


@router.delete("/{session_id}", status_code=204)
async def delete_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models.user import UserRole
    result = await db.execute(select(LiveSession).where(LiveSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    can_delete = (
        session.host_id == current_user.id
        or current_user.role == UserRole.operations_coordinator
        or current_user.role == UserRole.planning_officer
    )
    if not can_delete:
        raise HTTPException(status_code=403, detail="Only the host or coordinator can delete this session")
    await db.delete(session)
    await db.commit()
    await manager.broadcast({
        "type": "live_session_ended",
        "session_id": str(session_id),
        "ended_by": str(current_user.id),
    })


@router.post("/{session_id}/end")
async def end_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LiveSession).where(LiveSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session.is_active = False
    session.ended_at = datetime.utcnow()
    await db.commit()
    await manager.broadcast({"type": "live_session_ended", "session_id": str(session_id)})
    return {"message": "Session ended"}
