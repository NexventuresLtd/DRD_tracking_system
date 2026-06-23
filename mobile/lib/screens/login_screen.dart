import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

enum _Step { credentials, otp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  _Step _step = _Step.credentials;
  String _otpSession = '';
  String _emailHint = '';

  final List<TextEditingController> _otpCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());
  int _resendCooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    for (final c in _otpCtrl) { c.dispose(); }
    for (final f in _otpFocus) { f.dispose(); }
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _resendCooldown--);
      if (_resendCooldown <= 0) t.cancel();
    });
  }

  Future<void> _submitCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final result = await auth.initiateLogin(
      _emailCtrl.text.trim(), _passCtrl.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result != null) {
      setState(() {
        _otpSession = result['otp_session']!;
        _emailHint = result['email_hint']!;
        _step = _Step.otp;
      });
      _startCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocus[0].requestFocus();
      });
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpCtrl.map((c) => c.text).join();
    if (code.length != 6) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOtp(_otpSession, code);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      for (final c in _otpCtrl) { c.clear(); }
      _otpFocus[0].requestFocus();
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    final auth = context.read<AuthProvider>();
    await auth.resendOtp(_otpSession);
    for (final c in _otpCtrl) { c.clear(); }
    _startCooldown();
    _otpFocus[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final error = context.select<AuthProvider, String?>((a) => a.error);
    return Scaffold(
      backgroundColor: const Color(0xFF060E06),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogo(),
              const SizedBox(height: 40),
              if (_step == _Step.credentials) _buildCredentials(error),
              if (_step == _Step.otp) _buildOtp(error),
              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'AUTHORIZED PERSONNEL ONLY · DRD OPS',
                  style: TextStyle(
                    color: Color(0xFF162616),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      children: [
        Image.asset(
          'assets/images/logo1.png',
          height: 42,
          errorBuilder: (ctx, err, stack) => Container(
            width: 42, height: 42,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF16a34a))),
            alignment: Alignment.center,
            child: const Text('DRD',
              style: TextStyle(color: Color(0xFF22c55e), fontSize: 11,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DRD OPERATIONS',
              style: TextStyle(color: Color(0xFF22c55e), fontSize: 13,
                  fontWeight: FontWeight.bold, letterSpacing: 2,
                  fontFamily: 'monospace')),
            Text('FIELD COORDINATION SYSTEM',
              style: TextStyle(color: Color(0xFF1f4d1f), fontSize: 8,
                  letterSpacing: 2, fontFamily: 'monospace')),
          ],
        ),
      ],
    );
  }

  Widget _buildCredentials(String? error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sign In',
          style: TextStyle(color: Color(0xFFECFDF5), fontSize: 26,
              fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Enter your credentials to access the platform',
          style: TextStyle(color: Color(0xFF4B5563), fontSize: 14)),
        const SizedBox(height: 28),
        if (error != null) ...[_ErrorBanner(message: error), const SizedBox(height: 16)],
        Form(
          key: _formKey,
          child: Column(
            children: [
              _DrdField(
                controller: _emailCtrl,
                label: 'Email or Username',
                hint: 'your@email.com or username',
                icon: Icons.person_outline,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _DrdField(
                controller: _passCtrl,
                label: 'Password',
                hint: '••••••••••••',
                icon: Icons.lock_outline,
                obscure: _obscure,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: const Color(0xFF4B5563), size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (v) => (v == null || v.length < 4) ? 'Password too short' : null,
              ),
              const SizedBox(height: 24),
              _DrdButton(label: 'Continue', loading: _loading, onPressed: _submitCredentials),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/enroll'),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Enroll with QR / Voucher'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4B5563),
                  side: const BorderSide(color: Color(0xFF1F2D1F)),
                  minimumSize: const Size(double.infinity, 48),
                  shape: const RoundedRectangleBorder(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtp(String? error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Verify Identity',
          style: TextStyle(color: Color(0xFFECFDF5), fontSize: 26,
              fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            style: const TextStyle(color: Color(0xFF4B5563), fontSize: 14),
            children: [
              const TextSpan(text: 'A 6-digit code was sent to '),
              TextSpan(
                text: _emailHint,
                style: const TextStyle(
                    color: Color(0xFF22c55e), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (error != null) ...[_ErrorBanner(message: error), const SizedBox(height: 16)],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) => _OtpBox(
            controller: _otpCtrl[i],
            focusNode: _otpFocus[i],
            onChanged: (val) {
              if (val.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus();
              final full = _otpCtrl.map((c) => c.text).join();
              if (full.length == 6) _verifyOtp();
            },
            onBackspace: () {
              if (_otpCtrl[i].text.isEmpty && i > 0) {
                _otpCtrl[i - 1].clear();
                _otpFocus[i - 1].requestFocus();
              }
            },
          )),
        ),
        const SizedBox(height: 24),
        _DrdButton(label: 'Verify & Sign In', loading: _loading, onPressed: _verifyOtp),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                setState(() => _step = _Step.credentials);
                for (final c in _otpCtrl) { c.clear(); }
              },
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('← Back',
                style: TextStyle(color: Color(0xFF4B5563), fontSize: 13)),
            ),
            TextButton(
              onPressed: _resendCooldown > 0 ? null : _resend,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend code',
                style: TextStyle(
                  color: _resendCooldown > 0
                      ? const Color(0xFF374151)
                      : const Color(0xFF16a34a),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Shared sub-widgets ──

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0x2F7F1D1D),
        border: Border(
          left: const BorderSide(color: Color(0xFFDC2626), width: 3),
          top: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
          right: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
          bottom: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _DrdField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _DrdField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: const TextStyle(
              color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF374151)),
            prefixIcon: Icon(icon, color: const Color(0xFF4B5563), size: 18),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF050D05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.green.withValues(alpha: 0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.green.withValues(alpha: 0.15)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFF16a34a)),
            ),
            errorBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFDC2626)),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFDC2626)),
            ),
          ),
        ),
      ],
    );
  }
}

class _DrdButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _DrdButton({
    required this.label,
    required this.loading,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16a34a),
          disabledBackgroundColor: const Color(0xFF052e16),
          shape: const RoundedRectangleBorder(),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF22c55e)))
            : Text(label,
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF22c55e),
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: const Color(0xFF050D05),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.green.withValues(alpha: 0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.green.withValues(alpha: 0.15)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFF16a34a), width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
