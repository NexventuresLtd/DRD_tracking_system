import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user, require_coordinator, require_leader_or_above
from app.models.user import User
from app.schemas.team import TeamCreate, TeamUpdate, TeamResponse, TeamDetailResponse, AddMemberRequest, TeamMemberResponse
from app.services.team_service import TeamService

router = APIRouter(prefix="/teams", tags=["Teams"])


@router.get("", response_model=list[TeamResponse])
async def list_teams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = TeamService(db)
    teams = await svc.list_teams()
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
        member = await svc.add_member(team_id, data.user_id, data.role_in_team or "member")
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


@router.get("/{team_id}/locations")
async def get_team_locations(
    team_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import select
    from app.models.team import TeamMember
    from app.models.location import Location
    from app.models.user import User as UserModel

    members = await db.execute(select(TeamMember).where(TeamMember.team_id == team_id))
    member_ids = [m.user_id for m in members.scalars().all()]

    locations = await db.execute(
        select(Location, UserModel)
        .join(UserModel, Location.user_id == UserModel.id)
        .where(Location.user_id.in_(member_ids))
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
