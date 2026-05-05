# app/api/v1/events.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_, and_
from typing import Optional, List
from uuid import UUID
from datetime import datetime, timedelta, timezone
from pydantic import BaseModel

from app.database import get_db
from app.models.user import User, UserRole
from app.models.event import Event
from app.models.team import Team
from app.middleware.auth import get_current_user
from app.websocket.manager import manager
import asyncio

class EventCreate(BaseModel):
    event_type: str
    user_id: Optional[UUID] = None
    team_id: Optional[UUID] = None
    description: str
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None
    event_metadata: Optional[dict] = None  # Changed from metadata
    severity: str = "low"

class EventResponse(BaseModel):
    id: UUID
    event_type: str
    user_id: Optional[UUID]
    team_id: Optional[UUID]
    description: str
    location_lat: Optional[float]
    location_lng: Optional[float]
    event_metadata: Optional[dict]  # Changed from metadata
    severity: str
    created_at: datetime
    
    class Config:
        from_attributes = True

class EventListResponse(BaseModel):
    total: int
    items: List[EventResponse]
    page: int
    size: int

router = APIRouter(prefix="/events", tags=["Events"])

@router.get("/", response_model=EventListResponse)
async def list_events(
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=200),
    event_type: Optional[str] = None,
    severity: Optional[str] = None,
    team_id: Optional[UUID] = None,
    user_id: Optional[UUID] = None,
    start_time: Optional[datetime] = None,
    end_time: Optional[datetime] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List events with filters"""
    query = select(Event)
    count_query = select(func.count(Event.id))
    
    if event_type:
        query = query.where(Event.event_type == event_type)
        count_query = count_query.where(Event.event_type == event_type)
    
    if severity:
        query = query.where(Event.severity == severity)
        count_query = count_query.where(Event.severity == severity)
    
    if team_id:
        query = query.where(Event.team_id == team_id)
        count_query = count_query.where(Event.team_id == team_id)
    
    if user_id:
        query = query.where(Event.user_id == user_id)
        count_query = count_query.where(Event.user_id == user_id)
    
    if start_time:
        query = query.where(Event.created_at >= start_time)
        count_query = count_query.where(Event.created_at >= start_time)
    
    if end_time:
        query = query.where(Event.created_at <= end_time)
        count_query = count_query.where(Event.created_at <= end_time)
    
    # Get total count
    count_result = await db.execute(count_query)
    total = count_result.scalar()
    
    # Get paginated results
    query = query.order_by(Event.created_at.desc())
    query = query.offset((page - 1) * size).limit(size)
    
    result = await db.execute(query)
    events = result.scalars().all()
    
    return EventListResponse(
        total=total,
        items=[
            EventResponse(
                id=e.id,
                event_type=e.event_type,
                user_id=e.user_id,
                team_id=e.team_id,
                description=e.description,
                location_lat=e.location_lat,
                location_lng=e.location_lng,
                event_metadata=e.event_metadata,  # Changed
                severity=e.severity,
                created_at=e.created_at,
            )
            for e in events
        ],
        page=page,
        size=size,
    )

@router.post("/", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
async def create_event(
    data: EventCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new event"""
    is_elevated = current_user.role in {
        UserRole.SUPER_ADMIN,
        UserRole.ADMIN,
        UserRole.COMMANDER,
        UserRole.OPERATOR,
    }

    if not is_elevated:
        allowed_types = {"UPDATE", "FLAG", "ALERT", "POI"}
        if (data.event_type or "").upper() not in allowed_types:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This role cannot create that event type",
            )
        if data.user_id and data.user_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only create events for your own user",
            )

    event_user_id = data.user_id or current_user.id

    event = Event(
        event_type=data.event_type,
        user_id=event_user_id,
        team_id=data.team_id,
        description=data.description,
        location_lat=data.location_lat,
        location_lng=data.location_lng,
        event_metadata=data.event_metadata,  # Changed
        severity=data.severity,
    )
    
    db.add(event)
    await db.commit()
    await db.refresh(event)
    # Broadcast event to websocket clients (non-blocking)
    try:
        event_data = {
            "id": str(event.id),
            "event_type": event.event_type,
            "user_id": str(event.user_id) if event.user_id else None,
            "team_id": str(event.team_id) if event.team_id else None,
            "description": event.description,
            "location_lat": event.location_lat,
            "location_lng": event.location_lng,
            "event_metadata": event.event_metadata,
            "severity": event.severity,
            "created_at": event.created_at.isoformat() if event.created_at else None,
        }
        try:
            asyncio.create_task(manager.broadcast_event(event_data))
        except Exception:
            asyncio.get_event_loop().create_task(manager.broadcast_event(event_data))
    except Exception:
        pass

    return EventResponse(
        id=event.id,
        event_type=event.event_type,
        user_id=event.user_id,
        team_id=event.team_id,
        description=event.description,
        location_lat=event.location_lat,
        location_lng=event.location_lng,
        event_metadata=event.event_metadata,  # Changed
        severity=event.severity,
        created_at=event.created_at,
    )

@router.get("/{event_id}", response_model=EventResponse)
async def get_event(
    event_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get event details"""
    result = await db.execute(select(Event).where(Event.id == event_id))
    event = result.scalar_one_or_none()
    
    if not event:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found"
        )
    
    return EventResponse(
        id=event.id,
        event_type=event.event_type,
        user_id=event.user_id,
        team_id=event.team_id,
        description=event.description,
        location_lat=event.location_lat,
        location_lng=event.location_lng,
        event_metadata=event.event_metadata,
        severity=event.severity,
        created_at=event.created_at,
    )

@router.get("/stats")
async def get_event_stats(
    days: int = Query(7, ge=1, le=30),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get event statistics"""
    start_time = datetime.now(timezone.utc) - timedelta(days=days)
    
    # Total events
    total_result = await db.execute(
        select(func.count(Event.id)).where(Event.created_at >= start_time)
    )
    total_events = total_result.scalar()
    
    # Events by type
    type_result = await db.execute(
        select(Event.event_type, func.count(Event.id))
        .where(Event.created_at >= start_time)
        .group_by(Event.event_type)
    )
    events_by_type = {row[0]: row[1] for row in type_result}
    
    # Events by severity
    severity_result = await db.execute(
        select(Event.severity, func.count(Event.id))
        .where(Event.created_at >= start_time)
        .group_by(Event.severity)
    )
    events_by_severity = {row[0]: row[1] for row in severity_result}
    
    return {
        "total_events": total_events,
        "events_by_type": events_by_type,
        "events_by_severity": events_by_severity,
        "period_days": days,
    }