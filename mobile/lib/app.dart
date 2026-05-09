import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'widgets/offline_overlay.dart';

class DRDApp extends StatelessWidget {
  const DRDApp({super.key});

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
      // OfflineOverlay is placed INSIDE MaterialApp via builder so it
      // inherits Directionality, Theme, MediaQuery and all providers.
      builder: (context, child) => OfflineOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
