import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../config/constants.dart';

class RouteProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storage = StorageService();
  WebSocketChannel? _eventChannel;
  bool _realtimeStarted = false;
  
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _zones = [];
  Map<String, dynamic>? _currentRoute;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get routes => _routes;
  List<Map<String, dynamic>> get zones => _zones;
  Map<String, dynamic>? get currentRoute => _currentRoute;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchRoutes() async {
    await _ensureRealtime();
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/routes');
      if (response != null) {
        _routes = List<Map<String, dynamic>>.from(response);
        // Separate zones from routes
        _zones = _routes.where((r) => r['is_zone'] == true).toList();
        _routes = _routes.where((r) => r['is_zone'] != true).toList();
      }
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _ensureRealtime() async {
    if (_realtimeStarted) return;
    final token = await _storage.getToken();
    if (token == null) return;

    try {
      _eventChannel = WebSocketChannel.connect(
        Uri.parse('${AppConstants.wsUrl}/events?token=$token'),
      );
      _realtimeStarted = true;

      _eventChannel!.stream.listen((raw) async {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          final payload = (data['data'] ?? data) as Map<String, dynamic>;
          final eventType = (payload['event_type'] ?? '').toString().toUpperCase();

          if (eventType == 'ROUTE' || eventType == 'ZONE' || eventType == 'POI') {
            await fetchRoutes();
          }
        } catch (_) {
          // Ignore malformed ws frames.
        }
      }, onDone: () {
        _realtimeStarted = false;
      }, onError: (_) {
        _realtimeStarted = false;
      });
    } catch (_) {
      _realtimeStarted = false;
    }
  }

  Future<void> fetchRouteById(String routeId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/routes/$routeId');
      if (response != null) {
        _currentRoute = response;
      }
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createRoute(Map<String, dynamic> routeData) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.post('/routes', routeData);
      if (response != null) {
        await fetchRoutes();
        return true;
      }
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> assignRoute(String routeId, Map<String, dynamic> assignmentData) async {
    try {
      final response = await _apiService.post('/routes/$routeId/assign', assignmentData);
      return response != null;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  List<List<double>> getRouteCoordinates(String routeId) {
    final route = _routes.firstWhere(
      (r) => r['id'] == routeId,
      orElse: () => {},
    );
    
    if (route.isEmpty) return [];
    
    final waypoints = route['waypoints'] as List? ?? [];
    return waypoints.map((wp) {
      return [wp['latitude'] as double, wp['longitude'] as double];
    }).toList();
  }

  @override
  void dispose() {
    _eventChannel?.sink.close();
    super.dispose();
  }
}