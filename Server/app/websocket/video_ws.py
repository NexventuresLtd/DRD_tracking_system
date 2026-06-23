import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from jose import jwt, JWTError
from app.config import settings
from app.websocket.manager import manager

router = APIRouter()


@router.websocket("/ws/video/{call_id}")
async def video_websocket(websocket: WebSocket, call_id: str, token: str = Query(None)):
    if not token:
        await websocket.close(code=4001)
        return
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = payload.get("sub")
    except JWTError:
        await websocket.close(code=4001)
        return

    room = f"call:{call_id}"
    await manager.connect(websocket, user_id, room=room)
    await manager.broadcast_to_room(room, {"type": "participant_joined", "user_id": user_id, "call_id": call_id}, exclude=user_id)

    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            msg["from_user"] = user_id

            if msg.get("type") in ("webrtc_offer", "webrtc_answer", "webrtc_ice"):
                target = msg.get("target_user")
                if target:
                    await manager.send_to(target, msg)
                else:
                    await manager.broadcast_to_room(room, msg, exclude=user_id)
            else:
                await manager.broadcast_to_room(room, msg, exclude=user_id)
    except WebSocketDisconnect:
        manager.disconnect(user_id, room=room)
        await manager.broadcast_to_room(room, {"type": "participant_left", "user_id": user_id, "call_id": call_id})
