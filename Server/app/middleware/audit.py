# app/middleware/audit.py
from fastapi import Request
from typing import Optional, Any
from uuid import UUID
from app.services.audit_service import AuditService

class AuditMiddleware:
    """Middleware for automatic audit logging"""
    
    def __init__(self, audit_service: AuditService):
        self.audit_service = audit_service
    
    async def log_action(
        self,
        user_id: UUID,
        action: str,
        resource_type: str,
        resource_id: Optional[UUID] = None,
        old_values: Optional[dict] = None,
        new_values: Optional[dict] = None,
        request: Optional[Request] = None,
    ):
        """Log an audit action"""
        ip_address = None
        user_agent = None
        
        if request:
            ip_address = request.client.host if request.client else None
            user_agent = request.headers.get("user-agent")
        
        await self.audit_service.create_audit_log(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            old_values=old_values,
            new_values=new_values,
            ip_address=ip_address,
            user_agent=user_agent,
        )