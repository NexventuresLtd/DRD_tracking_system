import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/mesh_provider.dart';
import '../providers/auth_provider.dart';
import '../services/mesh_service.dart';
import '../services/ble_service.dart';
import '../services/permission_service.dart';

/// Full-screen overlay shown when the device is fully isolated (no path to server).
/// Shows both WiFi LAN mesh peers (green) and BLE peers (blue).
/// The user can dismiss it to continue using the app in offline/queued mode.
class MeshNetworkOverlay extends StatefulWidget {
  const MeshNetworkOverlay({super.key});

  @override
  State<MeshNetworkOverlay> createState() => _MeshNetworkOverlayState();
}

class _MeshNetworkOverlayState extends State<MeshNetworkOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  bool _dismissed = false;

  void _dismiss() => setState(() => _dismissed = true);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mesh = context.read<MeshProvider>();
      if (!mesh.active) {
        final userName = context.read<AuthProvider>().user?.username;
        mesh.start(userName: userName);
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshProvider>();

    // User chose to continue in offline/queued mode — show only a warning banner
    if (_dismissed) {
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0A0A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                const Icon(Icons.wifi_off, color: Color(0xFFEF4444), size: 14),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ISOLATED — data queuing locally',
                    style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _dismissed = false),
                  child: const Icon(Icons.fullscreen, color: Color(0xFF6B7280), size: 16),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Material(
      color: const Color(0xFF030712),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HexGridPainter())),

          SafeArea(
            child: Column(
              children: [
                _Header(
                  pulse: _pulse,
                  anyPeer: mesh.anyPeer,
                  bleAdapterOn: mesh.bleAdapterOn,
                ),

                // Scrollable body — node graph + permissions + device list + stats
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        // Node visualisation
                        SizedBox(
                          height: 200,
                          child: Center(
                            child: _NodeGraph(
                              pulse: _pulse,
                              wifiPeers: mesh.peers,
                              blePeers: mesh.blePeers,
                            ),
                          ),
                        ),

                        // Bluetooth permission check + grant
                        const _BlePermSection(),

                        // All nearby BLE devices with connect / pair
                        _DeviceList(peers: mesh.blePeers),

                        // BLE discovery stats bar
                        _BleBar(
                          adapterOn: mesh.bleAdapterOn,
                          nearby: mesh.bleNearby,
                          drd: mesh.bleDrd,
                          connected: mesh.bleConnected,
                        ),

                        _StatsRow(
                          peerCount: mesh.peerCount,
                          msgRelayed: mesh.msgRelayed,
                          active: mesh.active,
                          bleDrd: mesh.bleDrd,
                        ),

                        _EventLog(entries: mesh.log),
                      ],
                    ),
                  ),
                ),

                _ActionBar(mesh: mesh, onDismiss: _dismiss),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AnimationController pulse;
  final bool anyPeer;
  final bool bleAdapterOn;
  const _Header({required this.pulse, required this.anyPeer, required this.bleAdapterOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF050D05),
        border: Border(bottom: BorderSide(color: Color(0xFF0F2D0F), width: 1)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (_, _) => Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: anyPeer
                    ? Color.lerp(const Color(0xFF22C55E), const Color(0xFF86EFAC), pulse.value)
                    : Color.lerp(const Color(0xFFF59E0B), const Color(0xFFFBBF24), pulse.value),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'RETICULUM MESH',
            style: TextStyle(
              color: Color(0xFF22C55E),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          // BLE adapter chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bleAdapterOn
                  ? const Color(0xFF0C1A2E)
                  : const Color(0xFF1A0A0A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: bleAdapterOn ? const Color(0xFF1D4ED8) : const Color(0xFF7F1D1D),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: bleAdapterOn ? const Color(0xFF60A5FA) : const Color(0xFF6B7280),
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  bleAdapterOn ? 'BLE ON' : 'BLE OFF',
                  style: TextStyle(
                    color: bleAdapterOn ? const Color(0xFF93C5FD) : const Color(0xFF6B7280),
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // No-internet chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F2D0F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF166534)),
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_off, color: Color(0xFF22C55E), size: 12),
                SizedBox(width: 4),
                Text('NO INTERNET', style: TextStyle(color: Color(0xFF86EFAC), fontSize: 9, letterSpacing: 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── BLE discovery bar ─────────────────────────────────────────────────────────

class _BleBar extends StatelessWidget {
  final bool adapterOn;
  final int nearby;
  final int drd;
  final int connected;
  const _BleBar({
    required this.adapterOn,
    required this.nearby,
    required this.drd,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF050D1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1D3A6A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_searching, color: Color(0xFF60A5FA), size: 14),
          const SizedBox(width: 8),
          const Text(
            'BLE',
            style: TextStyle(
              color: Color(0xFF93C5FD),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
          if (!adapterOn)
            const Text(
              'Bluetooth adapter off — enable in Settings',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 10),
            )
          else ...[
            _BleStat(label: 'NEARBY', value: '$nearby',
                color: nearby > 0 ? const Color(0xFF60A5FA) : const Color(0xFF374151)),
            const SizedBox(width: 8),
            _BleStat(label: 'DRD', value: '$drd',
                color: drd > 0 ? const Color(0xFF22C55E) : const Color(0xFF374151)),
            const SizedBox(width: 8),
            _BleStat(label: 'LINKED', value: '$connected',
                color: connected > 0 ? const Color(0xFF4ADE80) : const Color(0xFF374151)),
          ],
          const Spacer(),
          Text(
            adapterOn
                ? (nearby > 0 ? 'SCANNING ▸ $nearby device${nearby == 1 ? "" : "s"}' : 'SCANNING…')
                : 'DISABLED',
            style: TextStyle(
              color: adapterOn ? const Color(0xFF3B82F6) : const Color(0xFF374151),
              fontSize: 9,
              letterSpacing: 1,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _BleStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BleStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 8, letterSpacing: 0.8),
        ),
      ],
    );
  }
}

// ── Node graph ────────────────────────────────────────────────────────────────

class _NodeGraph extends StatelessWidget {
  final AnimationController pulse;
  final List<MeshPeer> wifiPeers;
  final List<BlePeer> blePeers;
  const _NodeGraph({
    required this.pulse,
    required this.wifiPeers,
    required this.blePeers,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => CustomPaint(
        size: const Size(280, 240),
        painter: _NodePainter(
          pulse: pulse.value,
          wifiPeers: wifiPeers,
          blePeers: blePeers,
        ),
      ),
    );
  }
}

class _NodePainter extends CustomPainter {
  final double pulse;
  final List<MeshPeer> wifiPeers;
  final List<BlePeer> blePeers;
  const _NodePainter({
    required this.pulse,
    required this.wifiPeers,
    required this.blePeers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Pulse rings
    final ringPaint = Paint()
      ..color = const Color(0xFF22C55E).withValues(alpha: 0.08 + 0.12 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), 28 + 10 * pulse, ringPaint);
    canvas.drawCircle(Offset(cx, cy), 44 + 6 * pulse, ringPaint);

    // Self node
    canvas.drawCircle(
      Offset(cx, cy), 22,
      Paint()..color = const Color(0xFF22C55E).withValues(alpha: 0.15 + 0.1 * pulse),
    );
    canvas.drawCircle(
      Offset(cx, cy), 22,
      Paint()
        ..color = const Color(0xFF22C55E).withValues(alpha: 0.8 + 0.2 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _label(canvas, 'YOU', Offset(cx, cy), const Color(0xFF22C55E), 9);

    final totalPeers = wifiPeers.length + blePeers.length;

    if (totalPeers == 0) {
      // Searching rings
      final searchPaint = Paint()
        ..color = const Color(0xFF22C55E).withValues(alpha: 0.12 + 0.08 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (double dr = 60; dr < size.width / 2; dr += 30) {
        canvas.drawCircle(Offset(cx, cy), dr + 6 * pulse, searchPaint);
      }
      return;
    }

    final radius = size.width * 0.36;
    final allNames = [
      ...wifiPeers.take(4).map((p) => (name: p.endpointName, ble: false)),
      ...blePeers.take(4).map((p) => (name: p.name, ble: true)),
    ];

    for (int i = 0; i < allNames.length; i++) {
      final angle = (i / allNames.length) * 2 * math.pi - math.pi / 2;
      final px = cx + radius * math.cos(angle);
      final py = cy + radius * math.sin(angle);
      final isBle = allNames[i].ble;
      final nodeColor = isBle ? const Color(0xFF3B82F6) : const Color(0xFF16A34A);
      final glowColor = isBle ? const Color(0xFF60A5FA) : const Color(0xFF4ADE80);

      // Link line
      canvas.drawLine(
        Offset(cx, cy), Offset(px, py),
        Paint()
          ..color = nodeColor.withValues(alpha: 0.4 + 0.3 * pulse)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );

      // Animated relay dot
      final t = (pulse + i * 0.25) % 1.0;
      canvas.drawCircle(
        Offset(cx + (px - cx) * t, cy + (py - cy) * t),
        3,
        Paint()..color = glowColor.withValues(alpha: 0.8),
      );

      // Peer circle
      canvas.drawCircle(
        Offset(px, py), 18,
        Paint()..color = (isBle ? const Color(0xFF0C1A3A) : const Color(0xFF1A3A1A)).withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        Offset(px, py), 18,
        Paint()
          ..color = nodeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Transport badge (W/B)
      _label(canvas, isBle ? 'B' : 'W', Offset(px, py - 6), glowColor, 7);

      // Peer name
      final rawName = allNames[i].name;
      final short = rawName.length > 6 ? rawName.substring(0, 6) : rawName;
      _label(canvas, short, Offset(px, py + 4), nodeColor.withValues(alpha: 0.9), 7);
    }
  }

  void _label(Canvas canvas, String text, Offset center, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_NodePainter old) =>
      old.pulse != pulse ||
      old.wifiPeers.length != wifiPeers.length ||
      old.blePeers.length != blePeers.length;
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int peerCount;
  final int msgRelayed;
  final bool active;
  final int bleDrd;
  const _StatsRow({
    required this.peerCount,
    required this.msgRelayed,
    required this.active,
    required this.bleDrd,
  });

  @override
  Widget build(BuildContext context) {
    final linked = peerCount > 0 || bleDrd > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _Stat(label: 'WIFI', value: '$peerCount',
              color: peerCount > 0 ? const Color(0xFF22C55E) : const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          _Stat(label: 'BLE', value: '$bleDrd',
              color: bleDrd > 0 ? const Color(0xFF60A5FA) : const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          _Stat(label: 'RELAY', value: '$msgRelayed', color: const Color(0xFF38BDF8)),
          const SizedBox(width: 6),
          _Stat(
            label: 'STATUS',
            value: active ? (linked ? 'LINKED' : 'SCANNING') : 'OFFLINE',
            color: active
                ? (linked ? const Color(0xFF22C55E) : const Color(0xFFF59E0B))
                : const Color(0xFF6B7280),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1A0A),
              border: Border.all(color: const Color(0xFF1F4D1F)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.hub_outlined, color: Color(0xFF22C55E), size: 12),
                SizedBox(width: 4),
                Text('MESH+BLE', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 9, letterSpacing: 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 7, letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ── Event log ─────────────────────────────────────────────────────────────────

class _EventLog extends StatelessWidget {
  final List<String> entries;
  const _EventLog({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF020802),
        border: Border.all(color: const Color(0xFF0F2D0F)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF0F2D0F))),
            ),
            child: const Text(
              'EVENT LOG',
              style: TextStyle(color: Color(0xFF166534), fontSize: 9, letterSpacing: 2, fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text('Awaiting events…', style: TextStyle(color: Color(0xFF1F2937), fontSize: 11)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final isBle = e.contains('BLE');
                      return Text(
                        e,
                        style: TextStyle(
                          color: isBle ? const Color(0xFF60A5FA) : const Color(0xFF22C55E),
                          fontSize: 10,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Action bar ────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final MeshProvider mesh;
  final VoidCallback onDismiss;
  const _ActionBar({required this.mesh, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final userName = context.read<AuthProvider>().user?.username;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MeshButton(
                  label: mesh.active ? 'STOP MESH' : 'START MESH',
                  icon: mesh.active ? Icons.stop_circle_outlined : Icons.wifi_tethering,
                  color: mesh.active ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  onTap: () => mesh.active ? mesh.stop() : mesh.start(userName: userName),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MeshButton(
                  label: 'BROADCAST LOC',
                  icon: Icons.my_location,
                  color: const Color(0xFF0EA5E9),
                  onTap: mesh.active && mesh.anyPeer
                      ? () => mesh.sendLocation({'status': 'active'})
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MeshButton(
                  label: 'SYNC SERVER',
                  icon: Icons.sync,
                  color: const Color(0xFF8B5CF6),
                  onTap: () => mesh.flushToServer(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MeshButton(
            label: 'CONTINUE IN OFFLINE MODE  ▸',
            icon: Icons.arrow_forward,
            color: const Color(0xFF6B7280),
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _MeshButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _MeshButton({required this.label, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.1) : const Color(0xFF0A0A0A),
          border: Border.all(color: enabled ? color.withValues(alpha: 0.4) : const Color(0xFF1F2937)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: enabled ? color : const Color(0xFF374151), size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: enabled ? color : const Color(0xFF374151),
                fontSize: 8,
                letterSpacing: 0.8,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bluetooth permission section ──────────────────────────────────────────────

class _BlePermSection extends StatefulWidget {
  const _BlePermSection();

  @override
  State<_BlePermSection> createState() => _BlePermSectionState();
}

class _BlePermSectionState extends State<_BlePermSection> {
  final _svc = PermissionService.instance;

  Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = false;

  static const _blePerms = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
  ];

  static final _labels = {
    Permission.bluetoothScan:      'SCAN',
    Permission.bluetoothConnect:   'CONNECT',
    Permission.bluetoothAdvertise: 'ADVERTISE',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final map = <Permission, PermissionStatus>{};
    for (final p in _blePerms) {
      map[p] = await p.status;
    }
    if (mounted) setState(() => _statuses = map);
  }

  bool get _allGranted => _blePerms.every((p) =>
      _statuses[p]?.isGranted == true || _statuses[p]?.isLimited == true);

  Future<void> _grantAll() async {
    setState(() => _loading = true);
    await _svc.requestAll();
    await _refresh();
    setState(() => _loading = false);
  }

  Future<void> _grantOne(Permission p) async {
    await _svc.requestOne(p);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF050D1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _allGranted
              ? const Color(0xFF1D3A6A)
              : const Color(0xFF7F1D1D).withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              _allGranted ? Icons.bluetooth : Icons.bluetooth_disabled,
              color: _allGranted ? const Color(0xFF60A5FA) : const Color(0xFFEF4444),
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              'BLUETOOTH PERMISSIONS',
              style: TextStyle(
                color: _allGranted ? const Color(0xFF93C5FD) : const Color(0xFFFCA5A5),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            const Spacer(),
            if (!_allGranted)
              GestureDetector(
                onTap: _loading ? null : _grantAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D4ED8).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1D4ED8)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 10, height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF60A5FA)))
                      : const Text('GRANT ALL',
                          style: TextStyle(color: Color(0xFF60A5FA), fontSize: 9,
                              fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Row(
            children: _blePerms.map((p) {
              final granted = _statuses[p]?.isGranted == true ||
                              _statuses[p]?.isLimited == true;
              final denied  = _statuses[p]?.isPermanentlyDenied == true;
              final label   = _labels[p] ?? p.toString();
              final color   = granted
                  ? const Color(0xFF22C55E)
                  : denied ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

              return Expanded(
                child: GestureDetector(
                  onTap: granted ? null : () => denied
                      ? _svc.openSettings()
                      : _grantOne(p),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Column(children: [
                      Icon(
                        granted ? Icons.check_circle : (denied ? Icons.block : Icons.radio_button_unchecked),
                        color: color, size: 16,
                      ),
                      const SizedBox(height: 3),
                      Text(label,
                          style: TextStyle(color: color, fontSize: 7,
                              fontWeight: FontWeight.w700, letterSpacing: 0.8,
                              fontFamily: 'monospace')),
                      if (!granted) ...[
                        const SizedBox(height: 2),
                        Text(denied ? 'SETTINGS' : 'TAP',
                            style: TextStyle(color: color.withValues(alpha: 0.6),
                                fontSize: 6, letterSpacing: 0.5)),
                      ],
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── BLE device list (scan, pair, connect) ─────────────────────────────────────

class _DeviceList extends StatelessWidget {
  final List<BlePeer> peers;
  const _DeviceList({required this.peers});

  @override
  Widget build(BuildContext context) {
    // Combine BleService allPeers (includes non-DRD) with connected status
    final allPeers = BleService.instance.allPeers;

    // Sort: bridge first, then connected DRD, then other DRD, then others
    final sorted = [...allPeers]..sort((a, b) {
      int score(BlePeer p) {
        if (p.name.startsWith('DRD-BRIDGE')) return 0;
        if (p.connected && p.isDrd)          return 1;
        if (p.isDrd)                         return 2;
        return 3;
      }
      return score(a).compareTo(score(b));
    });

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF050D1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1D3A6A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              const Icon(Icons.bluetooth_searching, color: Color(0xFF60A5FA), size: 13),
              const SizedBox(width: 6),
              const Text('NEARBY DEVICES',
                  style: TextStyle(color: Color(0xFF93C5FD), fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 2,
                      fontFamily: 'monospace')),
              const Spacer(),
              Text('${allPeers.length} found',
                  style: const TextStyle(color: Color(0xFF374151), fontSize: 9)),
            ]),
          ),

          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Text('Scanning for devices…',
                  style: TextStyle(color: Color(0xFF374151), fontSize: 11)),
            )
          else
            ...sorted.map((peer) => _DeviceTile(peer: peer)),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final BlePeer peer;
  const _DeviceTile({required this.peer});

  bool get _isBridge => peer.name.startsWith('DRD-BRIDGE');

  @override
  Widget build(BuildContext context) {
    final Color borderColor;
    final Color iconColor;
    final IconData icon;

    if (_isBridge) {
      borderColor = const Color(0xFF1D4ED8);
      iconColor   = const Color(0xFF60A5FA);
      icon        = Icons.computer;
    } else if (peer.isDrd) {
      borderColor = const Color(0xFF166534);
      iconColor   = const Color(0xFF22C55E);
      icon        = Icons.smartphone;
    } else {
      borderColor = const Color(0xFF1F2937);
      iconColor   = const Color(0xFF374151);
      icon        = Icons.bluetooth;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        // Device icon
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 10),

        // Name + RSSI
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(peer.name,
                      style: TextStyle(color: peer.isDrd ? Colors.white : const Color(0xFF6B7280),
                          fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                if (_isBridge) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF1D4ED8)),
                    ),
                    child: const Text('BRIDGE',
                        style: TextStyle(color: Color(0xFF60A5FA), fontSize: 7,
                            fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text('${peer.rssi} dBm',
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10)),
            ],
          ),
        ),

        // Connection status / button
        if (peer.connected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF166534).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF166534)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check, color: Color(0xFF22C55E), size: 10),
              SizedBox(width: 3),
              Text('PAIRED', style: TextStyle(color: Color(0xFF22C55E),
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ]),
          )
        else if (peer.isDrd)
          GestureDetector(
            onTap: () => BleService.instance.connectTo(peer.deviceId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: iconColor.withValues(alpha: 0.5)),
              ),
              child: Text('CONNECT',
                  style: TextStyle(color: iconColor, fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ),
          ),
      ]),
    );
  }
}

// ── Hex grid painter ──────────────────────────────────────────────────────────

class _HexGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF22C55E).withValues(alpha: 0.025)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const h = 28.0;
    const w = 24.0;
    const v = 14.0;

    for (double y = 0; y < size.height + h; y += h + v) {
      for (double x = 0; x < size.width + w; x += w * 2) {
        _drawHex(canvas, paint, Offset(x, y), w, h);
        _drawHex(canvas, paint, Offset(x + w, y + h / 2 + v / 2), w, h);
      }
    }
  }

  void _drawHex(Canvas canvas, Paint paint, Offset center, double w, double h) {
    final path = Path();
    final pts = [
      Offset(center.dx, center.dy - h / 2),
      Offset(center.dx + w / 2, center.dy - h / 4),
      Offset(center.dx + w / 2, center.dy + h / 4),
      Offset(center.dx, center.dy + h / 2),
      Offset(center.dx - w / 2, center.dy + h / 4),
      Offset(center.dx - w / 2, center.dy - h / 4),
    ];
    path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < 6; i++) { path.lineTo(pts[i].dx, pts[i].dy); }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
