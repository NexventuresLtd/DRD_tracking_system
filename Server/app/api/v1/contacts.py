import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User
from app.services.contact_service import ContactService
from app.websocket.manager import manager

router = APIRouter(prefix="/contacts", tags=["Contacts"])


def _contact_dict(c) -> dict:
    return {
        "id": str(c.id),
        "name": c.name,
        "contact_type": c.contact_type.value,
        "latitude": c.latitude,
        "longitude": c.longitude,
        "altitude": c.altitude,
        "description": c.description,
        "callsign": c.callsign,
        "team_id": str(c.team_id) if c.team_id else None,
        "mission_id": str(c.mission_id) if c.mission_id else None,
        "created_by": str(c.created_by) if c.created_by else None,
        "is_active": c.is_active,
        "created_at": c.created_at.isoformat(),
        "updated_at": c.updated_at.isoformat(),
    }


@router.get("")
async def list_contacts(
    mission_id: uuid.UUID = None,
    team_id: uuid.UUID = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = ContactService(db)
    contacts = await svc.list_contacts(mission_id=mission_id, team_id=team_id)
    return [_contact_dict(c) for c in contacts]


@router.post("", status_code=201)
async def create_contact(
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = ContactService(db)
    contact = await svc.create(body, current_user.id)
    data = _contact_dict(contact)
    await manager.broadcast_to_room("events", {"type": "contact_shared", "contact": data, "shared_by": str(current_user.id)})
    return data


@router.get("/{contact_id}")
async def get_contact(
    contact_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = ContactService(db)
    c = await svc.get_by_id(contact_id)
    if not c:
        raise HTTPException(404, "Contact not found")
    return _contact_dict(c)


@router.put("/{contact_id}")
async def update_contact(
    contact_id: uuid.UUID,
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = ContactService(db)
    c = await svc.update(contact_id, body)
    if not c:
        raise HTTPException(404, "Contact not found")
    return _contact_dict(c)


@router.delete("/{contact_id}", status_code=204)
async def delete_contact(
    contact_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    svc = ContactService(db)
    if not await svc.delete(contact_id):
        raise HTTPException(404, "Contact not found")
