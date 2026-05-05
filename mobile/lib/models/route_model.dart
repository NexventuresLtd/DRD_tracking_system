class RouteModel {
  final String id;
  final String name;
  final String? description;
  final String createdBy;
  final String? assignedTeamId;
  final String? assignedUserId;
  final String color;
  final bool isActive;
  final bool isZone;
  final String? zoneType;
  final bool meetingPoint;
  final List<WaypointModel> waypoints;
  final DateTime createdAt;
  final DateTime updatedAt;

  RouteModel({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    this.assignedTeamId,
    this.assignedUserId,
    this.color = '#3B82F6',
    this.isActive = true,
    this.isZone = false,
    this.zoneType,
    this.meetingPoint = false,
    this.waypoints = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    return RouteModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      createdBy: json['created_by'] ?? '',
      assignedTeamId: json['assigned_team_id'],
      assignedUserId: json['assigned_user_id'],
      color: json['color'] ?? '#3B82F6',
      isActive: json['is_active'] ?? true,
      isZone: json['is_zone'] ?? false,
      zoneType: json['zone_type'],
      meetingPoint: json['meeting_point'] ?? false,
      waypoints: (json['waypoints'] as List? ?? [])
          .map((wp) => WaypointModel.fromJson(wp))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class WaypointModel {
  final String id;
  final int sequenceOrder;
  final double latitude;
  final double longitude;
  final String? label;
  final String? poiType;

  WaypointModel({
    required this.id,
    required this.sequenceOrder,
    required this.latitude,
    required this.longitude,
    this.label,
    this.poiType,
  });

  factory WaypointModel.fromJson(Map<String, dynamic> json) {
    return WaypointModel(
      id: json['id'] ?? '',
      sequenceOrder: json['sequence_order'] ?? 0,
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      label: json['label'],
      poiType: json['poi_type'],
    );
  }
}