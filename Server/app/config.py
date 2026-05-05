# app/config.py
from pydantic_settings import BaseSettings
from typing import List, Optional
import json


class Settings(BaseSettings):
    # =====================
    # DATABASE
    # =====================
    DATABASE_URL: str
    DATABASE_URL_SYNC: Optional[str] = None

    # =====================
    # SERVER
    # =====================
    PORT: int = 1104
    DOMAIN: str = "localhost"

    # =====================
    # JWT
    # =====================
    SECRET_KEY: str = "CHANGE_ME_SUPER_SECRET"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # =====================
    # REDIS
    # =====================
    REDIS_URL: str = "redis://localhost:6379/0"

    # =====================
    # CORS
    # =====================
    ALLOWED_ORIGINS: str = "*"

    # =====================
    # APP META
    # =====================
    APP_NAME: str = "DRD Field Coordination System"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    # =====================
    # HELPERS
    # =====================
    @property
    def allowed_origins_list(self) -> List[str]:
        if self.ALLOWED_ORIGINS.strip() == "*":
            return ["*"]
        try:
            return json.loads(self.ALLOWED_ORIGINS)
        except Exception:
            return [self.ALLOWED_ORIGINS]

    class Config:
        env_file = ".env"
        case_sensitive = True
        extra = "ignore"   # 🔥 THIS FIXES YOUR CRASH


# global instance
settings = Settings()