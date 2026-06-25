import uuid
import json
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User, UserDevice
from app.services.notification_service import NotificationService
from app.services.vapid_service import get_public_key, load_vapid_keys

# Pre-load VAPID keys at import time so they're ready
load_vapid_keys()

router = APIRouter(prefix="/notifications", tags=["Notifications"])


def _notif_dict(n) -> dict:
    return {
        "id": str(n.id),
        "user_id": str(n.user_id),
        "type": n.type,
        "title": n.title,
        "body": n.body,
        "ref_id": n.ref_id,
        "ref_type": n.ref_type,
        "is_read": n.is_read,
        "priority": n.priority,
        "created_at": n.created_at.isoformat(),
    }


@router.get("")
async def list_notifications(
    unread_only: bool = False,
    limit: int = 50,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = NotificationService(db)
    notifications = await svc.list_for_user(current_user.id, unread_only=unread_only, limit=limit)
    return [_notif_dict(n) for n in notifications]


@router.get("/unread-count")
async def unread_count(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = NotificationService(db)
    count = await svc.unread_count(current_user.id)
    return {"count": count}


@router.put("/{notification_id}/read")
async def mark_read(
    notification_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = NotificationService(db)
    if not await svc.mark_read(notification_id, current_user.id):
        raise HTTPException(404, "Notification not found")
    return {"ok": True}


@router.put("/read-all")
async def mark_all_read(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = NotificationService(db)
    await svc.mark_all_read(current_user.id)
    return {"ok": True}


# ── Web Push (VAPID) ──────────────────────────────────────────────────────────

@router.get("/vapid-public-key")
async def vapid_public_key():
    key = get_public_key()
    if not key:
        raise HTTPException(503, "Web push not configured")
    return {"public_key": key}


class WebPushSubscriptionBody(BaseModel):
    endpoint: str
    keys: dict  # {p256dh: str, auth: str}
    expirationTime: float | None = None


@router.post("/web-subscribe")
async def web_subscribe(
    body: WebPushSubscriptionBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub_json = json.dumps({"endpoint": body.endpoint, "keys": body.keys})
    # Upsert by endpoint — one row per browser subscription
    res = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == current_user.id,
            UserDevice.platform == "web",
            UserDevice.device_token == body.endpoint,
        )
    )
    device = res.scalar_one_or_none()
    if device:
        device.is_active = True
        # Store full subscription JSON as a second field we track via device_name
        if hasattr(device, "device_name"):
            device.device_name = sub_json
    else:
        device = UserDevice(
            user_id=current_user.id,
            device_token=body.endpoint,
            platform="web",
            is_active=True,
        )
        if hasattr(device, "device_name"):
            device.device_name = sub_json
        db.add(device)

    # Store full subscription alongside token using extra column if exists
    # Fallback: store endpoint as token; subscription JSON as name (relies on model having device_name)
    await db.commit()
    return {"subscribed": True}


@router.delete("/web-unsubscribe")
async def web_unsubscribe(
    endpoint: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == current_user.id,
            UserDevice.platform == "web",
            UserDevice.device_token == endpoint,
        )
    )
    device = res.scalar_one_or_none()
    if device:
        device.is_active = False
        await db.commit()
    return {"unsubscribed": True}
