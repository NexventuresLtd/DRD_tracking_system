# app/utils/geo_utils.py
import math
from typing import Tuple, List

def calculate_distance(
    lat1: float, lon1: float,
    lat2: float, lon2: float
) -> float:
    """
    Calculate distance between two points using Haversine formula
    Returns distance in meters
    """
    R = 6371000  # Earth's radius in meters
    
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = (math.sin(delta_phi / 2) ** 2 +
         math.cos(phi1) * math.cos(phi2) *
         math.sin(delta_lambda / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c

def calculate_bearing(
    lat1: float, lon1: float,
    lat2: float, lon2: float
) -> float:
    """
    Calculate bearing between two points
    Returns bearing in degrees (0-360)
    """
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_lambda = math.radians(lon2 - lon1)
    
    x = math.sin(delta_lambda) * math.cos(phi2)
    y = (math.cos(phi1) * math.sin(phi2) -
         math.sin(phi1) * math.cos(phi2) * math.cos(delta_lambda))
    
    bearing = math.degrees(math.atan2(x, y))
    return (bearing + 360) % 360

def interpolate_position(
    lat1: float, lon1: float,
    lat2: float, lon2: float,
    fraction: float
) -> Tuple[float, float]:
    """
    Interpolate position between two points
    fraction: 0.0 = point 1, 1.0 = point 2
    """
    lat = lat1 + (lat2 - lat1) * fraction
    lon = lon1 + (lon2 - lon1) * fraction
    return (lat, lon)

def is_within_geofence(
    lat: float, lon: float,
    min_lat: float, max_lat: float,
    min_lng: float, max_lng: float
) -> bool:
    """Check if point is within geofence boundaries"""
    return min_lat <= lat <= max_lat and min_lng <= lon <= max_lng

def calculate_speed_from_sensor(
    accel_x: float, accel_y: float, accel_z: float,
    prev_speed: float = 0,
    time_delta: float = 1.0  # seconds
) -> float:
    """
    Calculate speed from accelerometer data
    Returns speed in km/h
    """
    # Calculate acceleration magnitude (m/s²)
    accel_magnitude = math.sqrt(accel_x**2 + accel_y**2 + accel_z**2)
    
    # Remove gravity (9.81 m/s²)
    movement_accel = abs(accel_magnitude - 9.81)
    
    # Calculate new speed (m/s) using integration
    new_speed_ms = prev_speed + (movement_accel * time_delta)
    
    # Convert to km/h
    speed_kmh = new_speed_ms * 3.6
    
    return max(0, speed_kmh)

def calculate_heading_from_gyro(
    gyro_z: float,
    prev_heading: float = 0,
    time_delta: float = 1.0  # seconds
) -> float:
    """
    Calculate heading from gyroscope Z-axis data
    Returns heading in degrees (0-360)
    """
    # Gyroscope gives angular velocity in rad/s
    # Integrate to get angle change
    angle_change = math.degrees(gyro_z * time_delta)
    
    new_heading = (prev_heading + angle_change) % 360
    
    return new_heading