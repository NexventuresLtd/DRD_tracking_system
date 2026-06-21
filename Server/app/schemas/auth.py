# app/schemas/auth.py
from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from datetime import datetime
from uuid import UUID

class UserRegister(BaseModel):
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=8, max_length=100)
    full_name: str = Field(..., min_length=2, max_length=200)
    phone: Optional[str] = None
    role: Optional[str] = "field_unit"
    invite_token: Optional[str] = None

class UserLogin(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: dict

class RefreshToken(BaseModel):
    refresh_token: str

class ForgotPassword(BaseModel):
    email: EmailStr

class ResetPassword(BaseModel):
    token: str
    new_password: str = Field(..., min_length=8, max_length=100)

class ChangePassword(BaseModel):
    old_password: str
    new_password: str = Field(..., min_length=8, max_length=100)

class TokenPayload(BaseModel):
    sub: str
    exp: datetime
    type: str
    role: str

class OtpVerify(BaseModel):
    session_id: str
    otp: str

class OtpPendingResponse(BaseModel):
    status: str = "otp_required"
    session_id: str
    email_hint: str
    message: str = "A verification code has been sent to your email."