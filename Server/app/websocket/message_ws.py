# app/websocket/message_ws.py
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from app.websocket.manager import manager
from app.utils.security import verify_access_token
from datetime import datetime, timezone
from uuid import UUID

router = APIRouter()

@router.websocket("/ws/messages")
async def message_websocket(
    websocket: WebSocket,
    token: str = Query(...),
):
    """WebSocket for real-time messaging"""
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
            
            if msg_type == "send_message":
                message_data = data.get("data", {})
                to_user_id = message_data.get("to_user_id")
                to_team_id = message_data.get("to_team_id")
                to_all = message_data.get("to_all", False)
                content = message_data.get("content")
                
                message = {
                    "type": "new_message",
                    "data": {
                        "id": str(UUID.uuid4()),
                        "from_user_id": user_id,
                        "content": content,
                        "priority": message_data.get("priority", "normal"),
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    }
                }
                
                if to_all:
                    await manager.broadcast_to_all(message)
                elif to_team_id:
                    await manager.broadcast_to_team(str(to_team_id), message)
                elif to_user_id:
                    await manager.send_personal_message(message, str(to_user_id))
                    # Also send confirmation to sender
                    await manager.send_personal_message(message, user_id)
            
            elif msg_type == "typing":
                typing_data = data.get("data", {})
                await manager.send_personal_message(
                    {
                        "type": "user_typing",
                        "data": {
                            "user_id": user_id,
                            "is_typing": typing_data.get("is_typing", False),
                        }
                    },
                    str(typing_data.get("to_user_id")),
                )
            
            elif msg_type == "ping":
                await manager.send_personal_message(
                    {"type": "pong", "timestamp": datetime.now(timezone.utc).isoformat()},
                    user_id,
                )
    
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        manager.disconnect(websocket)
        print(f"WebSocket error: {e}")