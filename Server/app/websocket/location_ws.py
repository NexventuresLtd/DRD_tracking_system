import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from jose import jwt, JWTError
from app.config import settings
from app.websocket.manager import manager

router = APIRouter()


@router.websocket("/ws/location/{user_id}")
async def location_websocket(websocket: WebSocket, user_id: str, token: str = Query(None)):
    if not token:
        await websocket.close(code=4001)
        return
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("sub") != user_id:
            await websocket.close(code=4003)
            return
    except JWTError:
        await websocket.close(code=4001)
        return

    await manager.connect(websocket, user_id, room="locations")
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            msg["user_id"] = user_id
            await manager.broadcast({"type": "location_update", **msg}, room="locations")
    except WebSocketDisconnect:
        manager.disconnect(user_id, room="locations")
        await manager.broadcast({"type": "user_status_change", "user_id": user_id, "status": "offline"}, room="locations")
