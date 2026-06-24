import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class ZoneAssignment {
  final String id;
  final String zoneId;
  final String zoneName;
  final String userId;
  final double pointLat;
  final double pointLon;
  final String? label;
  final String status;
  final int? pointIndex;

  ZoneAssignment({
    required this.id,
    required this.zoneId,
    required this.zoneName,
    required this.userId,
    required this.pointLat,
    required this.pointLon,
    this.label,
    required this.status,
    this.pointIndex,
  });

  factory ZoneAssignment.fromJson(Map<String, dynamic> json, {String? zoneNameOverride}) => ZoneAssignment(
    id: json['id'] ?? '',
    zoneId: json['zone_id'] ?? '',
    zoneName: zoneNameOverride ?? (json['zone']?['name'] ?? 'Zone'),
    userId: json['user_id'] ?? '',
    pointLat: (json['point_lat'] ?? 0.0).toDouble(),
    pointLon: (json['point_lon'] ?? 0.0).toDouble(),
    label: json['label'],
    status: json['status'] ?? 'pending',
    pointIndex: json['point_index'],
  );

  ZoneAssignment copyWith({String? status}) => ZoneAssignment(
    id: id, zoneId: zoneId, zoneName: zoneName, userId: userId,
    pointLat: pointLat, pointLon: pointLon, label: label,
    status: status ?? this.status, pointIndex: pointIndex,
  );
}

class ZoneProvider extends ChangeNotifier {
  final _api = ApiService();

  List<ZoneAssignment> _myAssignments = [];
  bool _loading = false;
  String? _error;

  List<ZoneAssignment> get myAssignments => _myAssignments;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadMyAssignments() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.get('/zones/my/assignments');
      if (data is List) {
        _myAssignments = data.map((j) => ZoneAssignment.fromJson(j as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateStatus(String zoneId, String userId, String status) async {
    await _api.put('/zones/$zoneId/assignments/$userId/status', {'status': status});
    _myAssignments = _myAssignments.map((a) {
      if (a.zoneId == zoneId && a.userId == userId) return a.copyWith(status: status);
      return a;
    }).toList();
    notifyListeners();
  }

  Future<void> sendPatrolReport({
    required String zoneId,
    required String reportType,
    required String description,
    required double latitude,
    required double longitude,
    String severity = 'medium',
  }) async {
    await _api.post('/zones/$zoneId/patrol-report', {
      'report_type': reportType,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'severity': severity,
    });
  }
}
