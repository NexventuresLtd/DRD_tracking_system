# app/websocket/manager.py
from fastapi import WebSocket
from typing import Dict, Set, Any, Optional
from uuid import UUID
import json
import asyncio
from datetime import datetime, timezone

class ConnectionManager:
    """Manage WebSocket connections"""
    
    def __init__(self):
        # user_id -> set of WebSocket connections
        self.active_connections: Dict[str, Set[WebSocket]] = {}
        # team_id -> set of user_ids
        self.team_subscriptions: Dict[str, Set[str]] = {}
        # WebSocket -> user_id mapping
        self.ws_user_map: Dict[WebSocket, str] = {}
    
    async def connect(self, websocket: WebSocket, user_id: str):
        """Accept new WebSocket connection"""
        await websocket.accept()
        
        if user_id not in self.active_connections:
            self.active_connections[user_id] = set()
        
        self.active_connections[user_id].add(websocket)
        self.ws_user_map[websocket] = user_id
        
        # Notify others about user coming online
        await self.broadcast_to_role(
            ["admin", "commander", "operator"],
            {
                "type": "user_connected",
                "data": {
                    "user_id": user_id,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }
            }
        )
    
    def disconnect(self, websocket: WebSocket):
        """Handle WebSocket disconnection"""
        user_id = self.ws_user_map.get(websocket)
        
        if user_id and user_id in self.active_connections:
            self.active_connections[user_id].discard(websocket)
            
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]
        
        if websocket in self.ws_user_map:
            del self.ws_user_map[websocket]
        
        # Remove from team subscriptions
        for team_id in list(self.team_subscriptions.keys()):
            if user_id in self.team_subscriptions[team_id]:
                self.team_subscriptions[team_id].discard(user_id)
    
    async def send_personal_message(self, message: dict, user_id: str):
        """Send message to specific user"""
        if user_id not in self.active_connections:
            return
        # Snapshot the set so disconnect() mutations don't break iteration
        dead = []
        for websocket in list(self.active_connections[user_id]):
            try:
                await websocket.send_json(message)
            except Exception:
                dead.append(websocket)
        for ws in dead:
            self.disconnect(ws)

    async def broadcast_to_team(self, team_id: str, message: dict):
        """Broadcast message to all team members"""
        if team_id in self.team_subscriptions:
            for user_id in list(self.team_subscriptions[team_id]):
                await self.send_personal_message(message, user_id)

    async def broadcast_to_all(self, message: dict):
        """Broadcast to every connected user (snapshot keys to avoid mutation during iteration)"""
        for user_id in list(self.active_connections.keys()):
            await self.send_personal_message(message, user_id)

    async def broadcast_to_role(self, roles: list, message: dict):
        """Broadcast to all connected users (role lookup skipped — broadcast_to_all covers it)"""
        await self.broadcast_to_all(message)
    
    async def broadcast_location_update(self, location_data: dict):
        """Broadcast location update to authorized viewers"""
        message = {
            "type": "location_update",
            "data": location_data,
        }
        
        # Broadcast to commanders and operators
        await self.broadcast_to_role(
            ["admin", "commander", "operator"],
            message,
        )
        
        # Also send to team members
        team_id = location_data.get("team_id")
        if team_id:
            await self.broadcast_to_team(str(team_id), message)
    
    async def broadcast_event(self, event_data: dict):
        """Broadcast event to all users"""
        message = {
            "type": "new_event",
            "data": event_data,
        }
        await self.broadcast_to_all(message)
    
    def subscribe_to_team(self, user_id: str, team_id: str):
        """Subscribe user to team updates"""
        if team_id not in self.team_subscriptions:
            self.team_subscriptions[team_id] = set()
        self.team_subscriptions[team_id].add(user_id)
    
    def unsubscribe_from_team(self, user_id: str, team_id: str):
        """Unsubscribe user from team updates"""
        if team_id in self.team_subscriptions:
            self.team_subscriptions[team_id].discard(user_id)
    
    def get_connected_users(self) -> list:
        """Get list of connected user IDs"""
        return list(self.active_connections.keys())
    
    def get_user_connection_count(self) -> int:
        """Get total number of connected users"""
        return len(self.active_connections)

# Global connection manager instance
manager = ConnectionManager()