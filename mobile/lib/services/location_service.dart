import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;
  final _locationController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get locationStream => _locationController.stream;

  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  void startTracking() {
    _positionStream?.cancel();

    late LocationSettings locationSettings;

    if (Platform.isAndroid) {
      // Android: run as a foreground service so GPS continues in background
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'DRD Location Active',
          notificationText: 'Tracking your location for field operations',
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position pos) => _emit(pos),
      onError: (_) {
        // Restart stream on error after brief delay
        Future.delayed(const Duration(seconds: 3), startTracking);
      },
      cancelOnError: false,
    );
  }

  void _emit(Position pos) {
    _locationController.add({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'altitude': pos.altitude,
      'speed': pos.speed * 3.6, // m/s → km/h
      'heading': pos.heading,
      'accuracy': pos.accuracy,
      'timestamp': pos.timestamp.toIso8601String(),
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  Future<Position> getCurrentPosition() async {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  }

  void dispose() {
    stopTracking();
    _locationController.close();
  }
}
