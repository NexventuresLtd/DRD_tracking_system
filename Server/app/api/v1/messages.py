import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, not_, exists
from pydantic import BaseModel, model_validator
from datetime import datetime

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.message import Message, MessageRead, MessageChannel, MessageType
from app.models.team import Team, TeamMember
from app.websocket.manager import manager

router = APIRouter(prefix="/messages", tags=["Messages"])


def _msg_dict(m: Message, sender: Optional[User] = None) -> dict:
    return {
        "id": str(m.id),
        "channel_type": m.channel_type.value,
        "channel_id": m.channel_id,
        "sender_id": str(m.sender_id),
        "sender": {
            "id": str(sender.id),
            "full_name": sender.full_name or sender.username,
            "username": sender.username,
            "avatar_url": sender.avatar_url,
        } if sender else None,
        "content": m.content,
        "message_type": m.message_type.value,
        "sent_at": m.created_at.isoformat(),
        "created_at": m.created_at.isoformat(),
    }


def _parse_channel(channel: str, current_user_id: Optional[str] = None):
    """Parse a channel string like 'global', 'team:UUID', 'team/UUID', 'dm:UUID' etc."""
    channel = channel.strip()
    if channel == "global":
        return MessageChannel.global_chat, "global"
    if channel == "emergency":
        return MessageChannel.emergency, "emergency"
    # Accept both 'team:UUID' and 'team/UUID' (mobile vs web)
    for sep in (":", "/"):
        if channel.startswith(f"team{sep}"):
            team_id = channel[len(f"team{sep}"):]
            return MessageChannel.team, team_id
        if channel.startswith(f"dm{sep}"):
            other_id = channel[len(f"dm{sep}"):]
            # DM channel key is sorted pair of user IDs
            if current_user_id:
                key = "_".join(sorted([current_user_id, other_id]))
            else:
                key = other_id
            return MessageChannel.dm, key
    return MessageChannel.global_chat, "global"


class MessageCreate(BaseModel):
    # Accept either the proper channel_type or the shorthand 'channel' string
    channel_type: Optional[MessageChannel] = None
    channel: Optional[str] = None
    channel_id: Optional[str] = None
    content: str
    message_type: MessageType = MessageType.text
    reply_to_id: Optional[uuid.UUID] = None

    @model_validator(mode="after")
    def resolve_channel(self):
        if self.channel and not self.channel_type:
            ct, cid = _parse_channel(self.channel)
            self.channel_type = ct
            if not self.channel_id:
                self.channel_id = cid
        if not self.channel_type:
            self.channel_type = MessageChannel.global_chat
        return self


async def _fetch_messages(db: AsyncSession, channel_type: MessageChannel, channel_id: str, limit: int = 50):
    result = await db.execute(
        select(Message, User)
        .join(User, Message.sender_id == User.id, isouter=True)
        .where(Message.channel_type == channel_type, Message.channel_id == channel_id, Message.is_deleted == False)
        .order_by(Message.created_at.asc())
        .limit(limit)
    )
    return result.all()


# ── List channels ─────────────────────────────────────────────────────────────

@router.get("/channels")
async def list_channels(current_user: User = Depends(get_current_user)):
    return [
        {"type": "global", "id": "global", "name": "Global Channel"},
        {"type": "emergency", "id": "emergency", "name": "Emergency Channel"},
    ]


# ── GET endpoints matching both web format (path) and mobile format (colon) ──

@router.get("/channels/global")
async def get_global_via_channels(
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    msgs = await _fetch_messages(db, MessageChannel.global_chat, "global", limit)
    return [_msg_dict(m, sender) for m, sender in msgs]


@router.get("/channels/team/{team_id}")
async def get_team_via_channels(
    team_id: str,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    msgs = await _fetch_messages(db, MessageChannel.team, team_id, limit)
    return [_msg_dict(m, sender) for m, sender in msgs]


@router.get("/channels/dm/{other_user_id}")
async def get_dm_via_channels(
    other_user_id: str,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    channel_key = "_".join(sorted([str(current_user.id), other_user_id]))
    msgs = await _fetch_messages(db, MessageChannel.dm, channel_key, limit)
    return [_msg_dict(m, sender) for m, sender in msgs]


@router.get("/channels-meta")
async def get_channels_meta(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return metadata (last message, unread count) for all channels the current user can access."""
    user_id = current_user.id
    user_id_str = str(user_id)
    channels = []

    async def _last_message_for(channel_type: MessageChannel, channel_id: str) -> Optional[dict]:
        """Fetch the most recent message in a channel with sender name."""
        res = await db.execute(
            select(Message, User)
            .join(User, Message.sender_id == User.id, isouter=True)
            .where(
                Message.channel_type == channel_type,
                Message.channel_id == channel_id,
                Message.is_deleted == False,
            )
            .order_by(Message.created_at.desc())
            .limit(1)
        )
        row = res.first()
        if not row:
            return None
        msg, sender = row
        return {
            "content": msg.content,
            "sender_name": (sender.full_name or sender.username) if sender else "Unknown",
            "sent_at": msg.created_at.isoformat(),
        }

    async def _unread_count_for(channel_type: MessageChannel, channel_id: str) -> int:
        """Count unread messages (no MessageRead row for this user) in the last 100 messages."""
        subq = (
            select(Message.id)
            .where(
                Message.channel_type == channel_type,
                Message.channel_id == channel_id,
                Message.is_deleted == False,
            )
            .order_by(Message.created_at.desc())
            .limit(100)
            .subquery()
        )
        read_subq = (
            select(MessageRead.message_id)
            .where(
                MessageRead.user_id == user_id,
                MessageRead.message_id == subq.c.id,
            )
            .correlate(subq)
        )
        res = await db.execute(
            select(func.count())
            .select_from(subq)
            .where(not_(exists(read_subq)))
        )
        return res.scalar() or 0

    is_coordinator = current_user.role.value == "operations_coordinator"

    # 1. Global channel
    channels.append({
        "type": "global",
        "id": "global",
        "name": "Global Channel",
        "last_message": await _last_message_for(MessageChannel.global_chat, "global"),
        "unread_count": await _unread_count_for(MessageChannel.global_chat, "global"),
    })

    # 2. Emergency channel — visible to all, prominently for coordinator
    channels.append({
        "type": "emergency",
        "id": "emergency",
        "name": "Emergency",
        "last_message": await _last_message_for(MessageChannel.emergency, "emergency"),
        "unread_count": await _unread_count_for(MessageChannel.emergency, "emergency"),
    })

    # 3. Team channels — coordinator sees all teams, others see only their own
    if is_coordinator:
        team_ids_res = await db.execute(select(Team.id))
    else:
        team_ids_res = await db.execute(
            select(TeamMember.team_id).where(TeamMember.user_id == user_id)
        )
    for team_id in team_ids_res.scalars().all():
        team_id_str = str(team_id)
        team_res = await db.execute(select(Team).where(Team.id == team_id))
        team = team_res.scalar_one_or_none()
        team_name = team.name if team else f"Team {team_id_str[:8]}"
        channels.append({
            "type": "team",
            "id": f"team:{team_id_str}",
            "name": team_name,
            "last_message": await _last_message_for(MessageChannel.team, team_id_str),
            "unread_count": await _unread_count_for(MessageChannel.team, team_id_str),
        })

    # 3. Recent DM channels the user has participated in
    dm_channels_res = await db.execute(
        select(Message.channel_id)
        .where(
            Message.channel_type == MessageChannel.dm,
            Message.channel_id.contains(user_id_str),
            Message.is_deleted == False,
        )
        .distinct()
    )
    for dm_channel_id in dm_channels_res.scalars().all():
        if not dm_channel_id:
            continue
        # Derive the other user's ID from the sorted pair key (uid1_uid2)
        parts = dm_channel_id.split("_")
        other_uid_str = next((p for p in parts if p != user_id_str), None)
        if other_uid_str:
            try:
                other_uid = uuid.UUID(other_uid_str)
                other_res = await db.execute(select(User).where(User.id == other_uid))
                other_user = other_res.scalar_one_or_none()
                dm_name = f"DM: {other_user.full_name or other_user.username}" if other_user else f"DM: {other_uid_str[:8]}"
            except Exception:
                dm_name = f"DM: {other_uid_str[:8]}"
        else:
            dm_name = f"DM: {dm_channel_id}"
        channels.append({
            "type": "dm",
            "id": f"dm:{dm_channel_id}",
            "name": dm_name,
            "last_message": await _last_message_for(MessageChannel.dm, dm_channel_id),
            "unread_count": await _unread_count_for(MessageChannel.dm, dm_channel_id),
        })

    return channels


# Mobile uses 'team:UUID' as a single path segment
@router.get("/channels/{channel_str:path}")
async def get_channel_by_string(
    channel_str: str,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ct, cid = _parse_channel(channel_str, str(current_user.id))
    msgs = await _fetch_messages(db, ct, cid, limit)
    return [_msg_dict(m, sender) for m, sender in msgs]


# ── Existing GET endpoints (keep for backwards compat) ────────────────────────

@router.get("/global")
async def get_global_messages(
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    msgs = await _fetch_messages(db, MessageChannel.global_chat, "global", limit)
    return [_msg_dict(m, sender) for m, sender in msgs]


@router.get("/team/{team_id}")
async def get_team_messages(
    team_id: uuid.UUID,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    msgs = await _fetch_messages(db, MessageChannel.team, str(team_id), limit)
    return [_msg_dict(m, sender) for m, sender in msgs]


@router.get("/dm/{other_user_id}")
async def get_dm_messages(
    other_user_id: uuid.UUID,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    channel_key = "_".join(sorted([str(current_user.id), str(other_user_id)]))
    msgs = await _fetch_messages(db, MessageChannel.dm, channel_key, limit)
    return [_msg_dict(m, sender) for m, sender in msgs]


# ── Send message ──────────────────────────────────────────────────────────────

@router.post("", status_code=201)
async def send_message(
    data: MessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    channel_type = data.channel_type or MessageChannel.global_chat
    channel_id = data.channel_id

    # Normalise channel_id for DM (sort pair) and fixed channels
    if channel_type == MessageChannel.global_chat:
        channel_id = "global"
    elif channel_type == MessageChannel.emergency:
        channel_id = "emergency"
    elif channel_type == MessageChannel.dm and channel_id and "_" not in channel_id:
        # If only the other user's ID was sent, build the sorted pair key
        channel_id = "_".join(sorted([str(current_user.id), channel_id]))

    message = Message(
        channel_type=channel_type,
        channel_id=channel_id,
        sender_id=current_user.id,
        content=data.content,
        message_type=data.message_type,
        reply_to_id=data.reply_to_id,
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)

    msg_payload = {
        "type": "new_message",
        "message": {
            "id": str(message.id),
            "channel_id": channel_id,
            "sender_id": str(current_user.id),
            "sender": {
                "id": str(current_user.id),
                "full_name": current_user.full_name or current_user.username,
                "username": current_user.username,
                "avatar_url": current_user.avatar_url,
            },
            "content": message.content,
            "sent_at": message.created_at.isoformat(),
            "created_at": message.created_at.isoformat(),
        },
    }
    # Broadcast to all WS clients in this channel's room
    await manager.broadcast_to_room(f"chat:{channel_id}", msg_payload)

    # Send FCM push to offline channel members so they get the notification when app is closed
    from app.services.notification_service import NotificationService
    from app.models.user import UserDevice
    notif_svc = NotificationService(db)
    sender_name = current_user.full_name or current_user.username or "Someone"
    short_content = (data.content or "")[:80]

    offline_uids: set[str] = set()
    if channel_type == MessageChannel.dm and channel_id:
        for part in channel_id.split("_"):
            if part and part != str(current_user.id):
                offline_uids.add(part)
    elif channel_type == MessageChannel.team and channel_id:
        try:
            tm_res = await db.execute(
                select(TeamMember.user_id).where(TeamMember.team_id == uuid.UUID(channel_id))
            )
            for uid in tm_res.scalars().all():
                uid_s = str(uid)
                if uid_s != str(current_user.id):
                    offline_uids.add(uid_s)
        except Exception:
            pass

    chat_room = f"chat:{channel_id}"
    for uid_str in offline_uids:
        if manager.is_in_room(uid_str, chat_room):
            # Already receiving messages in the open chat screen — no extra notification needed
            continue
        if manager.is_online(uid_str):
            # Online but not viewing this chat — push via their events/notifications WS
            await manager.send_to(uid_str, {
                "type": "new_message",
                "channel_id": channel_id,
                "sender_name": sender_name,
                "content": short_content,
                "sender_id": str(current_user.id),
            })
        else:
            try:
                dev_res = await db.execute(
                    select(UserDevice).where(
                        UserDevice.user_id == uuid.UUID(uid_str),
                        UserDevice.is_active == True,
                    )
                )
                tokens = [d.device_token for d in dev_res.scalars().all() if d.device_token]
                if tokens:
                    from app.services.notification_service import _send_fcm
                    await _send_fcm(
                        tokens,
                        title=sender_name,
                        body=short_content,
                        data={
                            "type": "new_message",
                            "channel_id": channel_id,
                            "channel_type": channel_type.value,
                            "sender_id": str(current_user.id),
                        },
                    )
            except Exception:
                pass

    return {"id": str(message.id), "created_at": message.created_at.isoformat()}


@router.put("/{message_id}/read")
async def mark_read(
    message_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    existing = await db.execute(
        select(MessageRead).where(MessageRead.message_id == message_id, MessageRead.user_id == current_user.id)
    )
    if not existing.scalar_one_or_none():
        read = MessageRead(message_id=message_id, user_id=current_user.id)
        db.add(read)
        await db.commit()
    return {"status": "read"}
