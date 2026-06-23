"""Add avatar_url to users (missing from initial create_all bootstrap)

Revision ID: 0002
Revises: 0001
Create Date: 2026-06-23
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Use raw SQL so it's idempotent — safe whether column exists or not
    op.execute("""
        ALTER TABLE users
        ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(500)
    """)


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS avatar_url")
