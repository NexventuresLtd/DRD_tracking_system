"""evidence poi link

Revision ID: 0013
Revises: 0012
Create Date: 2026-06-25
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "evidence",
        sa.Column(
            "poi_id",
            UUID(as_uuid=True),
            sa.ForeignKey("pois.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.create_index("ix_evidence_poi_id", "evidence", ["poi_id"])
    op.create_index("ix_evidence_mission_id", "evidence", ["mission_id"])


def downgrade():
    op.drop_index("ix_evidence_mission_id", table_name="evidence")
    op.drop_index("ix_evidence_poi_id", table_name="evidence")
    op.drop_column("evidence", "poi_id")
