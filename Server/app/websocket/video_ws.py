"""WebRTC signaling WebSocket for live video feeds.

Protocol (JSON messages):
  join        { type:"join",  room_id, user_id, user_name, team_name [, role:"viewer"] }
  offer       { type:"offer", room_id, from_id, sdp }
  answer      { type:"answer",room_id, from_id, sdp }
  ice         { type:"ice",   room_id, from_id, candidate }
  mute        { type:"mute",  room_id, from_id, muted }
  leave       { type:"leave", room_id, from_id }
"""

import json
from typing import Dict, Set, Optional
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.services.auth_service import decode_token

router = APIRouter()

# room_id → set of connected WebSockets (broadcasters + viewers)
_rooms: Dict[str, Set[WebSocket]] = {}
# room_id → meta of the FIELD UNIT broadcaster (never overwritten by viewers)
_room_meta: Dict[str, dict] = {}
# room_id → the broadcaster's WebSocket (used to check room is still live)
_room_broadcaster_ws: Dict[str, WebSocket] = {}
# All commander/operator WebSockets that watch for live-feed alerts
_alert_watchers: Set[WebSocket] = set()


def _active_feeds() -> list:
    """Return only rooms that still have an active broadcaster connection."""
    result = []
    for room_id, meta in _room_meta.items():
        bws = _room_broadcaster_ws.get(room_id)
        if bws is not None and bws in _rooms.get(room_id, set()):
            result.append(meta)
    return result


async def _broadcast_to_room(room_id: str, message: dict, exclude: Optional[WebSocket] = None):
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
    if room_id == "alerts":
        _alert_watchers.add(websocket)
        active = _active_feeds()
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
                is_viewer = msg.get("role") == "viewer"
                if not is_viewer:
                    # Only the field unit broadcaster registers meta and alerts commanders.
                    # Viewers (commanders watching) never overwrite this.
                    _room_meta[room_id] = {
                        "room_id": room_id,
                        "user_id": msg.get("user_id"),
                        "user_name": msg.get("user_name", "Field Unit"),
                        "team_name": msg.get("team_name", ""),
                        "lat": msg.get("lat"),
                        "lng": msg.get("lng"),
                    }
                    _room_broadcaster_ws[room_id] = websocket
                    await _send_alert_to_watchers(_room_meta[room_id])
                # Tell other peers someone joined (needed for WebRTC handshake)
                await _broadcast_to_room(
                    room_id,
                    {"type": "peer_joined", "peer_id": msg.get("user_id"), "user_name": msg.get("user_name")},
                    exclude=websocket,
                )

            elif msg_type == "ignored":
                await _broadcast_to_room(room_id, {
                    "type": "request_ignored",
                    "message": "Command declined your live feed request.",
                    "room_id": room_id,
                }, exclude=websocket)

            elif msg_type in ("offer", "answer", "ice", "mute"):
                await _broadcast_to_room(room_id, msg, exclude=websocket)

            elif msg_type == "leave":
                break

            elif msg_type == "watch_alerts":
                _alert_watchers.add(websocket)
                active = _active_feeds()
                await websocket.send_text(json.dumps({"type": "active_feeds", "feeds": active}))

    except WebSocketDisconnect:
        pass
    finally:
        _rooms.get(room_id, set()).discard(websocket)
        _alert_watchers.discard(websocket)

        # If the broadcaster disconnected, clear the room
        if _room_broadcaster_ws.get(room_id) is websocket:
            _room_broadcaster_ws.pop(room_id, None)
            _room_meta.pop(room_id, None)
            _rooms.pop(room_id, None)
            await _send_alert_to_watchers({"type": "feed_ended", "room_id": room_id})
        elif not _rooms.get(room_id):
            # Room empty (last viewer left), clean up
            _rooms.pop(room_id, None)
