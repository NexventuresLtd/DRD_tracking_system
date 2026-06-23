import uuid
import os
import aiofiles
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.evidence import Evidence, EvidenceType
from app.config import settings

router = APIRouter(prefix="/evidence", tags=["Evidence"])


@router.get("")
async def list_evidence(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Evidence).order_by(Evidence.created_at.desc()))
    return result.scalars().all()


@router.post("", status_code=201)
async def upload_evidence(
    title: str = Form(...),
    evidence_type: EvidenceType = Form(...),
    description: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    mission_id: Optional[str] = Form(None),
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
        created_by=current_user.id,
    )
    db.add(evidence)
    await db.commit()
    await db.refresh(evidence)
    return {"id": str(evidence.id), "file_url": file_url}


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
    return ev


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
