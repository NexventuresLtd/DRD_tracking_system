import secrets
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional, List
from uuid import UUID

from app.database import get_db
from app.models.invite import InviteToken
from app.models.team import Team, TeamMember
from app.middleware.auth import require_operator, get_current_user
from app.models.user import User, UserRole

router = APIRouter(prefix="/invites", tags=["invites"])

_EXPIRY = {"1h": timedelta(hours=1), "24h": timedelta(hours=24), "7d": timedelta(days=7)}


class InviteCreate(BaseModel):
    team_id: Optional[UUID] = None
    role: str = "field_unit"
    team_member_role: str = "member"   # team role: lead, member, medic, scout, sniper, support
    expiry: str = "24h"
    label: Optional[str] = None


class InviteInfo(BaseModel):
    token: str
    team_id: Optional[UUID]
    team_name: Optional[str]
    role: str
    team_member_role: str = "member"
    expires_at: datetime
    label: Optional[str]
    join_count: int = 0
    is_expired: bool = False
    created_at: Optional[datetime] = None


@router.post("/", response_model=InviteInfo, status_code=status.HTTP_201_CREATED)
async def create_invite(
    data: InviteCreate,
    current_user: User = Depends(require_operator),
    db: AsyncSession = Depends(get_db),
):
    delta = _EXPIRY.get(data.expiry, timedelta(hours=24))
    expires_at = datetime.now(timezone.utc) + delta
    token = secrets.token_urlsafe(12)

    team_name = None
    if data.team_id:
        res = await db.execute(select(Team).where(Team.id == data.team_id))
        team = res.scalar_one_or_none()
        if team:
            team_name = team.name

    invite = InviteToken(
        token=token,
        created_by=current_user.id,
        team_id=data.team_id,
        role=data.role,
        team_member_role=data.team_member_role,
        expires_at=expires_at,
        label=data.label,
        join_count="0",
    )
    db.add(invite)
    await db.commit()
    await db.refresh(invite)

    return InviteInfo(
        token=token,
        team_id=data.team_id,
        team_name=team_name,
        role=data.role,
        team_member_role=data.team_member_role,
        expires_at=expires_at,
        label=data.label,
        join_count=0,
        is_expired=False,
        created_at=invite.created_at,
    )


@router.get("/", response_model=List[InviteInfo])
async def list_invites(
    current_user: User = Depends(require_operator),
    db: AsyncSession = Depends(get_db),
):
    """List all invites — operator and above."""
    res = await db.execute(select(InviteToken).order_by(InviteToken.created_at.desc()))
    invites = res.scalars().all()

    now = datetime.now(timezone.utc)
    result = []
    for inv in invites:
        team_name = None
        if inv.team_id:
            tr = await db.execute(select(Team).where(Team.id == inv.team_id))
            team = tr.scalar_one_or_none()
            if team:
                team_name = team.name
        result.append(InviteInfo(
            token=inv.token,
            team_id=inv.team_id,
            team_name=team_name,
            role=inv.role,
            team_member_role=inv.team_member_role or "member",
            expires_at=inv.expires_at,
            label=inv.label,
            join_count=int(inv.join_count or 0),
            is_expired=inv.expires_at < now,
            created_at=inv.created_at,
        ))
    return result


@router.delete("/{token}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_invite(
    token: str,
    current_user: User = Depends(require_operator),
    db: AsyncSession = Depends(get_db),
):
    """Revoke (delete) an invite token."""
    res = await db.execute(select(InviteToken).where(InviteToken.token == token))
    invite = res.scalar_one_or_none()
    if not invite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invite not found")
    await db.delete(invite)
    await db.commit()


@router.get("/{token}", response_model=InviteInfo)
async def validate_invite(token: str, db: AsyncSession = Depends(get_db)):
    """Validate invite token — public, no auth."""
    res = await db.execute(select(InviteToken).where(InviteToken.token == token))
    invite = res.scalar_one_or_none()

    if not invite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invite not found")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=status.HTTP_410_GONE, detail="Invite expired")

    team_name = None
    if invite.team_id:
        res2 = await db.execute(select(Team).where(Team.id == invite.team_id))
        team = res2.scalar_one_or_none()
        if team:
            team_name = team.name

    return InviteInfo(
        token=invite.token,
        team_id=invite.team_id,
        team_name=team_name,
        role=invite.role,
        team_member_role=invite.team_member_role or "member",
        expires_at=invite.expires_at,
        label=invite.label,
        join_count=int(invite.join_count or 0),
        is_expired=False,
        created_at=invite.created_at,
    )


@router.post("/{token}/join")
async def join_via_invite(
    token: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Consume an invite — assigns caller to team, updates role. Multi-use until expiry."""
    res = await db.execute(select(InviteToken).where(InviteToken.token == token))
    invite = res.scalar_one_or_none()

    if not invite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invite not found")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=status.HTTP_410_GONE, detail="Invite expired")

    # Update user system role
    try:
        current_user.role = UserRole(invite.role)
    except ValueError:
        pass

    # Assign to team
    team_name = None
    if invite.team_id:
        existing = await db.execute(
            select(TeamMember).where(
                TeamMember.user_id == current_user.id,
                TeamMember.team_id == invite.team_id,
            )
        )
        member = existing.scalar_one_or_none()
        tmr = invite.team_member_role or "member"

        if tmr == "lead":
            # Demote any existing lead first
            prev_lead = await db.execute(
                select(TeamMember).where(
                    TeamMember.team_id == invite.team_id,
                    TeamMember.role == "lead",
                    TeamMember.is_active == True,
                )
            )
            for pl in prev_lead.scalars().all():
                pl.role = "member"

        if member:
            member.is_active = True
            member.role = tmr
        else:
            db.add(TeamMember(
                team_id=invite.team_id,
                user_id=current_user.id,
                role=tmr,
            ))

        tr = await db.execute(select(Team).where(Team.id == invite.team_id))
        team = tr.scalar_one_or_none()
        if team:
            team_name = team.name

    # Track usage (multi-use — no single-use block)
    invite.join_count = str(int(invite.join_count or 0) + 1)
    invite.used_at = datetime.now(timezone.utc)
    await db.commit()

    return {
        "message": "Joined successfully",
        "team_id": str(invite.team_id) if invite.team_id else None,
        "team_name": team_name,
        "role": current_user.role.value,
        "team_member_role": invite.team_member_role or "member",
    }
