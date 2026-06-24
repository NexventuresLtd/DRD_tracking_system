"""zone assignments, team-zone linking, facility threat level and commander user

Revision ID: 0004
Revises: 0003
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── Extend zones ────────────────────────────────────────────────────────
    op.add_column("zones", sa.Column("team_id", postgresql.UUID(as_uuid=True),
        sa.ForeignKey("teams.id", ondelete="SET NULL"), nullable=True))
    op.add_column("zones", sa.Column("shape", sa.String(20), nullable=False, server_default="polygon"))
    op.add_column("zones", sa.Column("assignment_status", sa.String(20), nullable=False, server_default="draft"))
    op.create_index("ix_zones_team_id", "zones", ["team_id"])

    # ── zone_assignments ─────────────────────────────────────────────────────
    op.create_table(
        "zone_assignments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("zone_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("zones.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("point_index", sa.Integer, nullable=True),
        sa.Column("point_lat", sa.Float, nullable=False),
        sa.Column("point_lon", sa.Float, nullable=False),
        sa.Column("label", sa.String(100), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("assigned_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("assigned_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("arrived_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notes", sa.Text, nullable=True),
        sa.UniqueConstraint("zone_id", "user_id", name="uq_zone_user"),
    )
    op.create_index("ix_zone_assignments_zone_id", "zone_assignments", ["zone_id"])
    op.create_index("ix_zone_assignments_user_id", "zone_assignments", ["user_id"])

    # ── Extend posts ─────────────────────────────────────────────────────────
    op.add_column("posts", sa.Column("threat_level", sa.String(10), nullable=False, server_default="green"))
    op.add_column("posts", sa.Column("commander_user_id", postgresql.UUID(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True))


def downgrade() -> None:
    op.drop_column("posts", "commander_user_id")
    op.drop_column("posts", "threat_level")
    op.drop_index("ix_zone_assignments_user_id", "zone_assignments")
    op.drop_index("ix_zone_assignments_zone_id", "zone_assignments")
    op.drop_table("zone_assignments")
    op.drop_index("ix_zones_team_id", "zones")
    op.drop_column("zones", "assignment_status")
    op.drop_column("zones", "shape")
    op.drop_column("zones", "team_id")
