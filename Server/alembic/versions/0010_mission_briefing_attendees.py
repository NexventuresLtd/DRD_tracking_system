"""add briefing_attendees to missions

Revision ID: 0010
Revises: 0009
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision = '0010'
down_revision = '0009'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('missions', sa.Column('briefing_attendees', JSONB(), nullable=True))


def downgrade():
    op.drop_column('missions', 'briefing_attendees')
