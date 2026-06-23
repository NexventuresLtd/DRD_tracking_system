import uuid
import os
import aiofiles
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from fastapi import UploadFile

from app.config import settings
from app.models.user import User, UserRole
from app.schemas.user import UserUpdate, UserRoleUpdate


class UserService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, user_id: uuid.UUID) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    async def list_users(self, page: int = 1, page_size: int = 50, search: Optional[str] = None):
        query = select(User).where(User.is_active == True)
        count_query = select(func.count(User.id)).where(User.is_active == True)

        if search:
            search_term = f"%{search}%"
            from sqlalchemy import or_
            query = query.where(or_(User.username.ilike(search_term), User.full_name.ilike(search_term), User.email.ilike(search_term)))
            count_query = count_query.where(or_(User.username.ilike(search_term), User.full_name.ilike(search_term), User.email.ilike(search_term)))

        total = (await self.db.execute(count_query)).scalar()
        result = await self.db.execute(query.offset((page - 1) * page_size).limit(page_size))
        return result.scalars().all(), total

    async def update(self, user: User, data: UserUpdate) -> User:
        update_dict = data.model_dump(exclude_none=True)
        for key, value in update_dict.items():
            setattr(user, key, value)
        await self.db.commit()
        await self.db.refresh(user)
        return user

    async def update_role(self, user: User, data: UserRoleUpdate) -> User:
        user.role = data.role
        await self.db.commit()
        await self.db.refresh(user)
        return user

    async def upload_avatar(self, user: User, file: UploadFile) -> str:
        ext = os.path.splitext(file.filename or "avatar.jpg")[1].lower()
        filename = f"avatars/{user.id}{ext}"
        filepath = os.path.join(settings.UPLOAD_DIR, filename)
        os.makedirs(os.path.dirname(filepath), exist_ok=True)

        async with aiofiles.open(filepath, "wb") as f:
            content = await file.read()
            await f.write(content)

        avatar_url = f"/uploads/{filename}"
        user.avatar_url = avatar_url
        await self.db.commit()
        return avatar_url

    async def deactivate(self, user: User) -> User:
        user.is_active = False
        await self.db.commit()
        return user

    async def get_online_users(self):
        from datetime import datetime, timedelta
        from app.models.location import Location, LocationStatus
        result = await self.db.execute(
            select(User).join(Location, Location.user_id == User.id)
            .where(Location.status == LocationStatus.active)
        )
        return result.scalars().all()
