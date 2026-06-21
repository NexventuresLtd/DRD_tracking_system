# app/api/v1/teams.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import Optional, List
from uuid import UUID

from app.database import get_db
from app.models.team import Team, TeamMember
from app.models.user import User
from app.schemas.team import (
    TeamCreate, TeamUpdate, TeamResponse,
    TeamMemberCreate, TeamMemberResponse
)
from app.middleware.auth import get_current_user, require_commander

router = APIRouter(prefix="/teams", tags=["Teams"])

@router.get("/", response_model=List[TeamResponse])
async def list_teams(
    is_active: Optional[bool] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List all teams"""
    query = select(Team)
    
    if is_active is not None:
        query = query.where(Team.is_active == is_active)
    
    query = query.order_by(Team.name)
    
    result = await db.execute(query)
    teams = result.scalars().all()
    
    response = []
    for team in teams:
        # Count members
        member_count_result = await db.execute(
            select(func.count(TeamMember.id)).where(
                TeamMember.team_id == team.id,
                TeamMember.is_active == True,
            )
        )
        member_count = member_count_result.scalar()
        
        # Get members
        members_result = await db.execute(
            select(TeamMember, User).join(User).where(
                TeamMember.team_id == team.id,
                TeamMember.is_active == True,
            )
        )
        members = []
        for tm, user in members_result:
            members.append(TeamMemberResponse(
                id=tm.id,
                user_id=tm.user_id,
                user_name=user.full_name or user.username,
                role=tm.role,
                joined_at=tm.joined_at,
                is_active=tm.is_active,
            ))
        
        response.append(TeamResponse(
            id=team.id,
            name=team.name,
            code=team.code,
            color=team.color,
            description=team.description,
            lead_id=team.lead_id,
            is_active=team.is_active,
            created_at=team.created_at,
            updated_at=team.updated_at,
            members=members,
            member_count=member_count,
        ))
    
    return response

@router.post("/", response_model=TeamResponse, status_code=status.HTTP_201_CREATED)
async def create_team(
    data: TeamCreate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Create a new team"""
    # Check if name exists
    result = await db.execute(select(Team).where(Team.name == data.name))
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Team name already exists"
        )
    
    # Check if code exists
    result = await db.execute(select(Team).where(Team.code == data.code))
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Team code already exists"
        )
    
    team = Team(
        name=data.name,
        code=data.code,
        color=data.color or "#3b82f6",
        description=data.description,
        lead_id=data.lead_id,
    )
    
    db.add(team)
    await db.commit()
    await db.refresh(team)
    
    return TeamResponse(
        id=team.id,
        name=team.name,
        code=team.code,
        color=team.color,
        description=team.description,
        lead_id=team.lead_id,
        is_active=team.is_active,
        created_at=team.created_at,
        updated_at=team.updated_at,
        members=[],
        member_count=0,
    )

@router.get("/{team_id}", response_model=TeamResponse)
async def get_team(
    team_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get team details"""
    result = await db.execute(select(Team).where(Team.id == team_id))
    team = result.scalar_one_or_none()
    
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found"
        )
    
    # Count members
    member_count_result = await db.execute(
        select(func.count(TeamMember.id)).where(
            TeamMember.team_id == team.id,
            TeamMember.is_active == True,
        )
    )
    member_count = member_count_result.scalar()
    
    # Get members
    members_result = await db.execute(
        select(TeamMember, User).join(User).where(
            TeamMember.team_id == team.id,
            TeamMember.is_active == True,
        )
    )
    members = []
    for tm, user in members_result:
        members.append(TeamMemberResponse(
            id=tm.id,
            user_id=tm.user_id,
            user_name=user.full_name or user.username,
            role=tm.role,
            joined_at=tm.joined_at,
            is_active=tm.is_active,
        ))
    
    return TeamResponse(
        id=team.id,
        name=team.name,
        code=team.code,
        color=team.color,
        description=team.description,
        lead_id=team.lead_id,
        is_active=team.is_active,
        created_at=team.created_at,
        updated_at=team.updated_at,
        members=members,
        member_count=member_count,
    )

@router.put("/{team_id}", response_model=TeamResponse)
async def update_team(
    team_id: UUID,
    data: TeamUpdate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Update team"""
    result = await db.execute(select(Team).where(Team.id == team_id))
    team = result.scalar_one_or_none()
    
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found"
        )
    
    if data.name is not None:
        team.name = data.name
    if data.color is not None:
        team.color = data.color
    if data.description is not None:
        team.description = data.description
    if data.lead_id is not None:
        team.lead_id = data.lead_id
    if data.is_active is not None:
        team.is_active = data.is_active
    
    await db.commit()
    await db.refresh(team)
    
    return TeamResponse(
        id=team.id,
        name=team.name,
        code=team.code,
        color=team.color,
        description=team.description,
        lead_id=team.lead_id,
        is_active=team.is_active,
        created_at=team.created_at,
        updated_at=team.updated_at,
        members=[],
        member_count=0,
    )

@router.post("/{team_id}/members", status_code=status.HTTP_201_CREATED)
async def add_team_member(
    team_id: UUID,
    data: TeamMemberCreate,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Add member to team"""
    # Check team exists
    team_result = await db.execute(select(Team).where(Team.id == team_id))
    if not team_result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found"
        )
    
    # Check user exists
    user_result = await db.execute(select(User).where(User.id == data.user_id))
    if not user_result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Check if already member
    existing = await db.execute(
        select(TeamMember).where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == data.user_id,
        )
    )
    existing_member = existing.scalar_one_or_none()
    
    if existing_member:
        if existing_member.is_active:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="User is already a member of this team"
            )
        else:
            # Reactivate
            existing_member.is_active = True
            existing_member.role = data.role
            await db.commit()
            return {"message": "Team member reactivated"}
    
    # Enforce one lead per team: demote previous lead before assigning new one
    if data.role == "lead":
        prev_leads = await db.execute(
            select(TeamMember).where(
                TeamMember.team_id == team_id,
                TeamMember.role == "lead",
                TeamMember.is_active == True,
            )
        )
        for prev in prev_leads.scalars().all():
            prev.role = "support"
        # Update the Team.lead_id
        team_obj = (await db.execute(select(Team).where(Team.id == team_id))).scalar_one_or_none()
        if team_obj:
            team_obj.lead_id = data.user_id

    team_member = TeamMember(
        team_id=team_id,
        user_id=data.user_id,
        role=data.role,
    )

    db.add(team_member)
    await db.commit()

    return {"message": "Member added to team"}

@router.delete("/{team_id}/members/{user_id}")
async def remove_team_member(
    team_id: UUID,
    user_id: UUID,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Remove member from team"""
    result = await db.execute(
        select(TeamMember).where(
            TeamMember.team_id == team_id,
            TeamMember.user_id == user_id,
            TeamMember.is_active == True,
        )
    )
    member = result.scalar_one_or_none()
    
    if not member:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team member not found"
        )
    
    member.is_active = False
    await db.commit()

    return {"message": "Member removed from team"}

@router.put("/{team_id}/set-lead/{user_id}")
async def set_team_lead(
    team_id: UUID,
    user_id: UUID,
    current_user: User = Depends(require_commander),
    db: AsyncSession = Depends(get_db)
):
    """Set a new team lead (demotes the previous lead)"""
    team = (await db.execute(select(Team).where(Team.id == team_id))).scalar_one_or_none()
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    target = (await db.execute(
        select(TeamMember).where(TeamMember.team_id == team_id, TeamMember.user_id == user_id, TeamMember.is_active == True)
    )).scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="User is not a member of this team")

    # Demote all current leads
    prev_leads = await db.execute(
        select(TeamMember).where(TeamMember.team_id == team_id, TeamMember.role == "lead", TeamMember.is_active == True)
    )
    for prev in prev_leads.scalars().all():
        prev.role = "support"

    target.role = "lead"
    team.lead_id = user_id
    await db.commit()

    return {"message": "Team lead updated"}