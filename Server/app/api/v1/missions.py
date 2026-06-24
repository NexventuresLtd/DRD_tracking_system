import uuid
import json
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user, require_planning_or_above, require_leader_or_above, require_coordinator
from app.models.user import User
from app.models.team import TeamMember, Team
from app.models.mission import Mission, MissionIncident, CasualtyReport
from app.models.evidence import Evidence
from app.models.live_session import LiveSession
from app.services.mission_service import MissionService
from app.services.notification_service import NotificationService
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
        "briefing_datetime": m.briefing_datetime.isoformat() if getattr(m, "briefing_datetime", None) else None,
        "briefing_audience": getattr(m, "briefing_audience", "all"),
        "zone_ids": getattr(m, "zone_ids", []) or [],
        "route_ids": getattr(m, "route_ids", []) or [],
        "facility_ids": getattr(m, "facility_ids", []) or [],
        "live_session_id": str(m.live_session_id) if getattr(m, "live_session_id", None) else None,
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


def _incident_dict(i) -> dict:
    return {
        "id": str(i.id),
        "mission_id": str(i.mission_id),
        "reported_by": str(i.reported_by) if i.reported_by else None,
        "incident_type": i.incident_type,
        "title": i.title,
        "description": i.description,
        "severity": i.severity.value if i.severity else "medium",
        "latitude": i.latitude,
        "longitude": i.longitude,
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
                    user_id=tm.user_id,
                    type="mission_briefing",
                    title=f"MISSION BRIEFING: {mission.name}",
                    body=body.get("message") or mission.briefing_notes or "New mission briefing",
                    ref_id=str(mission_id),
                    ref_type="mission",
                    priority="high",
                )
                sent_count += 1
        elif assignment.user_id:
            await notif_svc.create_and_send(
                user_id=assignment.user_id,
                type="mission_briefing",
                title=f"MISSION BRIEFING: {mission.name}",
                body=body.get("message") or mission.briefing_notes or "New mission briefing",
                ref_id=str(mission_id),
                ref_type="mission",
                priority="high",
            )
            sent_count += 1

    await manager.broadcast({
        "type": "mission_notification",
        "mission_id": str(mission_id),
        "mission_name": mission.name,
        "message": body.get("message", "Mission briefing issued"),
    })
    return {"sent_to": sent_count}


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


@router.post("/{mission_id}/start-briefing", status_code=201)
async def start_mission_briefing(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_planning_or_above),
    db: AsyncSession = Depends(get_db),
):
    """Create an internal live session for the mission briefing and notify all assigned personnel."""
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")

    room_id = str(uuid.uuid4()).replace("-", "")
    session = LiveSession(
        title=f"BRIEFING: {mission.name}",
        host_id=current_user.id,
        room_id=room_id,
        mission_id=mission_id,
    )

    # Collect all assigned user IDs for invite list
    invited: list[str] = []
    for assignment in (mission.assignments or []):
        if assignment.team_id:
            q = select(TeamMember).where(TeamMember.team_id == assignment.team_id)
            audience = getattr(mission, "briefing_audience", "all")
            if audience == "team_leaders_only":
                q = q.where(TeamMember.role_in_team == "leader")
            res = await db.execute(q)
            for tm in res.scalars().all():
                uid = str(tm.user_id)
                if uid not in invited:
                    invited.append(uid)
        elif assignment.user_id:
            uid = str(assignment.user_id)
            if uid not in invited:
                invited.append(uid)

    if hasattr(session, "invite_list"):
        session.invite_list = invited
    db.add(session)

    # Link session to mission
    result = await db.execute(select(Mission).where(Mission.id == mission_id))
    m = result.scalar_one_or_none()
    if m:
        m.live_session_id = session.id

    await db.commit()
    await db.refresh(session)

    # Notify all invited users
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

    return {
        "session_id": str(session.id),
        "room_id": room_id,
        "title": session.title,
        "notified": len(invited),
    }


# ── Incidents ────────────────────────────────────────────────────────────────

@router.get("/{mission_id}/incidents")
async def list_incidents(
    mission_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionIncident)
        .where(MissionIncident.mission_id == mission_id)
        .order_by(MissionIncident.created_at.desc())
    )
    return [_incident_dict(i) for i in result.scalars().all()]


@router.post("/{mission_id}/incidents", status_code=201)
async def report_incident(
    mission_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models.mission import IncidentSeverity
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")

    incident = MissionIncident(
        mission_id=mission_id,
        reported_by=current_user.id,
        incident_type=body.get("incident_type", "patrol_report"),
        title=body.get("title", "Incident reported"),
        description=body.get("description"),
        severity=IncidentSeverity(body.get("severity", "medium")),
        latitude=body.get("latitude"),
        longitude=body.get("longitude"),
        ref_id=uuid.UUID(body["ref_id"]) if body.get("ref_id") else None,
        ref_type=body.get("ref_type"),
    )
    db.add(incident)
    await db.commit()
    await db.refresh(incident)

    data = _incident_dict(incident)
    await manager.broadcast({"type": "mission_incident", "mission_id": str(mission_id), "incident": data})
    return data


@router.patch("/{mission_id}/incidents/{incident_id}/resolve")
async def resolve_incident(
    mission_id: uuid.UUID,
    incident_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(MissionIncident).where(MissionIncident.id == incident_id, MissionIncident.mission_id == mission_id)
    )
    incident = result.scalar_one_or_none()
    if not incident:
        raise HTTPException(404, "Incident not found")
    incident.status = "resolved"
    await db.commit()
    return {"ok": True}


# ── Casualties ───────────────────────────────────────────────────────────────

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
    from app.models.mission import CasualtyType
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

    # Notify coordinators
    notif_svc = NotificationService(db)
    from app.models.user import User as UserModel, UserRole
    coordinators = await db.execute(
        select(UserModel).where(UserModel.role == UserRole.operations_coordinator)
    )
    for coord in coordinators.scalars().all():
        await notif_svc.create_and_send(
            user_id=coord.id,
            type="casualty_report",
            title=f"CASUALTY REPORT: {mission.name}",
            body=f"{body['casualty_type']} reported by {current_user.full_name or current_user.username}",
            ref_id=str(mission_id),
            ref_type="mission",
            priority="high",
        )

    return data


# ── Evidence approval ────────────────────────────────────────────────────────

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
    evs = result.scalars().all()
    return [
        {
            "id": str(e.id), "title": e.title, "evidence_type": e.evidence_type.value,
            "file_url": e.file_url, "latitude": e.latitude, "longitude": e.longitude,
            "approval_status": e.approval_status, "approved_by": str(e.approved_by) if e.approved_by else None,
            "approved_at": e.approved_at.isoformat() if e.approved_at else None,
            "created_by": str(e.created_by) if e.created_by else None,
            "created_at": e.created_at.isoformat(),
        }
        for e in evs
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
    action = body.get("action", "approve")
    ev.approval_status = "approved" if action == "approve" else "rejected"
    ev.approved_by = current_user.id
    ev.approved_at = datetime.utcnow()
    await db.commit()

    # Check if all mission evidence is approved → auto-complete mission
    all_ev_result = await db.execute(
        select(Evidence).where(Evidence.mission_id == mission_id)
    )
    all_ev = all_ev_result.scalars().all()
    if all_ev and all(e.approval_status == "approved" for e in all_ev):
        m_result = await db.execute(select(Mission).where(Mission.id == mission_id))
        m = m_result.scalar_one_or_none()
        if m and m.status.value == "active":
            from app.models.mission import MissionStatus
            m.status = MissionStatus.completed
            await db.commit()
            await manager.broadcast({"type": "mission_completed", "mission_id": str(mission_id)})

    return {"approval_status": ev.approval_status}


# ── Package download ─────────────────────────────────────────────────────────

@router.get("/{mission_id}/package")
async def download_package(
    mission_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    """Return all mission data as a single JSON package."""
    svc = MissionService(db)
    mission = await svc.get_by_id(mission_id)
    if not mission:
        raise HTTPException(404, "Mission not found")

    incidents_r = await db.execute(
        select(MissionIncident).where(MissionIncident.mission_id == mission_id)
    )
    casualties_r = await db.execute(
        select(CasualtyReport).where(CasualtyReport.mission_id == mission_id)
    )
    evidence_r = await db.execute(
        select(Evidence).where(Evidence.mission_id == mission_id)
    )

    package = {
        "mission": _mission_dict(mission),
        "incidents": [_incident_dict(i) for i in incidents_r.scalars().all()],
        "casualties": [_casualty_dict(c) for c in casualties_r.scalars().all()],
        "evidence": [
            {
                "id": str(e.id), "title": e.title, "type": e.evidence_type.value,
                "file_url": e.file_url, "latitude": e.latitude, "longitude": e.longitude,
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
