"""WebRTC signaling server for video calls."""
import json
from collections import defaultdict
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from jose import jwt, JWTError
from app.config import settings

router = APIRouter()

# In-memory room state: room_id -> {user_id: {"ws": WebSocket, "name": str}}
_rooms: dict[str, dict[str, dict]] = defaultdict(dict)


@router.websocket("/ws/video/{room_id}")
async def video_signaling(websocket: WebSocket, room_id: str, token: str = Query(None)):
    if not token:
        await websocket.close(code=4001)
        return
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = payload.get("sub")
        full_name = payload.get("name") or payload.get("full_name") or user_id
    except JWTError:
        await websocket.close(code=4001)
        return

    await websocket.accept()
    _rooms[room_id][user_id] = {"ws": websocket, "name": full_name}

    # Notify existing peers that someone joined (include count)
    await _broadcast_to_room(room_id, {
        "type": "peer_joined",
        "user_id": user_id,
        "name": full_name,
        "participant_count": len(_rooms[room_id]),
    }, exclude=user_id)

    # Send full room state to the new joiner
    await websocket.send_text(json.dumps({
        "type": "room_state",
        "room_id": room_id,
        "participant_count": len(_rooms[room_id]),
        "peers": [
            {"user_id": uid, "name": info["name"]}
            for uid, info in _rooms[room_id].items()
            if uid != user_id
        ],
    }))

    try:
        while True:
            raw = await websocket.receive_text()
            msg = json.loads(raw)
            msg_type = msg.get("type")
            target_id = msg.get("target")

            if msg_type in ("offer", "answer", "ice_candidate"):
                # Relay unicast to target peer
                if target_id and target_id in _rooms[room_id]:
                    msg["from"] = user_id
                    # Include sender name so the answerer can show it
                    if msg_type == "offer":
                        msg["name"] = _rooms[room_id][user_id]["name"]
                    target_ws = _rooms[room_id][target_id]["ws"]
                    try:
                        await target_ws.send_text(json.dumps(msg))
                    except Exception:
                        pass
            elif msg_type == "broadcast":
                # Relay broadcast to all peers (mute/camera state, etc.)
                await _broadcast_to_room(room_id, {**msg, "from": user_id}, exclude=user_id)
    except WebSocketDisconnect:
        _rooms[room_id].pop(user_id, None)
        if not _rooms[room_id]:
            del _rooms[room_id]
        else:
            await _broadcast_to_room(room_id, {
                "type": "peer_left",
                "user_id": user_id,
                "participant_count": len(_rooms[room_id]),
            }, exclude=None)


async def _broadcast_to_room(room_id: str, data: dict, exclude: str | None):
    payload = json.dumps(data)
    dead = []
    for uid, info in list(_rooms.get(room_id, {}).items()):
        if uid == exclude:
            continue
        try:
            await info["ws"].send_text(payload)
        except Exception:
            dead.append(uid)
    for uid in dead:
        _rooms[room_id].pop(uid, None)
