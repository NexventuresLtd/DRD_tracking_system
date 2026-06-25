import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  final _svc = PermissionService.instance;
  Map<Permission, PermissionStatus> _statuses = {};
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    final map = <Permission, PermissionStatus>{};
    for (final info in _svc.all) {
      map[info.permission] = await _svc.statusOf(info.permission);
    }
    if (mounted) setState(() { _statuses = map; _checking = false; });
  }

  Future<void> _requestOne(Permission p) async {
    final s = await _svc.requestOne(p);
    if (mounted) setState(() => _statuses[p] = s);
  }

  Future<void> _requestAll() async {
    final statuses = await _svc.requestAll();
    if (mounted) setState(() => _statuses = {..._statuses, ...statuses});
  }

  bool get _canContinue {
    for (final info in _svc.all.where((i) => i.critical)) {
      final s = _statuses[info.permission];
      if (s == null || (!s.isGranted && !s.isLimited)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const _Header(),
            const SizedBox(height: 32),
            Expanded(
              child: _checking
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: _svc.all.map((info) {
                        final status = _statuses[info.permission];
                        return _PermissionCard(
                          info: info,
                          status: status,
                          onGrant: () => _requestOne(info.permission),
                          onOpenSettings: _svc.openSettings,
                        );
                      }).toList(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  // Always-visible "Open Phone Settings" link
                  GestureDetector(
                    onTap: _svc.openSettings,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.settings_outlined, color: Color(0xFF60A5FA), size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Open Phone Settings',
                            style: TextStyle(color: Color(0xFF60A5FA), fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _requestAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F2937),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Grant All Permissions', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canContinue ? _continue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF14532D).withValues(alpha: 0.4),
                        disabledForegroundColor: const Color(0xFF4B5563),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  if (!_canContinue)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Grant all required permissions to continue.',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _continue() {
    Navigator.pushReplacementNamed(context, '/home');
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF052E16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF16A34A)),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF22C55E), size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'App Permissions',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'DRD Operations needs the following permissions to function in the field. Required permissions must be granted to continue.',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Permission card ───────────────────────────────────────────────────────────

class _PermissionCard extends StatelessWidget {
  final PermissionInfo info;
  final PermissionStatus? status;
  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;

  const _PermissionCard({
    required this.info,
    required this.status,
    required this.onGrant,
    required this.onOpenSettings,
  });

  bool get _granted => status?.isGranted == true || status?.isLimited == true;
  bool get _permanentlyDenied => status?.isPermanentlyDenied == true;

  Color get _statusColor {
    if (_granted) return const Color(0xFF22C55E);
    if (_permanentlyDenied) return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  IconData get _statusIcon {
    if (_granted) return Icons.check_circle;
    if (_permanentlyDenied) return Icons.block;
    return Icons.radio_button_unchecked;
  }

  String get _statusLabel {
    if (_granted) return 'Granted';
    if (_permanentlyDenied) return 'Blocked';
    if (status?.isDenied == true) return 'Denied';
    return 'Not requested';
  }

  IconData get _permIcon {
    switch (info.permission) {
      case Permission.locationAlways:
      case Permission.locationWhenInUse:
        return Icons.location_on_outlined;
      case Permission.camera:
        return Icons.camera_alt_outlined;
      case Permission.microphone:
        return Icons.mic_outlined;
      case Permission.notification:
        return Icons.notifications_outlined;
      case Permission.photos:
      case Permission.storage:
        return Icons.photo_library_outlined;
      case Permission.bluetoothScan:
        return Icons.bluetooth_searching;
      case Permission.bluetoothConnect:
        return Icons.bluetooth_connected;
      case Permission.bluetoothAdvertise:
        return Icons.settings_bluetooth;
      case Permission.nearbyWifiDevices:
        return Icons.wifi_find;
      default:
        return Icons.security_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _granted
              ? const Color(0xFF14532D)
              : _permanentlyDenied
                  ? const Color(0xFF7F1D1D)
                  : const Color(0xFF1F2937),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_permIcon, color: _statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(info.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 6),
                    if (!info.critical)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('optional', style: TextStyle(color: Color(0xFF6B7280), fontSize: 9, letterSpacing: 0.5)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(info.reason, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, height: 1.4)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(_statusIcon, color: _statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(_statusLabel, style: TextStyle(color: _statusColor, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!_granted)
            _ActionButton(
              label: _permanentlyDenied ? 'Settings' : 'Grant',
              onTap: _permanentlyDenied ? onOpenSettings : onGrant,
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF374151)),
        ),
        child: Text(label, style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
