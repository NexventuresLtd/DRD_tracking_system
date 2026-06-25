// HOW TO SET SERVER IP
// ─────────────────────────────────────────────────────────────────────────────
// Option A — PC hotspot demo (laptop IS the server):
//   Windows hotspot default gateway: 192.168.137.1
//   flutter run --dart-define=API_BASE_URL=http://192.168.137.1:8000 \
//               --dart-define=WS_BASE_URL=ws://192.168.137.1:8000
//
// Option B — Regular WiFi (server on same network):
//   flutter run --dart-define=API_BASE_URL=http://YOUR_LAPTOP_IP:8000 \
//               --dart-define=WS_BASE_URL=ws://YOUR_LAPTOP_IP:8000
//
// Option C — Edit the defaultValue below and rebuild.
// ─────────────────────────────────────────────────────────────────────────────
class EnvironmentConfig {
  static late String _apiBaseUrl;
  static late String _wsBaseUrl;
  static late String _env;

  static void init() {
    _env = const String.fromEnvironment('ENV', defaultValue: 'development');
    _apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://192.168.1.73:8000', // Windows hotspot default
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
