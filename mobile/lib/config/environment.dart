import 'package:flutter/foundation.dart';

/// Environment configuration for different build variants
enum BuildFlavor { development, staging, production }

class EnvironmentConfig {
  static late BuildFlavor buildFlavor;
  static late String apiBaseUrl;
  static late String wsUrl;

  /// Initialize environment based on flavor
  static void init([BuildFlavor? flavor]) {
    // Determine flavor: use provided flavor, or read from dart-define, or default to development
    flavor ??= _getFlavourFromEnv();

    buildFlavor = flavor;

    // All flavors always use the production server
    apiBaseUrl = 'https://drd.nexventures.net/api/v1';
    wsUrl = 'wss://drd.nexventures.net/ws';

    debugPrint('🔧 Environment initialized: ${flavor.name.toUpperCase()}');
    debugPrint('📡 API URL: $apiBaseUrl');
  }

  /// Get flavor from dart-define environment variable
  static BuildFlavor _getFlavourFromEnv() {
    const String flavor = String.fromEnvironment(
      'FLAVOR',
      defaultValue: 'production',
    );

    switch (flavor.toLowerCase()) {
      case 'staging':
        return BuildFlavor.staging;
      case 'production':
        return BuildFlavor.production;
      case 'development':
      default:
        return BuildFlavor.development;
    }
  }

  /// Get current API base URL
  static String getApiBaseUrl() => apiBaseUrl;

  /// Get current WebSocket URL
  static String getWsUrl() => wsUrl;

  /// Check if running in debug mode
  static bool isDebug() => buildFlavor == BuildFlavor.development;

  /// Check if production
  static bool isProduction() => buildFlavor == BuildFlavor.production;

  /// Get current flavor name
  static String getFlavourName() => buildFlavor.name;
}
