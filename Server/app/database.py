# app/database.py
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy import create_engine, text
from app.config import settings
import asyncio

# Async engine for FastAPI
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
)

# Sync engine for Alembic
sync_engine = create_engine(
    settings.DATABASE_URL_SYNC,
    echo=settings.DEBUG,
    pool_size=5,
    max_overflow=10,
)

# Async session factory
async_session = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

class Base(DeclarativeBase):
    pass

async def get_db() -> AsyncSession:
    """Dependency to get database session"""
    async with async_session() as session:
        try:
            yield session
        finally:
            await session.close()

async def init_db():
    """Initialize database tables"""
    # Import all models to ensure they're registered
    from app.models.user import User
    from app.models.team import Team, TeamMember
    from app.models.location import Location, LocationHistory
    from app.models.route import Route, RouteWaypoint, RouteVisibility, RouteHistory
    from app.models.route_follow import RouteFollowSession, RouteFollowPoint
    from app.models.poi import POI, POIVisibility
    from app.models.event import Event
    from app.models.message import Message
    from app.models.zone import Zone, ZoneCoordinate, ZoneAssignment
    from app.models.notification import Notification, UserFlag
    from app.models.audit import AuditLog, UserSession  # Changed from Session to UserSession
    
    async with engine.begin() as conn:
        # Create all tables
        await conn.run_sync(Base.metadata.create_all)
        
        # Create extensions if they don't exist
        await conn.execute(text('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"'))
        # await conn.execute(text('CREATE EXTENSION IF NOT EXISTS "postgis"'))  # Optional
    
    print("Database tables created successfully")