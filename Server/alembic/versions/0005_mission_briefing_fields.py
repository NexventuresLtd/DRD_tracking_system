"""add mission briefing, video call, zone/route ids

Revision ID: 0005
Revises: 0004
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("missions", sa.Column("briefing_datetime", sa.DateTime(timezone=True), nullable=True))
    op.add_column("missions", sa.Column("video_call_url", sa.String(1000), nullable=True))
    op.add_column("missions", sa.Column("briefing_audience", sa.String(50), nullable=True, server_default="all"))
    op.add_column("missions", sa.Column("zone_ids", sa.JSON(), nullable=True))
    op.add_column("missions", sa.Column("route_ids", sa.JSON(), nullable=True))


def downgrade():
    op.drop_column("missions", "route_ids")
    op.drop_column("missions", "zone_ids")
    op.drop_column("missions", "briefing_audience")
    op.drop_column("missions", "video_call_url")
    op.drop_column("missions", "briefing_datetime")
