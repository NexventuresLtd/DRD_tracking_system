# app/utils/validators.py
from typing import Optional, List
import re
from uuid import UUID

def validate_email(email: str) -> bool:
    """Validate email format"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))

def validate_password_strength(password: str) -> tuple[bool, Optional[str]]:
    """
    Validate password strength
    Returns (is_valid, error_message)
    """
    if len(password) < 8:
        return False, "Password must be at least 8 characters"
    
    if not re.search(r'[A-Z]', password):
        return False, "Password must contain uppercase letter"
    
    if not re.search(r'[a-z]', password):
        return False, "Password must contain lowercase letter"
    
    if not re.search(r'\d', password):
        return False, "Password must contain number"
    
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        return False, "Password must contain special character"
    
    return True, None

def validate_phone(phone: str) -> bool:
    """Validate phone number format"""
    pattern = r'^\+?[\d\s-]{10,15}$'
    return bool(re.match(pattern, phone))

def validate_coordinates(latitude: float, longitude: float) -> bool:
    """Validate GPS coordinates"""
    return -90 <= latitude <= 90 and -180 <= longitude <= 180

def validate_uuid_list(uuids: List[str]) -> List[UUID]:
    """Convert string list to UUID list, filtering invalid ones"""
    valid_uuids = []
    for uid in uuids:
        try:
            valid_uuids.append(UUID(uid))
        except ValueError:
            continue
    return valid_uuids