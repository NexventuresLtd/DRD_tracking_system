import os
import uuid
import shutil
from pathlib import Path
from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Form
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.evidence import Evidence
from app.models.user import User

router = APIRouter(prefix="/evidence", tags=["evidence"])

UPLOAD_DIR = Path("uploads/evidence")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_SIZE_MB = 10


@router.post("/upload")
async def upload_evidence(
    file: UploadFile = File(...),
    poi_id: Optional[str] = Form(None),
    message_id: Optional[str] = Form(None),
    caption: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail="Only image files are allowed (jpeg, png, webp, gif)")

    content = await file.read()
    size_mb = len(content) / (1024 * 1024)
    if size_mb > MAX_SIZE_MB:
        raise HTTPException(status_code=400, detail=f"File too large. Maximum size is {MAX_SIZE_MB}MB")

    ext = Path(file.filename or "image.jpg").suffix or ".jpg"
    unique_name = f"{uuid.uuid4()}{ext}"
    file_path = UPLOAD_DIR / unique_name

    with open(file_path, "wb") as f:
        f.write(content)

    evidence = Evidence(
        poi_id=uuid.UUID(poi_id) if poi_id else None,
        message_id=uuid.UUID(message_id) if message_id else None,
        uploaded_by=current_user.id,
        file_name=file.filename or unique_name,
        file_path=str(file_path),
        mime_type=file.content_type or "image/jpeg",
        file_size=len(content),
        caption=caption,
    )
    db.add(evidence)
    await db.commit()
    await db.refresh(evidence)

    return {
        "id": str(evidence.id),
        "url": f"/api/v1/evidence/{evidence.id}/file",
        "file_name": evidence.file_name,
        "caption": evidence.caption,
        "created_at": evidence.created_at.isoformat(),
    }


@router.get("/{evidence_id}/file")
async def get_evidence_file(evidence_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Evidence).where(Evidence.id == uuid.UUID(evidence_id)))
    ev = result.scalar_one_or_none()
    if not ev:
        raise HTTPException(status_code=404, detail="Evidence not found")
    if not os.path.exists(ev.file_path):
        raise HTTPException(status_code=404, detail="File not found on disk")
    return FileResponse(ev.file_path, media_type=ev.mime_type, filename=ev.file_name)


@router.get("/poi/{poi_id}")
async def get_poi_evidence(
    poi_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Evidence).where(Evidence.poi_id == uuid.UUID(poi_id)).order_by(Evidence.created_at.desc())
    )
    items = result.scalars().all()
    return [
        {
            "id": str(e.id),
            "url": f"/api/v1/evidence/{e.id}/file",
            "file_name": e.file_name,
            "caption": e.caption,
            "file_size": e.file_size,
            "created_at": e.created_at.isoformat(),
        }
        for e in items
    ]


@router.get("/message/{message_id}")
async def get_message_evidence(
    message_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Evidence).where(Evidence.message_id == uuid.UUID(message_id)).order_by(Evidence.created_at)
    )
    items = result.scalars().all()
    return [
        {
            "id": str(e.id),
            "url": f"/api/v1/evidence/{e.id}/file",
            "file_name": e.file_name,
            "caption": e.caption,
            "created_at": e.created_at.isoformat(),
        }
        for e in items
    ]


@router.delete("/{evidence_id}")
async def delete_evidence(
    evidence_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Evidence).where(Evidence.id == uuid.UUID(evidence_id)))
    ev = result.scalar_one_or_none()
    if not ev:
        raise HTTPException(status_code=404, detail="Evidence not found")
    if str(ev.uploaded_by) != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized")
    if os.path.exists(ev.file_path):
        os.remove(ev.file_path)
    await db.delete(ev)
    await db.commit()
    return {"ok": True}
