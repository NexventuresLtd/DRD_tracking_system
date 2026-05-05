# app/websocket/event_ws.py
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from app.websocket.manager import manager
from app.utils.security import verify_access_token
from datetime import datetime, timezone

router = APIRouter()

@router.websocket("/ws/events")
async def event_websocket(
    websocket: WebSocket,
    token: str = Query(...),
):
    """WebSocket for real-time event notifications"""
    # Verify token
    payload = verify_access_token(token)
    if not payload:
        await websocket.close(code=4001, reason="Invalid token")
        return
    
    user_id = payload.get("sub")
    if not user_id:
        await websocket.close(code=4001, reason="Invalid token payload")
        return
    
    # Accept connection
    await manager.connect(websocket, user_id)
    
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")
            
            if msg_type == "ping":
                await manager.send_personal_message(
                    {"type": "pong", "timestamp": datetime.now(timezone.utc).isoformat()},
                    user_id,
                )
    
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        manager.disconnect(websocket)
        print(f"WebSocket error: {e}")