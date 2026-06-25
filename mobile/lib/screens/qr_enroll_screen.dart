import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/auth_provider.dart';
import '../services/permission_service.dart';

enum EnrollMode { qr, voucher }

/// Step 2 of enrollment: scan QR or enter voucher code.
/// Receives user info from RegisterScreen via route arguments:
/// { full_name, username, email, password }
class QREnrollScreen extends StatefulWidget {
  const QREnrollScreen({super.key});

  @override
  State<QREnrollScreen> createState() => _QREnrollScreenState();
}

class _QREnrollScreenState extends State<QREnrollScreen> {
  EnrollMode _mode = EnrollMode.qr;
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _scanned = false;
  Map<String, String>? _userInfo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, String>) {
      _userInfo = args;
    } else if (args is Map) {
      _userInfo = {for (final e in args.entries) e.key.toString(): e.value.toString()};
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enroll(String code) async {
    if (_loading) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();

    bool ok;
    if (_userInfo != null) {
      // Full enrollment: user info + voucher code
      ok = await auth.enrollWithVoucher(
        voucherCode: code,
        email: _userInfo!['email'] ?? '',
        username: _userInfo!['username'] ?? '',
        fullName: _userInfo!['full_name'] ?? '',
        password: _userInfo!['password'] ?? '',
      );
    } else {
      // Legacy: only code (backward compat for direct /enroll navigation)
      ok = await auth.enrollLegacy(code);
    }

    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      final permsOk = await PermissionService.instance.allCriticalGranted();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, permsOk ? '/home' : '/permissions');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Invalid code or email already registered'),
          backgroundColor: const Color(0xFF7F1D1D),
        ),
      );
      setState(() => _scanned = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Scan Network Voucher', style: TextStyle(color: Colors.white, fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            children: [
              _Tab(label: 'QR Code', selected: _mode == EnrollMode.qr, onTap: () => setState(() { _mode = EnrollMode.qr; _scanned = false; })),
              _Tab(label: 'Voucher Code', selected: _mode == EnrollMode.voucher, onTap: () => setState(() => _mode = EnrollMode.voucher)),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          if (_userInfo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: const Color(0xFF052E16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enrolling as ${_userInfo!['full_name'] ?? ''} (${_userInfo!['email'] ?? ''})',
                      style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _mode == EnrollMode.qr ? _buildQR() : _buildVoucher()),
        ],
      ),
    );
  }

  Widget _buildQR() {
    return Column(
      children: [
        Expanded(
          child: _scanned
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF16A34A)))
              : MobileScanner(
                  onDetect: (capture) {
                    if (_scanned) return;
                    final code = capture.barcodes.first.rawValue;
                    if (code != null) {
                      setState(() => _scanned = true);
                      _enroll(code);
                    }
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF0F172A),
          child: const Text(
            'Point your camera at the network enrollment QR code provided by your coordinator.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildVoucher() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('Voucher Code', style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 2),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'XXXX-XXXX',
              hintStyle: const TextStyle(color: Color(0xFF4B5563), letterSpacing: 2),
              filled: true,
              fillColor: const Color(0xFF111827),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF374151))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF374151))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF16A34A))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : () => _enroll(_codeCtrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                disabledBackgroundColor: const Color(0xFF14532D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Join Network', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? const Color(0xFF16A34A) : Colors.transparent, width: 2))),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: selected ? const Color(0xFF4ADE80) : const Color(0xFF6B7280), fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    );
  }
}
