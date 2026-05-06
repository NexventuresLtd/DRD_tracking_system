import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'config/routes.dart';

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
    );
  }
}
