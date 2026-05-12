import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../config/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Permission flow state
  bool _permissionDenied = false;
  bool _permissionDeniedForever = false;
  String _statusText = 'INITIALIZING…';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();

    // Start permission check immediately — no artificial delay
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    setState(() => _statusText = 'CHECKING PERMISSIONS…');

    // ── 1. Location service must be on ──────────────────────────────────────
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {

        _permissionDenied = true;
        _statusText = 'LOCATION SERVICES OFF';
      });
      return;
    }

    // ── 2. Foreground location permission ───────────────────────────────────
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      setState(() => _statusText = 'REQUESTING LOCATION…');
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {

        _permissionDeniedForever = true;
        _permissionDenied = true;
        _statusText = 'LOCATION PERMISSION BLOCKED';
      });
      return;
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      setState(() {

        _permissionDenied = true;
        _statusText = 'LOCATION PERMISSION REQUIRED';
      });
      return;
    }

    // ── 3. Background location permission (Android 10+) ─────────────────────
    // Only request "always" when user has granted foreground first.
    if (permission == LocationPermission.whileInUse) {
      setState(() => _statusText = 'REQUESTING BACKGROUND LOCATION…');
      permission = await Geolocator.requestPermission();
      // If they decline background-only, proceed with foreground — don't block.
    }

    // ── 4. All good — proceed ────────────────────────────────────────────────
    if (!mounted) return;
    setState(() => _statusText = 'LOADING…');
    await _navigateToApp();
  }

  Future<void> _navigateToApp() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.checkAuthStatus();
    if (!mounted) return;

    final route = authProvider.isAuthenticated
        ? authProvider.getHomeRoute()
        : '/login';

    if (authProvider.isAuthenticated) {
      final userId = authProvider.user?.id;
      if (userId != null) {
        try {
          await context
              .read<LocationProvider>()
              .initialize(userId, teamId: authProvider.user?.teamId);
        } catch (e) {
          debugPrint('Location init error: $e');
        }
      }
    }

    if (mounted) Navigator.pushReplacementNamed(context, route);
  }

  Future<void> _retryPermission() async {
    setState(() {

      _permissionDenied = false;
      _permissionDeniedForever = false;
      _statusText = 'RETRYING…';
    });
    await _boot();
  }

  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
    // Re-check after user returns from settings
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) await _retryPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Logo ───────────────────────────────────────────────
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: DRDTheme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'lib/assets/logo1.png',
                        width: 110,
                        height: 110,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'DRD',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'FIELD COORDINATION SYSTEM',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: 3.5,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // ── Permission gate UI ─────────────────────────────────
                    if (_permissionDenied) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: DRDTheme.dangerColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: DRDTheme.dangerColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.location_off,
                              color: DRDTheme.dangerColor,
                              size: 36,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'LOCATION PERMISSION REQUIRED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'DRD needs access to your location to track your '
                              'position and send it to the command centre. '
                              'This app cannot function without it.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (_permissionDeniedForever) ...[
                              ElevatedButton.icon(
                                onPressed: _openSettings,
                                icon: const Icon(Icons.settings, size: 16),
                                label: const Text('OPEN APP SETTINGS'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: DRDTheme.primaryColor,
                                  minimumSize: const Size(double.infinity, 44),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Permission was permanently blocked. '
                                'Enable it in Settings → Permissions → Location.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 10,
                                  height: 1.5,
                                ),
                              ),
                            ] else
                              ElevatedButton.icon(
                                onPressed: _retryPermission,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('GRANT PERMISSION'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: DRDTheme.primaryColor,
                                  minimumSize: const Size(double.infinity, 44),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // ── Loading indicator ──────────────────────────────
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            DRDTheme.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
