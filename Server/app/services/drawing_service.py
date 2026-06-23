import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.drawing import Drawing, DrawingType, DrawingPoint


class DrawingService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, data: dict, created_by: uuid.UUID) -> Drawing:
        drawing = Drawing(
            name=data.get("name"),
            drawing_type=DrawingType(data["drawing_type"]),
            color=data.get("color", "#ef4444"),
            fill_color=data.get("fill_color"),
            stroke_width=data.get("stroke_width", 2.0),
            opacity=data.get("opacity", 1.0),
            radius=data.get("radius"),
            notes=data.get("notes"),
            mission_id=data.get("mission_id"),
            created_by=created_by,
        )
        self.db.add(drawing)
        await self.db.flush()

        for i, pt in enumerate(data.get("points", [])):
            self.db.add(DrawingPoint(
                drawing_id=drawing.id,
                order_index=i,
                latitude=pt["latitude"],
                longitude=pt["longitude"],
            ))

        await self.db.commit()
        await self.db.refresh(drawing)
        return drawing

    async def get_by_id(self, drawing_id: uuid.UUID) -> Optional[Drawing]:
        result = await self.db.execute(
            select(Drawing).options(selectinload(Drawing.points)).where(Drawing.id == drawing_id)
        )
        return result.scalar_one_or_none()

    async def list_drawings(self, mission_id: Optional[uuid.UUID] = None):
        q = select(Drawing).options(selectinload(Drawing.points))
        if mission_id:
            q = q.where(Drawing.mission_id == mission_id)
        q = q.order_by(Drawing.created_at.desc())
        result = await self.db.execute(q)
        return result.scalars().all()

    async def delete(self, drawing_id: uuid.UUID) -> bool:
        drawing = await self.get_by_id(drawing_id)
        if not drawing:
            return False
        await self.db.delete(drawing)
        await self.db.commit()
        return True
