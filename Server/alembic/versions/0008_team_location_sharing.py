"""add location_sharing to teams

Revision ID: 0008
Revises: 0007
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("teams", sa.Column("location_sharing", sa.Boolean(), nullable=False, server_default="false"))


def downgrade():
    op.drop_column("teams", "location_sharing")
