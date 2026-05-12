import 'environment.dart';

class AppConstants {
  // API Endpoints - sourced from environment config
  static String get baseUrl => EnvironmentConfig.getApiBaseUrl();
  static String get wsUrl => EnvironmentConfig.getWsUrl();
  // Storage Keys
  static const String tokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user_data';

  // Map Defaults
  static const double defaultLat = -1.9441;
  static const double defaultLng = 30.0619;
  static const double defaultZoom = 13.0;

  // Location Update Interval (seconds)
  static const int locationUpdateInterval = 5;

  // SOS Auto-send Interval (seconds)
  static const int sosInterval = 30;
}
