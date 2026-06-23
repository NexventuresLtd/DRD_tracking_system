import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user, require_planning_or_above, require_leader_or_above
from app.models.user import User
from app.services.mission_service import MissionService
from app.websocket.manager import manager

router = APIRouter(prefix="/missions", tags=["Missions"])


def _mission_dict(m) -> dict:
    return {
        "id": str(m.id),
        "name": m.name,
        "description": m.description,
        "status": m.status.value,
        "created_by": str(m.created_by) if m.created_by else None,
        "start_date": m.start_date.isoformat() if m.start_date else None,
        "end_date": m.end_date.isoformat() if m.end_date else None,
        "briefing_notes": m.briefing_notes,
        "area_of_operations": m.area_of_operations,
        "created_at": m.created_at.isoformat(),
        "updated_at": m.updated_at.isoformat(),
        "objectives": [
            {"id": str(o.id), "title": o.title, "description": o.description,
             "is_completed": o.is_completed, "order_index": o.order_index}
            for o in (m.objectives or [])
        ],
        "assignments": [
            {"id": str(a.id), "team_id": str(a.team_id) if a.team_id else None,
             "user_id": str(a.user_id) if a.user_id else None,
             "role_in_mission": a.role_in_mission}
            for a in (m.assignments or [])
        ],
    }


@router.get("")
async def list_missions(
    status: str = None,
    limit: int = 50,
    offset: int = 0,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    missions = await svc.list_missions(status=status, limit=limit, offset=offset)
    return [_mission_dict(m) for m in missions]


@router.post("", status_code=201)
async def create_mission(
    body: dict,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    mission = await svc.create(body, current_user.id)
    data = _mission_dict(mission)
    await manager.broadcast_to_room("events", {"type": "mission_created", "mission": data})
    return data


@router.get("/{mission_id}")
async def get_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")
    return _mission_dict(mission)


@router.put("/{mission_id}")
async def update_mission(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    mission = await svc.update(mission_id, body)
    if not mission:
        raise HTTPException(404, "Mission not found")
    data = _mission_dict(mission)
    await manager.broadcast_to_room("events", {"type": "mission_updated", "mission": data})
    return data


@router.delete("/{mission_id}", status_code=204)
async def delete_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    if not await svc.delete(mission_id):
        raise HTTPException(404, "Mission not found")


@router.post("/{mission_id}/assignments", status_code=201)
async def assign_to_mission(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    assignment = await svc.add_assignment(mission_id, body, current_user.id)
    return {"id": str(assignment.id), "mission_id": str(assignment.mission_id)}


@router.post("/{mission_id}/objectives/{objective_id}/complete")
async def complete_objective(
    mission_id: uuid.UUID,
    objective_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    if not await svc.complete_objective(objective_id):
        raise HTTPException(404, "Objective not found")
    return {"ok": True}
