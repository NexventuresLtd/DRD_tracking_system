import uuid
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_
from pydantic import BaseModel
from datetime import datetime

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.models.message import Message, MessageRead, MessageChannel, MessageType
from app.websocket.manager import manager

router = APIRouter(prefix="/messages", tags=["Messages"])


class MessageCreate(BaseModel):
    channel_type: MessageChannel
    channel_id: Optional[str] = None
    content: str
    message_type: MessageType = MessageType.text
    reply_to_id: Optional[uuid.UUID] = None


@router.get("/channels")
async def list_channels(current_user: User = Depends(get_current_user)):
    return [
        {"type": "global", "id": "global", "name": "Global Channel"},
        {"type": "emergency", "id": "emergency", "name": "Emergency Channel"},
    ]


@router.get("/global")
async def get_global_messages(
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Message)
        .where(Message.channel_type == MessageChannel.global_chat, Message.is_deleted == False)
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/team/{team_id}")
async def get_team_messages(
    team_id: uuid.UUID,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Message)
        .where(
            Message.channel_type == MessageChannel.team,
            Message.channel_id == str(team_id),
            Message.is_deleted == False,
        )
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/dm/{other_user_id}")
async def get_dm_messages(
    other_user_id: uuid.UUID,
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    channel_key = "_".join(sorted([str(current_user.id), str(other_user_id)]))
    result = await db.execute(
        select(Message)
        .where(
            Message.channel_type == MessageChannel.dm,
            Message.channel_id == channel_key,
            Message.is_deleted == False,
        )
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    return result.scalars().all()


@router.post("", status_code=201)
async def send_message(
    data: MessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    channel_id = data.channel_id
    if data.channel_type == MessageChannel.global_chat:
        channel_id = "global"
    elif data.channel_type == MessageChannel.emergency:
        channel_id = "emergency"

    message = Message(
        channel_type=data.channel_type,
        channel_id=channel_id,
        sender_id=current_user.id,
        content=data.content,
        message_type=data.message_type,
        reply_to_id=data.reply_to_id,
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)

    await manager.broadcast({
        "type": "new_message",
        "channel": channel_id,
        "message_id": str(message.id),
        "sender_id": str(current_user.id),
        "sender_name": current_user.full_name,
        "content": message.content,
        "timestamp": message.created_at.isoformat(),
    })
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
