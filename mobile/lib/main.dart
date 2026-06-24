import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'config/environment.dart';
import 'providers/auth_provider.dart';
import 'providers/location_provider.dart';
import 'providers/team_provider.dart';
import 'providers/route_provider.dart';
import 'providers/message_provider.dart';
import 'providers/zone_provider.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment - automatically detects flavor from --dart-define
  // or defaults to development if not specified
  EnvironmentConfig.init();

  // Initialize services
  await StorageService().init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => RouteProvider()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
        ChangeNotifierProvider(create: (_) => ZoneProvider()),
      ],
      child: const DRDApp(),
    ),
  );
}
