import uuid
from datetime import datetime
from pydantic import BaseModel
from typing import Optional
from app.models.user import UserRole
from app.models.invite import InviteType


class InviteCreate(BaseModel):
    assigned_role: UserRole = UserRole.field_user
    invite_type: InviteType = InviteType.voucher
    max_uses: int = 1
    expires_in_hours: Optional[int] = 168
    note: Optional[str] = None


class InviteResponse(BaseModel):
    id: uuid.UUID
    code: str
    invite_type: InviteType
    assigned_role: UserRole
    is_active: bool
    max_uses: int
    use_count: int
    expires_at: Optional[datetime] = None
    note: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}
