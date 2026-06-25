// Edit mobile/.env then run ./run.sh to change the server IP.
// Or: flutter run --dart-define=API_BASE_URL=http://YOUR_IP:8000
class EnvironmentConfig {
  static late String _apiBaseUrl;
  static late String _wsBaseUrl;
  static late String _env;

  static void init() {
    _env = const String.fromEnvironment('ENV', defaultValue: 'development');
    _apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://192.168.1.73:8000',
    );
    _wsBaseUrl = const String.fromEnvironment(
      'WS_BASE_URL',
      defaultValue: 'ws://192.168.1.73:8000',
    );
  }

  static String get apiBaseUrl => _apiBaseUrl;
  static String get wsBaseUrl => _wsBaseUrl;
  static String get env => _env;
  static bool get isDevelopment => _env == 'development';

  /// Converts a server-relative path (e.g. /uploads/avatars/x.jpg) to a full URL.
  static String resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_apiBaseUrl$path';
  }
}
