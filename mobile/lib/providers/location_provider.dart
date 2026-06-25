import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../services/api_service.dart';

class LocationData {
  final double lat;
  final double lng;
  final double? altitude;
  final double? heading;
  final double? speed;
  final double? accuracy;

  const LocationData({
    required this.lat,
    required this.lng,
    this.altitude,
    this.heading,
    this.speed,
    this.accuracy,
  });
}

class LocationProvider extends ChangeNotifier {
  LocationData? _current;
  bool _tracking = false;
  bool _online = true;
  String? _error;
  StreamSubscription<Position>? _sub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  DateTime? _lastSent;
  Position? _lastPos; // kept so we can resend immediately when internet returns

  LocationData? get current => _current;
  bool get tracking => _tracking;
  bool get online => _online;
  String? get error => _error;

  final _api = ApiService();

  Future<void> startTracking() async {
    if (_tracking) return;

    final granted = await _requestAlwaysLocation();
    if (!granted) {
      _error = 'Location permission denied — background tracking unavailable';
      notifyListeners();
      return;
    }

    _tracking = true;
    _error = null;
    notifyListeners();

    // Check initial connectivity state
    final initConn = await Connectivity().checkConnectivity();
    _online = _isOnline(initConn);

    // Listen for connectivity changes — send immediately when internet returns
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _online;
      _online = _isOnline(results);
      notifyListeners();
      if (!wasOnline && _online && _lastPos != null) {
        // Internet just came back — send current position right away
        _lastSent = null;
        _sendToServer(_lastPos!);
      }
    });

    final settings = _buildLocationSettings();
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _lastPos = pos;
        _current = LocationData(
          lat: pos.latitude,
          lng: pos.longitude,
          altitude: pos.altitude,
          heading: pos.heading,
          speed: pos.speed,
          accuracy: pos.accuracy,
        );
        notifyListeners();
        _sendToServer(pos);
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  bool _isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);

  // Request "locationAlways" for background tracking
  Future<bool> _requestAlwaysLocation() async {
    if (Platform.isIOS) {
      var when = await ph.Permission.locationWhenInUse.status;
      if (!when.isGranted) {
        when = await ph.Permission.locationWhenInUse.request();
        if (!when.isGranted) return false;
      }
    }
    var always = await ph.Permission.locationAlways.status;
    if (always.isGranted) return true;
    always = await ph.Permission.locationAlways.request();
    if (!always.isGranted) {
      final when = await ph.Permission.locationWhenInUse.status;
      return when.isGranted;
    }
    return true;
  }

  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'DRD Operations',
          notificationText: 'Location tracking active',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
  }

  // Throttled to once per 5 seconds AND only when online
  Future<void> _sendToServer(Position pos) async {
    if (!_online) return;

    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!).inSeconds < 5) return;

    // Double-check connectivity right before the call
    final conn = await Connectivity().checkConnectivity();
    if (!_isOnline(conn)) {
      _online = false;
      notifyListeners();
      return;
    }

    _lastSent = now;
    try {
      await _api.post('/locations', {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'altitude': pos.altitude,
        'heading': pos.heading,
        'speed': pos.speed,
        'accuracy': pos.accuracy,
      });
    } catch (_) {
      // Silent — next send will retry
    }
  }

  void stopTracking() {
    _sub?.cancel();
    _connSub?.cancel();
    _sub = null;
    _connSub = null;
    _tracking = false;
    notifyListeners();
  }
}
