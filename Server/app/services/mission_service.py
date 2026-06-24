import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.mission import Mission, MissionStatus, MissionObjective, MissionAssignment


class MissionService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, data: dict, created_by: uuid.UUID) -> Mission:
        mission = Mission(
            name=data["name"],
            description=data.get("description"),
            status=MissionStatus(data.get("status", "draft")),
            created_by=created_by,
            start_date=data.get("start_date"),
            end_date=data.get("end_date"),
            briefing_notes=data.get("briefing_notes"),
            area_of_operations=data.get("area_of_operations"),
            briefing_datetime=data.get("briefing_datetime"),
            briefing_audience=data.get("briefing_audience", "all"),
            zone_ids=data.get("zone_ids", []),
            route_ids=data.get("route_ids", []),
            facility_ids=data.get("facility_ids", []),
        )
        self.db.add(mission)
        await self.db.flush()

        for i, obj in enumerate(data.get("objectives", [])):
            self.db.add(MissionObjective(
                mission_id=mission.id,
                title=obj["title"],
                description=obj.get("description"),
                order_index=i,
            ))

        await self.db.commit()
        await self.db.refresh(mission)
        return mission

    async def get_by_id(self, mission_id: uuid.UUID) -> Optional[Mission]:
        result = await self.db.execute(
            select(Mission)
            .options(
                selectinload(Mission.objectives),
                selectinload(Mission.assignments),
                selectinload(Mission.incidents),
                selectinload(Mission.casualties),
            )
            .where(Mission.id == mission_id)
        )
        return result.scalar_one_or_none()

    async def list_missions(self, status: Optional[str] = None, limit: int = 50, offset: int = 0):
        q = select(Mission).options(selectinload(Mission.objectives), selectinload(Mission.assignments))
        if status:
            q = q.where(Mission.status == MissionStatus(status))
        q = q.order_by(Mission.created_at.desc()).offset(offset).limit(limit)
        result = await self.db.execute(q)
        return result.scalars().all()

    async def update(self, mission_id: uuid.UUID, data: dict) -> Optional[Mission]:
        mission = await self.get_by_id(mission_id)
        if not mission:
            return None
        for field in ("name", "description", "briefing_notes", "area_of_operations",
                      "start_date", "end_date", "briefing_datetime",
                      "briefing_audience", "zone_ids", "route_ids", "facility_ids", "live_session_id"):
            if field in data:
                setattr(mission, field, data[field])
        if "status" in data:
            mission.status = MissionStatus(data["status"])
        mission.updated_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(mission)
        return mission

    async def delete(self, mission_id: uuid.UUID) -> bool:
        mission = await self.get_by_id(mission_id)
        if not mission:
            return False
        await self.db.delete(mission)
        await self.db.commit()
        return True

    async def add_assignment(self, mission_id: uuid.UUID, data: dict, assigned_by: uuid.UUID) -> MissionAssignment:
        assignment = MissionAssignment(
            mission_id=mission_id,
            team_id=data.get("team_id"),
            user_id=data.get("user_id"),
            role_in_mission=data.get("role_in_mission"),
            assigned_by=assigned_by,
        )
        self.db.add(assignment)
        await self.db.commit()
        await self.db.refresh(assignment)
        return assignment

    async def complete_objective(self, objective_id: uuid.UUID) -> bool:
        result = await self.db.execute(select(MissionObjective).where(MissionObjective.id == objective_id))
        obj = result.scalar_one_or_none()
        if not obj:
            return False
        obj.is_completed = True
        await self.db.commit()
        return True
