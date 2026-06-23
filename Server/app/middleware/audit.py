import time
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from app.database import async_session
from app.models.audit import AuditLog

SKIP_PATHS = {"/health", "/", "/docs", "/redoc", "/openapi.json"}
SKIP_METHODS = {"GET", "HEAD", "OPTIONS"}


class AuditMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        if request.url.path in SKIP_PATHS or request.method in SKIP_METHODS:
            return await call_next(request)

        start = time.time()
        response = await call_next(request)

        try:
            user_id = None
            if hasattr(request.state, "user_id"):
                user_id = request.state.user_id

            action = f"{request.method}:{request.url.path}"
            async with async_session() as db:
                log = AuditLog(
                    user_id=user_id,
                    action=action,
                    path=str(request.url.path),
                    method=request.method,
                    status_code=response.status_code,
                    ip_address=request.client.host if request.client else None,
                    user_agent=request.headers.get("user-agent"),
                )
                db.add(log)
                await db.commit()
        except Exception:
            pass

        return response
