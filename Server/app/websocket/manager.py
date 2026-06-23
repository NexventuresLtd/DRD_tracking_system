import json
import asyncio
from typing import Optional
from fastapi import WebSocket
from collections import defaultdict


class ConnectionManager:
    def __init__(self):
        self.active: dict[str, WebSocket] = {}
        self.rooms: dict[str, set[str]] = defaultdict(set)

    async def connect(self, websocket: WebSocket, user_id: str, room: Optional[str] = None) -> None:
        await websocket.accept()
        self.active[user_id] = websocket
        if room:
            self.rooms[room].add(user_id)

    def disconnect(self, user_id: str, room: Optional[str] = None) -> None:
        self.active.pop(user_id, None)
        if room:
            self.rooms[room].discard(user_id)

    async def send_to(self, user_id: str, data: dict) -> None:
        ws = self.active.get(user_id)
        if ws:
            try:
                await ws.send_text(json.dumps(data))
            except Exception:
                self.active.pop(user_id, None)

    async def broadcast(self, data: dict, room: Optional[str] = None) -> None:
        payload = json.dumps(data)
        if room:
            targets = list(self.rooms.get(room, set()))
        else:
            targets = list(self.active.keys())

        dead = []
        for uid in targets:
            ws = self.active.get(uid)
            if ws:
                try:
                    await ws.send_text(payload)
                except Exception:
                    dead.append(uid)

        for uid in dead:
            self.active.pop(uid, None)
            if room:
                self.rooms[room].discard(uid)

    async def broadcast_to_room(self, room: str, data: dict, exclude: Optional[str] = None) -> None:
        payload = json.dumps(data)
        targets = list(self.rooms.get(room, set()))
        dead = []
        for uid in targets:
            if uid == exclude:
                continue
            ws = self.active.get(uid)
            if ws:
                try:
                    await ws.send_text(payload)
                except Exception:
                    dead.append(uid)
        for uid in dead:
            self.active.pop(uid, None)
            self.rooms[room].discard(uid)

    def get_online_count(self) -> int:
        return len(self.active)

    def is_online(self, user_id: str) -> bool:
        return user_id in self.active


manager = ConnectionManager()
