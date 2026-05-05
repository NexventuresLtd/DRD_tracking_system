class POIModel {
  final String id;
  final String name;
  final String? description;
  final String poiType;
  final double latitude;
  final double longitude;
  final String tacticalShape;
  final String status;
  final String? createdBy;
  final bool visibleToAll;
  final DateTime createdAt;
  final DateTime updatedAt;

  POIModel({
    required this.id,
    required this.name,
    this.description,
    required this.poiType,
    required this.latitude,
    required this.longitude,
    this.tacticalShape = 'diamond',
    this.status = 'active',
    this.createdBy,
    this.visibleToAll = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory POIModel.fromJson(Map<String, dynamic> json) {
    return POIModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      poiType: json['poi_type'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      tacticalShape: json['tactical_shape'] ?? 'diamond',
      status: json['status'] ?? 'active',
      createdBy: json['created_by'],
      visibleToAll: json['visible_to_all'] ?? true,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}