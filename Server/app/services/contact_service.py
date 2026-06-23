import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.contact import Contact, ContactType


class ContactService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, data: dict, created_by: uuid.UUID) -> Contact:
        contact = Contact(
            name=data["name"],
            contact_type=ContactType(data.get("contact_type", "unknown")),
            latitude=data["latitude"],
            longitude=data["longitude"],
            altitude=data.get("altitude"),
            description=data.get("description"),
            callsign=data.get("callsign"),
            team_id=data.get("team_id"),
            mission_id=data.get("mission_id"),
            created_by=created_by,
        )
        self.db.add(contact)
        await self.db.commit()
        await self.db.refresh(contact)
        return contact

    async def get_by_id(self, contact_id: uuid.UUID) -> Optional[Contact]:
        result = await self.db.execute(select(Contact).where(Contact.id == contact_id))
        return result.scalar_one_or_none()

    async def list_contacts(self, mission_id: Optional[uuid.UUID] = None, team_id: Optional[uuid.UUID] = None, active_only: bool = True):
        q = select(Contact)
        if active_only:
            q = q.where(Contact.is_active == True)
        if mission_id:
            q = q.where(Contact.mission_id == mission_id)
        if team_id:
            q = q.where(Contact.team_id == team_id)
        q = q.order_by(Contact.created_at.desc())
        result = await self.db.execute(q)
        return result.scalars().all()

    async def update(self, contact_id: uuid.UUID, data: dict) -> Optional[Contact]:
        contact = await self.get_by_id(contact_id)
        if not contact:
            return None
        for field in ("name", "contact_type", "latitude", "longitude", "altitude", "description", "callsign"):
            if field in data:
                val = ContactType(data[field]) if field == "contact_type" else data[field]
                setattr(contact, field, val)
        contact.updated_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(contact)
        return contact

    async def delete(self, contact_id: uuid.UUID) -> bool:
        contact = await self.get_by_id(contact_id)
        if not contact:
            return False
        contact.is_active = False
        await self.db.commit()
        return True
