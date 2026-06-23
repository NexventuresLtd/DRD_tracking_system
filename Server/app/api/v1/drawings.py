import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.services.drawing_service import DrawingService
from app.websocket.manager import manager

router = APIRouter(prefix="/drawings", tags=["Drawings"])


def _drawing_dict(d) -> dict:
    return {
        "id": str(d.id),
        "name": d.name,
        "drawing_type": d.drawing_type.value,
        "color": d.color,
        "fill_color": d.fill_color,
        "stroke_width": d.stroke_width,
        "opacity": d.opacity,
        "radius": d.radius,
        "notes": d.notes,
        "mission_id": str(d.mission_id) if d.mission_id else None,
        "created_by": str(d.created_by) if d.created_by else None,
        "created_at": d.created_at.isoformat(),
        "updated_at": d.updated_at.isoformat(),
        "points": [
            {"lat": p.latitude, "lng": p.longitude, "order": p.order_index}
            for p in (d.points or [])
        ],
    }


@router.get("")
async def list_drawings(
    mission_id: uuid.UUID = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = DrawingService(db)
    drawings = await svc.list_drawings(mission_id=mission_id)
    return [_drawing_dict(d) for d in drawings]


@router.post("", status_code=201)
async def create_drawing(
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = DrawingService(db)
    drawing = await svc.create(body, current_user.id)
    data = _drawing_dict(drawing)
    room = f"mission:{body.get('mission_id', 'global')}"
    await manager.broadcast_to_room(room, {"type": "drawing_update", "drawing": data, "author": str(current_user.id)})
    return data


@router.get("/{drawing_id}")
async def get_drawing(
    drawing_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = DrawingService(db)
    d = await svc.get_by_id(drawing_id)
    if not d:
        raise HTTPException(404, "Drawing not found")
    return _drawing_dict(d)


@router.delete("/{drawing_id}", status_code=204)
async def delete_drawing(
    drawing_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = DrawingService(db)
    if not await svc.delete(drawing_id):
        raise HTTPException(404, "Drawing not found")
