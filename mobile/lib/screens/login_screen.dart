import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../config/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _usernameFocused = false;
  bool _passwordFocused = false;

  late AnimationController _entranceController;
  late AnimationController _waveController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _waveAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.1, 1.0, curve: Curves.easeOutCubic),
    ));
    _waveAnim = CurvedAnimation(parent: _waveController, curve: Curves.linear);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    if (success && mounted) {
      final userId = authProvider.user?.id;
      if (userId != null) {
        try {
          await context.read<LocationProvider>().initialize(userId);
        } catch (e) {
          debugPrint('Location init error: $e');
        }
      }
      if (mounted) Navigator.pushReplacementNamed(context, authProvider.getHomeRoute());
    }
  }

  String _friendlyError(String? raw) {
    final s = (raw ?? '').toLowerCase();
    if (s.contains('401') || s.contains('invalid') || s.contains('incorrect') || s.contains('wrong')) {
      return 'Invalid credentials. Check your ID and access code.';
    }
    if (s.contains('network') || s.contains('connect') || s.contains('timeout')) {
      return 'Cannot reach command server. Check your connection.';
    }
    if (s.contains('locked') || s.contains('disabled')) {
      return 'Account locked. Contact your administrator.';
    }
    return raw ?? 'Authentication failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF050C1A),
      body: Stack(
        children: [
          // ── Background gradient ────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A1628), Color(0xFF050C1A)],
              ),
            ),
          ),

          // ── Animated bubbles (background decoration) ───────────────────
          AnimatedBuilder(
            animation: _waveAnim,
            builder: (context2, child) {
              return CustomPaint(
                painter: _BubblePainter(_waveAnim.value),
                size: Size(size.width, size.height),
              );
            },
          ),

          // ── Top wave section ───────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: size.height * 0.42,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A3A6B), Color(0xFF0D2144)],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      // Shield icon with pulse
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, child) => Transform.scale(
                          scale: _pulseAnim.value,
                          child: child,
                        ),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: DRDTheme.primaryColor.withValues(alpha: 0.2),
                            border: Border.all(
                              color: DRDTheme.primaryColor.withValues(alpha: 0.6),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: DRDTheme.primaryColor.withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'drd_tracking',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'FIELD COORDINATION SYSTEM',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 9,
                          letterSpacing: 3,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom form section ────────────────────────────────────────
          Positioned(
            top: size.height * 0.34,
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: _slideAnim,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    24 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome Back',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in to your tactical account',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 28),

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Error banner
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) {
                                if (auth.errorMessage == null) return const SizedBox.shrink();
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.only(bottom: 18),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: DRDTheme.dangerColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: DRDTheme.dangerColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: DRDTheme.dangerColor, size: 16),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _friendlyError(auth.errorMessage),
                                          style: const TextStyle(
                                            color: DRDTheme.dangerColor,
                                            fontSize: 11,
                                            fontFamily: 'Poppins',
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            // Username field
                            _buildField(
                              label: 'OPERATOR ID / USERNAME',
                              hint: 'commander.alpha or user@drd.mil',
                              icon: Icons.person_outline_rounded,
                              controller: _usernameController,
                              focused: _usernameFocused,
                              onFocusChange: (v) => setState(() => _usernameFocused = v),
                              validator: (v) => (v == null || v.isEmpty) ? 'Enter your operator ID' : null,
                            ),
                            const SizedBox(height: 16),

                            // Password field
                            _buildField(
                              label: 'ACCESS CODE',
                              hint: '••••••••••',
                              icon: Icons.lock_outline_rounded,
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              focused: _passwordFocused,
                              onFocusChange: (v) => setState(() => _passwordFocused = v),
                              suffix: IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              validator: (v) => (v == null || v.isEmpty) ? 'Enter your access code' : null,
                            ),
                            const SizedBox(height: 28),

                            // Submit button
                            Consumer<AuthProvider>(
                              builder: (context, auth, _) => _LoginButton(
                                isLoading: auth.isLoading,
                                onPressed: auth.isLoading ? null : _handleLogin,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Footer
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF22C55E),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'SECURE ENCRYPTED CONNECTION',
                                    style: TextStyle(
                                      fontSize: 8,
                                      letterSpacing: 2,
                                      color: Colors.white.withValues(alpha: 0.2),
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    bool obscureText = false,
    required bool focused,
    required ValueChanged<bool> onFocusChange,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            fontFamily: 'Poppins',
            color: focused ? DRDTheme.primaryColor : Colors.white.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: focused ? const Color(0xFF0D2144) : const Color(0xFF0A1628),
            border: Border.all(
              color: focused
                  ? DRDTheme.primaryColor.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Focus(
            onFocusChange: onFocusChange,
            child: TextFormField(
              controller: controller,
              obscureText: obscureText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'Poppins',
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 12,
                  fontFamily: 'Poppins',
                ),
                prefixIcon: Icon(
                  icon,
                  color: focused ? DRDTheme.primaryColor : Colors.white.withValues(alpha: 0.25),
                  size: 18,
                ),
                suffixIcon: suffix,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                errorStyle: const TextStyle(
                  color: DRDTheme.dangerColor,
                  fontSize: 10,
                  fontFamily: 'Poppins',
                ),
              ),
              validator: validator,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  const _LoginButton({required this.isLoading, required this.onPressed});

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) => _ctrl.reverse(),
        onTapCancel: () => _ctrl.reverse(),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.onPressed == null
                  ? DRDTheme.primaryColor.withValues(alpha: 0.45)
                  : DRDTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: widget.onPressed == null ? 0 : 4,
              shadowColor: DRDTheme.primaryColor.withValues(alpha: 0.4),
            ),
            child: widget.isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('AUTHENTICATING...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, fontFamily: 'Poppins')),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 16),
                      SizedBox(width: 8),
                      Text('AUTHENTICATE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.5, fontFamily: 'Poppins')),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Wave clip shape ────────────────────────────────────────────────────────
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 44);
    path.quadraticBezierTo(size.width * 0.25, size.height, size.width * 0.5, size.height - 22);
    path.quadraticBezierTo(size.width * 0.75, size.height - 44, size.width, size.height - 22);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper _) => false;
}

// ── Floating bubble background painter ────────────────────────────────────
class _BubblePainter extends CustomPainter {
  final double t;
  _BubblePainter(this.t);

  static const _bubbles = [
    (0.1, 0.2, 60.0), (0.8, 0.15, 40.0), (0.6, 0.35, 25.0),
    (0.2, 0.55, 35.0), (0.9, 0.6, 50.0), (0.4, 0.8, 20.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var (x, y, r) in _bubbles) {
      final dy = (t * 0.04) % 1.0;
      final cy = ((y - dy + 1.0) % 1.0) * size.height;
      final paint = Paint()
        ..color = const Color(0xFF3B82F6).withValues(alpha: 0.06)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x * size.width, cy), r, paint);
      final stroke = Paint()
        ..color = const Color(0xFF3B82F6).withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(Offset(x * size.width, cy), r, stroke);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.t != t;
}
