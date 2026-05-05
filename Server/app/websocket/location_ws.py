# app/websocket/location_ws.py
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional
import json
from datetime import datetime, timezone
from uuid import UUID

from app.database import get_db
from app.websocket.manager import manager
from app.utils.security import verify_access_token
from app.services.location_service import LocationService
from app.schemas.location import LocationCreate

router = APIRouter()

@router.websocket("/ws/locations")
async def location_websocket(
    websocket: WebSocket,
    token: str = Query(...),
):
    """WebSocket for real-time location updates"""
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
    
    # Create database session
    async for db in get_db():
        location_service = LocationService(db)
        
        try:
            while True:
                # Receive location data
                data = await websocket.receive_json()
                
                # Handle different message types
                msg_type = data.get("type")
                
                if msg_type == "location_update":
                    location_data = data.get("data", {})
                    
                    # Update location in database
                    location = LocationCreate(
                        user_id=UUID(user_id),
                        team_id=UUID(location_data.get("team_id")) if location_data.get("team_id") else None,
                        latitude=location_data["latitude"],
                        longitude=location_data["longitude"],
                        altitude=location_data.get("altitude"),
                        speed=location_data.get("speed"),
                        heading=location_data.get("heading"),
                        accuracy=location_data.get("accuracy"),
                        battery_level=location_data.get("battery_level"),
                        device_info=location_data.get("device_info"),
                        sensor_data=location_data.get("sensor_data"),
                        recorded_at=datetime.now(timezone.utc),
                    )
                    
                    updated_location = await location_service.update_location(location)
                    
                    # Broadcast to others
                    await manager.broadcast_location_update({
                        "user_id": user_id,
                        "team_id": str(updated_location.team_id) if updated_location.team_id else None,
                        "latitude": updated_location.latitude,
                        "longitude": updated_location.longitude,
                        "altitude": updated_location.altitude,
                        "speed": updated_location.speed,
                        "heading": updated_location.heading,
                        "accuracy": updated_location.accuracy,
                        "accel_x": updated_location.accel_x,
                        "accel_y": updated_location.accel_y,
                        "accel_z": updated_location.accel_z,
                        "gyro_x": updated_location.gyro_x,
                        "gyro_y": updated_location.gyro_y,
                        "gyro_z": updated_location.gyro_z,
                        "battery_level": updated_location.battery_level,
                        "status": updated_location.status,
                        "recorded_at": updated_location.recorded_at.isoformat(),
                    })
                    
                    # Confirm to sender
                    await manager.send_personal_message(
                        {
                            "type": "location_ack",
                            "data": {
                                "status": "received",
                                "timestamp": datetime.now(timezone.utc).isoformat(),
                            }
                        },
                        user_id,
                    )
                
                elif msg_type == "subscribe_team":
                    team_id = data.get("team_id")
                    if team_id:
                        manager.subscribe_to_team(user_id, str(team_id))
                        await manager.send_personal_message(
                            {
                                "type": "subscription_ack",
                                "data": {"team_id": str(team_id), "status": "subscribed"}
                            },
                            user_id,
                        )
                
                elif msg_type == "unsubscribe_team":
                    team_id = data.get("team_id")
                    if team_id:
                        manager.unsubscribe_from_team(user_id, str(team_id))
                        await manager.send_personal_message(
                            {
                                "type": "subscription_ack",
                                "data": {"team_id": str(team_id), "status": "unsubscribed"}
                            },
                            user_id,
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