import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class RegisterScreen extends StatefulWidget {
  // All params optional — invite-based and free registration share this screen
  final String? inviteToken;
  final String? teamName;
  final String? role;
  final String? serverUrl;

  const RegisterScreen({
    super.key,
    this.inviteToken,
    this.teamName,
    this.role,
    this.serverUrl,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  bool get _hasInvite => widget.inviteToken != null && widget.inviteToken!.isNotEmpty;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'operator': return 'Planning Officer';
      case 'commander': return 'Coordinator';
      case 'admin': return 'Administrator';
      default: return 'Field Unit';
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final body = <String, dynamic>{
        'full_name': _fullNameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'password': _passwordCtrl.text,
      };
      if (_hasInvite) body['invite_token'] = widget.inviteToken!;

      await _api.registerWithInvite(body);

      // Auto-login after registration
      final loginRes = await _api.post('/auth/login', {
        'username': _usernameCtrl.text.trim(),
        'password': _passwordCtrl.text,
      });

      if (!mounted) return;

      if (loginRes != null && loginRes['status'] == 'otp_required') {
        _showOtpSheet(loginRes['session_id'] as String, loginRes['email_hint'] as String? ?? '');
        return;
      }

      if (loginRes != null && loginRes['access_token'] != null) {
        await _storage.saveToken(loginRes['access_token']);
        if (loginRes['refresh_token'] != null) await _storage.saveRefreshToken(loginRes['refresh_token']);
        if (loginRes['user'] != null) await _storage.saveUserData(loginRes['user'] as Map<String, dynamic>);
      }

      if (!mounted) return;
      if (_hasInvite) {
        Navigator.of(context).pushNamedAndRemoveUntil('/splash', (_) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/join-network', (_) => false);
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showOtpSheet(String sessionId, String emailHint) {
    final otpCtrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1628),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSS) {
        String? sheetError;
        bool sheetLoading = false;

        Future<void> verify() async {
          if (otpCtrl.text.trim().length < 6) return;
          setSS(() { sheetLoading = true; sheetError = null; });
          try {
            final res = await _api.post('/auth/verify-otp', {
              'session_id': sessionId,
              'otp': otpCtrl.text.trim(),
            });
            if (res != null && res['access_token'] != null) {
              await _storage.saveToken(res['access_token']);
              if (res['refresh_token'] != null) await _storage.saveRefreshToken(res['refresh_token']);
              if (res['user'] != null) await _storage.saveUserData(res['user'] as Map<String, dynamic>);
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil('/join-network', (_) => false);
            } else {
              setSS(() { sheetError = 'Verification failed'; sheetLoading = false; });
            }
          } catch (e) {
            setSS(() { sheetError = e.toString().replaceFirst('Exception: ', ''); sheetLoading = false; });
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('VERIFY EMAIL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
              fontSize: 14, letterSpacing: 2, fontFamily: 'Poppins')),
            const SizedBox(height: 6),
            Text('Code sent to $emailHint',
              style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Poppins')),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(color: const Color(0xFF0A1628), borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DRDTheme.primaryColor.withValues(alpha: 0.4))),
              child: TextField(
                controller: otpCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900,
                  letterSpacing: 12, fontFamily: 'Poppins'),
                decoration: const InputDecoration(hintText: '000000',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 28, letterSpacing: 12),
                  border: InputBorder.none, counterText: '',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                onChanged: (v) { if (v.length == 6) verify(); },
              ),
            ),
            if (sheetError != null) ...[
              const SizedBox(height: 10),
              Text(sheetError!, style: const TextStyle(color: DRDTheme.dangerColor, fontSize: 11, fontFamily: 'Poppins')),
            ],
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: sheetLoading ? null : verify,
                style: ElevatedButton.styleFrom(backgroundColor: DRDTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: sheetLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('VERIFY', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2, fontFamily: 'Poppins')),
              ),
            ),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        title: const Text('CREATE ACCOUNT',
          style: TextStyle(fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_hasInvite ? DRDTheme.primaryColor : const Color(0xFF22C55E)).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_hasInvite ? DRDTheme.primaryColor : const Color(0xFF22C55E)).withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_hasInvite ? Icons.verified_user_outlined : Icons.person_add_alt_1_outlined,
                    color: _hasInvite ? DRDTheme.primaryColor : const Color(0xFF22C55E), size: 14),
                  const SizedBox(width: 8),
                  Text(_hasInvite ? 'INVITE VERIFIED' : 'FREE REGISTRATION',
                    style: TextStyle(
                      color: _hasInvite ? DRDTheme.primaryColor : const Color(0xFF22C55E),
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontFamily: 'Poppins')),
                ]),
                const SizedBox(height: 8),
                if (_hasInvite) ...[
                  _infoRow('Role', _roleLabel(widget.role)),
                  if (widget.teamName != null) _infoRow('Team', widget.teamName!),
                  _infoRow('Server', (widget.serverUrl ?? AppConstants.baseUrl).length > 36
                    ? '${(widget.serverUrl ?? AppConstants.baseUrl).substring(0, 36)}…'
                    : (widget.serverUrl ?? AppConstants.baseUrl)),
                ] else
                  const Text(
                    'Create a free account. You can join a team by scanning a QR code after registration.',
                    style: TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Poppins', height: 1.5)),
              ]),
            ),
            const SizedBox(height: 24),

            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: DRDTheme.dangerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DRDTheme.dangerColor.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: DRDTheme.dangerColor, size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(
                    color: DRDTheme.dangerColor, fontSize: 11, fontFamily: 'Poppins'))),
                ]),
              ),

            Form(
              key: _formKey,
              child: Column(children: [
                _field('FULL NAME', 'John Doe', Icons.person_outline, _fullNameCtrl,
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null),
                const SizedBox(height: 14),
                _field('USERNAME', 'soldier.alpha', Icons.badge_outlined, _usernameCtrl,
                  validator: (v) => (v == null || v.trim().length < 3) ? 'Min 3 characters' : null),
                const SizedBox(height: 14),
                _field('EMAIL', 'you@example.com', Icons.email_outlined, _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter valid email' : null),
                const SizedBox(height: 14),
                _field('ACCESS CODE', '••••••••', Icons.lock_outline, _passwordCtrl,
                  obscure: _obscurePass,
                  suffixIcon: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.white38, size: 16),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass)),
                  validator: (v) => (v == null || v.length < 8) ? 'Min 8 characters' : null),
                const SizedBox(height: 14),
                _field('CONFIRM ACCESS CODE', '••••••••', Icons.lock_outline, _confirmCtrl,
                  obscure: _obscureConfirm,
                  suffixIcon: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.white38, size: 16),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm)),
                  validator: (v) => v != _passwordCtrl.text ? 'Passwords do not match' : null),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _loading
                        ? DRDTheme.primaryColor.withValues(alpha: 0.4)
                        : DRDTheme.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('CREATE ACCOUNT', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2, fontFamily: 'Poppins')),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(children: [
      Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Poppins')),
      Expanded(child: Text(value, style: const TextStyle(
        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Poppins'),
        overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _field(String label, String hint, IconData icon, TextEditingController ctrl, {
    bool obscure = false, Widget? suffixIcon, TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 1.5, fontFamily: 'Poppins')),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: const Color(0xFF0A1628), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
        child: TextFormField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Poppins'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13, fontFamily: 'Poppins'),
            prefixIcon: Icon(icon, color: Colors.white38, size: 17),
            suffixIcon: suffixIcon,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            errorStyle: const TextStyle(color: DRDTheme.dangerColor, fontSize: 10, fontFamily: 'Poppins'),
          ),
          validator: validator,
        ),
      ),
    ]);
  }
}

