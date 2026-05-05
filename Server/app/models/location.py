# app/models/location.py
from sqlalchemy import Column, String, Float, Integer, DateTime, ForeignKey, UUID, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid
from app.database import Base

class Location(Base):
    __tablename__ = "locations"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    team_id = Column(UUID(as_uuid=True), ForeignKey("teams.id"))
    
    # GPS Data
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    altitude = Column(Float)  # meters
    
    # Movement Data
    speed = Column(Float)  # km/h
    heading = Column(Float)  # degrees
    accuracy = Column(Float)  # meters
    
    # Accelerometer Data (m/s²)
    accel_x = Column(Float)
    accel_y = Column(Float)
    accel_z = Column(Float)
    
    # Gyroscope Data (rad/s)
    gyro_x = Column(Float)
    gyro_y = Column(Float)
    gyro_z = Column(Float)
    
    # Device Info
    battery_level = Column(Integer)
    device_info = Column(JSON)
    status = Column(String(20), default="active")  # active, stale, offline
    
    recorded_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User", back_populates="locations")
    team = relationship("Team", back_populates="locations")

class LocationHistory(Base):
    __tablename__ = "location_history"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    altitude = Column(Float)
    speed = Column(Float)
    heading = Column(Float)
    
    # Accelerometer & Gyroscope
    accel_x = Column(Float)
    accel_y = Column(Float)
    accel_z = Column(Float)
    gyro_x = Column(Float)
    gyro_y = Column(Float)
    gyro_z = Column(Float)
    
    recorded_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User", back_populates="location_history")