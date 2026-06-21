"""add profile_picture_url to users

Revision ID: c3d4e5f6g7h8
Revises: a1b2c3d4e5f6
Create Date: 2026-06-21 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = 'c3d4e5f6g7h8'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.add_column('users', sa.Column('profile_picture_url', sa.String(500), nullable=True))

def downgrade() -> None:
    op.drop_column('users', 'profile_picture_url')
