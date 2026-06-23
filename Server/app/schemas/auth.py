from pydantic import BaseModel, EmailStr
from typing import Optional
from app.models.user import UserRole


class RegisterRequest(BaseModel):
    email: EmailStr
    username: str
    full_name: str
    password: str
    phone: Optional[str] = None
    invite_code: Optional[str] = None


class LoginRequest(BaseModel):
    email: str  # accepts email or username
    password: str
    device_id: Optional[str] = None
    device_name: Optional[str] = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: "UserResponse"


class RefreshRequest(BaseModel):
    refresh_token: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str


class RegisterDeviceRequest(BaseModel):
    device_token: str
    platform: str
    device_name: Optional[str] = None


class OTPSessionResponse(BaseModel):
    requires_otp: bool = True
    otp_session: str
    email_hint: str


class VerifyOTPRequest(BaseModel):
    otp_session: str
    otp_code: str
    device_id: Optional[str] = None
    device_name: Optional[str] = None


class QREnrollRequest(BaseModel):
    qr_code: str
    email: EmailStr
    username: str
    full_name: str
    password: str


class VoucherEnrollRequest(BaseModel):
    voucher_code: str
    email: EmailStr
    username: str
    full_name: str
    password: str


from app.schemas.user import UserResponse
TokenResponse.model_rebuild()
