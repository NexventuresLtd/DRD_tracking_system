# app/main.py
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
import uvicorn
import asyncio

from app.config import settings
from app.database import init_db
from app.api.v1 import auth, users, teams, locations, routes, pois, events, messages, zones, route_follow_sessions, evidence, live_sessions
from fastapi.staticfiles import StaticFiles
from app.websocket import location_ws, event_ws, message_ws, video_ws
from app.middleware.cors import setup_cors
from app.websocket.manager import manager

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    print(f"Starting {settings.APP_NAME}...")
    
    # Initialize database
    try:
        await init_db()
        print("Database initialized successfully")
    except Exception as e:
        print(f"Database initialization error: {e}")
        print("Continuing without database initialization...")
    
    # Start background tasks
    loop = asyncio.get_event_loop()
    
    # Start location status updater
    async def update_location_statuses():
        while True:
            try:
                from app.database import async_session
                from app.services.location_service import LocationService
                async with async_session() as db:
                    location_service = LocationService(db)
                    await location_service.update_location_statuses()
            except Exception as e:
                print(f"Error updating location statuses: {e}")
            await asyncio.sleep(30)  # Run every 30 seconds
    
    background_task = loop.create_task(update_location_statuses())
    
    yield
    
    # Cleanup
    background_task.cancel()
    try:
        await background_task
    except asyncio.CancelledError:
        pass
    
    print(f"Shutting down {settings.APP_NAME}...")

# Create FastAPI app
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="DRD Field Coordination System - Real-time tactical operations management",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# Setup CORS
setup_cors(app)

# Health check endpoints
@app.get("/")
async def root():
    return {
        "name": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "operational",
        "docs": "/docs",
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "version": settings.APP_VERSION,
    }

# Include API routers
app.include_router(auth.router, prefix="/api/v1")
app.include_router(users.router, prefix="/api/v1")
app.include_router(teams.router, prefix="/api/v1")
app.include_router(locations.router, prefix="/api/v1")
app.include_router(routes.router, prefix="/api/v1")
app.include_router(route_follow_sessions.router, prefix="/api/v1")
app.include_router(pois.router, prefix="/api/v1")
app.include_router(events.router, prefix="/api/v1")
app.include_router(messages.router, prefix="/api/v1")
app.include_router(zones.router, prefix="/api/v1")
app.include_router(evidence.router, prefix="/api/v1")
app.include_router(live_sessions.router, prefix="/api/v1")

# Serve uploaded files
import os
os.makedirs("uploads/evidence", exist_ok=True)
os.makedirs("uploads/live_sessions", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# Include WebSocket routers
app.include_router(location_ws.router)
app.include_router(event_ws.router)
app.include_router(message_ws.router)
app.include_router(video_ws.router)

# Error handlers
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler"""
    print(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "detail": str(exc) if settings.DEBUG else "An unexpected error occurred",
        },
    )

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower(),
    )