import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'providers/location_provider.dart';
import 'widgets/offline_overlay.dart';

class DRDApp extends StatefulWidget {
  const DRDApp({super.key});

  @override
  State<DRDApp> createState() => _DRDAppState();
}

class _DRDAppState extends State<DRDApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final loc = context.read<LocationProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // App going to background or being closed — mark offline immediately
      loc.markOffline();
    } else if (state == AppLifecycleState.resumed) {
      // App came back to foreground — resume tracking
      loc.onResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'drd_tracking',
      debugShowCheckedModeBanner: false,
      theme: DRDTheme.lightTheme,
      darkTheme: DRDTheme.darkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: '/splash',
      onGenerateRoute: AppRoutes.generateRoute,
      builder: (context, child) => OfflineOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
