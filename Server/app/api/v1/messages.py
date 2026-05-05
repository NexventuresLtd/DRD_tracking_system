# app/api/v1/messages.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_, and_
from typing import Optional, List
from uuid import UUID
from datetime import datetime, timezone
from pydantic import BaseModel, Field

from app.database import get_db
from app.models.user import User
from app.models.message import Message
from app.models.team import Team, TeamMember
from app.middleware.auth import get_current_user, require_any_user

class MessageSend(BaseModel):
    to_user_id: Optional[UUID] = None
    to_team_id: Optional[UUID] = None
    to_all: bool = False
    content: str = Field(..., min_length=1, max_length=5000)
    priority: str = "normal"

class MessageResponse(BaseModel):
    id: UUID
    from_user_id: UUID
    to_user_id: Optional[UUID]
    to_team_id: Optional[UUID]
    to_all: bool
    content: str
    priority: str
    is_read: bool
    read_at: Optional[datetime]
    created_at: datetime
    from_user_name: Optional[str] = None
    
    class Config:
        from_attributes = True

class MessageListResponse(BaseModel):
    total: int
    items: List[MessageResponse]
    page: int
    size: int
    unread_count: int

router = APIRouter(prefix="/messages", tags=["Messages"])

@router.get("/", response_model=MessageListResponse)
async def list_messages(
    page: int = Query(1, ge=1),
    size: int = Query(30, ge=1, le=100),
    is_read: Optional[bool] = None,
    priority: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List messages for current user"""
    # Messages where user is recipient or sender
    query = select(Message).where(
        or_(
            Message.to_user_id == current_user.id,
            Message.from_user_id == current_user.id,
            Message.to_all == True,
            # Messages to user's teams
            Message.to_team_id.in_(
                select(TeamMember.team_id).where(
                    TeamMember.user_id == current_user.id,
                    TeamMember.is_active == True,
                )
            ),
        )
    )
    
    count_query = select(func.count(Message.id)).where(
        or_(
            Message.to_user_id == current_user.id,
            Message.from_user_id == current_user.id,
            Message.to_all == True,
            Message.to_team_id.in_(
                select(TeamMember.team_id).where(
                    TeamMember.user_id == current_user.id,
                    TeamMember.is_active == True,
                )
            ),
        )
    )
    
    if is_read is not None:
        query = query.where(Message.is_read == is_read)
        count_query = count_query.where(Message.is_read == is_read)
    
    if priority:
        query = query.where(Message.priority == priority)
        count_query = count_query.where(Message.priority == priority)
    
    # Get unread count
    unread_query = select(func.count(Message.id)).where(
        or_(
            Message.to_user_id == current_user.id,
            Message.to_all == True,
            Message.to_team_id.in_(
                select(TeamMember.team_id).where(
                    TeamMember.user_id == current_user.id,
                    TeamMember.is_active == True,
                )
            ),
        ),
        Message.is_read == False,
    )
    unread_result = await db.execute(unread_query)
    unread_count = unread_result.scalar()
    
    # Get total count
    count_result = await db.execute(count_query)
    total = count_result.scalar()
    
    # Get paginated results
    query = query.order_by(Message.created_at.desc())
    query = query.offset((page - 1) * size).limit(size)
    
    result = await db.execute(query)
    messages = result.scalars().all()
    
    items = []
    for msg in messages:
        # Get sender name
        sender_result = await db.execute(
            select(User).where(User.id == msg.from_user_id)
        )
        sender = sender_result.scalar_one_or_none()
        
        items.append(MessageResponse(
            id=msg.id,
            from_user_id=msg.from_user_id,
            to_user_id=msg.to_user_id,
            to_team_id=msg.to_team_id,
            to_all=msg.to_all,
            content=msg.content,
            priority=msg.priority,
            is_read=msg.is_read,
            read_at=msg.read_at,
            created_at=msg.created_at,
            from_user_name=sender.full_name if sender else "Unknown",
        ))
    
    return MessageListResponse(
        total=total,
        items=items,
        page=page,
        size=size,
        unread_count=unread_count,
    )

@router.post("/", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    data: MessageSend,
    current_user: User = Depends(require_any_user),
    db: AsyncSession = Depends(get_db)
):
    """Send a message"""
    # Validate recipients
    if not data.to_all and not data.to_user_id and not data.to_team_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Must specify recipient (user, team, or all)"
        )
    
    message = Message(
        from_user_id=current_user.id,
        to_user_id=data.to_user_id,
        to_team_id=data.to_team_id,
        to_all=data.to_all,
        content=data.content,
        priority=data.priority,
    )
    
    db.add(message)
    await db.commit()
    await db.refresh(message)
    
    return MessageResponse(
        id=message.id,
        from_user_id=message.from_user_id,
        to_user_id=message.to_user_id,
        to_team_id=message.to_team_id,
        to_all=message.to_all,
        content=message.content,
        priority=message.priority,
        is_read=message.is_read,
        read_at=message.read_at,
        created_at=message.created_at,
        from_user_name=current_user.full_name,
    )

@router.post("/broadcast", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def broadcast_message(
    data: MessageSend,
    current_user: User = Depends(require_any_user),
    db: AsyncSession = Depends(get_db)
):
    """Broadcast message to all users or team"""
    message = Message(
        from_user_id=current_user.id,
        to_all=data.to_all,
        to_team_id=data.to_team_id,
        content=data.content,
        priority=data.priority,
    )
    
    db.add(message)
    await db.commit()
    await db.refresh(message)
    
    return MessageResponse(
        id=message.id,
        from_user_id=message.from_user_id,
        to_user_id=message.to_user_id,
        to_team_id=message.to_team_id,
        to_all=message.to_all,
        content=message.content,
        priority=message.priority,
        is_read=message.is_read,
        read_at=message.read_at,
        created_at=message.created_at,
        from_user_name=current_user.full_name,
    )

@router.put("/{message_id}/read")
async def mark_as_read(
    message_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Mark message as read"""
    result = await db.execute(
        select(Message).where(
            Message.id == message_id,
            or_(
                Message.to_user_id == current_user.id,
                Message.to_all == True,
            ),
        )
    )
    message = result.scalar_one_or_none()
    
    if not message:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Message not found"
        )
    
    message.is_read = True
    message.read_at = datetime.now(timezone.utc)
    await db.commit()
    
    return {"message": "Marked as read"}

@router.put("/read-all")
async def mark_all_as_read(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Mark all messages as read"""
    result = await db.execute(
        select(Message).where(
            or_(
                Message.to_user_id == current_user.id,
                Message.to_all == True,
            ),
            Message.is_read == False,
        )
    )
    messages = result.scalars().all()
    
    for message in messages:
        message.is_read = True
        message.read_at = datetime.now(timezone.utc)
    
    await db.commit()
    
    return {"message": f"{len(messages)} messages marked as read"}