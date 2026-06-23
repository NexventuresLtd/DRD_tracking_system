"""add posts/facilities table

Revision ID: 0003
Revises: 0002
Create Date: 2026-06-24
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE facilitytype AS ENUM (
                'forward_operating_base','main_operating_base','combat_outpost',
                'checkpoint','logistics_depot','medical_center','command_center',
                'communications_hub','armory','training_facility','detention_center',
                'airfield','naval_facility','office','border_post','safe_house',
                'intelligence_post','barracks','supply_point','other'
            );
        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    """)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE facilitystatus AS ENUM (
                'active','inactive','decommissioned','under_construction'
            );
        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    """)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE facilityvisibility AS ENUM (
                'all_personnel','planning_only','assigned_teams'
            );
        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    """)

    op.create_table(
        "posts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("facility_type", sa.Enum("forward_operating_base","main_operating_base","combat_outpost","checkpoint","logistics_depot","medical_center","command_center","communications_hub","armory","training_facility","detention_center","airfield","naval_facility","office","border_post","safe_house","intelligence_post","barracks","supply_point","other", name="facilitytype"), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("mission", sa.Text, nullable=True),
        sa.Column("latitude", sa.Float, nullable=False),
        sa.Column("longitude", sa.Float, nullable=False),
        sa.Column("address", sa.String(500), nullable=True),
        sa.Column("region", sa.String(255), nullable=True),
        sa.Column("status", sa.Enum("active","inactive","decommissioned","under_construction", name="facilitystatus"), nullable=False, server_default="active"),
        sa.Column("is_published", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("visibility", sa.Enum("all_personnel","planning_only","assigned_teams", name="facilityvisibility"), nullable=False, server_default="all_personnel"),
        sa.Column("capacity", sa.Integer, nullable=True),
        sa.Column("commander_name", sa.String(255), nullable=True),
        sa.Column("contact_info", sa.String(500), nullable=True),
        sa.Column("classification", sa.String(50), nullable=False, server_default="'restricted'"),
        sa.Column("allowed_team_ids", postgresql.JSON, nullable=True),
        sa.Column("editor_ids", postgresql.JSON, nullable=True),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("updated_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_posts_facility_type", "posts", ["facility_type"])
    op.create_index("ix_posts_is_published", "posts", ["is_published"])
    op.create_index("ix_posts_status", "posts", ["status"])


def downgrade() -> None:
    op.drop_table("posts")
    op.execute("DROP TYPE IF EXISTS facilitytype")
    op.execute("DROP TYPE IF EXISTS facilitystatus")
    op.execute("DROP TYPE IF EXISTS facilityvisibility")
