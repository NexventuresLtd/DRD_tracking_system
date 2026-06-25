import uuid
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Body
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.middleware.auth import get_current_user, require_planning_or_above, require_leader_or_above, require_coordinator
from app.models.user import User, UserRole
from app.models.team import TeamMember
from app.models.mission import (
    Mission, MissionStatus, MissionPriority, MissionObjective,
    MissionIncident, MissionAssignment, CasualtyReport, IncidentSeverity, CasualtyType,
    MissionAcknowledgement, AcknowledgementStatus,
    MissionBriefingAttendance, AttendanceStatus,
    MissionSitrep, MissionCompletionReport, MissionDebriefRecord,
    ReportCategory,
)
from app.models.evidence import Evidence
from app.models.live_session import LiveSession
from app.models.zone import Zone
from app.models.route import Route, RouteWaypoint
from app.models.post import Post
from app.services.mission_service import MissionService
from app.services.notification_service import NotificationService
from app.websocket.manager import manager

router = APIRouter(prefix="/missions", tags=["Missions"])


# ── Serialisers ───────────────────────────────────────────────────────────────

def _mission_dict(m) -> dict:
    return {
        "id": str(m.id),
        "name": m.name,
        "mission_code": getattr(m, "mission_code", None),
        "description": m.description,
        "status": m.status.value,
        "priority": (getattr(m, "priority", None) or MissionPriority.medium).value,
        "created_by": str(m.created_by) if m.created_by else None,
        "start_date": m.start_date.isoformat() if m.start_date else None,
        "end_date": m.end_date.isoformat() if m.end_date else None,
        "briefing_notes": m.briefing_notes,
        "area_of_operations": m.area_of_operations,
        "supporting_assets": getattr(m, "supporting_assets", None),
        "suspension_reason": getattr(m, "suspension_reason", None),
        "extraction_point": getattr(m, "extraction_point", None),
        "briefing_datetime": m.briefing_datetime.isoformat() if getattr(m, "briefing_datetime", None) else None,
        "briefing_audience": getattr(m, "briefing_audience", "all"),
        "zone_ids": getattr(m, "zone_ids", []) or [],
        "route_ids": getattr(m, "route_ids", []) or [],
        "facility_ids": getattr(m, "facility_ids", []) or [],
        "live_session_id": str(m.live_session_id) if getattr(m, "live_session_id", None) else None,
        "created_at": m.created_at.isoformat(),
        "updated_at": m.updated_at.isoformat(),
        "objectives": [
            {
                "id": str(o.id), "title": o.title, "description": o.description,
                "is_completed": o.is_completed, "order_index": o.order_index,
                "zone_id":     str(o.zone_id)     if getattr(o, "zone_id", None)     else None,
                "route_id":    str(o.route_id)    if getattr(o, "route_id", None)    else None,
                "facility_id": str(o.facility_id) if getattr(o, "facility_id", None) else None,
                "completed_by": str(o.completed_by) if getattr(o, "completed_by", None) else None,
                "completed_at": o.completed_at.isoformat() if getattr(o, "completed_at", None) else None,
                "completed_lat": getattr(o, "completed_lat", None),
                "completed_lng": getattr(o, "completed_lng", None),
            }
            for o in (m.objectives or [])
        ],
        "assignments": [
            {
                "id": str(a.id),
                "team_id": str(a.team_id) if a.team_id else None,
                "user_id": str(a.user_id) if a.user_id else None,
                "role_in_mission": a.role_in_mission,
            }
            for a in (m.assignments or [])
        ],
    }


def _incident_dict(i) -> dict:
    return {
        "id": str(i.id),
        "mission_id": str(i.mission_id),
        "reported_by": str(i.reported_by) if i.reported_by else None,
        "report_category": (getattr(i, "report_category", None) or ReportCategory.incident).value,
        "incident_type": i.incident_type,
        "title": i.title,
        "description": i.description,
        "severity": i.severity.value if i.severity else "medium",
        "latitude": i.latitude,
        "longitude": i.longitude,
        "contact_size": getattr(i, "contact_size", None),
        "contact_activity": getattr(i, "contact_activity", None),
        "contact_unit": getattr(i, "contact_unit", None),
        "contact_equipment": getattr(i, "contact_equipment", None),
        "ref_id": str(i.ref_id) if i.ref_id else None,
        "ref_type": i.ref_type,
        "status": i.status,
        "created_at": i.created_at.isoformat(),
    }


def _casualty_dict(c) -> dict:
    return {
        "id": str(c.id),
        "mission_id": str(c.mission_id),
        "reported_by": str(c.reported_by) if c.reported_by else None,
        "user_id": str(c.user_id) if c.user_id else None,
        "casualty_type": c.casualty_type.value,
        "notes": c.notes,
        "evidence_id": str(c.evidence_id) if c.evidence_id else None,
        "latitude": c.latitude,
        "longitude": c.longitude,
        "created_at": c.created_at.isoformat(),
    }


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _get_mission_or_404(mission_id: uuid.UUID, db: AsyncSession) -> Mission:
    result = await db.execute(
        select(Mission)
        .options(selectinload(Mission.objectives), selectinload(Mission.assignments))
        .where(Mission.id == mission_id)
    )
    m = result.scalar_one_or_none()
    if not m:
        raise HTTPException(404, "Mission not found")
    return m


@router.get("/{mission_id}/resources")
async def get_mission_resources(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return all zones, routes, and facilities linked to a mission — no team/role filter."""
    mission = await _get_mission_or_404(mission_id, db)

    zone_ids: set[uuid.UUID] = set()
    route_ids: set[uuid.UUID] = set()
    facility_ids: set[uuid.UUID] = set()

    for raw in (mission.zone_ids or []):
        try: zone_ids.add(uuid.UUID(str(raw)))
        except Exception: pass
    for raw in (mission.route_ids or []):
        try: route_ids.add(uuid.UUID(str(raw)))
        except Exception: pass
    for raw in (mission.facility_ids or []):
        try: facility_ids.add(uuid.UUID(str(raw)))
        except Exception: pass

    for obj in (mission.objectives or []):
        if obj.zone_id:     zone_ids.add(obj.zone_id)
        if obj.route_id:    route_ids.add(obj.route_id)
        if obj.facility_id: facility_ids.add(obj.facility_id)

    zones, routes, facilities = [], [], []

    if zone_ids:
        res = await db.execute(select(Zone).where(Zone.id.in_(zone_ids), Zone.is_active == True))
        for z in res.scalars().all():
            zones.append({
                "id": str(z.id), "name": z.name, "zone_type": z.zone_type,
                "color": z.color, "fill_color": getattr(z, "fill_color", None),
                "polygon_points": z.polygon_points,
                "center_lat": z.center_lat, "center_lng": z.center_lng,
                "radius": z.radius, "is_circle": z.is_circle, "is_active": z.is_active,
            })

    if route_ids:
        res = await db.execute(
            select(Route).options(selectinload(Route.waypoints))
            .where(Route.id.in_(route_ids), Route.is_active == True)
        )
        for r in res.scalars().all():
            wps = sorted(r.waypoints or [], key=lambda w: w.order_index)
            routes.append({
                "id": str(r.id), "name": r.name, "color": r.color,
                "route_type": r.route_type.value,
                "waypoints": [
                    {"order": w.order_index, "latitude": w.latitude,
                     "longitude": w.longitude, "name": w.name}
                    for w in wps
                ],
            })

    if facility_ids:
        res = await db.execute(select(Post).where(Post.id.in_(facility_ids)))
        for p in res.scalars().all():
            facilities.append({
                "id": str(p.id), "name": p.name,
                "facility_type": p.facility_type.value,
                "latitude": p.latitude, "longitude": p.longitude,
                "threat_level": getattr(p, "threat_level", None),
                "status": p.status.value if p.status else None,
            })

    return {"zones": zones, "routes": routes, "facilities": facilities}


async def _notify_assigned(mission: Mission, db: AsyncSession, title: str, body: str, type_: str = "mission_assigned"):
    notif_svc = NotificationService(db)
    for assignment in (mission.assignments or []):
        if assignment.team_id:
            res = await db.execute(select(TeamMember).where(TeamMember.team_id == assignment.team_id))
            for tm in res.scalars().all():
                await notif_svc.create_and_send(
                    user_id=tm.user_id, type=type_, title=title, body=body,
                    ref_id=str(mission.id), ref_type="mission", priority="high",
                )
        elif assignment.user_id:
            await notif_svc.create_and_send(
                user_id=assignment.user_id, type=type_, title=title, body=body,
                ref_id=str(mission.id), ref_type="mission", priority="high",
            )


async def _collect_assigned_user_ids(mission: Mission, db: AsyncSession) -> list[str]:
    user_ids: list[str] = []
    for a in (mission.assignments or []):
        if a.team_id:
            res = await db.execute(select(TeamMember.user_id).where(TeamMember.team_id == a.team_id))
            user_ids.extend(str(uid) for uid in res.scalars().all())
        elif a.user_id:
            user_ids.append(str(a.user_id))
    return list(set(user_ids))


# ── My Active Mission ─────────────────────────────────────────────────────────

@router.get("/my-active")
async def get_my_active_mission(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return the calling user's currently active mission, or null."""
    team_ids_res = await db.execute(
        select(TeamMember.team_id).where(TeamMember.user_id == current_user.id)
    )
    my_team_ids = [str(t) for t in team_ids_res.scalars().all()]

    cond = MissionAssignment.user_id == current_user.id
    if my_team_ids:
        cond = cond | MissionAssignment.team_id.in_([uuid.UUID(t) for t in my_team_ids])

    assigned_ids_res = await db.execute(select(MissionAssignment.mission_id).where(cond))
    mission_ids = list({str(m) for m in assigned_ids_res.scalars().all()})

    if not mission_ids:
        return None

    result = await db.execute(
        select(Mission)
        .options(selectinload(Mission.objectives), selectinload(Mission.assignments))
        .where(
            Mission.id.in_([uuid.UUID(mid) for mid in mission_ids]),
            Mission.status == MissionStatus.active,
        )
        .limit(1)
    )
    m = result.scalar_one_or_none()
    return _mission_dict(m) if m else None


# ── Mission CRUD ──────────────────────────────────────────────────────────────

@router.get("")
async def list_missions(
    status: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    my_missions: bool = False,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    is_field_user = current_user.role == UserRole.field_user

    if my_missions:
        team_ids_res = await db.execute(
            select(TeamMember.team_id).where(TeamMember.user_id == current_user.id)
        )
        my_team_ids = [str(t) for t in team_ids_res.scalars().all()]
        cond = MissionAssignment.user_id == current_user.id
        if my_team_ids:
            cond = cond | MissionAssignment.team_id.in_([uuid.UUID(t) for t in my_team_ids])
        assigned_ids_res = await db.execute(select(MissionAssignment.mission_id).where(cond))
        mission_ids = list({str(m) for m in assigned_ids_res.scalars().all()})
        if not mission_ids:
            return []
        q = (
            select(Mission)
            .options(selectinload(Mission.objectives), selectinload(Mission.assignments))
            .where(Mission.id.in_([uuid.UUID(mid) for mid in mission_ids]))
            .order_by(Mission.created_at.desc())
            .limit(limit).offset(offset)
        )
        if status:
            q = q.where(Mission.status == MissionStatus(status))
        elif is_field_user:
            q = q.where(Mission.status != MissionStatus.draft)
    else:
        svc = MissionService(db)
        missions = await svc.list_missions(status=status, limit=limit, offset=offset)
        if is_field_user:
            missions = [m for m in missions if m.status != MissionStatus.draft]
        return [_mission_dict(m) for m in missions]

    result = await db.execute(q)
    return [_mission_dict(m) for m in result.scalars().all()]


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
    mission = await _get_mission_or_404(mission_id, db)
    if current_user.role == UserRole.field_user and mission.status == MissionStatus.draft:
        raise HTTPException(403, "Access denied")
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
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    if not await svc.delete(mission_id):
        raise HTTPException(404, "Mission not found")


# ── Lifecycle transitions (coordinator only) ──────────────────────────────────

@router.post("/{mission_id}/approve")
async def approve_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    if mission.status != MissionStatus.draft:
        raise HTTPException(400, f"Mission must be in DRAFT to approve (current: {mission.status.value})")
    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.approved
    await db.commit()
    await manager.broadcast_to_room("events", {"type": "mission_approved", "mission_id": str(mission_id)})
    return {"status": "approved"}


@router.post("/{mission_id}/activate")
async def activate_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    allowed = {MissionStatus.briefing, MissionStatus.assigned, MissionStatus.pending_acknowledgement}
    if mission.status not in allowed:
        raise HTTPException(400, f"Mission must be in BRIEFING, ASSIGNED, or PENDING_ACKNOWLEDGEMENT to activate (current: {mission.status.value})")
    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.active
    await db.commit()
    await _notify_assigned(mission, db, f"MISSION ACTIVE: {mission.name}", "Mission is now active. Deploy immediately.", "mission_active")
    await manager.broadcast_to_room("events", {"type": "mission_active", "mission_id": str(mission_id)})
    return {"status": "active"}


@router.post("/{mission_id}/suspend")
async def suspend_mission(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    if not body.get("reason"):
        raise HTTPException(400, "reason is required when suspending a mission")
    mission = await _get_mission_or_404(mission_id, db)
    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.suspended
    m.suspension_reason = body["reason"]
    await db.commit()
    await _notify_assigned(mission, db, f"MISSION SUSPENDED: {mission.name}", body["reason"], "mission_suspended")
    await manager.broadcast_to_room("events", {"type": "mission_suspended", "mission_id": str(mission_id)})
    return {"status": "suspended"}


@router.post("/{mission_id}/resume")
async def resume_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    if mission.status != MissionStatus.suspended:
        raise HTTPException(400, "Mission is not suspended")
    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.active
    m.suspension_reason = None
    await db.commit()
    await _notify_assigned(mission, db, f"MISSION RESUMED: {mission.name}", "Mission has been resumed.", "mission_resumed")
    return {"status": "active"}


@router.post("/{mission_id}/complete")
async def complete_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    if mission.status in {MissionStatus.completed, MissionStatus.archived}:
        raise HTTPException(400, f"Mission is already {mission.status.value}")
    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.completed
    await db.commit()
    await manager.broadcast_to_room("events", {"type": "mission_completed", "mission_id": str(mission_id)})
    return {"status": "completed"}


@router.post("/{mission_id}/archive")
async def archive_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    if mission.status != MissionStatus.completed:
        raise HTTPException(400, "Mission must be COMPLETED before archiving")
    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.archived
    await db.commit()
    return {"status": "archived"}


# ── Assignments (coordinator only) ────────────────────────────────────────────

@router.post("/{mission_id}/assignments", status_code=201)
async def assign_to_mission(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    allowed_statuses = {
        MissionStatus.draft, MissionStatus.approved, MissionStatus.assigned,
        MissionStatus.pending_acknowledgement, MissionStatus.active,
    }
    if mission.status not in allowed_statuses:
        raise HTTPException(400, "Cannot assign teams to missions in this status")

    svc = MissionService(db)
    assignment = await svc.add_assignment(mission_id, body, current_user.id)

    # For draft missions: save assignment only, no status change or notifications
    if mission.status == MissionStatus.draft:
        return {"id": str(assignment.id), "mission_id": str(assignment.mission_id), "status": "draft"}

    # Transition to assigned if still approved
    m = await db.get(Mission, mission_id)
    if m.status == MissionStatus.approved:
        m.status = MissionStatus.assigned
        await db.commit()

    # Collect user IDs for this new assignment
    notify_uids: list[str] = []
    if assignment.team_id:
        res = await db.execute(select(TeamMember.user_id).where(TeamMember.team_id == assignment.team_id))
        notify_uids = [str(uid) for uid in res.scalars().all()]
    elif assignment.user_id:
        notify_uids = [str(assignment.user_id)]

    # Create acknowledgement records
    for uid_str in notify_uids:
        existing = await db.execute(
            select(MissionAcknowledgement).where(
                MissionAcknowledgement.mission_id == mission_id,
                MissionAcknowledgement.user_id == uuid.UUID(uid_str),
            )
        )
        if not existing.scalar_one_or_none():
            db.add(MissionAcknowledgement(
                id=uuid.uuid4(),
                mission_id=mission_id,
                user_id=uuid.UUID(uid_str),
                status=AcknowledgementStatus.pending,
            ))

    m.status = MissionStatus.pending_acknowledgement
    await db.commit()

    zone_ids = list(m.zone_ids or [])
    route_ids = list(m.route_ids or [])
    facility_ids = list(m.facility_ids or [])

    notif_svc = NotificationService(db)
    for uid_str in notify_uids:
        try:
            await manager.send_to(uid_str, {
                "type": "mission_assigned",
                "mission_id": str(mission_id),
                "zone_ids": zone_ids,
                "route_ids": route_ids,
                "facility_ids": facility_ids,
            })
            await notif_svc.create_and_send(
                user_id=uuid.UUID(uid_str),
                type="mission_assigned",
                title=f"MISSION ASSIGNED: {m.name}",
                body="You have been assigned to a mission. Acknowledge immediately.",
                ref_id=str(mission_id),
                ref_type="mission",
                priority="high",
            )
        except Exception:
            pass

    return {"id": str(assignment.id), "mission_id": str(assignment.mission_id), "status": "pending_acknowledgement"}


@router.delete("/{mission_id}/assignments/{assignment_id}", status_code=204)
async def remove_assignment(
    mission_id: uuid.UUID,
    assignment_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionAssignment).where(
            MissionAssignment.id == assignment_id,
            MissionAssignment.mission_id == mission_id,
        )
    )
    assignment = result.scalar_one_or_none()
    if not assignment:
        raise HTTPException(404, "Assignment not found")
    await db.delete(assignment)
    await db.commit()


# ── Acknowledgement ───────────────────────────────────────────────────────────

@router.post("/{mission_id}/acknowledge")
async def acknowledge_mission(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionAcknowledgement).where(
            MissionAcknowledgement.mission_id == mission_id,
            MissionAcknowledgement.user_id == current_user.id,
        )
    )
    ack = result.scalar_one_or_none()
    if not ack:
        ack = MissionAcknowledgement(
            id=uuid.uuid4(),
            mission_id=mission_id,
            user_id=current_user.id,
            status=AcknowledgementStatus.pending,
        )
        db.add(ack)

    ack.status = AcknowledgementStatus.acknowledged
    ack.acknowledged_at = datetime.utcnow()
    await db.commit()

    await manager.broadcast_to_room("events", {
        "type": "mission_acknowledged",
        "mission_id": str(mission_id),
        "user_id": str(current_user.id),
        "user_name": current_user.full_name or current_user.username,
    })
    return {"acknowledged": True}


@router.get("/{mission_id}/acknowledgements")
async def list_acknowledgements(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionAcknowledgement).where(MissionAcknowledgement.mission_id == mission_id)
    )
    acks = result.scalars().all()
    out = []
    for ack in acks:
        ur = await db.execute(select(User).where(User.id == ack.user_id))
        u = ur.scalar_one_or_none()
        out.append({
            "id": str(ack.id),
            "user_id": str(ack.user_id),
            "user_name": u.full_name or u.username if u else str(ack.user_id),
            "status": ack.status.value,
            "acknowledged_at": ack.acknowledged_at.isoformat() if ack.acknowledged_at else None,
        })
    return out


# ── Briefing ──────────────────────────────────────────────────────────────────

@router.post("/{mission_id}/briefing/start", status_code=201)
async def start_mission_briefing(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)

    room_id = str(uuid.uuid4()).replace("-", "")
    session = LiveSession(
        title=f"BRIEFING: {mission.name}",
        host_id=current_user.id,
        room_id=room_id,
        mission_id=mission_id,
    )

    invited = await _collect_assigned_user_ids(mission, db)
    if hasattr(session, "invite_list"):
        session.invite_list = invited
    db.add(session)

    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.briefing
    m.live_session_id = session.id
    await db.commit()
    await db.refresh(session)

    notif_svc = NotificationService(db)
    for uid_str in invited:
        try:
            await notif_svc.create_and_send(
                user_id=uuid.UUID(uid_str),
                type="mission_briefing",
                title=f"LIVE BRIEFING NOW: {mission.name}",
                body="Your presence is required. Join the live briefing immediately.",
                ref_id=str(session.id),
                ref_type="live_session",
                priority="high",
            )
        except Exception:
            pass

    await manager.broadcast({
        "type": "mission_briefing_started",
        "mission_id": str(mission_id),
        "session_id": str(session.id),
        "room_id": room_id,
        "title": session.title,
    })
    return {"session_id": str(session.id), "room_id": room_id, "title": session.title, "notified": len(invited)}


@router.post("/{mission_id}/debrief/start", status_code=201)
async def start_mission_debrief_call(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    """Create a live debrief session and invite all assigned team members."""
    mission = await _get_mission_or_404(mission_id, db)

    room_id = str(uuid.uuid4()).replace("-", "")
    session = LiveSession(
        title=f"DEBRIEF: {mission.name}",
        host_id=current_user.id,
        room_id=room_id,
        mission_id=mission_id,
    )

    invited = await _collect_assigned_user_ids(mission, db)
    if hasattr(session, "invite_list"):
        session.invite_list = invited
    db.add(session)

    m = await db.get(Mission, mission_id)
    m.live_session_id = session.id
    await db.commit()
    await db.refresh(session)

    notif_svc = NotificationService(db)
    for uid_str in invited:
        try:
            await notif_svc.create_and_send(
                user_id=uuid.UUID(uid_str),
                type="mission_debrief",
                title=f"DEBRIEF CALL: {mission.name}",
                body="Join the live debrief session now.",
                ref_id=str(session.id),
                ref_type="live_session",
                priority="high",
            )
        except Exception:
            pass

    await manager.broadcast({
        "type": "mission_debrief_started",
        "mission_id": str(mission_id),
        "session_id": str(session.id),
        "room_id": room_id,
        "title": session.title,
    })
    return {"session_id": str(session.id), "room_id": room_id, "title": session.title, "notified": len(invited)}


# Keep legacy endpoint alias
@router.post("/{mission_id}/start-briefing", status_code=201)
async def start_briefing_legacy(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    return await start_mission_briefing(mission_id, current_user, db)


# ── Attendance (team leader marks) ────────────────────────────────────────────

@router.get("/{mission_id}/briefing/attendance")
async def get_attendance(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionBriefingAttendance).where(MissionBriefingAttendance.mission_id == mission_id)
    )
    records = result.scalars().all()
    out = []
    for rec in records:
        ur = await db.execute(select(User).where(User.id == rec.user_id))
        u = ur.scalar_one_or_none()
        out.append({
            "id": str(rec.id),
            "user_id": str(rec.user_id),
            "user_name": u.full_name or u.username if u else str(rec.user_id),
            "status": rec.status.value,
            "marked_by": str(rec.marked_by) if rec.marked_by else None,
            "marked_at": rec.marked_at.isoformat(),
        })
    return out


@router.put("/{mission_id}/briefing/attendance/{user_id}")
async def mark_attendance(
    mission_id: uuid.UUID,
    user_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    attendance_status = AttendanceStatus(body.get("status", "present"))
    result = await db.execute(
        select(MissionBriefingAttendance).where(
            MissionBriefingAttendance.mission_id == mission_id,
            MissionBriefingAttendance.user_id == user_id,
        )
    )
    rec = result.scalar_one_or_none()
    if rec:
        rec.status = attendance_status
        rec.marked_by = current_user.id
        rec.marked_at = datetime.utcnow()
    else:
        rec = MissionBriefingAttendance(
            id=uuid.uuid4(),
            mission_id=mission_id,
            user_id=user_id,
            status=attendance_status,
            marked_by=current_user.id,
            marked_at=datetime.utcnow(),
        )
        db.add(rec)
    await db.commit()
    return {"status": rec.status.value}


# Legacy self-attend endpoint (kept for backwards compat)
@router.post("/{mission_id}/briefing/attend", status_code=200)
async def attend_briefing_legacy(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Mission).where(Mission.id == mission_id))
    mission = result.scalar_one_or_none()
    if not mission:
        raise HTTPException(404, "Mission not found")
    attendees = list(getattr(mission, "briefing_attendees", None) or [])
    uid_str = str(current_user.id)
    if uid_str not in attendees:
        attendees.append(uid_str)
        mission.briefing_attendees = attendees
        await db.commit()
    return {"attended": True, "attendees": attendees}


@router.get("/{mission_id}/briefing/attendees")
async def get_briefing_attendees_legacy(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Mission).where(Mission.id == mission_id))
    mission = result.scalar_one_or_none()
    if not mission:
        raise HTTPException(404, "Mission not found")
    attendees = list(getattr(mission, "briefing_attendees", None) or [])
    out = []
    for uid_str in attendees:
        try:
            ur = await db.execute(select(User).where(User.id == uuid.UUID(uid_str)))
            u = ur.scalar_one_or_none()
            if u:
                out.append({"id": uid_str, "full_name": u.full_name, "username": u.username})
        except Exception:
            pass
    return out


# ── Objectives ────────────────────────────────────────────────────────────────

@router.post("/{mission_id}/objectives/{objective_id}/complete")
async def complete_objective(
    mission_id: uuid.UUID,
    objective_id: uuid.UUID,
    body: dict = Body(default={}),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionObjective).where(
            MissionObjective.id == objective_id,
            MissionObjective.mission_id == mission_id,
        )
    )
    obj = result.scalar_one_or_none()
    if not obj:
        raise HTTPException(404, "Objective not found")
    obj.is_completed = True
    obj.completed_by = current_user.id
    obj.completed_at = datetime.utcnow()
    obj.completed_lat = body.get("lat") or body.get("latitude")
    obj.completed_lng = body.get("lng") or body.get("longitude")
    await db.commit()

    # Find next uncompleted objective
    next_res = await db.execute(
        select(MissionObjective)
        .where(
            MissionObjective.mission_id == mission_id,
            MissionObjective.is_completed == False,
        )
        .order_by(MissionObjective.order_index)
        .limit(1)
    )
    next_obj = next_res.scalar_one_or_none()

    await manager.broadcast_to_room("events", {
        "type": "objective_completed",
        "mission_id": str(mission_id),
        "objective_id": str(objective_id),
        "completed_by": str(current_user.id),
        "next_objective": {
            "id": str(next_obj.id),
            "title": next_obj.title,
            "description": next_obj.description,
            "order_index": next_obj.order_index,
        } if next_obj else None,
    })

    # Push next objective directly to all assigned personnel
    if next_obj:
        mission_for_notify = await _get_mission_or_404(mission_id, db)
        user_ids = await _collect_assigned_user_ids(mission_for_notify, db)
        for uid in user_ids:
            await manager.send_to(uid, {
                "type": "objective_advanced",
                "mission_id": str(mission_id),
                "next_objective": {
                    "id": str(next_obj.id),
                    "title": next_obj.title,
                    "description": next_obj.description,
                    "order_index": next_obj.order_index,
                },
            })

    return {"ok": True, "completed_at": obj.completed_at.isoformat()}


# ── SITREPs (team leader only) ────────────────────────────────────────────────

@router.get("/{mission_id}/sitreps")
async def list_sitreps(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionSitrep)
        .where(MissionSitrep.mission_id == mission_id)
        .order_by(MissionSitrep.submitted_at.desc())
    )
    sitreps = result.scalars().all()
    return [
        {
            "id": str(s.id), "mission_id": str(s.mission_id),
            "submitted_by": str(s.submitted_by) if s.submitted_by else None,
            "team_status": s.team_status, "objective_progress": s.objective_progress,
            "conditions": s.conditions, "delays": s.delays, "risks": s.risks,
            "requests": s.requests, "submitted_at": s.submitted_at.isoformat(),
        }
        for s in sitreps
    ]


@router.post("/{mission_id}/sitreps", status_code=201)
async def submit_sitrep(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    sitrep = MissionSitrep(
        id=uuid.uuid4(),
        mission_id=mission_id,
        submitted_by=current_user.id,
        team_status=body.get("team_status"),
        objective_progress=body.get("objective_progress"),
        conditions=body.get("conditions"),
        delays=body.get("delays"),
        risks=body.get("risks"),
        requests=body.get("requests"),
        submitted_at=datetime.utcnow(),
    )
    db.add(sitrep)
    await db.commit()
    await db.refresh(sitrep)

    await manager.broadcast_to_room("events", {
        "type": "sitrep_submitted",
        "mission_id": str(mission_id),
        "submitted_by": current_user.full_name or current_user.username,
    })

    notif_svc = NotificationService(db)
    coordinators = await db.execute(select(User).where(User.role == UserRole.operations_coordinator))
    for coord in coordinators.scalars().all():
        await notif_svc.create_and_send(
            user_id=coord.id, type="sitrep", title="SITREP RECEIVED",
            body=f"From {current_user.full_name or current_user.username}",
            ref_id=str(mission_id), ref_type="mission", priority="medium",
        )

    return {"id": str(sitrep.id), "submitted_at": sitrep.submitted_at.isoformat()}


# ── Completion report (team leader submits → AWAITING_REVIEW) ─────────────────

@router.get("/{mission_id}/completion-report")
async def get_completion_report(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionCompletionReport)
        .where(MissionCompletionReport.mission_id == mission_id)
        .order_by(MissionCompletionReport.submitted_at.desc())
    )
    report = result.scalar_one_or_none()
    if not report:
        raise HTTPException(404, "No completion report submitted yet")
    return {
        "id": str(report.id),
        "mission_id": str(report.mission_id),
        "submitted_by": str(report.submitted_by) if report.submitted_by else None,
        "objective_summary": report.objective_summary,
        "personnel_status": report.personnel_status,
        "incident_summary": report.incident_summary,
        "evidence_summary": report.evidence_summary,
        "recommendations": report.recommendations,
        "review_decision": report.review_decision,
        "review_notes": report.review_notes,
        "reviewed_by": str(report.reviewed_by) if report.reviewed_by else None,
        "reviewed_at": report.reviewed_at.isoformat() if report.reviewed_at else None,
        "submitted_at": report.submitted_at.isoformat(),
    }


@router.post("/{mission_id}/completion-report", status_code=201)
async def submit_completion_report(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    if mission.status not in {MissionStatus.active, MissionStatus.extraction}:
        raise HTTPException(400, f"Cannot submit completion report from status: {mission.status.value}")

    report = MissionCompletionReport(
        id=uuid.uuid4(),
        mission_id=mission_id,
        submitted_by=current_user.id,
        objective_summary=body.get("objective_summary"),
        personnel_status=body.get("personnel_status"),
        incident_summary=body.get("incident_summary"),
        evidence_summary=body.get("evidence_summary"),
        recommendations=body.get("recommendations"),
        submitted_at=datetime.utcnow(),
    )
    db.add(report)

    m = await db.get(Mission, mission_id)
    m.status = MissionStatus.awaiting_review
    await db.commit()
    await db.refresh(report)

    notif_svc = NotificationService(db)
    coordinators = await db.execute(select(User).where(User.role == UserRole.operations_coordinator))
    for coord in coordinators.scalars().all():
        await notif_svc.create_and_send(
            user_id=coord.id, type="completion_report",
            title=f"MISSION COMPLETE: {mission.name}",
            body=f"Awaiting your review. Submitted by {current_user.full_name or current_user.username}",
            ref_id=str(mission_id), ref_type="mission", priority="high",
        )

    await manager.broadcast_to_room("events", {"type": "mission_awaiting_review", "mission_id": str(mission_id)})
    return {"id": str(report.id), "status": "awaiting_review"}


# ── Command review ────────────────────────────────────────────────────────────

@router.post("/{mission_id}/review")
async def review_mission(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    if mission.status != MissionStatus.awaiting_review:
        raise HTTPException(400, "Mission is not awaiting review")

    decision = body.get("decision")  # "complete" | "return"
    if decision not in {"complete", "return"}:
        raise HTTPException(400, "decision must be 'complete' or 'return'")

    result = await db.execute(
        select(MissionCompletionReport)
        .where(MissionCompletionReport.mission_id == mission_id)
        .order_by(MissionCompletionReport.submitted_at.desc())
    )
    report = result.scalar_one_or_none()
    if report:
        report.review_decision = decision
        report.review_notes = body.get("notes")
        report.reviewed_by = current_user.id
        report.reviewed_at = datetime.utcnow()

    m = await db.get(Mission, mission_id)
    if decision == "complete":
        m.status = MissionStatus.debrief
        await _notify_assigned(mission, db, f"MISSION UNDER DEBRIEF: {mission.name}", "Command has accepted the mission. Proceed to debrief.", "mission_debrief")
    else:
        m.status = MissionStatus.active
        await _notify_assigned(mission, db, f"MISSION RETURNED: {mission.name}", body.get("notes") or "Command returned mission for clarification.", "mission_returned")

    await db.commit()
    return {"decision": decision, "new_status": m.status.value}


# ── Debrief ───────────────────────────────────────────────────────────────────

@router.get("/{mission_id}/debrief")
async def get_debriefs(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionDebriefRecord)
        .where(MissionDebriefRecord.mission_id == mission_id)
        .order_by(MissionDebriefRecord.created_at.asc())
    )
    return [
        {
            "id": str(d.id), "mission_id": str(d.mission_id),
            "submitted_by": str(d.submitted_by) if d.submitted_by else None,
            "lessons_learned": d.lessons_learned, "incident_review": d.incident_review,
            "evidence_review": d.evidence_review, "team_feedback": d.team_feedback,
            "created_at": d.created_at.isoformat(),
        }
        for d in result.scalars().all()
    ]


@router.post("/{mission_id}/debrief", status_code=201)
async def submit_debrief(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    mission = await _get_mission_or_404(mission_id, db)
    if mission.status != MissionStatus.debrief:
        raise HTTPException(400, f"Mission is not in DEBRIEF status (current: {mission.status.value})")

    record = MissionDebriefRecord(
        id=uuid.uuid4(),
        mission_id=mission_id,
        submitted_by=current_user.id,
        lessons_learned=body.get("lessons_learned"),
        incident_review=body.get("incident_review"),
        evidence_review=body.get("evidence_review"),
        team_feedback=body.get("team_feedback"),
        created_at=datetime.utcnow(),
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)
    return {"id": str(record.id), "created_at": record.created_at.isoformat()}


# ── Notifications ─────────────────────────────────────────────────────────────

@router.post("/{mission_id}/notify")
async def notify_mission(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")

    audience = body.get("audience", getattr(mission, "briefing_audience", "all"))
    notif_svc = NotificationService(db)
    sent_count = 0

    for assignment in (mission.assignments or []):
        if assignment.team_id:
            q = select(TeamMember).where(TeamMember.team_id == assignment.team_id)
            if audience == "team_leaders_only":
                q = q.where(TeamMember.role_in_team == "leader")
            result = await db.execute(q)
            for tm in result.scalars().all():
                await notif_svc.create_and_send(
                    user_id=tm.user_id, type="mission_briefing",
                    title=f"MISSION BRIEFING: {mission.name}",
                    body=body.get("message") or mission.briefing_notes or "New mission briefing",
                    ref_id=str(mission_id), ref_type="mission", priority="high",
                )
                sent_count += 1
        elif assignment.user_id:
            await notif_svc.create_and_send(
                user_id=assignment.user_id, type="mission_briefing",
                title=f"MISSION BRIEFING: {mission.name}",
                body=body.get("message") or mission.briefing_notes or "New mission briefing",
                ref_id=str(mission_id), ref_type="mission", priority="high",
            )
            sent_count += 1

    await manager.broadcast({
        "type": "mission_notification",
        "mission_id": str(mission_id),
        "mission_name": mission.name,
        "message": body.get("message", "Mission briefing issued"),
    })
    return {"sent_to": sent_count}


# ── Incidents & Reports ───────────────────────────────────────────────────────

@router.get("/{mission_id}/incidents")
async def list_incidents(
    mission_id: uuid.UUID,
    category: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = select(MissionIncident).where(MissionIncident.mission_id == mission_id)
    if category:
        q = q.where(MissionIncident.report_category == ReportCategory(category))
    q = q.order_by(MissionIncident.created_at.desc())
    result = await db.execute(q)
    return [_incident_dict(i) for i in result.scalars().all()]


@router.post("/{mission_id}/incidents", status_code=201)
async def report_incident(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")

    raw_category = body.get("report_category", "incident")
    try:
        category = ReportCategory(raw_category)
    except ValueError:
        category = ReportCategory.incident

    incident = MissionIncident(
        mission_id=mission_id,
        reported_by=current_user.id,
        report_category=category,
        incident_type=body.get("incident_type", "patrol_report"),
        title=body.get("title", "Incident reported"),
        description=body.get("description"),
        severity=IncidentSeverity(body.get("severity", "medium")),
        latitude=body.get("latitude"),
        longitude=body.get("longitude"),
        contact_size=body.get("contact_size"),
        contact_activity=body.get("contact_activity"),
        contact_unit=body.get("contact_unit"),
        contact_equipment=body.get("contact_equipment"),
        ref_id=uuid.UUID(body["ref_id"]) if body.get("ref_id") else None,
        ref_type=body.get("ref_type"),
    )
    db.add(incident)
    await db.commit()
    await db.refresh(incident)

    data = _incident_dict(incident)
    await manager.broadcast({"type": "mission_incident", "mission_id": str(mission_id), "incident": data})

    if category == ReportCategory.contact:
        notif_svc = NotificationService(db)
        coordinators = await db.execute(select(User).where(User.role == UserRole.operations_coordinator))
        for coord in coordinators.scalars().all():
            await notif_svc.create_and_send(
                user_id=coord.id, type="contact_report",
                title=f"CONTACT REPORT: {mission.name}",
                body=f"Reported by {current_user.full_name or current_user.username}",
                ref_id=str(mission_id), ref_type="mission", priority="high",
            )
    return data


@router.patch("/{mission_id}/incidents/{incident_id}/resolve")
async def resolve_incident(
    mission_id: uuid.UUID,
    incident_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionIncident).where(
            MissionIncident.id == incident_id,
            MissionIncident.mission_id == mission_id,
        )
    )
    incident = result.scalar_one_or_none()
    if not incident:
        raise HTTPException(404, "Incident not found")
    incident.status = "resolved"
    await db.commit()
    return {"ok": True}


# ── Casualties ────────────────────────────────────────────────────────────────

@router.get("/{mission_id}/casualties")
async def list_casualties(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CasualtyReport)
        .where(CasualtyReport.mission_id == mission_id)
        .order_by(CasualtyReport.created_at.desc())
    )
    return [_casualty_dict(c) for c in result.scalars().all()]


@router.post("/{mission_id}/casualties", status_code=201)
async def report_casualty(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")

    report = CasualtyReport(
        mission_id=mission_id,
        reported_by=current_user.id,
        user_id=uuid.UUID(body["user_id"]) if body.get("user_id") else None,
        casualty_type=CasualtyType(body["casualty_type"]),
        notes=body.get("notes"),
        evidence_id=uuid.UUID(body["evidence_id"]) if body.get("evidence_id") else None,
        latitude=body.get("latitude"),
        longitude=body.get("longitude"),
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)

    data = _casualty_dict(report)
    await manager.broadcast({"type": "mission_casualty", "mission_id": str(mission_id), "report": data})

    notif_svc = NotificationService(db)
    coordinators = await db.execute(select(User).where(User.role == UserRole.operations_coordinator))
    for coord in coordinators.scalars().all():
        await notif_svc.create_and_send(
            user_id=coord.id, type="casualty_report",
            title=f"CASUALTY REPORT: {mission.name}",
            body=f"{body['casualty_type']} reported by {current_user.full_name or current_user.username}",
            ref_id=str(mission_id), ref_type="mission", priority="high",
        )
    return data


# ── Evidence ──────────────────────────────────────────────────────────────────

@router.get("/{mission_id}/evidence")
async def list_mission_evidence(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Evidence)
        .where(Evidence.mission_id == mission_id)
        .order_by(Evidence.created_at.desc())
    )
    return [
        {
            "id": str(e.id), "title": e.title, "description": e.description,
            "evidence_type": e.evidence_type.value,
            "file_url": e.file_url, "latitude": e.latitude, "longitude": e.longitude,
            "poi_id": str(e.poi_id) if e.poi_id else None,
            "approval_status": e.approval_status,
            "approved_by": str(e.approved_by) if e.approved_by else None,
            "approved_at": e.approved_at.isoformat() if e.approved_at else None,
            "created_by": str(e.created_by) if e.created_by else None,
            "created_at": e.created_at.isoformat(),
        }
        for e in result.scalars().all()
    ]


@router.patch("/{mission_id}/evidence/{evidence_id}/approve")
async def approve_evidence(
    mission_id: uuid.UUID,
    evidence_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Evidence).where(Evidence.id == evidence_id, Evidence.mission_id == mission_id)
    )
    ev = result.scalar_one_or_none()
    if not ev:
        raise HTTPException(404, "Evidence not found")
    ev.approval_status = "approved" if body.get("action") == "approve" else "rejected"
    ev.approved_by = current_user.id
    ev.approved_at = datetime.utcnow()
    await db.commit()
    return {"approval_status": ev.approval_status}


# ── Mission data package ──────────────────────────────────────────────────────

@router.get("/{mission_id}/package")
async def download_package(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")

    incidents_r = await db.execute(select(MissionIncident).where(MissionIncident.mission_id == mission_id))
    casualties_r = await db.execute(select(CasualtyReport).where(CasualtyReport.mission_id == mission_id))
    evidence_r = await db.execute(select(Evidence).where(Evidence.mission_id == mission_id))
    sitreps_r = await db.execute(select(MissionSitrep).where(MissionSitrep.mission_id == mission_id))

    package = {
        "mission": _mission_dict(mission),
        "incidents": [_incident_dict(i) for i in incidents_r.scalars().all()],
        "casualties": [_casualty_dict(c) for c in casualties_r.scalars().all()],
        "sitreps": [
            {
                "id": str(s.id), "team_status": s.team_status,
                "objective_progress": s.objective_progress, "submitted_at": s.submitted_at.isoformat(),
            }
            for s in sitreps_r.scalars().all()
        ],
        "evidence": [
            {
                "id": str(e.id), "title": e.title, "description": e.description,
                "type": e.evidence_type.value,
                "file_url": e.file_url, "latitude": e.latitude, "longitude": e.longitude,
                "poi_id": str(e.poi_id) if e.poi_id else None,
                "approval_status": e.approval_status, "created_at": e.created_at.isoformat(),
            }
            for e in evidence_r.scalars().all()
        ],
        "exported_at": datetime.utcnow().isoformat(),
        "exported_by": str(current_user.id),
    }

    return JSONResponse(
        content=package,
        headers={"Content-Disposition": f'attachment; filename="mission_{mission_id}.json"'},
    )
