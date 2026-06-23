from pydantic_settings import BaseSettings
from typing import List
import os


class Settings(BaseSettings):
    APP_NAME: str = "DRD Field Coordination System"
    APP_VERSION: str = "2.0.0"
    DEBUG: bool = True
    LOG_LEVEL: str = "INFO"

    DATABASE_URL: str = "postgresql+asyncpg://postgres:YourStrongPassword@localhost:5432/dod_tracking"
    DATABASE_URL_SYNC: str = "postgresql://postgres:YourStrongPassword@localhost:5432/dod_tracking"

    SECRET_KEY: str = "drd_field_ops_secret_key_2024_super_secure_random_string_here"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    REDIS_URL: str = "redis://localhost:6379/0"

    ALLOWED_ORIGINS: List[str] = ["*"]

    PORT: int = 1104
    DOMAIN: str = "localhost"

    EMAIL_SMTP_SERVER: str = "mail.nexventures.net"
    EMAIL_SMTP_PORT: int = 587
    EMAIL_SENDER_EMAIL: str = "security@nexventures.net"
    EMAIL_SENDER_PASSWORD: str = ""
    EMAIL_LOGIN: str = "security@nexventures.net"

    UPLOAD_DIR: str = "uploads"
    MAX_UPLOAD_SIZE_MB: int = 50

    MINIO_ENDPOINT: str = "localhost:9000"
    MINIO_ACCESS_KEY: str = "minioadmin"
    MINIO_SECRET_KEY: str = "minioadmin123"
    MINIO_BUCKET: str = "drd-evidence"
    MINIO_SECURE: bool = False

    class Config:
        env_file = ".env"
        case_sensitive = True
        extra = "ignore"


settings = Settings()
