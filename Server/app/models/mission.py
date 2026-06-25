import uuid
import enum
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Enum, ForeignKey, Text, Integer, JSON, Float
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class MissionStatus(str, enum.Enum):
    # Planning
    draft = "draft"
    approved = "approved"
    # Assignment
    assigned = "assigned"
    pending_acknowledgement = "pending_acknowledgement"
    # Execution
    briefing = "briefing"
    active = "active"
    deploying = "deploying"
    extraction = "extraction"
    # Closure
    suspended = "suspended"
    awaiting_review = "awaiting_review"
    debrief = "debrief"
    completed = "completed"
    archived = "archived"
    # Legacy (kept for backwards compat)
    planned = "planned"


class MissionPriority(str, enum.Enum):
    critical = "critical"
    high = "high"
    medium = "medium"
    low = "low"


class IncidentSeverity(str, enum.Enum):
    low = "low"
    medium = "medium"
    high = "high"
    critical = "critical"


class ReportCategory(str, enum.Enum):
    contact = "contact"
    incident = "incident"
    intelligence = "intelligence"
    casualty = "casualty"
    evidence = "evidence"


class CasualtyType(str, enum.Enum):
    KIA = "KIA"
    WIA = "WIA"
    MIA = "MIA"
    CAPTURED = "captured"


class AttendanceStatus(str, enum.Enum):
    present = "present"
    absent = "absent"
    excused = "excused"


class AcknowledgementStatus(str, enum.Enum):
    pending = "pending"
    acknowledged = "acknowledged"


class Mission(Base):
    __tablename__ = "missions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    mission_code: Mapped[str | None] = mapped_column(String(50), nullable=True, unique=True, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[MissionStatus] = mapped_column(Enum(MissionStatus, name="missionstatus"), default=MissionStatus.draft)
    priority: Mapped[MissionPriority] = mapped_column(Enum(MissionPriority, name="missionpriority"), default=MissionPriority.medium)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    start_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    end_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    area_of_operations: Mapped[str | None] = mapped_column(String(500), nullable=True)
    supporting_assets: Mapped[str | None] = mapped_column(Text, nullable=True)
    suspension_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    extraction_point: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    # Briefing
    briefing_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    briefing_datetime: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    briefing_audience: Mapped[str | None] = mapped_column(String(50), nullable=True, default="all")
    briefing_attendees: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    # Resources
    zone_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)
    route_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)
    facility_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)
    live_session_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("live_sessions.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    objectives: Mapped[list["MissionObjective"]] = relationship("MissionObjective", back_populates="mission", cascade="all, delete-orphan", order_by="MissionObjective.order_index")
    assignments: Mapped[list["MissionAssignment"]] = relationship("MissionAssignment", back_populates="mission", cascade="all, delete-orphan")
    incidents: Mapped[list["MissionIncident"]] = relationship("MissionIncident", back_populates="mission", cascade="all, delete-orphan")
    casualties: Mapped[list["CasualtyReport"]] = relationship("CasualtyReport", back_populates="mission", cascade="all, delete-orphan")
    acknowledgements: Mapped[list["MissionAcknowledgement"]] = relationship("MissionAcknowledgement", back_populates="mission", cascade="all, delete-orphan")
    attendance_records: Mapped[list["MissionBriefingAttendance"]] = relationship("MissionBriefingAttendance", back_populates="mission", cascade="all, delete-orphan")
    sitreps: Mapped[list["MissionSitrep"]] = relationship("MissionSitrep", back_populates="mission", cascade="all, delete-orphan")
    completion_reports: Mapped[list["MissionCompletionReport"]] = relationship("MissionCompletionReport", back_populates="mission", cascade="all, delete-orphan")
    debrief_records: Mapped[list["MissionDebriefRecord"]] = relationship("MissionDebriefRecord", back_populates="mission", cascade="all, delete-orphan")


class MissionObjective(Base):
    __tablename__ = "mission_objectives"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    order_index: Mapped[int] = mapped_column(Integer, default=0)
    # Direct link to a specific zone, route, or facility for this objective step
    zone_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("zones.id", ondelete="SET NULL"), nullable=True)
    route_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("routes.id", ondelete="SET NULL"), nullable=True)
    facility_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("posts.id", ondelete="SET NULL"), nullable=True)
    # Completion tracking (set by team leader)
    completed_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    completed_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="objectives")


class MissionAssignment(Base):
    __tablename__ = "mission_assignments"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    team_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("teams.id", ondelete="CASCADE"), nullable=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=True)
    role_in_mission: Mapped[str | None] = mapped_column(String(100), nullable=True)
    assigned_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    assigned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="assignments")


class MissionAcknowledgement(Base):
    __tablename__ = "mission_acknowledgements"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    status: Mapped[AcknowledgementStatus] = mapped_column(Enum(AcknowledgementStatus, name="acknowledgementstatus"), default=AcknowledgementStatus.pending)
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="acknowledgements")


class MissionBriefingAttendance(Base):
    __tablename__ = "mission_briefing_attendance"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    status: Mapped[AttendanceStatus] = mapped_column(Enum(AttendanceStatus, name="attendancestatus"), default=AttendanceStatus.absent)
    marked_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    marked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="attendance_records")


class MissionSitrep(Base):
    __tablename__ = "mission_sitreps"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    submitted_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    team_status: Mapped[str | None] = mapped_column(Text, nullable=True)
    objective_progress: Mapped[str | None] = mapped_column(Text, nullable=True)
    conditions: Mapped[str | None] = mapped_column(Text, nullable=True)
    delays: Mapped[str | None] = mapped_column(Text, nullable=True)
    risks: Mapped[str | None] = mapped_column(Text, nullable=True)
    requests: Mapped[str | None] = mapped_column(Text, nullable=True)
    submitted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="sitreps")


class MissionCompletionReport(Base):
    __tablename__ = "mission_completion_reports"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    submitted_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    objective_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    personnel_status: Mapped[str | None] = mapped_column(Text, nullable=True)
    incident_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    evidence_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    recommendations: Mapped[str | None] = mapped_column(Text, nullable=True)
    review_decision: Mapped[str | None] = mapped_column(String(20), nullable=True)
    review_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    submitted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="completion_reports")


class MissionDebriefRecord(Base):
    __tablename__ = "mission_debrief_records"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    submitted_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    lessons_learned: Mapped[str | None] = mapped_column(Text, nullable=True)
    incident_review: Mapped[str | None] = mapped_column(Text, nullable=True)
    evidence_review: Mapped[str | None] = mapped_column(Text, nullable=True)
    team_feedback: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="debrief_records")


class MissionIncident(Base):
    __tablename__ = "mission_incidents"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    reported_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    report_category: Mapped[ReportCategory] = mapped_column(Enum(ReportCategory, name="reportcategory"), default=ReportCategory.incident)
    incident_type: Mapped[str] = mapped_column(String(50), nullable=False, default="patrol_report")
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    severity: Mapped[IncidentSeverity] = mapped_column(Enum(IncidentSeverity), default=IncidentSeverity.medium)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    # SALUTE fields for contact reports
    contact_size: Mapped[str | None] = mapped_column(String(200), nullable=True)
    contact_activity: Mapped[str | None] = mapped_column(Text, nullable=True)
    contact_unit: Mapped[str | None] = mapped_column(String(200), nullable=True)
    contact_equipment: Mapped[str | None] = mapped_column(Text, nullable=True)
    ref_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    ref_type: Mapped[str | None] = mapped_column(String(50), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="incidents")


class CasualtyReport(Base):
    __tablename__ = "casualty_reports"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    mission_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("missions.id", ondelete="CASCADE"), nullable=False, index=True)
    reported_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    casualty_type: Mapped[CasualtyType] = mapped_column(Enum(CasualtyType), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    evidence_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("evidence.id", ondelete="SET NULL"), nullable=True)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    mission: Mapped["Mission"] = relationship("Mission", back_populates="casualties")
