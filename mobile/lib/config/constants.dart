class AppConstants {
  // API Endpoints
  // static const String baseUrl = 'http://192.168.14.84:8000/api/v1';
  // static const String wsUrl = 'ws://192.168.14.84:8000/ws';
  static const String baseUrl = 'https://drd.nexventures.net/api/v1';
  static const String wsUrl = 'wss://drd.nexventures.net/ws';
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
