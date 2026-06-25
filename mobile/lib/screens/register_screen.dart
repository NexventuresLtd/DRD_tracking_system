import 'package:flutter/material.dart';

/// Step 1 of enrollment: collect user info, then proceed to QR/voucher scan.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pushNamed(context, '/enroll', arguments: {
      'full_name': _nameCtrl.text.trim(),
      'username': _usernameCtrl.text.trim().toLowerCase(),
      'email': _emailCtrl.text.trim().toLowerCase(),
      'password': _passCtrl.text,
    });
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
    prefixIcon: Icon(icon, color: const Color(0xFF374151), size: 18),
    filled: true,
    fillColor: const Color(0xFF111827),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF374151))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF374151))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF16A34A))),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626))),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626))),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(height: 2, color: const Color(0xFF16A34A)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Step indicator
              Row(
                children: [
                  _StepDot(number: 1, label: 'Your Info', active: true),
                  Expanded(child: Container(height: 1, color: const Color(0xFF1F2937))),
                  _StepDot(number: 2, label: 'Scan Voucher', active: false),
                ],
              ),
              const SizedBox(height: 28),
              const Text('Personal Information', style: TextStyle(color: Color(0xFF22C55E), fontSize: 11, letterSpacing: 2, fontFamily: 'monospace')),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _dec('Full Name *', Icons.person_outline),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _dec('Username *', Icons.alternate_email),
                autocorrect: false,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length < 3) return 'At least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _dec('Email Address *', Icons.email_outlined),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text('Security', style: TextStyle(color: Color(0xFF22C55E), fontSize: 11, letterSpacing: 2, fontFamily: 'monospace')),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _dec('Password *', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF6B7280), size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 8) return 'At least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _dec('Confirm Password *', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF6B7280), size: 18),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) => v != _passCtrl.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Next — Scan Network Voucher', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Already have an account? Sign in', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int number;
  final String label;
  final bool active;
  const _StepDot({required this.number, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF16A34A) : const Color(0xFF1F2937),
            border: Border.all(color: active ? const Color(0xFF16A34A) : const Color(0xFF374151)),
          ),
          child: Center(
            child: Text('$number', style: TextStyle(color: active ? Colors.white : const Color(0xFF6B7280), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: active ? const Color(0xFF22C55E) : const Color(0xFF4B5563), fontSize: 10)),
      ],
    );
  }
}
