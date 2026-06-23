from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User

router = APIRouter(prefix="/events", tags=["Events"])


@router.get("")
async def list_events(current_user: User = Depends(get_current_user)):
    return []
