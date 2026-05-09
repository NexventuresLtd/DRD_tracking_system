import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from typing import Optional

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.live_session import LiveSession
from app.models.user import User

router = APIRouter(prefix="/live-sessions", tags=["live-sessions"])

VIDEO_DIR = Path("uploads/live_sessions")
VIDEO_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/start")
async def start_session(
    body: dict,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = LiveSession(
        room_id=body.get("room_id", str(uuid.uuid4())),
        initiator_name=body.get("initiator_name", current_user.full_name or current_user.username),
        team_name=body.get("team_name", ""),
        lat=body.get("lat"),
        lng=body.get("lng"),
        saved=bool(body.get("saved", False)),
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return {"id": str(session.id), "room_id": session.room_id, "started_at": session.started_at.isoformat()}


@router.patch("/{session_id}/end")
async def end_session(
    session_id: str,
    body: dict,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveSession).where(LiveSession.id == uuid.UUID(session_id)))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    now = datetime.now(timezone.utc)
    session.ended_at = now
    if session.started_at:
        session.duration_seconds = (now - session.started_at.replace(tzinfo=timezone.utc)).total_seconds()
    await db.commit()
    return {"ok": True}


@router.get("")
async def list_sessions(
    saved_only: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = select(LiveSession).order_by(desc(LiveSession.started_at)).limit(100)
    if saved_only:
        q = q.where(LiveSession.saved == True)  # noqa: E712
    result = await db.execute(q)
    sessions = result.scalars().all()
    return [
        {
            "id": str(s.id),
            "room_id": s.room_id,
            "initiator_name": s.initiator_name,
            "team_name": s.team_name,
            "lat": s.lat,
            "lng": s.lng,
            "saved": s.saved,
            "has_video": bool(s.video_file_path and os.path.exists(s.video_file_path)),
            "duration_seconds": s.duration_seconds,
            "started_at": s.started_at.isoformat() if s.started_at else None,
            "ended_at": s.ended_at.isoformat() if s.ended_at else None,
        }
        for s in sessions
    ]


@router.post("/{session_id}/upload-video")
async def upload_video(
    session_id: str,
    video: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveSession).where(LiveSession.id == uuid.UUID(session_id)))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    content = await video.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty video file")

    ext = Path(video.filename or "recording.webm").suffix or ".webm"
    filename = f"live_{session_id}{ext}"
    file_path = VIDEO_DIR / filename

    with open(file_path, "wb") as f:
        f.write(content)

    session.video_file_path = str(file_path)
    await db.commit()
    return {"ok": True, "size_bytes": len(content)}


@router.get("/{session_id}/video")
async def get_video(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveSession).where(LiveSession.id == uuid.UUID(session_id)))
    session = result.scalar_one_or_none()
    if not session or not session.video_file_path:
        raise HTTPException(status_code=404, detail="No video for this session")
    if not os.path.exists(session.video_file_path):
        raise HTTPException(status_code=404, detail="Video file missing on disk")
    return FileResponse(
        session.video_file_path,
        media_type="video/webm",
        filename=f"live_{session_id}.webm",
        headers={"Accept-Ranges": "bytes"},
    )
