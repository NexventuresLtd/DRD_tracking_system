import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from jose import jwt, JWTError
from app.config import settings
from app.websocket.manager import manager
from app.api.v1.messages import _parse_channel

router = APIRouter()


@router.websocket("/ws/messages/{channel}")
async def message_websocket(websocket: WebSocket, channel: str, token: str = Query(None)):
    if not token:
        await websocket.close(code=4001)
        return
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = payload.get("sub")
    except JWTError:
        await websocket.close(code=4001)
        return

    # Normalize channel to the same key that send_message uses when broadcasting,
    # so WS subscribers and REST broadcasts always end up in the same room.
    # e.g. "team:UUID" → "UUID", "dm:OTHER_ID" → "sorted_A_B", "global" → "global"
    _, channel_id = _parse_channel(channel, user_id)
    room = f"chat:{channel_id}"
    await manager.connect(websocket, user_id, room=room)
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            msg["sender_id"] = user_id
            await manager.broadcast_to_room(room, msg, exclude=user_id)
    except WebSocketDisconnect:
        manager.disconnect(user_id, room=room)
