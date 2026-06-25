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
import 'services/push_notification_service.dart';
import 'providers/connectivity_provider.dart';
import 'providers/mesh_provider.dart';

/// Global navigator key — import this to navigate from outside the widget tree
/// (e.g. push-notification tap callbacks).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  EnvironmentConfig.init();

  await StorageService().init();
  await PushNotificationService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => MeshProvider()),
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
