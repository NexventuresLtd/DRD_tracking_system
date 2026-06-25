import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/permission_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Run delay, permission check, and connectivity probe in parallel so
    // ConnectivityProvider has the accurate offline/online state the instant
    // we navigate — the builder then shows MeshNetworkOverlay immediately.
    final delayFuture       = Future<void>.delayed(const Duration(seconds: 2));
    final permFuture        = PermissionService.instance.allCriticalGranted();
    final connFuture        = context.read<ConnectivityProvider>().forceCheck();

    await delayFuture;
    final permissionsOk = await permFuture;
    await connFuture;

    if (!mounted) return;

    final auth = context.read<AuthProvider>();

    if (auth.status == AuthStatus.authenticated) {
      // Connectivity state is now accurate — the builder will immediately
      // show MeshNetworkOverlay on top of /home if the device is offline.
      Navigator.pushReplacementNamed(context, permissionsOk ? '/home' : '/permissions');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C1A),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'lib/assets/images/logo1.png',
                width: 80,
                height: 80,
                errorBuilder: (ctx, err, st) => Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF052e16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF16a34a)),
                  ),
                  child: const Icon(Icons.security, color: Color(0xFF22c55e), size: 40),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'DRD OPERATIONS',
                style: TextStyle(
                  color: Color(0xFF22c55e),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Field Coordination Platform',
                style: TextStyle(color: Color(0xFF60A5FA), fontSize: 13),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
