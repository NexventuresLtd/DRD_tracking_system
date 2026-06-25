"""Per-objective zone/route/facility linking

Revision ID: 0012
Revises: 0011
Create Date: 2026-06-25
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = '0012'
down_revision = '0011'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('mission_objectives', sa.Column('zone_id',     UUID(as_uuid=True), sa.ForeignKey('zones.id', ondelete='SET NULL'), nullable=True))
    op.add_column('mission_objectives', sa.Column('route_id',    UUID(as_uuid=True), sa.ForeignKey('routes.id', ondelete='SET NULL'), nullable=True))
    op.add_column('mission_objectives', sa.Column('facility_id', UUID(as_uuid=True), sa.ForeignKey('posts.id', ondelete='SET NULL'), nullable=True))


def downgrade():
    op.drop_column('mission_objectives', 'zone_id')
    op.drop_column('mission_objectives', 'route_id')
    op.drop_column('mission_objectives', 'facility_id')
