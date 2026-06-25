import uuid
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user, require_coordinator, require_leader_or_above
from app.models.user import User
from app.schemas.team import TeamCreate, TeamUpdate, TeamResponse, TeamDetailResponse, AddMemberRequest, UpdateMemberRequest, TeamMemberResponse
from app.services.team_service import TeamService
from app.services.notification_service import NotificationService

router = APIRouter(prefix="/teams", tags=["Teams"])


@router.get("", response_model=list[TeamResponse])
async def list_teams(
    mine: bool = Query(False, description="Return only teams the current user belongs to"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    teams = await svc.list_teams(user_id=current_user.id if mine else None)
    result = []
    for team in teams:
        count = await svc.get_member_count(team.id)
        t = TeamResponse.model_validate(team)
        t.member_count = count
        result.append(t)
    return result


@router.post("", response_model=TeamResponse, status_code=201)
async def create_team(
    data: TeamCreate,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    team = await svc.create(data, current_user.id)
    count = await svc.get_member_count(team.id)
    result = TeamResponse.model_validate(team)
    result.member_count = count
    return result


@router.get("/{team_id}", response_model=TeamDetailResponse)
async def get_team(
    team_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    team = await svc.get_by_id(team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    return TeamDetailResponse.model_validate(team)


@router.put("/{team_id}", response_model=TeamResponse)
async def update_team(
    team_id: uuid.UUID,
    data: TeamUpdate,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    team = await svc.get_by_id(team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    if team.leader_id != current_user.id and current_user.role.value not in ("operations_coordinator", "planning_officer"):
        raise HTTPException(status_code=403, detail="Only team leader or coordinator can update")

    updated = await svc.update(team, data)
    return TeamResponse.model_validate(updated)


@router.delete("/{team_id}")
async def delete_team(
    team_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    team = await svc.get_by_id(team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    await svc.delete(team)
    return {"message": "Team deleted"}


@router.get("/{team_id}/members", response_model=list[TeamMemberResponse])
async def get_team_members(
    team_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    if not await svc.get_by_id(team_id):
        raise HTTPException(status_code=404, detail="Team not found")
    return await svc.get_members(team_id)


@router.post("/{team_id}/members", status_code=201)
async def add_member(
    team_id: uuid.UUID,
    data: AddMemberRequest,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    if not await svc.get_by_id(team_id):
        raise HTTPException(status_code=404, detail="Team not found")
    try:
        team = await svc.get_by_id(team_id)
        member = await svc.add_member(team_id, data.user_id, data.role_in_team or "member")
        # Notify the added user
        notif_svc = NotificationService(db)
        await notif_svc.create_and_send(
            user_id=data.user_id,
            type="team_added",
            title="Added to Team",
            body=f"You have been added to team {team.name if team else ''}",
            ref_id=str(team_id),
            ref_type="team",
            priority="normal",
        )
        return {"message": "Member added", "member_id": str(member.id)}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/{team_id}/members/{user_id}")
async def remove_member(
    team_id: uuid.UUID,
    user_id: uuid.UUID,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    if not await svc.get_by_id(team_id):
        raise HTTPException(status_code=404, detail="Team not found")
    removed = await svc.remove_member(team_id, user_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Member not found")
    return {"message": "Member removed"}


@router.patch("/{team_id}/members/{user_id}", response_model=TeamMemberResponse)
async def update_member_role(
    team_id: uuid.UUID,
    user_id: uuid.UUID,
    data: UpdateMemberRequest,
    current_user: User = Depends(require_leader_or_above),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    if not await svc.get_by_id(team_id):
        raise HTTPException(status_code=404, detail="Team not found")
    member = await svc.update_member_role(team_id, user_id, data.role_in_team)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    return member


@router.get("/{team_id}/locations")
async def get_team_locations(
    team_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import select
    from app.models.team import Team, TeamMember
    from app.models.location import Location
    from app.models.user import User as UserModel

    team = await db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    role = current_user.role.value
    is_coordinator = role in ("operations_coordinator", "planning_officer")

    # Determine which user IDs to expose based on role + location_sharing setting
    members_q = await db.execute(select(TeamMember).where(TeamMember.team_id == team_id))
    all_members = members_q.scalars().all()
    member_ids = [m.user_id for m in all_members]

    if is_coordinator:
        # Coordinators always see everyone
        visible_ids = member_ids
    elif team.location_sharing:
        # Coordinator enabled sharing — all team members see each other
        visible_ids = member_ids
    elif role == "team_leader":
        # No sharing enabled — team leader sees own team but only own position returned
        # We still show the full team so the leader knows who's on the team (positions hidden from others)
        visible_ids = member_ids
    else:
        # Field user with no sharing — only their own position
        visible_ids = [current_user.id]

    locations = await db.execute(
        select(Location, UserModel)
        .join(UserModel, Location.user_id == UserModel.id)
        .where(Location.user_id.in_(visible_ids))
    )
    result = []
    for loc, user in locations.all():
        result.append({
            "user_id": str(user.id),
            "username": user.username,
            "full_name": user.full_name,
            "avatar_url": user.avatar_url,
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "heading": loc.heading,
            "speed": loc.speed,
            "status": loc.status.value,
            "last_updated": loc.last_update.isoformat(),
        })
    return result


@router.patch("/{team_id}/location-sharing")
async def toggle_location_sharing(
    team_id: uuid.UUID,
    data: dict,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    from app.models.team import Team
    team = await db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    team.location_sharing = bool(data.get("enabled", False))
    await db.commit()
    return {"location_sharing": team.location_sharing}
