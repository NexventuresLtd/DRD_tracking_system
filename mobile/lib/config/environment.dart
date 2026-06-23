class EnvironmentConfig {
  static late String _apiBaseUrl;
  static late String _wsBaseUrl;
  static late String _env;

  static void init() {
    _env = const String.fromEnvironment('ENV', defaultValue: 'development');
    _apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:1104',
    );
    _wsBaseUrl = const String.fromEnvironment(
      'WS_BASE_URL',
      defaultValue: 'ws://localhost:1104',
    );
  }

  static String get apiBaseUrl => _apiBaseUrl;
  static String get wsBaseUrl => _wsBaseUrl;
  static String get env => _env;
  static bool get isDevelopment => _env == 'development';
}
