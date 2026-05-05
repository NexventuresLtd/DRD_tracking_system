from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from math import asin, cos, pi, sin, sqrt
from typing import Iterable, Optional
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import and_, desc, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.location import Location
from app.models.route import Route
from app.models.route_follow import RouteFollowPoint, RouteFollowSession
from app.models.user import User, UserRole
from app.websocket.manager import manager


@dataclass(frozen=True)
class RouteProgressSnapshot:
    current_waypoint_index: int
    progress_percent: float
    distance_to_destination_m: Optional[float]
    eta_seconds: Optional[int]


class RouteFollowService:
    """Route follow session persistence and progress tracking."""

    def __init__(self, db: AsyncSession):
        self.db = db

    @staticmethod
    def _distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
        radius = 6371000.0
        d_lat = (lat2 - lat1) * pi / 180
        d_lng = (lng2 - lng1) * pi / 180
        lat1_rad = lat1 * pi / 180
        lat2_rad = lat2 * pi / 180
        a = (
            sin(d_lat / 2) ** 2
            + cos(lat1_rad) * cos(lat2_rad) * sin(d_lng / 2) ** 2
        )
        return 2 * radius * asin(min(1.0, sqrt(a)))

    def _route_length_meters(self, waypoints: list[dict]) -> float:
        if len(waypoints) < 2:
            return 0.0
        total = 0.0
        for current, nxt in zip(waypoints, waypoints[1:]):
            total += self._distance_meters(
                float(current["latitude"]),
                float(current["longitude"]),
                float(nxt["latitude"]),
                float(nxt["longitude"]),
            )
        return total

    def _progress_snapshot(
        self,
        waypoints: list[dict],
        latitude: float,
        longitude: float,
        speed_kmh: Optional[float],
    ) -> RouteProgressSnapshot:
        if not waypoints:
            return RouteProgressSnapshot(0, 0.0, None, None)

        destination = waypoints[-1]
        distance_to_destination_m = self._distance_meters(
            latitude,
            longitude,
            float(destination["latitude"]),
            float(destination["longitude"]),
        )

        route_length = self._route_length_meters(waypoints)
        if route_length <= 0:
            progress_percent = 0.0
        else:
            progress_percent = max(0.0, min(100.0, (1 - (distance_to_destination_m / route_length)) * 100.0))

        threshold_m = 50.0
        current_waypoint_index = 0
        for index, waypoint in enumerate(waypoints):
            waypoint_distance = self._distance_meters(
                latitude,
                longitude,
                float(waypoint["latitude"]),
                float(waypoint["longitude"]),
            )
            if waypoint_distance <= threshold_m:
                current_waypoint_index = index + 1

        eta_seconds = None
        if speed_kmh and speed_kmh > 0:
            eta_seconds = int((distance_to_destination_m / (speed_kmh * 1000 / 3600)))

        return RouteProgressSnapshot(
            current_waypoint_index=min(current_waypoint_index, max(0, len(waypoints) - 1)),
            progress_percent=round(progress_percent, 2),
            distance_to_destination_m=round(distance_to_destination_m, 2),
            eta_seconds=eta_seconds,
        )

    @staticmethod
    def _waypoint_payload(route: Route) -> list[dict]:
        return [
            {
                "id": str(waypoint.id),
                "sequence_order": waypoint.sequence_order,
                "latitude": waypoint.latitude,
                "longitude": waypoint.longitude,
                "label": waypoint.label,
                "poi_type": waypoint.poi_type,
            }
            for waypoint in route.waypoints
        ]

    async def _load_route(self, route_id: UUID) -> Route:
        result = await self.db.execute(
            select(Route)
            .options(selectinload(Route.waypoints))
            .where(Route.id == route_id)
        )
        route = result.scalar_one_or_none()
        if not route:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Route not found")
        return route

    def _session_query(self, *, user_id: Optional[UUID] = None, route_id: Optional[UUID] = None, team_id: Optional[UUID] = None, status: Optional[str] = "active"):
        query = select(RouteFollowSession)
        if status is not None:
            query = query.where(RouteFollowSession.status == status)
        if user_id is not None:
            query = query.where(RouteFollowSession.user_id == user_id)
        if route_id is not None:
            query = query.where(RouteFollowSession.route_id == route_id)
        if team_id is not None:
            query = query.where(RouteFollowSession.team_id == team_id)
        return query.order_by(RouteFollowSession.started_at.desc())

    async def get_active_session_for_user(self, user_id: UUID) -> Optional[RouteFollowSession]:
        # Keep lookup deterministic even if legacy data contains more than one
        # active row for a user.
        result = await self.db.execute(
            self._session_query(user_id=user_id).limit(1)
        )
        return result.scalar_one_or_none()

    async def get_session_by_id(self, session_id: UUID) -> Optional[RouteFollowSession]:
        result = await self.db.execute(
            select(RouteFollowSession).where(RouteFollowSession.id == session_id)
        )
        return result.scalar_one_or_none()

    async def list_sessions(
        self,
        *,
        route_id: Optional[UUID] = None,
        user_id: Optional[UUID] = None,
        team_id: Optional[UUID] = None,
        status: Optional[str] = "active",
    ) -> list[RouteFollowSession]:
        result = await self.db.execute(
            self._session_query(user_id=user_id, route_id=route_id, team_id=team_id, status=status)
        )
        return result.scalars().all()

    async def start_follow(
        self,
        *,
        route_id: UUID,
        current_user: User,
        current_latitude: Optional[float] = None,
        current_longitude: Optional[float] = None,
    ) -> RouteFollowSession:
        route = await self._load_route(route_id)

        existing = await self.get_active_session_for_user(current_user.id)
        if existing and existing.route_id == route.id:
            return existing
        if existing and existing.route_id != route.id:
            existing.status = "stopped"
            existing.ended_at = datetime.now(timezone.utc)

        route_waypoints = self._waypoint_payload(route)
        if not route_waypoints:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Route has no waypoints")

        session = RouteFollowSession(
            route_id=route.id,
            user_id=current_user.id,
            team_id=route.assigned_team_id or getattr(current_user, "team_id", None),
            status="active",
            route_name_snapshot=route.name,
            route_description_snapshot=route.description,
            route_color_snapshot=route.color,
            waypoints_snapshot=route_waypoints,
            start_latitude=current_latitude,
            start_longitude=current_longitude,
            last_latitude=current_latitude,
            last_longitude=current_longitude,
            last_recorded_at=datetime.now(timezone.utc),
        )
        self.db.add(session)
        await self.db.flush()

        if current_latitude is not None and current_longitude is not None:
            snapshot = self._progress_snapshot(route_waypoints, current_latitude, current_longitude, None)
            session.current_waypoint_index = snapshot.current_waypoint_index
            session.progress_percent = snapshot.progress_percent
            session.distance_to_destination_m = snapshot.distance_to_destination_m
            session.eta_seconds = snapshot.eta_seconds

            point = RouteFollowPoint(
                session_id=session.id,
                route_id=route.id,
                user_id=current_user.id,
                latitude=current_latitude,
                longitude=current_longitude,
                recorded_at=datetime.now(timezone.utc),
            )
            self.db.add(point)

        await self.db.commit()
        await self.db.refresh(session)
        return session

    async def stop_follow(self, session_id: UUID, current_user: User, note: Optional[str] = None) -> RouteFollowSession:
        result = await self.db.execute(
            select(RouteFollowSession).where(RouteFollowSession.id == session_id)
        )
        session = result.scalar_one_or_none()
        if not session:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Follow session not found")

        if session.user_id != current_user.id and current_user.role not in {
            UserRole.SUPER_ADMIN,
            UserRole.ADMIN,
            UserRole.COMMANDER,
            UserRole.OPERATOR,
        }:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to stop this session")

        session.status = "stopped"
        session.ended_at = datetime.now(timezone.utc)
        if note:
            session.completion_note = note

        await self.db.commit()
        await self.db.refresh(session)
        return session

    async def complete_follow(self, session_id: UUID, current_user: User, note: Optional[str] = None) -> RouteFollowSession:
        if current_user.role not in {
            UserRole.SUPER_ADMIN,
            UserRole.ADMIN,
            UserRole.COMMANDER,
            UserRole.OPERATOR,
        }:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to complete follow sessions")

        result = await self.db.execute(
            select(RouteFollowSession).where(RouteFollowSession.id == session_id)
        )
        session = result.scalar_one_or_none()
        if not session:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Follow session not found")

        session.status = "completed"
        session.ended_at = datetime.now(timezone.utc)
        if note:
            session.completion_note = note
        session.progress_percent = 100.0
        session.current_waypoint_index = max(session.current_waypoint_index, len(session.waypoints_snapshot or []))

        result_route = await self.db.execute(
            select(Route).where(Route.id == session.route_id)
        )
        route = result_route.scalar_one_or_none()
        if route:
            route.is_active = False

        await self.db.commit()
        await self.db.refresh(session)
        return session

    async def record_location(self, *, user_id: UUID, location: Location) -> Optional[RouteFollowSession]:
        session = await self.get_active_session_for_user(user_id)
        if not session:
            return None

        waypoints = session.waypoints_snapshot or []
        snapshot = self._progress_snapshot(
            waypoints,
            float(location.latitude),
            float(location.longitude),
            float(location.speed) if location.speed is not None else None,
        )

        session.last_latitude = location.latitude
        session.last_longitude = location.longitude
        session.current_waypoint_index = snapshot.current_waypoint_index
        session.progress_percent = snapshot.progress_percent
        session.distance_to_destination_m = snapshot.distance_to_destination_m
        session.eta_seconds = snapshot.eta_seconds
        session.last_recorded_at = location.recorded_at

        point = RouteFollowPoint(
            session_id=session.id,
            route_id=session.route_id,
            user_id=user_id,
            latitude=location.latitude,
            longitude=location.longitude,
            altitude=location.altitude,
            speed=location.speed,
            heading=location.heading,
            accuracy=location.accuracy,
            battery_level=location.battery_level,
            recorded_at=location.recorded_at,
        )
        self.db.add(point)
        await self.db.commit()
        await self.db.refresh(session)
        return session

    async def get_session_trail(self, session_id: UUID, limit: int = 100) -> list[RouteFollowPoint]:
        return await self.recent_trail(session_id, limit=limit)

    async def recent_trail(self, session_id: UUID, limit: int = 100) -> list[RouteFollowPoint]:
        result = await self.db.execute(
            select(RouteFollowPoint)
            .where(RouteFollowPoint.session_id == session_id)
            .order_by(desc(RouteFollowPoint.recorded_at))
            .limit(limit)
        )
        return result.scalars().all()

    async def broadcast_session_update(self, session: RouteFollowSession, event_type: str) -> None:
        suffix = event_type.removeprefix("route_follow_").replace("_", " ")
        payload = {
            "id": str(session.id),
            "event_type": event_type,
            "route_id": str(session.route_id),
            "user_id": str(session.user_id),
            "team_id": str(session.team_id) if session.team_id else None,
            "description": f"Route follow {suffix}: {session.route_name_snapshot}",
            "status": session.status,
            "route_name_snapshot": session.route_name_snapshot,
            "route_color_snapshot": session.route_color_snapshot,
            "progress_percent": session.progress_percent,
            "current_waypoint_index": session.current_waypoint_index,
            "distance_to_destination_m": session.distance_to_destination_m,
            "eta_seconds": session.eta_seconds,
            "last_latitude": session.last_latitude,
            "last_longitude": session.last_longitude,
            "last_recorded_at": session.last_recorded_at.isoformat() if session.last_recorded_at else None,
            "started_at": session.started_at.isoformat() if session.started_at else None,
            "updated_at": session.updated_at.isoformat() if session.updated_at else None,
            "ended_at": session.ended_at.isoformat() if session.ended_at else None,
        }
        try:
            await manager.broadcast_event(payload)
        except Exception:
            pass
