import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'main.dart' show navigatorKey;
import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/qr_enroll_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/live_map_screen.dart';
import 'screens/chat_hub_screen.dart';
import 'screens/mission_list_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/zone_assignment_screen.dart';
import 'screens/team_detail_screen.dart';
import 'screens/facilities_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/live_session_screen.dart';
import 'screens/video_call_screen.dart';
import 'providers/location_provider.dart';
import 'services/push_notification_service.dart';
import 'providers/connectivity_provider.dart';
import 'screens/mesh_network_screen.dart';
import 'services/navigation_state.dart';

class DRDApp extends StatelessWidget {
  const DRDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DRD Operations',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF16A34A),
          surface: Color(0xFF0F172A),
        ),
        scaffoldBackgroundColor: const Color(0xFF030712),
        fontFamily: 'Poppins',
        useMaterial3: true,
      ),
      builder: (context, child) {
        final online = context.watch<ConnectivityProvider>().online;
        return Stack(
          children: [
            child!,
            if (!online) const MeshNetworkOverlay(),
          ],
        );
      },
      navigatorKey: navigatorKey,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/enroll': (_) => const QREnrollScreen(),
        '/permissions': (_) => const PermissionScreen(),
        '/home': (_) => const _AuthGuard(child: MainShell()),
        '/notifications': (_) => const _AuthGuard(child: NotificationsScreen()),
        '/sos': (_) => const _AuthGuard(child: SOSScreen()),
        '/zones': (_) => const _AuthGuard(child: ZoneAssignmentScreen()),
        '/facilities': (_) => const _AuthGuard(child: FacilitiesScreen()),
        '/live': (_) => const _AuthGuard(child: LiveSessionScreen()),
        '/video-call': (ctx) {
          final args = (ModalRoute.of(ctx)!.settings.arguments as Map?)?.cast<String, dynamic>() ?? {};
          return _AuthGuard(child: VideoCallScreen(
            roomId: args['roomId'] as String? ?? 'default',
            roomTitle: args['roomTitle'] as String? ?? 'Video Call',
          ));
        },
      },
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/teams/')) {
          final teamId = name.substring('/teams/'.length);
          return MaterialPageRoute(builder: (_) => _AuthGuard(child: TeamDetailScreen(teamId: teamId)));
        }
        return null;
      },
    );
  }
}

// ── Auth guard ────────────────────────────────────────────────────────────────

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

// ── Bottom nav shell ──────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    appTabNotifier.addListener(_onTabNotifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().startTracking();
      final userId = context.read<AuthProvider>().user?.id;
      if (userId != null) {
        PushNotificationService.instance.connectForUser(userId);
      }
    });
  }

  void _onTabNotifier() {
    if (mounted) setState(() => _tab = appTabNotifier.value);
  }

  @override
  void dispose() {
    appTabNotifier.removeListener(_onTabNotifier);
    super.dispose();
  }

  Future<void> _confirmLogout() async {
    final auth = context.read<AuthProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF060D06),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Color(0xFF7F1D1D))),
        title: const Text('Disconnect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Color(0xFF9CA3AF))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await auth.logout();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  static const _screens = [
    HomeScreen(),
    LiveMapScreen(),
    MissionListScreen(),
    ChatHubScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: _screens),
          // Transparent left-edge strip — swipe right from here to trigger logout
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 22,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                if (details.velocity.pixelsPerSecond.dx > 400) {
                  _confirmLogout();
                }
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0F0A),
          border: Border(top: BorderSide(color: Color(0xFF0F2D0F), width: 1)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _NavTab(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
                _NavTab(icon: Icons.map_outlined, activeIcon: Icons.map, label: 'Map', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
                _NavTab(icon: Icons.assignment_outlined, activeIcon: Icons.assignment, label: 'Missions', active: _tab == 2, onTap: () => setState(() => _tab = 2)),
                _NavTab(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Comms', active: _tab == 3, onTap: () => setState(() => _tab = 3)),
                _NavTab(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile', active: _tab == 4, onTap: () => setState(() => _tab = 4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? activeIcon : icon, color: active ? const Color(0xFF22C55E) : const Color(0xFF374151), size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: active ? const Color(0xFF22C55E) : const Color(0xFF374151), fontSize: 10, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
