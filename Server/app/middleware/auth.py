# app/middleware/auth.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from uuid import UUID

from app.database import get_db
from app.models.user import User, UserRole
from app.utils.security import verify_access_token

security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db)
) -> User:
    """Get current authenticated user"""
    token = credentials.credentials
    payload = verify_access_token(token)
    
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
        )
    
    result = await db.execute(
        select(User).where(User.id == UUID(user_id))
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )
    
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is disabled",
        )
    
    return user

class RoleChecker:
    """Dependency for checking user roles"""
    
    def __init__(self, allowed_roles: list[UserRole]):
        self.allowed_roles = allowed_roles
    
    async def __call__(
        self,
        user: User = Depends(get_current_user)
    ) -> User:
        if user.role not in self.allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Required role: {[r.value for r in self.allowed_roles]}",
            )
        return user

# Pre-defined role checkers
require_admin = RoleChecker([UserRole.SUPER_ADMIN, UserRole.ADMIN])
require_commander = RoleChecker([
    UserRole.SUPER_ADMIN, UserRole.ADMIN, UserRole.COMMANDER
])
require_operator = RoleChecker([
    UserRole.SUPER_ADMIN, UserRole.ADMIN, UserRole.COMMANDER, UserRole.OPERATOR
])
require_any_user = RoleChecker([
    UserRole.SUPER_ADMIN, UserRole.ADMIN, UserRole.COMMANDER,
    UserRole.OPERATOR, UserRole.VIEWER, UserRole.FIELD_UNIT
])