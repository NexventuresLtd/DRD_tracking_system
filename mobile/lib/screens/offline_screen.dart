import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class OfflineOverlay extends StatefulWidget {
  const OfflineOverlay({super.key});

  @override
  State<OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<OfflineOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    final result = await Connectivity().checkConnectivity();
    final online = result.isNotEmpty && !result.every((r) => r == ConnectivityResult.none);
    if (!online && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still no connection. Try again.'),
          backgroundColor: Color(0xFF7F1D1D),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF030712),
      child: Stack(
        children: [
          // Tactical grid background
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing no-wifi icon
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) => Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(
                            const Color(0xFFDC2626).withValues(alpha: 0.08),
                            const Color(0xFFDC2626).withValues(alpha: 0.18),
                            _pulse.value,
                          ),
                          border: Border.all(
                            color: Color.lerp(
                              const Color(0xFFDC2626).withValues(alpha: 0.3),
                              const Color(0xFFDC2626).withValues(alpha: 0.7),
                              _pulse.value,
                            )!,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 40),
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
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'DRD Operations requires a network connection to track field positions and receive command updates.',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 13, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Status rows
                    _StatusRow(
                      color: const Color(0xFFDC2626),
                      label: 'Command link severed',
                      animate: true,
                    ),
                    const SizedBox(height: 8),
                    _StatusRow(
                      color: const Color(0xFFF59E0B),
                      label: 'Waiting for network…',
                      animate: false,
                    ),
                    const SizedBox(height: 32),

                    // Retry button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _retry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          'Retry Connection',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'AUTHORIZED PERSONNEL ONLY · DRD OPS',
                      style: TextStyle(color: Color(0xFF1F2937), fontSize: 9, letterSpacing: 2),
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
}

class _StatusRow extends StatelessWidget {
  final Color color;
  final String label;
  final bool animate;
  const _StatusRow({required this.color, required this.label, required this.animate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          if (animate)
            _PingDot(color: color)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PingDot extends StatefulWidget {
  final Color color;
  const _PingDot({required this.color});

  @override
  State<_PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<_PingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.4 + 0.6 * _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF22C55E).withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
