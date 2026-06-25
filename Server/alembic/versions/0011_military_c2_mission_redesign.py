"""Military C2 mission system redesign

Revision ID: 0011
Revises: 0010
Create Date: 2026-06-25
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision = '0011'
down_revision = '0010'
branch_labels = None
depends_on = None


def upgrade():
    # ── 0. Extend casualtytype enum ───────────────────────────────────────────
    op.execute(sa.text("ALTER TYPE casualtytype ADD VALUE IF NOT EXISTS 'captured'"))

    # ── 1. Extend missionstatus enum ─────────────────────────────────────────
    new_statuses = [
        'approved', 'assigned', 'pending_acknowledgement', 'briefing',
        'deploying', 'extraction', 'awaiting_review', 'debrief',
    ]
    for s in new_statuses:
        op.execute(sa.text(f"ALTER TYPE missionstatus ADD VALUE IF NOT EXISTS '{s}'"))

    # ── 2. Create new enum types (DO block = PG < 16 safe, idempotent) ───────
    for type_name, values in [
        ('missionpriority', "'critical','high','medium','low'"),
        ('acknowledgementstatus', "'pending','acknowledged'"),
        ('attendancestatus', "'present','absent','excused'"),
        ('reportcategory', "'contact','incident','intelligence','casualty','evidence'"),
    ]:
        op.execute(sa.text(f"""
            DO $$ BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = '{type_name}') THEN
                    CREATE TYPE {type_name} AS ENUM ({values});
                END IF;
            END $$
        """))

    # ── 3. New columns on missions (raw SQL = no SQLAlchemy type recreation) ─
    op.execute(sa.text(
        "ALTER TABLE missions ADD COLUMN IF NOT EXISTS mission_code VARCHAR(50)"
    ))
    op.execute(sa.text(
        "ALTER TABLE missions ADD COLUMN IF NOT EXISTS priority missionpriority DEFAULT 'medium'"
    ))
    op.execute(sa.text(
        "ALTER TABLE missions ADD COLUMN IF NOT EXISTS supporting_assets TEXT"
    ))
    op.execute(sa.text(
        "ALTER TABLE missions ADD COLUMN IF NOT EXISTS suspension_reason TEXT"
    ))
    op.execute(sa.text(
        "ALTER TABLE missions ADD COLUMN IF NOT EXISTS extraction_point JSONB"
    ))
    # unique constraint — ignore if already exists
    op.execute(sa.text("""
        DO $$ BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'uq_missions_mission_code'
            ) THEN
                ALTER TABLE missions ADD CONSTRAINT uq_missions_mission_code UNIQUE (mission_code);
            END IF;
        END $$
    """))

    # ── 4. New columns on mission_objectives ──────────────────────────────────
    op.execute(sa.text(
        "ALTER TABLE mission_objectives ADD COLUMN IF NOT EXISTS completed_by UUID REFERENCES users(id) ON DELETE SET NULL"
    ))
    op.execute(sa.text(
        "ALTER TABLE mission_objectives ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ"
    ))
    op.execute(sa.text(
        "ALTER TABLE mission_objectives ADD COLUMN IF NOT EXISTS completed_lat FLOAT"
    ))
    op.execute(sa.text(
        "ALTER TABLE mission_objectives ADD COLUMN IF NOT EXISTS completed_lng FLOAT"
    ))

    # ── 5. New columns on mission_incidents ───────────────────────────────────
    op.execute(sa.text(
        "ALTER TABLE mission_incidents ADD COLUMN IF NOT EXISTS report_category reportcategory DEFAULT 'incident'"
    ))
    op.execute(sa.text(
        "ALTER TABLE mission_incidents ADD COLUMN IF NOT EXISTS contact_size VARCHAR(200)"
    ))
    op.execute(sa.text(
        "ALTER TABLE mission_incidents ADD COLUMN IF NOT EXISTS contact_activity TEXT"
    ))
    op.execute(sa.text(
        "ALTER TABLE mission_incidents ADD COLUMN IF NOT EXISTS contact_unit VARCHAR(200)"
    ))
    op.execute(sa.text(
        "ALTER TABLE mission_incidents ADD COLUMN IF NOT EXISTS contact_equipment TEXT"
    ))

    # ── 6. New table: mission_acknowledgements ────────────────────────────────
    op.execute(sa.text("""
        CREATE TABLE IF NOT EXISTS mission_acknowledgements (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            mission_id UUID NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            status acknowledgementstatus NOT NULL DEFAULT 'pending',
            acknowledged_at TIMESTAMPTZ
        )
    """))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS ix_mission_acknowledgements_mission_id ON mission_acknowledgements(mission_id)"
    ))

    # ── 7. New table: mission_briefing_attendance ─────────────────────────────
    op.execute(sa.text("""
        CREATE TABLE IF NOT EXISTS mission_briefing_attendance (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            mission_id UUID NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            status attendancestatus NOT NULL DEFAULT 'absent',
            marked_by UUID REFERENCES users(id) ON DELETE SET NULL,
            marked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS ix_mission_briefing_attendance_mission_id ON mission_briefing_attendance(mission_id)"
    ))

    # ── 8. New table: mission_sitreps ─────────────────────────────────────────
    op.execute(sa.text("""
        CREATE TABLE IF NOT EXISTS mission_sitreps (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            mission_id UUID NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
            submitted_by UUID REFERENCES users(id) ON DELETE SET NULL,
            team_status TEXT,
            objective_progress TEXT,
            conditions TEXT,
            delays TEXT,
            risks TEXT,
            requests TEXT,
            submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS ix_mission_sitreps_mission_id ON mission_sitreps(mission_id)"
    ))

    # ── 9. New table: mission_completion_reports ──────────────────────────────
    op.execute(sa.text("""
        CREATE TABLE IF NOT EXISTS mission_completion_reports (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            mission_id UUID NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
            submitted_by UUID REFERENCES users(id) ON DELETE SET NULL,
            objective_summary TEXT,
            personnel_status TEXT,
            incident_summary TEXT,
            evidence_summary TEXT,
            recommendations TEXT,
            review_decision VARCHAR(20),
            review_notes TEXT,
            reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
            reviewed_at TIMESTAMPTZ,
            submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS ix_mission_completion_reports_mission_id ON mission_completion_reports(mission_id)"
    ))

    # ── 10. New table: mission_debrief_records ────────────────────────────────
    op.execute(sa.text("""
        CREATE TABLE IF NOT EXISTS mission_debrief_records (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            mission_id UUID NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
            submitted_by UUID REFERENCES users(id) ON DELETE SET NULL,
            lessons_learned TEXT,
            incident_review TEXT,
            evidence_review TEXT,
            team_feedback TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """))
    op.execute(sa.text(
        "CREATE INDEX IF NOT EXISTS ix_mission_debrief_records_mission_id ON mission_debrief_records(mission_id)"
    ))


def downgrade():
    op.execute(sa.text("DROP TABLE IF EXISTS mission_debrief_records"))
    op.execute(sa.text("DROP TABLE IF EXISTS mission_completion_reports"))
    op.execute(sa.text("DROP TABLE IF EXISTS mission_sitreps"))
    op.execute(sa.text("DROP TABLE IF EXISTS mission_briefing_attendance"))
    op.execute(sa.text("DROP TABLE IF EXISTS mission_acknowledgements"))

    for col in ['contact_equipment', 'contact_unit', 'contact_activity', 'contact_size', 'report_category']:
        op.execute(sa.text(f"ALTER TABLE mission_incidents DROP COLUMN IF EXISTS {col}"))

    for col in ['completed_lng', 'completed_lat', 'completed_at', 'completed_by']:
        op.execute(sa.text(f"ALTER TABLE mission_objectives DROP COLUMN IF EXISTS {col}"))

    for col in ['extraction_point', 'suspension_reason', 'supporting_assets', 'priority', 'mission_code']:
        op.execute(sa.text(f"ALTER TABLE missions DROP COLUMN IF EXISTS {col}"))

    op.execute(sa.text("DROP TYPE IF EXISTS reportcategory"))
    op.execute(sa.text("DROP TYPE IF EXISTS attendancestatus"))
    op.execute(sa.text("DROP TYPE IF EXISTS acknowledgementstatus"))
    op.execute(sa.text("DROP TYPE IF EXISTS missionpriority"))
