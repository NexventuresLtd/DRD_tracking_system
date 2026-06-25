import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connectivity_provider.dart';

/// Wraps a screen or feature that needs internet.
///
/// [bleAllowed] — if true, the feature also works in BLE-bridge mode
/// (chat, location, SOS pass bleAllowed: true; everything else doesn't).
class RequiresOnline extends StatelessWidget {
  final Widget child;
  final bool bleAllowed;

  const RequiresOnline({super.key, required this.child, this.bleAllowed = false});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityProvider>();
    final allowed = conn.online || (bleAllowed && conn.isBleOnly);
    if (allowed) return child;
    return _BlockedOverlay(bleMode: conn.isBleOnly, bleAllowed: bleAllowed);
  }
}

class _BlockedOverlay extends StatelessWidget {
  final bool bleMode;
  final bool bleAllowed;
  const _BlockedOverlay({required this.bleMode, required this.bleAllowed});

  @override
  Widget build(BuildContext context) {
    final message = bleMode && !bleAllowed
        ? 'This feature requires an internet connection.\nCurrently running on BLE bridge only.'
        : 'No internet connection.\nConnect to WiFi or pair with the BLE bridge to continue.';

    final icon = bleMode ? Icons.bluetooth_disabled : Icons.wifi_off;
    final color = bleMode ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                bleMode ? 'BLE BRIDGE MODE' : 'NO CONNECTION',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13, height: 1.6),
                textAlign: TextAlign.center,
              ),
              if (bleMode && !bleAllowed) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1A3A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1D4ED8).withValues(alpha: 0.4)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 14),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Available over BLE: SOS · Location',
                        style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
