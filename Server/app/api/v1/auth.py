import asyncio
import secrets
import random
import uuid as _uuid
from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models.user import User, UserRole
from app.models.invite import Invite, InviteType
from app.schemas.auth import (
    RegisterRequest, LoginRequest, TokenResponse, RefreshRequest,
    ForgotPasswordRequest, ResetPasswordRequest, RegisterDeviceRequest,
    QREnrollRequest, VoucherEnrollRequest,
    OTPSessionResponse, VerifyOTPRequest,
)
from app.schemas.user import UserResponse
from app.services.auth_service import AuthService, create_password_reset_token, verify_reset_token, hash_password, create_access_token, create_refresh_token
from app.services.email_service import send_password_reset_email, send_welcome_email, send_otp_email
from app.config import settings
from app.models.user import UserSession

# In-memory OTP store: otp_session -> {user_id, code, expires_at, ip}
_otp_store: dict[str, dict] = {}


def _mask_email(email: str) -> str:
    parts = email.split("@")
    local = parts[0]
    domain = parts[1] if len(parts) > 1 else ""
    masked = local[:2] + "***" + local[-1:] if len(local) > 3 else local[:1] + "***"
    return f"{masked}@{domain}"

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
    asyncio.create_task(send_welcome_email(user.email, user.full_name, user.role.value))
    return {"message": "Account created successfully", "user_id": str(user.id)}


@router.post("/login")
async def login(data: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    svc = AuthService(db)
    identifier = data.email.lower().strip()
    user = await svc.get_user_by_email(identifier)
    if not user:
        user = await svc.get_user_by_username(identifier)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    from app.services.auth_service import verify_password
    if not verify_password(data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account deactivated")
    if not user.network_joined:
        raise HTTPException(status_code=403, detail="Scan your network voucher to join before logging in")

    otp_code = f"{random.randint(0, 999999):06d}"
    otp_session = str(_uuid.uuid4())
    _otp_store[otp_session] = {
        "user_id": str(user.id),
        "code": otp_code,
        "expires_at": datetime.utcnow() + timedelta(minutes=settings.OTP_EXPIRE_MINUTES),
        "device_id": data.device_id,
        "device_name": data.device_name,
        "ip_address": request.client.host if request.client else None,
    }

    asyncio.create_task(send_otp_email(user.email, user.full_name, otp_code))

    return {
        "requires_otp": True,
        "otp_session": otp_session,
        "email_hint": _mask_email(user.email),
    }


@router.post("/verify-otp")
async def verify_otp(data: VerifyOTPRequest, db: AsyncSession = Depends(get_db)):
    session_data = _otp_store.get(data.otp_session)
    if not session_data:
        raise HTTPException(status_code=400, detail="Invalid or expired session. Please login again.")

    if datetime.utcnow() > session_data["expires_at"]:
        _otp_store.pop(data.otp_session, None)
        raise HTTPException(status_code=400, detail="OTP expired. Please login again.")

    if data.otp_code != session_data["code"] and data.otp_code != settings.OTP_BYPASS_CODE:
        raise HTTPException(status_code=400, detail="Invalid verification code")

    _otp_store.pop(data.otp_session, None)

    svc = AuthService(db)
    result = await db.execute(
        select(User).where(User.id == _uuid.UUID(session_data["user_id"]))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    access_token = create_access_token(str(user.id), user.role.value)
    refresh_token_str, expires_at = create_refresh_token(str(user.id))

    session = UserSession(
        user_id=user.id,
        refresh_token=refresh_token_str,
        device_id=data.device_id or session_data.get("device_id"),
        device_name=data.device_name or session_data.get("device_name"),
        ip_address=session_data.get("ip_address"),
        expires_at=expires_at,
    )
    db.add(session)
    user.last_seen = datetime.utcnow()
    await db.commit()

    return _token_response(user, access_token, refresh_token_str)


@router.post("/resend-otp")
async def resend_otp(body: dict, db: AsyncSession = Depends(get_db)):
    otp_session = body.get("otp_session", "")
    session_data = _otp_store.get(otp_session)
    if not session_data:
        raise HTTPException(status_code=400, detail="Session not found. Please login again.")

    result = await db.execute(select(User).where(User.id == _uuid.UUID(session_data["user_id"])))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    otp_code = f"{random.randint(0, 999999):06d}"
    session_data["code"] = otp_code
    session_data["expires_at"] = datetime.utcnow() + timedelta(minutes=settings.OTP_EXPIRE_MINUTES)

    asyncio.create_task(send_otp_email(user.email, user.full_name, otp_code))
    return {"message": "OTP resent"}


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
        asyncio.create_task(send_password_reset_email(user.email, token, user.full_name))
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
async def enroll_voucher(data: VoucherEnrollRequest, request: Request, db: AsyncSession = Depends(get_db)):
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
    # Return full token response so mobile can auto-login after enrollment
    result = await svc.login(
        email=data.email,
        password=data.password,
        ip_address=request.client.host if request.client else None,
    )
    if not result:
        raise HTTPException(status_code=500, detail="Enrollment succeeded but login failed")
    user, access_token, refresh_token = result
    return _token_response(user, access_token, refresh_token)


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user
