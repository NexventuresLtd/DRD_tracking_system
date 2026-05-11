# app/schemas/location.py
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from datetime import datetime
from uuid import UUID

class SensorData(BaseModel):
    """Accelerometer & Gyroscope data"""
    accel_x: Optional[float] = None  # m/s²
    accel_y: Optional[float] = None  # m/s²
    accel_z: Optional[float] = None  # m/s²
    gyro_x: Optional[float] = None  # rad/s
    gyro_y: Optional[float] = None  # rad/s
    gyro_z: Optional[float] = None  # rad/s

class LocationCreate(BaseModel):
    user_id: UUID
    team_id: Optional[UUID] = None
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    altitude: Optional[float] = None  # meters
    speed: Optional[float] = None  # km/h
    heading: Optional[float] = None  # degrees (0-360)
    accuracy: Optional[float] = None  # meters
    battery_level: Optional[int] = Field(None, ge=0, le=100)
    device_info: Optional[Dict[str, Any]] = None
    sensor_data: Optional[SensorData] = None
    recorded_at: Optional[datetime] = None

class LocationBatchCreate(BaseModel):
    """Batch location updates for efficiency"""
    locations: list[LocationCreate]

class LocationResponse(BaseModel):
    id: UUID
    user_id: UUID
    team_id: Optional[UUID]
    latitude: float
    longitude: float
    altitude: Optional[float]
    speed: Optional[float]
    heading: Optional[float]
    accuracy: Optional[float]
    accel_x: Optional[float]
    accel_y: Optional[float]
    accel_z: Optional[float]
    gyro_x: Optional[float]
    gyro_y: Optional[float]
    gyro_z: Optional[float]
    battery_level: Optional[int]
    status: str
    recorded_at: datetime
    created_at: datetime
    name: Optional[str] = None
    team_name: Optional[str] = None

    class Config:
        from_attributes = True

class LocationHistoryResponse(BaseModel):
    id: UUID
    user_id: UUID
    latitude: float
    longitude: float
    altitude: Optional[float]
    speed: Optional[float]
    heading: Optional[float]
    accel_x: Optional[float]
    accel_y: Optional[float]
    accel_z: Optional[float]
    gyro_x: Optional[float]
    gyro_y: Optional[float]
    gyro_z: Optional[float]
    recorded_at: datetime
    
    class Config:
        from_attributes = True

class GeofenceQuery(BaseModel):
    """Query locations within bounds"""
    min_lat: float
    max_lat: float
    min_lng: float
    max_lng: float
    team_id: Optional[UUID] = None