"""mission incidents, casualty reports, live session invite, evidence approval

Revision ID: 0006
Revises: 0005
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    # live_sessions: add invite_list, is_recording, recorded_url
    op.add_column("live_sessions", sa.Column("invite_list", postgresql.JSONB(), nullable=True))
    op.add_column("live_sessions", sa.Column("is_recording", sa.Boolean(), nullable=False, server_default="false"))
    op.add_column("live_sessions", sa.Column("recorded_url", sa.String(1000), nullable=True))

    # missions: add facility_ids, live_session_id, drop video_call_url
    op.add_column("missions", sa.Column("facility_ids", sa.JSON(), nullable=True))
    op.add_column("missions", sa.Column(
        "live_session_id",
        postgresql.UUID(as_uuid=True),
        sa.ForeignKey("live_sessions.id", ondelete="SET NULL"),
        nullable=True,
    ))
    # keep video_call_url col but it's no longer used in code

    # evidence: add approval fields
    op.add_column("evidence", sa.Column("approval_status", sa.String(20), nullable=False, server_default="pending"))
    op.add_column("evidence", sa.Column(
        "approved_by",
        postgresql.UUID(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    ))
    op.add_column("evidence", sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True))

    # mission_incidents table
    op.create_table(
        "mission_incidents",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("mission_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("reported_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("incident_type", sa.String(50), nullable=False, server_default="patrol_report"),
        sa.Column("title", sa.String(500), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("severity", sa.Enum("low", "medium", "high", "critical", name="incidentseverity"), nullable=False, server_default="medium"),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("ref_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("ref_type", sa.String(50), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="open"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # casualty_reports table
    op.create_table(
        "casualty_reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("mission_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("reported_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("casualty_type", sa.Enum("KIA", "WIA", "MIA", name="casualtytype"), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("evidence_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("evidence.id", ondelete="SET NULL"), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade():
    op.drop_table("casualty_reports")
    op.drop_table("mission_incidents")
    op.drop_column("evidence", "approved_at")
    op.drop_column("evidence", "approved_by")
    op.drop_column("evidence", "approval_status")
    op.drop_column("missions", "live_session_id")
    op.drop_column("missions", "facility_ids")
    op.drop_column("live_sessions", "recorded_url")
    op.drop_column("live_sessions", "is_recording")
    op.drop_column("live_sessions", "invite_list")
