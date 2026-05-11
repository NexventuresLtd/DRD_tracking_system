import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class OfflineOverlay extends StatefulWidget {
  final Widget child;
  const OfflineOverlay({super.key, required this.child});

  @override
  State<OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<OfflineOverlay>
    with SingleTickerProviderStateMixin {
  bool _offline = false;
  StreamSubscription? _sub;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _checkInitial();
    _sub = Connectivity().onConnectivityChanged.listen(_onChanged);
  }

  Future<void> _checkInitial() async {
    final results = await Connectivity().checkConnectivity();
    _evalConnectivity(results);
  }

  void _evalConnectivity(List<ConnectivityResult> results) {
    final isOffline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (mounted && isOffline != _offline) setState(() => _offline = isOffline);
  }

  void _onChanged(List<ConnectivityResult> results) => _evalConnectivity(results);

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand, // ensures child (Navigator) fills all available space
      children: [
        widget.child,
        if (_offline) _buildOfflineScreen(context),
      ],
    );
  }

  Widget _buildOfflineScreen(BuildContext context) {
    return Material(
      color: const Color(0xFF050C1A),
      child: Stack(
        children: [
          // Tactical grid background
          CustomPaint(painter: _GridPainter(), size: Size.infinite),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pulsing disconnected icon
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEF4444).withValues(
                            alpha: 0.08 + 0.07 * _pulseCtrl.value,
                          ),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(
                              alpha: 0.3 + 0.2 * _pulseCtrl.value,
                            ),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.wifi_off_rounded,
                          color: Color(0xFFEF4444),
                          size: 36,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    const Text(
                      'NO CONNECTION',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'DRD Tracking requires an active network connection to receive live field data and send your position.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                        height: 1.6,
                        fontFamily: 'Poppins',
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Status items
                    _statusRow(
                      Icons.link_off_rounded,
                      'Command link severed',
                      const Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => _statusRow(
                        Icons.sensors_rounded,
                        'Waiting for network…',
                        Color.lerp(
                          const Color(0xFFF59E0B),
                          Colors.white54,
                          _pulseCtrl.value,
                        )!,
                      ),
                    ),

                    const SizedBox(height: 36),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _checkInitial,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Retry Connection',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    Text(
                      'AUTHORIZED PERSONNEL ONLY · DRD OPS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.15),
                        fontSize: 9,
                        letterSpacing: 2,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(IconData icon, String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    const sp = 44.0;
    for (double x = 0; x <= size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
