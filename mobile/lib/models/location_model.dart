class LocationModel {
  final String id;
  final String userId;
  final String? teamId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speed;
  final double? heading;
  final double? accuracy;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;
  final int? batteryLevel;
  final String status;
  final DateTime recordedAt;

  LocationModel({
    required this.id,
    required this.userId,
    this.teamId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    this.heading,
    this.accuracy,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.batteryLevel,
    this.status = 'active',
    required this.recordedAt,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      teamId: json['team_id'],
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      altitude: json['altitude']?.toDouble(),
      speed: json['speed']?.toDouble(),
      heading: json['heading']?.toDouble(),
      accuracy: json['accuracy']?.toDouble(),
      accelX: json['accel_x']?.toDouble(),
      accelY: json['accel_y']?.toDouble(),
      accelZ: json['accel_z']?.toDouble(),
      gyroX: json['gyro_x']?.toDouble(),
      gyroY: json['gyro_y']?.toDouble(),
      gyroZ: json['gyro_z']?.toDouble(),
      batteryLevel: json['battery_level'],
      status: json['status'] ?? 'active',
      recordedAt: DateTime.parse(json['recorded_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'team_id': teamId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'accel_x': accelX,
      'accel_y': accelY,
      'accel_z': accelZ,
      'gyro_x': gyroX,
      'gyro_y': gyroY,
      'gyro_z': gyroZ,
      'battery_level': batteryLevel,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}