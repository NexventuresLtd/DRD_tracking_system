# app/services/auth_service.py
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from uuid import UUID
from datetime import datetime, timezone
import time
import uuid as _uuid

from app.models.user import User, UserRole
from app.models.team import Team, TeamMember
from app.models.event import Event
from app.models.invite import InviteToken
from app.websocket.manager import manager
import asyncio
from app.schemas.auth import UserRegister, UserLogin
from app.utils.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
    decode_token,
)
from app.utils.validators import validate_email, validate_password_strength
from app.services.email_service import EmailService

# In-memory OTP store: session_id -> {otp, user_id, expires_at}
_otp_store: dict[str, dict] = {}
_OTP_TTL = 600  # 10 minutes

def _cleanup_otp_store():
    now = time.time()
    expired = [k for k, v in _otp_store.items() if v["expires_at"] < now]
    for k in expired:
        del _otp_store[k]

def _mask_email(email: str) -> str:
    parts = email.split("@")
    if len(parts) != 2:
        return email
    local, domain = parts
    masked = local[:2] + "***" if len(local) > 2 else "***"
    return f"{masked}@{domain}"

class AuthService:
    """Authentication service"""
    
    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def register_user(self, data: UserRegister) -> User:
        """Register a new user"""
        # Validate email
        if not validate_email(data.email):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid email format"
            )
        
        # Validate password
        is_valid, error_msg = validate_password_strength(data.password)
        if not is_valid:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_msg
            )
        
        # Check if email exists
        result = await self.db.execute(
            select(User).where(User.email == data.email)
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered"
            )
        
        # Check if username exists
        result = await self.db.execute(
            select(User).where(User.username == data.username)
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Username already taken"
            )
        
        # Resolve invite token — overrides role and captures team assignment
        invite: InviteToken | None = None
        team_id_from_invite = None
        if data.invite_token:
            inv_result = await self.db.execute(
                select(InviteToken).where(InviteToken.token == data.invite_token)
            )
            invite = inv_result.scalar_one_or_none()
            if not invite:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid invite token")
            if invite.used_at is not None:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invite already used")
            if invite.expires_at < datetime.now(timezone.utc):
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invite expired")
            data.role = invite.role
            team_id_from_invite = invite.team_id

        # Validate role
        if data.role not in [r.value for r in UserRole]:
            data.role = UserRole.FIELD_UNIT.value

        # Create user
        user = User(
            email=data.email,
            username=data.username,
            hashed_password=hash_password(data.password),
            full_name=data.full_name,
            phone=data.phone,
            role=UserRole(data.role),
        )

        self.db.add(user)
        await self.db.commit()
        await self.db.refresh(user)

        # Auto-assign team if invite specified one
        if team_id_from_invite:
            member = TeamMember(
                team_id=team_id_from_invite,
                user_id=user.id,
                role="member",
            )
            self.db.add(member)

        # Mark invite as consumed
        if invite:
            invite.used_at = datetime.now(timezone.utc)

        if team_id_from_invite or invite:
            await self.db.commit()

        return user
    
    async def login(self, data: UserLogin) -> dict:
        """Validate credentials, send OTP, return pending-OTP session."""
        result = await self.db.execute(
            select(User).where(
                (User.username == data.username) |
                (User.email == data.username)
            )
        )
        user = result.scalar_one_or_none()

        if not user or not verify_password(data.password, user.hashed_password):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

        if not user.is_active:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is disabled")

        _cleanup_otp_store()
        otp = EmailService.generate_otp()
        session_id = str(_uuid.uuid4())
        _otp_store[session_id] = {
            "otp": otp,
            "user_id": str(user.id),
            "expires_at": time.time() + _OTP_TTL,
        }

        # Fire-and-forget email — don't block login on SMTP failure
        asyncio.create_task(
            EmailService.send_otp_email(user.email, otp, user.full_name or user.username)
        )

        return {
            "status": "otp_required",
            "session_id": session_id,
            "email_hint": _mask_email(user.email),
            "message": "A verification code has been sent to your email.",
        }

    async def verify_otp(self, session_id: str, otp: str) -> dict:
        """Verify OTP (or universal bypass 555555) and return tokens."""
        _cleanup_otp_store()
        session = _otp_store.get(session_id)
        if not session:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired session")
        if time.time() > session["expires_at"]:
            _otp_store.pop(session_id, None)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Verification code expired")
        if otp != "555555" and otp != session["otp"]:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid verification code")

        _otp_store.pop(session_id, None)

        user_id = session["user_id"]
        result = await self.db.execute(select(User).where(User.id == UUID(user_id)))
        user = result.scalar_one_or_none()
        if not user or not user.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or disabled")

        # Audit event
        user.last_login = datetime.now(timezone.utc)
        login_event = Event(
            event_type="LOGIN",
            user_id=user.id,
            description=f"{user.full_name or user.username} logged in",
            severity="low",
            event_metadata={"role": user.role.value, "username": user.username},
        )
        self.db.add(login_event)
        await self.db.commit()
        await self.db.refresh(login_event)
        try:
            event_data = {
                "id": str(login_event.id),
                "event_type": "LOGIN",
                "user_id": str(user.id),
                "description": login_event.description,
                "severity": "low",
                "created_at": login_event.created_at.isoformat() if login_event.created_at else None,
                "event_metadata": login_event.event_metadata,
            }
            try:
                asyncio.create_task(manager.broadcast_event(event_data))
            except Exception:
                asyncio.get_event_loop().create_task(manager.broadcast_event(event_data))
        except Exception:
            pass

        token_data = {"sub": str(user.id), "role": user.role.value, "username": user.username}
        access_token  = create_access_token(token_data)
        refresh_token = create_refresh_token(token_data)

        tm_result = await self.db.execute(
            select(TeamMember, Team)
            .join(Team, TeamMember.team_id == Team.id)
            .where(TeamMember.user_id == user.id, TeamMember.is_active == True)
            .limit(1)
        )
        tm_row = tm_result.first()

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": 1800,
            "user": {
                "id": str(user.id),
                "email": user.email,
                "username": user.username,
                "full_name": user.full_name,
                "role": user.role.value,
                "team_id": str(tm_row[0].team_id) if tm_row else None,
                "team_name": tm_row[1].name if tm_row else None,
                "team_role": tm_row[0].role if tm_row else None,
            },
        }
    
    async def refresh_token(self, refresh_token: str) -> dict:
        """Refresh access token"""
        payload = verify_refresh_token(refresh_token)
        if not payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid refresh token"
            )
        
        user_id = payload.get("sub")
        result = await self.db.execute(
            select(User).where(User.id == UUID(user_id))
        )
        user = result.scalar_one_or_none()
        
        if not user or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found or disabled"
            )
        
        # Generate new tokens
        token_data = {
            "sub": str(user.id),
            "role": user.role.value,
            "username": user.username,
        }
        
        new_access_token = create_access_token(token_data)
        new_refresh_token = create_refresh_token(token_data)

        tm_result = await self.db.execute(
            select(TeamMember, Team)
            .join(Team, TeamMember.team_id == Team.id)
            .where(TeamMember.user_id == user.id, TeamMember.is_active == True)
            .limit(1)
        )
        tm_row = tm_result.first()

        return {
            "access_token": new_access_token,
            "refresh_token": new_refresh_token,
            "token_type": "bearer",
            "expires_in": 1800,
            "user": {
                "id": str(user.id),
                "email": user.email,
                "username": user.username,
                "full_name": user.full_name,
                "role": user.role.value,
                "team_id": str(tm_row[0].team_id) if tm_row else None,
                "team_name": tm_row[1].name if tm_row else None,
                "team_role": tm_row[0].role if tm_row else None,
            },
        }
    
    async def change_password(
        self,
        user: User,
        old_password: str,
        new_password: str
    ) -> bool:
        """Change user password"""
        if not verify_password(old_password, user.hashed_password):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Current password is incorrect"
            )
        
        is_valid, error_msg = validate_password_strength(new_password)
        if not is_valid:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_msg
            )
        
        user.hashed_password = hash_password(new_password)
        await self.db.commit()
        
        return True