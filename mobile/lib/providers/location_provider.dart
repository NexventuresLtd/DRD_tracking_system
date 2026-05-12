import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/offline_sync_service.dart';

class LocationProvider extends ChangeNotifier {
  final LocationService _gps = LocationService();
  final ApiService _api = ApiService();
  final OfflineSyncService _sync = OfflineSyncService();
  final Battery _battery = Battery();

  double _latitude = 0;
  double _longitude = 0;
  double _speed = 0;
  double _heading = 0;
  double _altitude = 0;
  double _accuracy = 0;
  int _batteryLevel = 100;
  bool _isTracking = false;
  bool _hasRealFix = false; // true once we have a real GPS fix
  int _pendingCount = 0;
  bool _locationEnabled = false;

  String? _userId;
  String? _teamId;
  StreamSubscription<Map<String, dynamic>>? _gpsSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _heartbeatTimer;

  double get latitude => _latitude;
  double get longitude => _longitude;
  double get speed => _speed;
  double get heading => _heading;
  double get altitude => _altitude;
  double get accuracy => _accuracy;
  int get batteryLevel => _batteryLevel;
  bool get isTracking => _isTracking;
  bool get hasRealFix => _hasRealFix;
  int get pendingCount => _pendingCount;
  bool get locationEnabled => _locationEnabled;

  Future<void> initialize(String userId, {String? teamId}) async {
    if (_userId == userId && _isTracking) return;
    _userId = userId;
    _teamId = teamId;

    final hasPermission = await _gps.requestPermissions();
    _locationEnabled = hasPermission;
    notifyListeners();
    if (!hasPermission) return;

    await startTracking();

    // Get immediate one-shot fix to start with
    try {
      final position = await _gps.getCurrentPosition();
      await _onGpsUpdate({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'altitude': position.altitude,
        'speed': position.speed * 3.6,
        'heading': position.heading,
        'accuracy': position.accuracy,
        'timestamp': position.timestamp.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Initial GPS fix failed: $e');
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivityChange);
    _pendingCount = await _sync.getPendingCount();
    notifyListeners();

    // Heartbeat: re-send last known position every 10s even if not moving
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sendHeartbeat());
  }

  Future<void> startTracking() async {
    if (_isTracking) return;
    _isTracking = true;
    _gps.startTracking();
    _gpsSub = _gps.locationStream.listen(_onGpsUpdate, onError: (e) {
      debugPrint('GPS stream error: $e');
    });
    notifyListeners();
  }

  Future<void> stopTracking() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (!_isTracking) return;
    _isTracking = false;
    await _gpsSub?.cancel();
    _gpsSub = null;
    _gps.stopTracking();
    notifyListeners();
  }

  /// Call when the app goes to background / is closed.
  Future<void> markOffline() async {
    if (_userId == null) return;
    try {
      await _api.post('/locations/offline', {});
    } catch (_) {}
  }

  /// Call when the app returns to foreground — resumes GPS and flips status back to active.
  Future<void> onResume() async {
    if (_userId == null) return;
    if (!_isTracking) await startTracking();
    if (_hasRealFix) await _sendToServer();
  }

  Future<void> _onGpsUpdate(Map<String, dynamic> data) async {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    _latitude = lat;
    _longitude = lng;
    _speed = (data['speed'] as num?)?.toDouble() ?? 0;
    _heading = (data['heading'] as num?)?.toDouble() ?? 0;
    _altitude = (data['altitude'] as num?)?.toDouble() ?? 0;
    _accuracy = (data['accuracy'] as num?)?.toDouble() ?? 0;
    _hasRealFix = true;

    try { _batteryLevel = await _battery.batteryLevel; } catch (_) {}
    notifyListeners();
    await _sendToServer();
  }

  Future<void> _sendHeartbeat() async {
    if (!_hasRealFix || _userId == null) return;
    await _sendToServer();
  }

  Future<void> _sendToServer() async {
    if (_userId == null || !_hasRealFix) return;

    final payload = <String, dynamic>{
      'user_id': _userId,
      if (_teamId != null) 'team_id': _teamId,
      'latitude': _latitude,
      'longitude': _longitude,
      'speed': _speed,
      'heading': _heading,
      'altitude': _altitude,
      'accuracy': _accuracy,
      'battery_level': _batteryLevel,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    };

    debugPrint('📍 Sending location: lat=$_latitude, lng=$_longitude');

    final result = await _api.post('/locations', payload);
    if (result == null) {
      await _sync.enqueue(_userId!, payload);
      _pendingCount = await _sync.getPendingCount();
      notifyListeners();
    } else if (_pendingCount > 0) {
      await _flushQueue();
    }
  }

  Future<void> _flushQueue() async {
    if (_userId == null) return;
    _pendingCount = await _sync.flush(
      (payload) async => await _api.post('/locations', payload) != null,
    );
    notifyListeners();
  }

  void _onConnectivityChange(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) {
      if (_pendingCount > 0) _flushQueue();
      if (_hasRealFix) _sendToServer(); // immediately re-send on reconnect
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    stopTracking();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
