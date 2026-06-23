import uuid
import enum
from datetime import datetime
from typing import List
from sqlalchemy import String, DateTime, ForeignKey, Text, Float, Boolean, Enum, Integer, JSON
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from app.database import Base


class FacilityType(str, enum.Enum):
    forward_operating_base  = "forward_operating_base"
    main_operating_base     = "main_operating_base"
    combat_outpost          = "combat_outpost"
    checkpoint              = "checkpoint"
    logistics_depot         = "logistics_depot"
    medical_center          = "medical_center"
    command_center          = "command_center"
    communications_hub      = "communications_hub"
    armory                  = "armory"
    training_facility       = "training_facility"
    detention_center        = "detention_center"
    airfield                = "airfield"
    naval_facility          = "naval_facility"
    office                  = "office"
    border_post             = "border_post"
    safe_house              = "safe_house"
    intelligence_post       = "intelligence_post"
    barracks                = "barracks"
    supply_point            = "supply_point"
    other                   = "other"


class FacilityStatus(str, enum.Enum):
    active        = "active"
    inactive      = "inactive"
    decommissioned = "decommissioned"
    under_construction = "under_construction"


class FacilityVisibility(str, enum.Enum):
    # Who can see this post (beyond coordinator + planning_officer who always see all)
    all_personnel   = "all_personnel"      # field_user + team_leader can see on map when published
    planning_only   = "planning_only"      # only coord + planning (never on field map)
    assigned_teams  = "assigned_teams"     # only specific teams


class Post(Base):
    __tablename__ = "posts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    facility_type: Mapped[FacilityType] = mapped_column(Enum(FacilityType), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    mission: Mapped[str | None] = mapped_column(Text, nullable=True)      # what this facility does

    # Location
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    address: Mapped[str | None] = mapped_column(String(500), nullable=True)
    region: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # Status & visibility
    status: Mapped[FacilityStatus] = mapped_column(Enum(FacilityStatus), nullable=False, default=FacilityStatus.active)
    is_published: Mapped[bool] = mapped_column(Boolean, default=False)
    visibility: Mapped[FacilityVisibility] = mapped_column(Enum(FacilityVisibility), nullable=False, default=FacilityVisibility.all_personnel)

    # Metadata
    capacity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    commander_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    contact_info: Mapped[str | None] = mapped_column(String(500), nullable=True)
    classification: Mapped[str] = mapped_column(String(50), default="restricted")  # unclassified/restricted/confidential/secret

    # Teams that can see this (when visibility=assigned_teams) - stored as JSON list of team UUIDs
    allowed_team_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)

    # Users (planning_officers) granted edit access - list of user UUIDs
    editor_ids: Mapped[list | None] = mapped_column(JSON, nullable=True)

    # Audit
    created_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    updated_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)
