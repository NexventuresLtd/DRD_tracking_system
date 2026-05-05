# alembic/env.py
from logging.config import fileConfig
from sqlalchemy import engine_from_config
from sqlalchemy import pool
from alembic import context
import sys
import os

# Add project root to path
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

from app.config import settings
from app.database import Base

# Import all models to ensure they're registered
from app.models.user import User
from app.models.team import Team, TeamMember
from app.models.location import Location, LocationHistory
from app.models.route import Route, RouteWaypoint, RouteVisibility
from app.models.route_follow import RouteFollowSession, RouteFollowPoint
from app.models.poi import POI, POIVisibility
from app.models.event import Event
from app.models.message import Message
from app.models.zone import Zone, ZoneCoordinate, ZoneAssignment
from app.models.notification import Notification, UserFlag
from app.models.audit import AuditLog, UserSession  # Changed from Session to UserSession

# Alembic Config object
config = context.config

# Set the SQLAlchemy URL
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL_SYNC)

# Interpret the config file for Python logging
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# MetaData object for autogenerate support
target_metadata = Base.metadata

def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()

def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )

        with context.begin_transaction():
            context.run_migrations()

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()