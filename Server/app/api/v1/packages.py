import uuid
import json
import zipfile
import io
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user, require_planning_or_above
from app.models.user import User
from app.models.package import MissionPackage, MissionPackageItem
from app.models.mission import Mission
from app.models.route import Route
from app.models.evidence import Evidence

router = APIRouter(prefix="/packages", tags=["Mission Packages"])


class PackageCreate(BaseModel):
    name: str
    description: Optional[str] = None
    mission_id: Optional[uuid.UUID] = None
    include_routes: bool = True
    include_evidence: bool = True
    include_contacts: bool = True


@router.get("")
async def list_packages(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionPackage)
        .options(selectinload(MissionPackage.items))
        .order_by(MissionPackage.created_at.desc())
    )
    packages = result.scalars().all()
    return [
        {
            "id": str(p.id),
            "name": p.name,
            "description": p.description,
            "mission_id": str(p.mission_id) if p.mission_id else None,
            "item_count": len(p.items),
            "created_at": p.created_at.isoformat(),
        }
        for p in packages
    ]


@router.post("", status_code=201)
async def create_package(
    data: PackageCreate,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    package = MissionPackage(
        name=data.name,
        description=data.description,
        mission_id=data.mission_id,
        created_by=current_user.id,
    )
    db.add(package)
    await db.flush()

    items_added = 0

    if data.mission_id:
        # Mission data
        m_result = await db.execute(select(Mission).where(Mission.id == data.mission_id))
        mission = m_result.scalar_one_or_none()
        if mission:
            db.add(MissionPackageItem(package_id=package.id, item_type="mission", item_id=str(mission.id), item_name=mission.name))
            items_added += 1

        if data.include_routes:
            r_result = await db.execute(select(Route).where(Route.mission_id == data.mission_id, Route.is_active == True))
            for route in r_result.scalars().all():
                db.add(MissionPackageItem(package_id=package.id, item_type="route", item_id=str(route.id), item_name=route.name))
                items_added += 1

        if data.include_evidence:
            e_result = await db.execute(select(Evidence).where(Evidence.mission_id == data.mission_id))
            for ev in e_result.scalars().all():
                db.add(MissionPackageItem(package_id=package.id, item_type="evidence", item_id=str(ev.id), item_name=ev.title))
                items_added += 1

    await db.commit()
    await db.refresh(package)
    return {"id": str(package.id), "name": package.name, "items": items_added}


@router.get("/{package_id}/download")
async def download_package(
    package_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionPackage)
        .options(selectinload(MissionPackage.items))
        .where(MissionPackage.id == package_id)
    )
    package = result.scalar_one_or_none()
    if not package:
        raise HTTPException(status_code=404, detail="Package not found")

    # Build ZIP in memory
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        manifest = {
            "package_id": str(package.id),
            "name": package.name,
            "description": package.description,
            "created_at": package.created_at.isoformat(),
            "items": [
                {"type": i.item_type, "id": i.item_id, "name": i.item_name}
                for i in package.items
            ],
        }
        zf.writestr("manifest.json", json.dumps(manifest, indent=2))

        # Fetch each item's data
        for item in package.items:
            if item.item_type == "mission":
                m = await db.get(Mission, uuid.UUID(item.item_id))
                if m:
                    zf.writestr(
                        f"missions/{item.item_id}.json",
                        json.dumps({"id": str(m.id), "name": m.name, "status": m.status.value}, indent=2),
                    )
            elif item.item_type == "route":
                r = await db.get(Route, uuid.UUID(item.item_id))
                if r:
                    zf.writestr(
                        f"routes/{item.item_id}.json",
                        json.dumps({"id": str(r.id), "name": r.name, "type": r.route_type.value, "color": r.color}, indent=2),
                    )
            elif item.item_type == "evidence":
                e = await db.get(Evidence, uuid.UUID(item.item_id))
                if e:
                    zf.writestr(
                        f"evidence/{item.item_id}.json",
                        json.dumps({"id": str(e.id), "title": e.title, "type": e.evidence_type.value, "file_url": e.file_url}, indent=2),
                    )

    buf.seek(0)
    filename = f"drd_package_{package.name.replace(' ', '_')}_{datetime.utcnow().strftime('%Y%m%d')}.zip"
    return StreamingResponse(
        buf,
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.delete("/{package_id}")
async def delete_package(
    package_id: uuid.UUID,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(MissionPackage).where(MissionPackage.id == package_id))
    package = result.scalar_one_or_none()
    if not package:
        raise HTTPException(status_code=404, detail="Package not found")
    await db.delete(package)
    await db.commit()
    return {"message": "Deleted"}
