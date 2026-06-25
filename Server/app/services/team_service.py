import uuid
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload

from app.models.team import Team, TeamMember
from app.models.user import User
from app.schemas.team import TeamCreate, TeamUpdate, AddMemberRequest


class TeamService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, data: TeamCreate, created_by: uuid.UUID) -> Team:
        team = Team(
            name=data.name,
            description=data.description,
            color=data.color or "#3b82f6",
            icon=data.icon,
            leader_id=created_by,
        )
        self.db.add(team)
        await self.db.commit()
        await self.db.refresh(team)
        return team

    async def get_by_id(self, team_id: uuid.UUID) -> Optional[Team]:
        result = await self.db.execute(
            select(Team)
            .options(selectinload(Team.members).selectinload(TeamMember.user))
            .where(Team.id == team_id, Team.is_active == True)
        )
        return result.scalar_one_or_none()

    async def list_teams(self, user_id: Optional[uuid.UUID] = None):
        query = select(Team).where(Team.is_active == True)
        if user_id is not None:
            query = query.join(TeamMember, TeamMember.team_id == Team.id).where(
                TeamMember.user_id == user_id
            )
        result = await self.db.execute(query)
        return result.scalars().all()

    async def update(self, team: Team, data: TeamUpdate) -> Team:
        update_dict = data.model_dump(exclude_none=True)
        for key, value in update_dict.items():
            setattr(team, key, value)
        await self.db.commit()
        await self.db.refresh(team)
        return team

    async def delete(self, team: Team) -> None:
        team.is_active = False
        await self.db.commit()

    async def add_member(self, team_id: uuid.UUID, user_id: uuid.UUID, role_in_team: str = "member") -> TeamMember:
        existing = await self.db.execute(
            select(TeamMember).where(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        )
        if existing.scalar_one_or_none():
            raise ValueError("User is already a member of this team")

        member = TeamMember(team_id=team_id, user_id=user_id, role_in_team=role_in_team)
        self.db.add(member)
        await self.db.commit()
        await self.db.refresh(member)
        return member

    async def update_member_role(self, team_id: uuid.UUID, user_id: uuid.UUID, role_in_team: str) -> Optional[TeamMember]:
        result = await self.db.execute(
            select(TeamMember).where(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        )
        member = result.scalar_one_or_none()
        if not member:
            return None
        member.role_in_team = role_in_team
        await self.db.commit()
        # Re-fetch with user loaded since refresh doesn't reload relationships
        updated = await self.db.execute(
            select(TeamMember)
            .options(selectinload(TeamMember.user))
            .where(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        )
        return updated.scalar_one_or_none()

    async def remove_member(self, team_id: uuid.UUID, user_id: uuid.UUID) -> bool:
        result = await self.db.execute(
            select(TeamMember).where(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        )
        member = result.scalar_one_or_none()
        if not member:
            return False
        await self.db.delete(member)
        await self.db.commit()
        return True

    async def get_members(self, team_id: uuid.UUID) -> list[TeamMember]:
        result = await self.db.execute(
            select(TeamMember)
            .options(selectinload(TeamMember.user))
            .where(TeamMember.team_id == team_id)
        )
        return result.scalars().all()

    async def get_member_count(self, team_id: uuid.UUID) -> int:
        result = await self.db.execute(
            select(func.count(TeamMember.id)).where(TeamMember.team_id == team_id)
        )
        return result.scalar() or 0

    async def is_member(self, team_id: uuid.UUID, user_id: uuid.UUID) -> bool:
        result = await self.db.execute(
            select(TeamMember).where(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        )
        return result.scalar_one_or_none() is not None
