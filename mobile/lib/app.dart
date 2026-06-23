import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/qr_enroll_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/live_map_screen.dart';
import 'screens/chat_hub_screen.dart';
import 'screens/mission_list_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/sos_screen.dart';

class DRDApp extends StatelessWidget {
  const DRDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DRD System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          surface: Color(0xFF0F172A),
        ),
        scaffoldBackgroundColor: const Color(0xFF030712),
        fontFamily: 'Poppins',
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/enroll': (_) => const QREnrollScreen(),
        '/home': (_) => const _AuthGuard(child: HomeScreen()),
        '/profile': (_) => const _AuthGuard(child: ProfileScreen()),
        '/map': (_) => const _AuthGuard(child: LiveMapScreen()),
        '/comms': (_) => const _AuthGuard(child: ChatHubScreen()),
        '/missions': (_) => const _AuthGuard(child: MissionListScreen()),
        '/notifications': (_) => const _AuthGuard(child: NotificationsScreen()),
        '/teams': (_) => const _AuthGuard(child: _ComingSoon(title: 'Teams')),
        '/sos': (_) => const _AuthGuard(child: SOSScreen()),
      },
    );
  }
}

class _AuthGuard extends StatelessWidget {
  final Widget child;
  const _AuthGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthProvider, AuthStatus>((a) => a.status);
    if (status == AuthStatus.unauthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
    }
    return child;
  }
}

class _ComingSoon extends StatelessWidget {
  final String title;
  const _ComingSoon({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined, color: Color(0xFF374151), size: 48),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Coming soon', style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
