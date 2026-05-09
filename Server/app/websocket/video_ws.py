"""WebRTC signaling WebSocket for live video feeds.

Protocol (JSON messages):
  join        { type:"join",  room_id, user_id, user_name, team_name }
  offer       { type:"offer", room_id, from_id, sdp }
  answer      { type:"answer",room_id, from_id, sdp }
  ice         { type:"ice",   room_id, from_id, candidate }
  mute        { type:"mute",  room_id, from_id, muted }
  leave       { type:"leave", room_id, from_id }
  alert       { type:"alert", room_id, user_id, user_name, team_name, lat, lng }
"""

import json
import asyncio
from typing import Dict, Set
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.services.auth_service import decode_token

router = APIRouter()

# room_id → set of connected WebSockets
_rooms: Dict[str, Set[WebSocket]] = {}
# room_id → room meta (who started the feed)
_room_meta: Dict[str, dict] = {}
# All commander/operator WebSockets that watch for alerts
_alert_watchers: Set[WebSocket] = set()


async def _broadcast_to_room(room_id: str, message: dict, exclude: WebSocket | None = None):
    dead = set()
    for ws in list(_rooms.get(room_id, set())):
        if ws is exclude:
            continue
        try:
            await ws.send_text(json.dumps(message))
        except Exception:
            dead.add(ws)
    _rooms.get(room_id, set()).difference_update(dead)


async def _send_alert_to_watchers(meta: dict):
    """Notify all connected commanders/operators of a new live feed."""
    dead = set()
    msg = json.dumps({"type": "live_alert", **meta})
    for ws in list(_alert_watchers):
        try:
            await ws.send_text(msg)
        except Exception:
            dead.add(ws)
    _alert_watchers.difference_update(dead)


@router.websocket("/ws/video/{room_id}")
async def video_ws(room_id: str, websocket: WebSocket):
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4001)
        return
    try:
        payload = decode_token(token)
        if not payload:
            await websocket.close(code=4001)
            return
    except Exception:
        await websocket.close(code=4001)
        return

    await websocket.accept()

    if room_id not in _rooms:
        _rooms[room_id] = set()
    _rooms[room_id].add(websocket)

    # Auto-register as alert watcher when connecting to the "alerts" room
    # This avoids the race condition of needing to send watch_alerts after connection
    if room_id == "alerts":
        _alert_watchers.add(websocket)
        active = [meta for meta in _room_meta.values() if _rooms.get(meta.get("room_id", ""))]
        if active:
            try:
                await websocket.send_text(json.dumps({"type": "active_feeds", "feeds": active}))
            except Exception:
                pass

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except Exception:
                continue

            msg_type = msg.get("type", "")

            if msg_type == "join":
                # Register meta for alerts
                _room_meta[room_id] = {
                    "room_id": room_id,
                    "user_id": msg.get("user_id"),
                    "user_name": msg.get("user_name", "Field Unit"),
                    "team_name": msg.get("team_name", ""),
                    "lat": msg.get("lat"),
                    "lng": msg.get("lng"),
                }
                # Tell all other room members a new peer joined
                await _broadcast_to_room(room_id, {"type": "peer_joined", "peer_id": msg.get("user_id"), "user_name": msg.get("user_name")}, exclude=websocket)
                # Alert commander watchers
                await _send_alert_to_watchers(_room_meta[room_id])

            elif msg_type == "ignored":
                # Commander ignored the live feed request — relay to soldier
                await _broadcast_to_room(room_id, {
                    "type": "request_ignored",
                    "message": "Command declined your live feed request.",
                    "room_id": room_id,
                }, exclude=websocket)

            elif msg_type in ("offer", "answer", "ice", "mute"):
                # Relay to everyone else in the room
                await _broadcast_to_room(room_id, msg, exclude=websocket)

            elif msg_type == "leave":
                break

            elif msg_type == "watch_alerts":
                # A commander registers to receive live-feed alerts
                _alert_watchers.add(websocket)
                # Send current active rooms
                active = [meta for meta in _room_meta.values() if _rooms.get(meta["room_id"])]
                await websocket.send_text(json.dumps({"type": "active_feeds", "feeds": active}))

    except WebSocketDisconnect:
        pass
    finally:
        _rooms.get(room_id, set()).discard(websocket)
        _alert_watchers.discard(websocket)
        if not _rooms.get(room_id):
            _rooms.pop(room_id, None)
            _room_meta.pop(room_id, None)
            # Notify watchers the feed ended
            await _send_alert_to_watchers({"type": "feed_ended", "room_id": room_id})
