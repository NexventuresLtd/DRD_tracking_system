import uuid
from typing import Optional
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification
from app.websocket.manager import manager


class NotificationService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_and_send(
        self,
        user_id: uuid.UUID,
        type: str,
        title: str,
        body: Optional[str] = None,
        ref_id: Optional[str] = None,
        ref_type: Optional[str] = None,
        priority: str = "normal",
    ) -> Notification:
        notif = Notification(
            user_id=user_id,
            type=type,
            title=title,
            body=body,
            ref_id=ref_id,
            ref_type=ref_type,
            priority=priority,
        )
        self.db.add(notif)
        await self.db.commit()
        await self.db.refresh(notif)

        await manager.send_to(str(user_id), {
            "type": "notification",
            "notification_id": str(notif.id),
            "notif_type": type,
            "title": title,
            "body": body,
            "ref_id": ref_id,
            "ref_type": ref_type,
            "priority": priority,
        })
        return notif

    async def list_for_user(self, user_id: uuid.UUID, unread_only: bool = False, limit: int = 50):
        q = select(Notification).where(Notification.user_id == user_id)
        if unread_only:
            q = q.where(Notification.is_read == False)
        q = q.order_by(Notification.created_at.desc()).limit(limit)
        result = await self.db.execute(q)
        return result.scalars().all()

    async def mark_read(self, notification_id: uuid.UUID, user_id: uuid.UUID) -> bool:
        result = await self.db.execute(
            select(Notification).where(
                Notification.id == notification_id,
                Notification.user_id == user_id,
            )
        )
        notif = result.scalar_one_or_none()
        if not notif:
            return False
        notif.is_read = True
        await self.db.commit()
        return True

    async def mark_all_read(self, user_id: uuid.UUID):
        await self.db.execute(
            update(Notification)
            .where(Notification.user_id == user_id, Notification.is_read == False)
            .values(is_read=True)
        )
        await self.db.commit()

    async def unread_count(self, user_id: uuid.UUID) -> int:
        result = await self.db.execute(
            select(Notification).where(Notification.user_id == user_id, Notification.is_read == False)
        )
        return len(result.scalars().all())
