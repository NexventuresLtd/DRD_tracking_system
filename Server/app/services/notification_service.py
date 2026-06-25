import uuid
import logging
from typing import Optional
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification
from app.websocket.manager import manager

log = logging.getLogger(__name__)


async def _send_fcm(tokens: list[str], title: str, body: str, data: dict) -> None:
    """Fire-and-forget FCM push via Legacy HTTP API."""
    from app.config import settings
    if not settings.FCM_SERVER_KEY or not tokens:
        return
    try:
        import httpx
        payload = {
            "registration_ids": tokens,
            "notification": {"title": title, "body": body, "sound": "default"},
            "data": data,
            "priority": "high",
        }
        async with httpx.AsyncClient(timeout=8.0) as client:
            await client.post(
                "https://fcm.googleapis.com/fcm/send",
                json=payload,
                headers={
                    "Authorization": f"key={settings.FCM_SERVER_KEY}",
                    "Content-Type": "application/json",
                },
            )
    except Exception as exc:
        log.warning("FCM send failed: %s", exc)


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

        ws_payload = {
            "type": "notification",
            "notification_id": str(notif.id),
            "notif_type": type,
            "title": title,
            "body": body,
            "ref_id": ref_id,
            "ref_type": ref_type,
            "priority": priority,
        }
        await manager.send_to(str(user_id), ws_payload)

        # Push via FCM (mobile) and Web Push (browser) when app/tab is closed
        from app.models.user import UserDevice
        import json as _json
        result = await self.db.execute(
            select(UserDevice).where(
                UserDevice.user_id == user_id,
                UserDevice.is_active == True,
            )
        )
        devices = result.scalars().all()
        fcm_tokens = [d.device_token for d in devices if d.device_token and d.platform in ("ios", "android")]
        web_subs = [d for d in devices if d.platform == "web" and d.device_token]

        if fcm_tokens:
            await _send_fcm(
                fcm_tokens,
                title=title,
                body=body or "",
                data={k: str(v) for k, v in ws_payload.items() if v is not None},
            )

        if web_subs:
            from app.services.vapid_service import send_web_push
            push_payload = {"title": title, "body": body or "", "type": type, "ref_id": ref_id}
            for dev in web_subs:
                try:
                    # device_name stores full subscription JSON; device_token is just the endpoint
                    sub_json = getattr(dev, "device_name", None)
                    if sub_json:
                        sub = _json.loads(sub_json)
                    else:
                        # Minimal subscription from endpoint only — won't work without keys, skip
                        continue
                    await send_web_push(sub, push_payload)
                except Exception:
                    pass

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
