import uuid
import os
import aiofiles
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.evidence import Evidence, EvidenceType
from app.models.poi import POI
from app.models.mission import Mission
from app.config import settings

router = APIRouter(prefix="/evidence", tags=["Evidence"])


def _ev_dict(ev: Evidence) -> dict:
    return {
        "id": str(ev.id),
        "title": ev.title,
        "description": ev.description,
        "evidence_type": ev.evidence_type,
        "file_url": ev.file_url,
        "thumbnail_url": ev.thumbnail_url,
        "file_size": ev.file_size,
        "mime_type": ev.mime_type,
        "latitude": ev.latitude,
        "longitude": ev.longitude,
        "altitude": ev.altitude,
        "captured_at": ev.captured_at.isoformat() if ev.captured_at else None,
        "metadata_json": ev.metadata_json,
        "mission_id": str(ev.mission_id) if ev.mission_id else None,
        "poi_id": str(ev.poi_id) if ev.poi_id else None,
        "team_id": str(ev.team_id) if ev.team_id else None,
        "created_by": str(ev.created_by) if ev.created_by else None,
        "approval_status": ev.approval_status,
        "approved_by": str(ev.approved_by) if ev.approved_by else None,
        "approved_at": ev.approved_at.isoformat() if ev.approved_at else None,
        "created_at": ev.created_at.isoformat() if ev.created_at else None,
    }


@router.get("")
async def list_evidence(
    mission_id: Optional[uuid.UUID] = Query(None),
    poi_id: Optional[uuid.UUID] = Query(None),
    team_id: Optional[uuid.UUID] = Query(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = select(Evidence)
    if mission_id:
        q = q.where(Evidence.mission_id == mission_id)
    if poi_id:
        q = q.where(Evidence.poi_id == poi_id)
    if team_id:
        q = q.where(Evidence.team_id == team_id)
    result = await db.execute(q.order_by(Evidence.created_at.desc()))
    return [_ev_dict(e) for e in result.scalars().all()]


@router.post("", status_code=201)
async def upload_evidence(
    title: Optional[str] = Form(None),
    evidence_type: Optional[EvidenceType] = Form(None),
    description: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    mission_id: Optional[str] = Form(None),
    poi_id: Optional[str] = Form(None),
    team_id: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    file_url = None
    file_size = None
    mime_type = None

    if file:
        ext = os.path.splitext(file.filename or "file")[1].lower()
        filename = f"evidence/{uuid.uuid4()}{ext}"
        filepath = os.path.join(settings.UPLOAD_DIR, filename)
        os.makedirs(os.path.dirname(filepath), exist_ok=True)

        async with aiofiles.open(filepath, "wb") as f:
            content = await file.read()
            await f.write(content)
            file_size = len(content)

        file_url = f"/uploads/{filename}"
        mime_type = file.content_type

        if evidence_type is None:
            ct = (mime_type or "").lower()
            if ct.startswith("video"):
                evidence_type = EvidenceType.video
            elif ct.startswith("audio"):
                evidence_type = EvidenceType.audio
            else:
                evidence_type = EvidenceType.image

        if not title:
            title = file.filename or "Field Evidence"

    if not title:
        title = "Field Evidence"
    if evidence_type is None:
        evidence_type = EvidenceType.note

    evidence = Evidence(
        title=title,
        description=description,
        evidence_type=evidence_type,
        file_url=file_url,
        file_size=file_size,
        mime_type=mime_type,
        latitude=latitude,
        longitude=longitude,
        captured_at=datetime.utcnow(),
        mission_id=uuid.UUID(mission_id) if mission_id else None,
        poi_id=uuid.UUID(poi_id) if poi_id else None,
        team_id=uuid.UUID(team_id) if team_id else None,
        created_by=current_user.id,
    )
    db.add(evidence)
    await db.commit()
    await db.refresh(evidence)
    return _ev_dict(evidence)


@router.get("/{evidence_id}")
async def get_evidence(
    evidence_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Evidence).where(Evidence.id == evidence_id))
    ev = result.scalar_one_or_none()
    if not ev:
        raise HTTPException(status_code=404, detail="Evidence not found")
    return _ev_dict(ev)


@router.patch("/{evidence_id}/link")
async def link_evidence(
    evidence_id: uuid.UUID,
    mission_id: Optional[uuid.UUID] = None,
    poi_id: Optional[uuid.UUID] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Link an existing evidence item to a mission and/or POI marker."""
    result = await db.execute(select(Evidence).where(Evidence.id == evidence_id))
    ev = result.scalar_one_or_none()
    if not ev:
        raise HTTPException(status_code=404, detail="Evidence not found")
    if mission_id is not None:
        ev.mission_id = mission_id
    if poi_id is not None:
        ev.poi_id = poi_id
    await db.commit()
    await db.refresh(ev)
    return _ev_dict(ev)


@router.delete("/{evidence_id}")
async def delete_evidence(
    evidence_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Evidence).where(Evidence.id == evidence_id))
    ev = result.scalar_one_or_none()
    if not ev:
        raise HTTPException(status_code=404, detail="Evidence not found")
    if ev.created_by != current_user.id and current_user.role.value != "operations_coordinator":
        raise HTTPException(status_code=403, detail="Access denied")
    await db.delete(ev)
    await db.commit()
    return {"message": "Deleted"}
