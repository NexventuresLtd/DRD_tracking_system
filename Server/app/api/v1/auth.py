# app/api/v1/auth.py
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Request
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional
import uuid
from pathlib import Path

from app.database import get_db
from app.schemas.auth import (
    UserRegister, UserLogin, TokenResponse,
    RefreshToken, ForgotPassword, ResetPassword, ChangePassword,
    OtpVerify, OtpPendingResponse
)
from app.services.auth_service import AuthService
from app.middleware.auth import get_current_user, security
from app.models.user import User

router = APIRouter(prefix="/auth", tags=["Authentication"])

AVATAR_DIR = Path("uploads/avatars")
AVATAR_DIR.mkdir(parents=True, exist_ok=True)

@router.post("/register", response_model=dict, status_code=status.HTTP_201_CREATED)
async def register(
    data: UserRegister,
    db: AsyncSession = Depends(get_db)
):
    """Register a new user"""
    auth_service = AuthService(db)
    user = await auth_service.register_user(data)
    
    return {
        "message": "User registered successfully",
        "user_id": str(user.id),
        "email": user.email,
        "username": user.username,
    }

@router.post("/login", response_model=TokenResponse | OtpPendingResponse)
async def login(
    data: UserLogin,
    db: AsyncSession = Depends(get_db)
):
    """Login and get access tokens"""
    auth_service = AuthService(db)
    return await auth_service.login(data)


@router.post("/verify-otp", response_model=TokenResponse)
async def verify_otp(
    data: OtpVerify,
    db: AsyncSession = Depends(get_db)
):
    """Verify OTP and exchange the session for tokens."""
    auth_service = AuthService(db)
    return await auth_service.verify_otp(data.session_id, data.otp)

@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    data: RefreshToken,
    db: AsyncSession = Depends(get_db)
):
    """Refresh access token"""
    auth_service = AuthService(db)
    try:
        return await auth_service.refresh_token(data.refresh_token)
    finally:
        # Lightweight log for troubleshooting repeated refresh attempts
        print("Auth refresh attempted")


@router.post("/refresh/", response_model=TokenResponse, include_in_schema=False)
async def refresh_token_slash(
    data: RefreshToken,
    db: AsyncSession = Depends(get_db)
):
    """Trailing-slash alias for refresh to avoid 307 redirects from clients."""
    auth_service = AuthService(db)
    print("Auth refresh (slash) attempted")
    return await auth_service.refresh_token(data.refresh_token)

@router.post("/logout")
async def logout(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Logout user (invalidate token)"""
    # In a production system, you'd blacklist the token in Redis
    return {"message": "Logged out successfully"}

@router.get("/me")
async def get_current_user_info(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get current user information including team membership"""
    from sqlalchemy import select
    from app.models.team import Team, TeamMember

    tm_result = await db.execute(
        select(TeamMember, Team)
        .join(Team, TeamMember.team_id == Team.id)
        .where(TeamMember.user_id == user.id, TeamMember.is_active == True)
        .limit(1)
    )
    tm_row = tm_result.first()

    return {
        "id": str(user.id),
        "email": user.email,
        "username": user.username,
        "full_name": user.full_name,
        "role": user.role.value,
        "phone": user.phone,
        "profile_picture_url": user.profile_picture_url,
        "is_active": user.is_active,
        "is_verified": user.is_verified,
        "last_login": user.last_login.isoformat() if user.last_login else None,
        "created_at": user.created_at.isoformat(),
        "team_id": str(tm_row[0].team_id) if tm_row else None,
        "team_name": tm_row[1].name if tm_row else None,
        "team_role": tm_row[0].role if tm_row else None,
    }

@router.post("/upload-avatar")
async def upload_avatar(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    request: Request = None,
):
    """Upload profile picture for current user"""
    allowed = {"image/jpeg", "image/png", "image/webp", "image/gif"}
    if file.content_type not in allowed:
        raise HTTPException(status_code=400, detail="Only image files allowed")
    content = await file.read()
    if len(content) > 5 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large (max 5MB)")
    ext = Path(file.filename or "avatar.jpg").suffix or ".jpg"
    fname = f"{current_user.id}{ext}"
    fpath = AVATAR_DIR / fname
    with open(fpath, "wb") as f:
        f.write(content)
    # Build absolute URL
    base = str(request.base_url).rstrip("/") if request else ""
    url = f"{base}/uploads/avatars/{fname}"
    current_user.profile_picture_url = url
    db.add(current_user)
    await db.commit()
    return {"profile_picture_url": url}

@router.put("/change-password")
async def change_password(
    data: ChangePassword,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Change user password"""
    auth_service = AuthService(db)
    await auth_service.change_password(user, data.old_password, data.new_password)
    return {"message": "Password changed successfully"}

@router.post("/forgot-password")
async def forgot_password(
    data: ForgotPassword,
    db: AsyncSession = Depends(get_db)
):
    """Request password reset"""
    # In production, send email with reset link
    return {
        "message": "If the email exists, a password reset link has been sent"
    }

@router.post("/reset-password")
async def reset_password(
    data: ResetPassword,
    db: AsyncSession = Depends(get_db)
):
    """Reset password with token"""
    # In production, verify reset token from email
    return {"message": "Password reset successfully"}