import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

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
  String? _error;

  LocationData? get current => _current;
  bool get tracking => _tracking;
  String? get error => _error;

  Future<bool> requestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<void> startTracking() async {
    final granted = await requestPermission();
    if (!granted) {
      _error = 'Location permission denied';
      notifyListeners();
      return;
    }
    _tracking = true;
    _error = null;
    notifyListeners();

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      _current = LocationData(
        lat: pos.latitude,
        lng: pos.longitude,
        altitude: pos.altitude,
        heading: pos.heading,
        speed: pos.speed,
        accuracy: pos.accuracy,
      );
      notifyListeners();
    });
  }

  void stopTracking() {
    _tracking = false;
    notifyListeners();
  }
}
