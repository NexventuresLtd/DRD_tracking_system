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

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _logoFadeAnim;
  late Animation<Offset> _logoSlideAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _logoFadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _logoSlideAnim = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
    ));

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _fadeController.forward();
        _slideController.forward();
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
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
      if (mounted) {
        Navigator.pushReplacementNamed(context, authProvider.getHomeRoute());
      }
    }
  }

  String _getFieldError(String? value, String field) {
    if (value == null || value.isEmpty) {
      return field == 'username'
          ? 'Enter your operator ID or username'
          : 'Access code is required';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C1A),
      body: Stack(
        children: [
          // Animated background grid
          _buildGrid(),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo section
                    SlideTransition(
                      position: _logoSlideAnim,
                      child: FadeTransition(
                        opacity: _logoFadeAnim,
                        child: _buildLogoSection(),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Form card
                    SlideTransition(
                      position: _slideAnim,
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: _buildFormCard(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Footer
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: _buildFooter(),
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

  Widget _buildGrid() {
    return CustomPaint(
      painter: _GridPainter(),
      size: Size.infinite,
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        // Shield icon with pulse
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) {
            return Transform.scale(
              scale: _pulseAnim.value,
              child: child,
            );
          },
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DRDTheme.primaryColor.withValues(alpha: 0.12),
              border: Border.all(
                color: DRDTheme.primaryColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 38,
                  color: DRDTheme.primaryColor,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF22C55E),
                      border: Border.all(
                        color: const Color(0xFF050C1A),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'DRD TRACKING',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 4,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'FIELD COORDINATION SYSTEM',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.35),
            letterSpacing: 3,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.sensors,
                    size: 13,
                    color: DRDTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AUTHENTICATE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.5),
                      letterSpacing: 3,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Error message from auth provider
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  if (auth.errorMessage == null) return const SizedBox.shrink();
                  String friendlyMsg = auth.errorMessage!;
                  if (auth.errorMessage!.toLowerCase().contains('401') ||
                      auth.errorMessage!.toLowerCase().contains('invalid') ||
                      auth.errorMessage!.toLowerCase().contains('incorrect') ||
                      auth.errorMessage!.toLowerCase().contains('wrong')) {
                    friendlyMsg = 'Invalid credentials. Verify your operator ID and access code.';
                  } else if (auth.errorMessage!.toLowerCase().contains('network') ||
                      auth.errorMessage!.toLowerCase().contains('connect') ||
                      auth.errorMessage!.toLowerCase().contains('timeout')) {
                    friendlyMsg = 'Cannot reach the command server. Check your network connection.';
                  } else if (auth.errorMessage!.toLowerCase().contains('locked') ||
                      auth.errorMessage!.toLowerCase().contains('disabled')) {
                    friendlyMsg = 'Account is locked. Contact your system administrator.';
                  }
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: DRDTheme.dangerColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DRDTheme.dangerColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: DRDTheme.dangerColor,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            friendlyMsg,
                            style: const TextStyle(
                              color: DRDTheme.dangerColor,
                              fontSize: 12,
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
              _AnimatedField(
                label: 'OPERATOR ID / USERNAME',
                hint: 'commander.alpha or user@drd.mil',
                icon: Icons.person_outline_rounded,
                controller: _usernameController,
                focused: _usernameFocused,
                onFocusChange: (v) => setState(() => _usernameFocused = v),
                validator: (v) {
                  final err = _getFieldError(v, 'username');
                  return err.isEmpty ? null : err;
                },
              ),
              const SizedBox(height: 16),

              // Password field
              _AnimatedField(
                label: 'ACCESS CODE',
                hint: '••••••••••',
                icon: Icons.lock_outline_rounded,
                controller: _passwordController,
                obscureText: _obscurePassword,
                focused: _passwordFocused,
                onFocusChange: (v) => setState(() => _passwordFocused = v),
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white38,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) {
                  final err = _getFieldError(v, 'password');
                  return err.isEmpty ? null : err;
                },
              ),
              const SizedBox(height: 28),

              // Submit button
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return _LoginButton(
                    isLoading: auth.isLoading,
                    onPressed: auth.isLoading ? null : _handleLogin,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF22C55E),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'SECURE ENCRYPTED CONNECTION',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.2),
            letterSpacing: 2,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }
}

class _AnimatedField extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool obscureText;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final Widget? suffix;
  final String? Function(String?)? validator;

  const _AnimatedField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscureText = false,
    required this.focused,
    required this.onFocusChange,
    this.suffix,
    this.validator,
  });

  @override
  State<_AnimatedField> createState() => _AnimatedFieldState();
}

class _AnimatedFieldState extends State<_AnimatedField> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: widget.focused
                ? DRDTheme.primaryColor
                : Colors.white.withValues(alpha: 0.3),
            letterSpacing: 2,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.focused
                  ? DRDTheme.primaryColor.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
              width: widget.focused ? 1.5 : 1,
            ),
            color: widget.focused
                ? DRDTheme.primaryColor.withValues(alpha: 0.05)
                : const Color(0xFF0A1628),
          ),
          child: Focus(
            onFocusChange: widget.onFocusChange,
            child: TextFormField(
              controller: widget.controller,
              obscureText: widget.obscureText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'Poppins',
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 12,
                  fontFamily: 'Poppins',
                ),
                prefixIcon: Icon(
                  widget.icon,
                  color: widget.focused
                      ? DRDTheme.primaryColor
                      : Colors.white.withValues(alpha: 0.25),
                  size: 18,
                ),
                suffixIcon: widget.suffix,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                errorStyle: const TextStyle(
                  color: DRDTheme.dangerColor,
                  fontSize: 10,
                  fontFamily: 'Poppins',
                ),
              ),
              validator: widget.validator,
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
  late AnimationController _pressController;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _pressAnim = Tween<double>(begin: 1.0, end: 0.97)
        .animate(_pressController);
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pressAnim,
      child: GestureDetector(
        onTapDown: (_) => _pressController.forward(),
        onTapUp: (_) => _pressController.reverse(),
        onTapCancel: () => _pressController.reverse(),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.isLoading || widget.onPressed == null
                  ? DRDTheme.primaryColor.withValues(alpha: 0.5)
                  : DRDTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: widget.isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'AUTHENTICATING...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.8),
                          letterSpacing: 2,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'AUTHENTICATE',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E3A5F).withValues(alpha: 0.15)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.3),
      size.width * 0.5,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}
