import json
from typing import Optional
from fastapi import WebSocket
from collections import defaultdict


class ConnectionManager:
    """
    Supports multiple simultaneous WebSocket connections per user (one per room).
    Keys in `active` are "{user_id}:{room}" so the same user can hold connections
    to /ws/events, /ws/location/…, and /ws/notifications/… concurrently without
    them overwriting each other.
    """

    def __init__(self):
        self.active: dict[str, WebSocket] = {}          # "{user_id}:{room}" → socket
        self.rooms: dict[str, set[str]] = defaultdict(set)  # room → set of user_ids

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _key(self, user_id: str, room: Optional[str]) -> str:
        return f"{user_id}:{room or 'default'}"

    def _uid(self, key: str) -> str:
        return key.split(":", 1)[0]

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    async def connect(self, websocket: WebSocket, user_id: str, room: Optional[str] = None) -> None:
        await websocket.accept()
        self.active[self._key(user_id, room)] = websocket
        if room:
            self.rooms[room].add(user_id)

    def disconnect(self, user_id: str, room: Optional[str] = None) -> None:
        self.active.pop(self._key(user_id, room), None)
        if room:
            self.rooms[room].discard(user_id)

    # ── Sending ───────────────────────────────────────────────────────────────

    async def send_to(self, user_id: str, data: dict) -> None:
        """Send to every active connection belonging to this user."""
        payload = json.dumps(data)
        dead = []
        for key, ws in list(self.active.items()):
            if self._uid(key) == user_id:
                try:
                    await ws.send_text(payload)
                except Exception:
                    dead.append(key)
        for key in dead:
            self.active.pop(key, None)

    async def broadcast(self, data: dict, room: Optional[str] = None) -> None:
        """Broadcast to a room, or to every active connection if room is None."""
        payload = json.dumps(data)
        if room:
            keys = [self._key(uid, room) for uid in list(self.rooms.get(room, set()))]
        else:
            keys = list(self.active.keys())

        dead = []
        for key in keys:
            ws = self.active.get(key)
            if ws:
                try:
                    await ws.send_text(payload)
                except Exception:
                    dead.append(key)
        for key in dead:
            self.active.pop(key, None)
            uid = self._uid(key)
            for r, s in self.rooms.items():
                if self._key(uid, r) == key:
                    s.discard(uid)

    async def broadcast_to_room(self, room: str, data: dict, exclude: Optional[str] = None) -> None:
        """Broadcast to all users in a room, optionally skipping one user_id."""
        payload = json.dumps(data)
        dead = []
        for uid in list(self.rooms.get(room, set())):
            if uid == exclude:
                continue
            key = self._key(uid, room)
            ws = self.active.get(key)
            if ws:
                try:
                    await ws.send_text(payload)
                except Exception:
                    dead.append((uid, key))
        for uid, key in dead:
            self.active.pop(key, None)
            self.rooms[room].discard(uid)

    # ── Queries ───────────────────────────────────────────────────────────────

    def is_online(self, user_id: str) -> bool:
        return any(self._uid(k) == user_id for k in self.active)

    def is_in_room(self, user_id: str, room: str) -> bool:
        return user_id in self.rooms.get(room, set())

    def get_online_count(self) -> int:
        return len({self._uid(k) for k in self.active})


manager = ConnectionManager()
