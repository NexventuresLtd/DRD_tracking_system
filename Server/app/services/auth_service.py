import uuid
import secrets
from datetime import datetime, timedelta
from typing import Optional
from jose import jwt
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.models.user import User, UserRole, UserSession
from app.models.invite import Invite, InviteType

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(user_id: str, role: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode(
        {"sub": user_id, "role": role, "type": "access", "exp": expire},
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )


def create_refresh_token(user_id: str) -> str:
    expire = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    token = secrets.token_urlsafe(64)
    return token, expire


def create_password_reset_token(user_id: str) -> str:
    expire = datetime.utcnow() + timedelta(hours=2)
    return jwt.encode(
        {"sub": user_id, "type": "reset", "exp": expire},
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )


def verify_reset_token(token: str) -> Optional[str]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("type") != "reset":
            return None
        return payload.get("sub")
    except Exception:
        return None


class AuthService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_user_by_email(self, email: str) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.email == email.lower()))
        return result.scalar_one_or_none()

    async def get_user_by_username(self, username: str) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.username == username.lower()))
        return result.scalar_one_or_none()

    async def get_invite(self, code: str) -> Optional[Invite]:
        result = await self.db.execute(
            select(Invite).where(
                Invite.code == code,
                Invite.is_active == True,
            )
        )
        return result.scalar_one_or_none()

    async def validate_invite(self, code: str) -> Optional[Invite]:
        invite = await self.get_invite(code)
        if not invite:
            return None
        if invite.expires_at and invite.expires_at < datetime.utcnow():
            return None
        if invite.use_count >= invite.max_uses:
            return None
        return invite

    async def register(
        self,
        email: str,
        username: str,
        full_name: str,
        password: str,
        phone: Optional[str] = None,
        role: UserRole = UserRole.field_user,
        invite_code: Optional[str] = None,
    ) -> User:
        assigned_role = role

        if invite_code:
            invite = await self.validate_invite(invite_code)
            if invite:
                assigned_role = invite.assigned_role

        user = User(
            email=email.lower(),
            username=username.lower(),
            full_name=full_name,
            hashed_password=hash_password(password),
            phone=phone,
            role=assigned_role,
            is_verified=True,
        )
        self.db.add(user)
        await self.db.flush()

        if invite_code:
            invite = await self.validate_invite(invite_code)
            if invite:
                invite.use_count += 1
                invite.used_by = user.id
                invite.used_at = datetime.utcnow()
                if invite.use_count >= invite.max_uses:
                    invite.is_active = False

        await self.db.commit()
        await self.db.refresh(user)
        return user

    async def login(
        self,
        email: str,
        password: str,
        device_id: Optional[str] = None,
        device_name: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> Optional[tuple[User, str, str]]:
        identifier = email.lower().strip()
        user = await self.get_user_by_email(identifier)
        if not user:
            user = await self.get_user_by_username(identifier)
        if not user or not verify_password(password, user.hashed_password):
            return None
        if not user.is_active:
            return None

        access_token = create_access_token(str(user.id), user.role.value)
        refresh_token_str, expires_at = create_refresh_token(str(user.id))

        session = UserSession(
            user_id=user.id,
            refresh_token=refresh_token_str,
            device_id=device_id,
            device_name=device_name,
            ip_address=ip_address,
            expires_at=expires_at,
        )
        self.db.add(session)
        user.last_seen = datetime.utcnow()
        await self.db.commit()

        return user, access_token, refresh_token_str

    async def refresh(self, refresh_token: str) -> Optional[tuple[str, str]]:
        result = await self.db.execute(
            select(UserSession).where(
                UserSession.refresh_token == refresh_token,
                UserSession.is_active == True,
            )
        )
        session = result.scalar_one_or_none()
        if not session or session.expires_at < datetime.utcnow():
            if session:
                session.is_active = False
                await self.db.commit()
            return None

        user_result = await self.db.execute(select(User).where(User.id == session.user_id, User.is_active == True))
        user = user_result.scalar_one_or_none()
        if not user:
            return None

        new_access = create_access_token(str(user.id), user.role.value)
        new_refresh, new_expires = create_refresh_token(str(user.id))

        session.refresh_token = new_refresh
        session.expires_at = new_expires
        await self.db.commit()

        return new_access, new_refresh

    async def logout(self, refresh_token: str) -> bool:
        result = await self.db.execute(
            select(UserSession).where(UserSession.refresh_token == refresh_token)
        )
        session = result.scalar_one_or_none()
        if session:
            session.is_active = False
            await self.db.commit()
            return True
        return False

    async def logout_all(self, user_id: uuid.UUID) -> None:
        result = await self.db.execute(
            select(UserSession).where(UserSession.user_id == user_id, UserSession.is_active == True)
        )
        sessions = result.scalars().all()
        for s in sessions:
            s.is_active = False
        await self.db.commit()
