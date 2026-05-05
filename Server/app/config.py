# app/config.py
from pydantic_settings import BaseSettings
from typing import List
import json

class Settings(BaseSettings):
    # Database
    DATABASE_URL: str = "postgresql+asyncpg://postgres:YourStrongPassword@localhost:5432/dod_tracking"
    DATABASE_URL_SYNC: str = "postgresql://postgres:YourStrongPassword@localhost:5432/dod_tracking"
    
    # JWT
    SECRET_KEY: str = "drd_field_ops_secret_key_2024_super_secure_random_string_here"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"
    
    # CORS
    ALLOWED_ORIGINS: str = '*'
    
    # App
    APP_NAME: str = "DRD Field Coordination System"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    LOG_LEVEL: str = "INFO"
    
    @property
    def allowed_origins_list(self) -> List[str]:
        return json.loads(self.ALLOWED_ORIGINS)
    
    class Config:
        env_file = ".env"
        case_sensitive = True

settings = Settings()