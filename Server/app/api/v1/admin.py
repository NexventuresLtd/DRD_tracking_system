import secrets
import uuid
from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from pydantic import BaseModel, EmailStr

from app.database import get_db
from app.middleware.auth import require_coordinator
from app.models.user import User, UserRole
from app.models.invite import Invite, InviteType
from app.models.audit import AuditLog
from app.models.team import Team, TeamMember
from app.models.location import Location, LocationStatus
from app.schemas.user import UserResponse, UserListResponse
from app.schemas.invite import InviteCreate, InviteResponse
from app.services.user_service import UserService
from app.services.auth_service import hash_password
import qrcode
import io
import base64


class CreateUserRequest(BaseModel):
    email: EmailStr
    username: str
    full_name: str
    password: str
    role: UserRole = UserRole.field_user
    phone: Optional[str] = None


class UpdateRoleRequest(BaseModel):
    role: UserRole


class UpdateUserRequest(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    role: Optional[UserRole] = None
    is_active: Optional[bool] = None

router = APIRouter(prefix="/admin", tags=["Admin"])


@router.get("/users", response_model=UserListResponse)
async def admin_list_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    search: Optional[str] = None,
    role: Optional[str] = None,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    svc = UserService(db)
    users, total = await svc.list_users(page=page, page_size=page_size, search=search)
    return {"users": users, "total": total, "page": page, "page_size": page_size}


@router.post("/users", response_model=UserResponse, status_code=201)
async def admin_create_user(
    data: CreateUserRequest,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    if (await db.execute(select(User).where(User.email == data.email.lower()))).scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")
    if (await db.execute(select(User).where(User.username == data.username.lower()))).scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Username already taken")
    user = User(
        email=data.email.lower(),
        username=data.username.lower(),
        full_name=data.full_name,
        hashed_password=hash_password(data.password),
        role=data.role,
        phone=data.phone,
        is_active=True,
        is_verified=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.patch("/users/{user_id}", response_model=UserResponse)
async def admin_update_user(
    user_id: uuid.UUID,
    data: UpdateUserRequest,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if data.full_name is not None:
        user.full_name = data.full_name
    if data.phone is not None:
        user.phone = data.phone
    if data.role is not None:
        user.role = data.role
    if data.is_active is not None:
        user.is_active = data.is_active
    await db.commit()
    await db.refresh(user)
    return user


@router.delete("/users/{user_id}")
async def admin_delete_user(
    user_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    await db.delete(user)
    await db.commit()
    return {"message": "User deleted"}


@router.post("/users/{user_id}/reset-password")
async def admin_reset_password(
    user_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    new_password = body.get("new_password", "")
    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")
    user.hashed_password = hash_password(new_password)
    await db.commit()
    return {"message": "Password reset successfully"}


@router.get("/stats")
async def get_stats(
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    total_users = (await db.execute(select(func.count(User.id)).where(User.is_active == True))).scalar()
    total_teams = (await db.execute(select(func.count(Team.id)).where(Team.is_active == True))).scalar()
    active_users = (await db.execute(select(func.count(Location.id)).where(Location.status == LocationStatus.active))).scalar()
    total_invites = (await db.execute(select(func.count(Invite.id)).where(Invite.is_active == True))).scalar()

    role_counts = {}
    for role in UserRole:
        count = (await db.execute(select(func.count(User.id)).where(User.role == role, User.is_active == True))).scalar()
        role_counts[role.value] = count

    return {
        "total_users": total_users,
        "total_teams": total_teams,
        "active_users_now": active_users,
        "active_invites": total_invites,
        "users_by_role": role_counts,
    }


@router.post("/invites", response_model=InviteResponse, status_code=201)
async def create_invite(
    data: InviteCreate,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    code = secrets.token_urlsafe(16).upper()
    expires_at = None
    if data.expires_in_hours:
        expires_at = datetime.utcnow() + timedelta(hours=data.expires_in_hours)

    invite = Invite(
        code=code,
        invite_type=data.invite_type,
        assigned_role=data.assigned_role,
        created_by=current_user.id,
        max_uses=data.max_uses,
        expires_at=expires_at,
        note=data.note,
    )
    db.add(invite)
    await db.commit()
    await db.refresh(invite)
    return invite


@router.get("/invites", response_model=list[InviteResponse])
async def list_invites(
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Invite).order_by(Invite.created_at.desc()))
    return result.scalars().all()


@router.delete("/invites/{invite_id}")
async def revoke_invite(
    invite_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Invite).where(Invite.id == invite_id))
    invite = result.scalar_one_or_none()
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found")
    invite.is_active = False
    await db.commit()
    return {"message": "Invite revoked"}


@router.get("/invites/{invite_id}/qr")
async def get_invite_qr(
    invite_id: uuid.UUID,
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Invite).where(Invite.id == invite_id))
    invite = result.scalar_one_or_none()
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found")

    qr = qrcode.make(invite.code)
    buffer = io.BytesIO()
    qr.save(buffer, format="PNG")
    buffer.seek(0)
    qr_b64 = base64.b64encode(buffer.getvalue()).decode()

    return {
        "code": invite.code,
        "qr_image_base64": f"data:image/png;base64,{qr_b64}",
        "role": invite.assigned_role.value,
        "expires_at": invite.expires_at.isoformat() if invite.expires_at else None,
    }


@router.get("/audit-logs")
async def get_audit_logs(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    current_user: User = Depends(require_coordinator),
    db: AsyncSession = Depends(get_db),
):
    total = (await db.execute(select(func.count(AuditLog.id)))).scalar()
    result = await db.execute(
        select(AuditLog)
        .order_by(AuditLog.timestamp.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    logs = result.scalars().all()
    return {
        "logs": [
            {
                "id": str(log.id),
                "user_id": str(log.user_id) if log.user_id else None,
                "action": log.action,
                "entity_type": log.entity_type,
                "entity_id": log.entity_id,
                "path": log.path,
                "method": log.method,
                "status_code": log.status_code,
                "ip_address": log.ip_address,
                "timestamp": log.timestamp.isoformat(),
            }
            for log in logs
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
    }
