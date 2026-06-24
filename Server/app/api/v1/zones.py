import uuid
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from pydantic import BaseModel

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User, UserRole
from app.models.zone import Zone, ZoneAssignment
from app.models.team import TeamMember
from app.websocket.manager import manager

router = APIRouter(prefix="/zones", tags=["Zones"])

COORD = UserRole.operations_coordinator
PLANNING = UserRole.planning_officer
LEADER = UserRole.team_leader
FIELD = UserRole.field_user


# ── Schemas ──────────────────────────────────────────────────────────────────

class ZoneCreate(BaseModel):
    name: str
    description: Optional[str] = None
    zone_type: str = "operational"
    shape: str = "polygon"
    color: str = "#6366f1"
    fill_color: Optional[str] = None
    polygon_points: Optional[dict] = None
    center_lat: Optional[float] = None
    center_lng: Optional[float] = None
    radius: Optional[float] = None
    is_circle: bool = False
    mission_id: Optional[uuid.UUID] = None
    team_id: Optional[uuid.UUID] = None


class AssignTeamRequest(BaseModel):
    team_id: Optional[uuid.UUID] = None
    assignment_status: str = "assigned"


class ZoneAssignmentCreate(BaseModel):
    user_id: uuid.UUID
    point_lat: float
    point_lon: float
    point_index: Optional[int] = None
    label: Optional[str] = None
    notes: Optional[str] = None


class AssignmentStatusUpdate(BaseModel):
    status: str


class PatrolReport(BaseModel):
    report_type: str  # enemy_sighted, suspicious_activity, incident, all_clear, medical, request_support
    description: str
    latitude: float
    longitude: float
    severity: str = "medium"


# ── Helpers ──────────────────────────────────────────────────────────────────

def _serialize_zone(z: Zone) -> dict:
    return {
        "id": str(z.id),
        "name": z.name,
        "description": z.description,
        "zone_type": z.zone_type,
        "shape": z.shape,
        "color": z.color,
        "fill_color": z.fill_color,
        "polygon_points": z.polygon_points,
        "center_lat": z.center_lat,
        "center_lng": z.center_lng,
        "radius": z.radius,
        "is_circle": z.is_circle,
        "team_id": str(z.team_id) if z.team_id else None,
        "assignment_status": z.assignment_status,
        "mission_id": str(z.mission_id) if z.mission_id else None,
        "created_by": str(z.created_by) if z.created_by else None,
        "is_active": z.is_active,
        "created_at": z.created_at.isoformat() if z.created_at else None,
    }


def _serialize_assignment(a: ZoneAssignment, user: Optional[User] = None) -> dict:
    return {
        "id": str(a.id),
        "zone_id": str(a.zone_id),
        "user_id": str(a.user_id),
        "point_index": a.point_index,
        "point_lat": a.point_lat,
        "point_lon": a.point_lon,
        "label": a.label,
        "status": a.status,
        "assigned_by": str(a.assigned_by) if a.assigned_by else None,
        "assigned_at": a.assigned_at.isoformat() if a.assigned_at else None,
        "arrived_at": a.arrived_at.isoformat() if a.arrived_at else None,
        "completed_at": a.completed_at.isoformat() if a.completed_at else None,
        "notes": a.notes,
        "user": {
            "id": str(user.id),
            "full_name": user.full_name,
            "username": user.username,
            "avatar_url": getattr(user, "avatar_url", None),
            "role": user.role.value,
        } if user else None,
    }


# ── Zone CRUD ────────────────────────────────────────────────────────────────

@router.get("")
async def list_zones(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = select(Zone).where(Zone.is_active == True)

    if current_user.role in (FIELD, LEADER):
        tm = await db.execute(select(TeamMember.team_id).where(TeamMember.user_id == current_user.id))
        team_ids = [row[0] for row in tm.all()]
        if not team_ids:
            return []
        q = q.where(Zone.team_id.in_(team_ids))

    result = await db.execute(q.order_by(Zone.created_at.desc()))
    return [_serialize_zone(z) for z in result.scalars().all()]


@router.post("", status_code=201)
async def create_zone(
    data: ZoneCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role not in (COORD, PLANNING):
        raise HTTPException(403, "Only coordinators and planning officers can create zones")

    zone = Zone(**data.model_dump(exclude_none=True), created_by=current_user.id)
    db.add(zone)
    await db.commit()
    await db.refresh(zone)

    payload = _serialize_zone(zone)
    await manager.broadcast({"type": "zone_created", **payload})
    return payload


@router.put("/{zone_id}")
async def update_zone(
    zone_id: uuid.UUID,
    data: ZoneCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role not in (COORD, PLANNING):
        raise HTTPException(403, "Insufficient permissions")

    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(404, "Zone not found")

    for k, v in data.model_dump(exclude_none=True).items():
        setattr(zone, k, v)
    await db.commit()
    await db.refresh(zone)

    payload = _serialize_zone(zone)
    await manager.broadcast({"type": "zone_updated", **payload})
    return payload


@router.delete("/{zone_id}", status_code=204)
async def delete_zone(
    zone_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role not in (COORD, PLANNING):
        raise HTTPException(403, "Insufficient permissions")

    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(404, "Zone not found")

    zone.is_active = False
    await db.commit()
    await manager.broadcast({"type": "zone_deleted", "zone_id": str(zone_id)})


# ── Team Assignment ───────────────────────────────────────────────────────────

@router.put("/{zone_id}/assign-team")
async def assign_team(
    zone_id: uuid.UUID,
    body: AssignTeamRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role not in (COORD, PLANNING):
        raise HTTPException(403, "Insufficient permissions")

    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(404, "Zone not found")

    zone.team_id = body.team_id
    zone.assignment_status = body.assignment_status if body.team_id else "draft"
    await db.commit()
    await db.refresh(zone)

    payload = _serialize_zone(zone)
    if body.team_id:
        tm = await db.execute(select(TeamMember.user_id).where(TeamMember.team_id == body.team_id))
        for (uid,) in tm.all():
            await manager.send_to_user(str(uid), {"type": "zone_assigned", **payload})
    await manager.broadcast({"type": "zone_updated", **payload})
    return payload


# ── Point Assignments ─────────────────────────────────────────────────────────

@router.get("/{zone_id}/assignments")
async def get_assignments(
    zone_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(ZoneAssignment).where(ZoneAssignment.zone_id == zone_id))
    assignments = result.scalars().all()

    out = []
    for a in assignments:
        ur = await db.execute(select(User).where(User.id == a.user_id))
        out.append(_serialize_assignment(a, ur.scalar_one_or_none()))
    return out


@router.post("/{zone_id}/assignments", status_code=201)
async def create_assignment(
    zone_id: uuid.UUID,
    data: ZoneAssignmentCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role == FIELD:
        raise HTTPException(403, "Field users cannot create assignments")

    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(404, "Zone not found")

    await db.execute(
        delete(ZoneAssignment).where(
            ZoneAssignment.zone_id == zone_id,
            ZoneAssignment.user_id == data.user_id,
        )
    )

    a = ZoneAssignment(
        zone_id=zone_id,
        user_id=data.user_id,
        point_lat=data.point_lat,
        point_lon=data.point_lon,
        point_index=data.point_index,
        label=data.label,
        notes=data.notes,
        assigned_by=current_user.id,
        status="pending",
    )
    db.add(a)

    if zone.assignment_status == "assigned":
        zone.assignment_status = "active"

    zone_name = zone.name  # capture before commit expires the object

    await db.commit()
    await db.refresh(a)

    ur = await db.execute(select(User).where(User.id == data.user_id))
    u = ur.scalar_one_or_none()
    payload = _serialize_assignment(a, u)

    await manager.send_to_user(str(data.user_id), {
        "type": "zone_point_assigned",
        "zone_id": str(zone_id),
        "zone_name": zone_name,
        **payload,
    })
    await manager.broadcast({"type": "zone_assignment_updated", "zone_id": str(zone_id), **payload})
    return payload


@router.put("/{zone_id}/assignments/{user_id}/status")
async def update_assignment_status(
    zone_id: uuid.UUID,
    user_id: uuid.UUID,
    body: AssignmentStatusUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role == FIELD and str(current_user.id) != str(user_id):
        raise HTTPException(403, "Can only update your own status")

    result = await db.execute(
        select(ZoneAssignment).where(
            ZoneAssignment.zone_id == zone_id,
            ZoneAssignment.user_id == user_id,
        )
    )
    assignment = result.scalar_one_or_none()
    if not assignment:
        raise HTTPException(404, "Assignment not found")

    assignment.status = body.status
    if body.status == "arrived" and not assignment.arrived_at:
        assignment.arrived_at = datetime.utcnow()
    if body.status == "completed" and not assignment.completed_at:
        assignment.completed_at = datetime.utcnow()

    await db.commit()

    ur = await db.execute(select(User).where(User.id == user_id))
    u = ur.scalar_one_or_none()
    payload = _serialize_assignment(assignment, u)
    await manager.broadcast({"type": "zone_assignment_updated", "zone_id": str(zone_id), **payload})
    return payload


@router.delete("/{zone_id}/assignments/{user_id}", status_code=204)
async def remove_assignment(
    zone_id: uuid.UUID,
    user_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role == FIELD:
        raise HTTPException(403, "Field users cannot remove assignments")

    await db.execute(
        delete(ZoneAssignment).where(
            ZoneAssignment.zone_id == zone_id,
            ZoneAssignment.user_id == user_id,
        )
    )
    await db.commit()
    await manager.broadcast({
        "type": "zone_assignment_removed",
        "zone_id": str(zone_id),
        "user_id": str(user_id),
    })


# ── Patrol Report ─────────────────────────────────────────────────────────────

@router.post("/{zone_id}/patrol-report", status_code=201)
async def patrol_report(
    zone_id: uuid.UUID,
    data: PatrolReport,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(404, "Zone not found")

    zone_name = zone.name  # capture before any potential expiry

    report = {
        "type": "patrol_report",
        "zone_id": str(zone_id),
        "zone_name": zone_name,
        "report_type": data.report_type,
        "description": data.description,
        "latitude": data.latitude,
        "longitude": data.longitude,
        "severity": data.severity,
        "reported_by": {
            "id": str(current_user.id),
            "full_name": current_user.full_name,
            "username": current_user.username,
            "avatar_url": getattr(current_user, "avatar_url", None),
        },
        "reported_at": datetime.utcnow().isoformat(),
    }
    await manager.broadcast(report)
    return report


# ── My assignments ────────────────────────────────────────────────────────────

@router.get("/my/assignments")
async def my_assignments(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ZoneAssignment, Zone)
        .join(Zone, ZoneAssignment.zone_id == Zone.id)
        .where(ZoneAssignment.user_id == current_user.id)
        .where(Zone.is_active == True)
        .where(ZoneAssignment.status.notin_(["completed"]))
    )
    rows = result.all()
    return [
        {**_serialize_assignment(a), "zone": _serialize_zone(z)}
        for a, z in rows
    ]
