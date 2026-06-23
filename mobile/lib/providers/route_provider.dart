import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class RouteData {
  final String id;
  final String name;
  final String? description;
  final String routeType;
  final List<Map<String, dynamic>> waypoints;

  const RouteData({
    required this.id,
    required this.name,
    this.description,
    required this.routeType,
    required this.waypoints,
  });

  factory RouteData.fromJson(Map<String, dynamic> j) => RouteData(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        routeType: j['route_type'] as String? ?? 'custom',
        waypoints: (j['waypoints'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
      );
}

class RouteProvider extends ChangeNotifier {
  List<RouteData> _routes = [];
  bool _loading = false;

  List<RouteData> get routes => _routes;
  bool get loading => _loading;

  final _api = ApiService();

  Future<void> loadRoutes() async {
    _loading = true;
    notifyListeners();
    try {
      final data = await _api.get('/routes') as List<dynamic>;
      _routes = data.map((e) => RouteData.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }
}
