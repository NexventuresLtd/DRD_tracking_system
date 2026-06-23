import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../services/api_service.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  bool _confirming = false;
  bool _sending = false;
  bool _sent = false;
  int _countdown = 5;
  Timer? _timer;
  String _message = '';
  final _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _startConfirm() {
    setState(() { _confirming = true; _countdown = 5; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) { t.cancel(); _sendSOS(); }
    });
  }

  void _cancel() {
    _timer?.cancel();
    setState(() { _confirming = false; _countdown = 5; _message = ''; });
    _msgCtrl.clear();
  }

  Future<void> _sendSOS() async {
    _timer?.cancel();
    setState(() { _sending = true; _confirming = false; });
    final loc = context.read<LocationProvider>().current;
    try {
      await ApiService().post('/sos', {
        if (loc != null) 'latitude': loc.lat,
        if (loc != null) 'longitude': loc.lng,
        if (_message.isNotEmpty) 'message': _message,
      });
      if (mounted) setState(() { _sent = true; _sending = false; });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _sent = false);
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
    _msgCtrl.clear();
    _message = '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('SOS Alert', style: TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: _sent
            ? _buildSentState()
            : _confirming
                ? _buildConfirmState()
                : _buildIdleState(),
      ),
    );
  }

  Widget _buildIdleState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(const Color(0xFFDC2626), const Color(0xFFEF4444), _pulse.value),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.3 + 0.3 * _pulse.value),
                  blurRadius: 40 + 20 * _pulse.value,
                  spreadRadius: 8 + 8 * _pulse.value,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(90),
                onTap: _startConfirm,
                child: const Center(
                  child: Text('SOS', style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 4)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Text('Tap to send emergency alert', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
        const SizedBox(height: 8),
        const Text('Your location will be broadcast to all command personnel', textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF4B5563), fontSize: 12)),
        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: TextField(
            controller: _msgCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: (v) => _message = v,
            decoration: InputDecoration(
              hintText: 'Optional message…',
              hintStyle: const TextStyle(color: Color(0xFF4B5563)),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF374151))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDC2626))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFDC2626), width: 3),
              color: const Color(0xFF1A0505),
            ),
            child: Center(
              child: Text('$_countdown', style: const TextStyle(color: Color(0xFFDC2626), fontSize: 56, fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(height: 24),
          const Text('SENDING SOS IN', style: TextStyle(color: Color(0xFFEF4444), fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 8),
          const Text('Your location will be broadcast to all command personnel', textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF374151)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('CANCEL', style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _sending ? null : _sendSOS,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('SEND NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSentState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF166534),
              boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.4), blurRadius: 32)],
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 24),
          const Text('SOS SENT', style: TextStyle(color: Color(0xFF22C55E), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3)),
          const SizedBox(height: 8),
          const Text('Command has been alerted. Help is on the way.', textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
        ],
      ),
    );
  }
}
