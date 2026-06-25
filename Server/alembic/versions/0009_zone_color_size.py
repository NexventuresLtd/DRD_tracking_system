"""increase zone color column size to fit rgba hex colors

Revision ID: 0009
Revises: 0008
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade():
    op.alter_column("zones", "color", type_=sa.String(20), existing_nullable=False)
    op.alter_column("zones", "fill_color", type_=sa.String(20), existing_nullable=True)


def downgrade():
    op.alter_column("zones", "color", type_=sa.String(7), existing_nullable=False)
    op.alter_column("zones", "fill_color", type_=sa.String(7), existing_nullable=True)
