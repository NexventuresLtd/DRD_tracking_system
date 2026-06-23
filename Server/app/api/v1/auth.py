import secrets
from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User, UserRole
from app.models.invite import Invite, InviteType
from app.schemas.auth import (
    RegisterRequest, LoginRequest, TokenResponse, RefreshRequest,
    ForgotPasswordRequest, ResetPasswordRequest, RegisterDeviceRequest,
    QREnrollRequest, VoucherEnrollRequest,
)
from app.schemas.user import UserResponse
from app.services.auth_service import AuthService, create_password_reset_token, verify_reset_token, hash_password
from app.services.email_service import send_password_reset_email, send_welcome_email
from app.config import settings

router = APIRouter(prefix="/auth", tags=["Authentication"])


def _token_response(user: User, access: str, refresh: str) -> dict:
    return {
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "bearer",
        "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        "user": UserResponse.model_validate(user),
    }


@router.post("/register", status_code=201)
async def register(data: RegisterRequest, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    if await svc.get_user_by_email(data.email):
        raise HTTPException(status_code=400, detail="Email already registered")
    if await svc.get_user_by_username(data.username):
        raise HTTPException(status_code=400, detail="Username already taken")

    if data.invite_code:
        invite = await svc.validate_invite(data.invite_code)
        if not invite:
            raise HTTPException(status_code=400, detail="Invalid or expired invite code")

    user = await svc.register(
        email=data.email,
        username=data.username,
        full_name=data.full_name,
        password=data.password,
        phone=data.phone,
        invite_code=data.invite_code,
    )
    await send_welcome_email(user.email, user.full_name, user.role.value)
    return {"message": "Account created successfully", "user_id": str(user.id)}


@router.post("/login")
async def login(data: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    result = await svc.login(
        email=data.email,
        password=data.password,
        device_id=data.device_id,
        device_name=data.device_name,
        ip_address=request.client.host if request.client else None,
    )
    if not result:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    user, access, refresh = result
    return _token_response(user, access, refresh)


@router.post("/refresh")
async def refresh_token(data: RefreshRequest, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    result = await svc.refresh(data.refresh_token)
    if not result:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")
    access, refresh = result
    return {"access_token": access, "refresh_token": refresh, "token_type": "bearer"}


@router.post("/logout")
async def logout(data: RefreshRequest, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    await svc.logout(data.refresh_token)
    return {"message": "Logged out"}


@router.post("/forgot-password")
async def forgot_password(data: ForgotPasswordRequest, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    user = await svc.get_user_by_email(data.email)
    if user:
        token = create_password_reset_token(str(user.id))
        await send_password_reset_email(user.email, token, user.full_name)
    return {"message": "If this email exists, a reset link has been sent"}


@router.post("/reset-password")
async def reset_password(data: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    from sqlalchemy import select
    import uuid
    user_id = verify_reset_token(data.token)
    if not user_id:
        raise HTTPException(status_code=400, detail="Invalid or expired token")

    from app.models.user import User
    result = await db.execute(select(User).where(User.id == uuid.UUID(user_id)))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.hashed_password = hash_password(data.new_password)
    await db.commit()
    return {"message": "Password updated successfully"}


@router.post("/register-device")
async def register_device(
    data: RegisterDeviceRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.models.user import UserDevice
    device = UserDevice(
        user_id=current_user.id,
        device_token=data.device_token,
        platform=data.platform,
        device_name=data.device_name,
    )
    db.add(device)
    await db.commit()
    return {"message": "Device registered"}


@router.post("/enroll/qr")
async def enroll_qr(data: QREnrollRequest, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    invite = await svc.validate_invite(data.qr_code)
    if not invite or invite.invite_type != InviteType.qr:
        raise HTTPException(status_code=400, detail="Invalid QR enrollment code")

    if await svc.get_user_by_email(data.email):
        raise HTTPException(status_code=400, detail="Email already registered")

    user = await svc.register(
        email=data.email,
        username=data.username,
        full_name=data.full_name,
        password=data.password,
        invite_code=data.qr_code,
    )
    return {"message": "Enrolled via QR code", "user_id": str(user.id)}


@router.post("/enroll/voucher")
async def enroll_voucher(data: VoucherEnrollRequest, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    invite = await svc.validate_invite(data.voucher_code)
    if not invite:
        raise HTTPException(status_code=400, detail="Invalid voucher code")

    if await svc.get_user_by_email(data.email):
        raise HTTPException(status_code=400, detail="Email already registered")

    user = await svc.register(
        email=data.email,
        username=data.username,
        full_name=data.full_name,
        password=data.password,
        invite_code=data.voucher_code,
    )
    return {"message": "Enrolled via voucher", "user_id": str(user.id)}


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user
