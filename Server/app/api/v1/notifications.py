import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.services.notification_service import NotificationService

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
