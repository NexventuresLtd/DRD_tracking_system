import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/zone_provider.dart';
import '../providers/location_provider.dart';

class ZoneAssignmentScreen extends StatefulWidget {
  const ZoneAssignmentScreen({super.key});

  @override
  State<ZoneAssignmentScreen> createState() => _ZoneAssignmentScreenState();
}

class _ZoneAssignmentScreenState extends State<ZoneAssignmentScreen> {
  final MapController _mapController = MapController();
  ZoneAssignment? _selected;
  bool _showPatrolModal = false;

  static const _green = Color(0xFF22c55e);
  static const _bg = Color(0xFF060e06);
  static const _panel = Color(0xFF0c150c);
  static const _border = Color(0xFF1a2e1a);

  static const _statusColors = {
    'pending': Color(0xFF6b7280),
    'en_route': Color(0xFFf59e0b),
    'arrived': Color(0xFF3b82f6),
    'on_patrol': Color(0xFF22c55e),
    'completed': Color(0xFF9ca3af),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ZoneProvider>().loadMyAssignments();
    });
  }

  void _goToAssignment(ZoneAssignment a) {
    setState(() => _selected = a);
    _mapController.move(LatLng(a.pointLat, a.pointLon), 14);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _panel,
        title: const Text(
          'ZONE ASSIGNMENTS',
          style: TextStyle(
            color: _green,
            fontFamily: 'JetBrainsMono',
            fontSize: 13,
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _green),
            onPressed: () => context.read<ZoneProvider>().loadMyAssignments(),
          ),
        ],
      ),
      body: Consumer<ZoneProvider>(
        builder: (context, zp, _) {
          if (zp.loading) {
            return const Center(child: CircularProgressIndicator(color: _green));
          }

          if (zp.myAssignments.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.crop_free, color: Color(0xFF1a2e1a), size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No active zone assignments',
                    style: TextStyle(color: Color(0xFF4b5563), fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Map
              SizedBox(
                height: 300,
                child: _buildMap(zp),
              ),

              // Assignment list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: zp.myAssignments.length,
                  itemBuilder: (context, i) {
                    final a = zp.myAssignments[i];
                    final isSelected = _selected?.id == a.id;
                    final statusColor = _statusColors[a.status] ?? const Color(0xFF6b7280);
                    return GestureDetector(
                      onTap: () => _goToAssignment(a),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _panel,
                          border: Border.all(
                            color: isSelected ? _green : _border,
                            width: isSelected ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.crop_free, color: statusColor, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    a.zoneName,
                                    style: const TextStyle(
                                      color: Color(0xFFd1fae5),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(
                                    a.status.replaceAll('_', ' ').toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (a.label != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                a.label!,
                                style: const TextStyle(color: Color(0xFF6b7280), fontSize: 12),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${a.pointLat.toStringAsFixed(5)}, ${a.pointLon.toStringAsFixed(5)}',
                              style: const TextStyle(
                                color: Color(0xFF374151),
                                fontSize: 10,
                                fontFamily: 'JetBrainsMono',
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Action buttons
                            Row(
                              children: [
                                if (a.status == 'pending')
                                  _ActionBtn(
                                    label: 'EN ROUTE',
                                    color: const Color(0xFFf59e0b),
                                    onTap: () => _updateStatus(a, 'en_route'),
                                  ),
                                if (a.status == 'en_route')
                                  _ActionBtn(
                                    label: 'ARRIVED',
                                    color: const Color(0xFF3b82f6),
                                    onTap: () => _updateStatus(a, 'arrived'),
                                  ),
                                if (a.status == 'arrived')
                                  _ActionBtn(
                                    label: 'ON PATROL',
                                    color: _green,
                                    onTap: () => _updateStatus(a, 'on_patrol'),
                                  ),
                                if (a.status == 'on_patrol') ...[
                                  _ActionBtn(
                                    label: 'REPORT',
                                    color: const Color(0xFFef4444),
                                    onTap: () {
                                      setState(() { _selected = a; _showPatrolModal = true; });
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  _ActionBtn(
                                    label: 'COMPLETE',
                                    color: const Color(0xFF9ca3af),
                                    onTap: () => _updateStatus(a, 'completed'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),

      // Patrol report FAB
      floatingActionButton: _showPatrolModal && _selected != null
          ? null
          : (_selected != null && _selected!.status == 'on_patrol'
              ? FloatingActionButton.extended(
                  backgroundColor: const Color(0xFFef4444),
                  icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  label: const Text('PATROL REPORT', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  onPressed: () => setState(() => _showPatrolModal = true),
                )
              : null),

      // Patrol report bottom sheet overlay
      bottomSheet: (_showPatrolModal && _selected != null)
          ? _PatrolReportSheet(
              assignment: _selected!,
              onClose: () => setState(() => _showPatrolModal = false),
            )
          : null,
    );
  }

  Widget _buildMap(ZoneProvider zp) {
    final locProvider = context.watch<LocationProvider>();
    final myLat = locProvider.current?.lat;
    final myLon = locProvider.current?.lng;

    final assignments = zp.myAssignments;
    final initialCenter = assignments.isNotEmpty
        ? LatLng(assignments.first.pointLat, assignments.first.pointLon)
        : const LatLng(-1.9441, 30.0619);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: initialCenter, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
        ),

        // Route line from my location to selected assignment
        if (_selected != null && myLat != null && myLon != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [LatLng(myLat, myLon), LatLng(_selected!.pointLat, _selected!.pointLon)],
                color: const Color(0xFF22c55e),
                strokeWidth: 2.5,
                isDotted: true,
              ),
            ],
          ),

        // Assignment markers
        MarkerLayer(
          markers: [
            // My position
            if (myLat != null && myLon != null)
              Marker(
                point: LatLng(myLat, myLon),
                width: 14,
                height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),

            // Zone point markers
            ...assignments.map((a) {
              final isSelected = _selected?.id == a.id;
              final statusColor = _statusColors[a.status] ?? const Color(0xFF6b7280);
              return Marker(
                point: LatLng(a.pointLat, a.pointLon),
                width: isSelected ? 48 : 36,
                height: isSelected ? 48 : 36,
                child: GestureDetector(
                  onTap: () => _goToAssignment(a),
                  child: Container(
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: statusColor, width: isSelected ? 3 : 2),
                    ),
                    child: Center(
                      child: Text(
                        a.label?.substring(0, 1).toUpperCase() ?? '${(a.pointIndex ?? 0) + 1}',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: isSelected ? 16 : 12,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Future<void> _updateStatus(ZoneAssignment a, String status) async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.user?.id ?? '';
    try {
      await context.read<ZoneProvider>().updateStatus(a.zoneId, userId, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated: ${status.replaceAll("_", " ").toUpperCase()}'),
            backgroundColor: const Color(0xFF052e16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade900),
        );
      }
    }
  }
}

// ── Action button widget ────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ── Patrol Report bottom sheet ────────────────────────────────────────────────

class _PatrolReportSheet extends StatefulWidget {
  final ZoneAssignment assignment;
  final VoidCallback onClose;

  const _PatrolReportSheet({required this.assignment, required this.onClose});

  @override
  State<_PatrolReportSheet> createState() => _PatrolReportSheetState();
}

class _PatrolReportSheetState extends State<_PatrolReportSheet> {
  String _reportType = 'suspicious_activity';
  String _severity = 'medium';
  final _descController = TextEditingController();
  bool _sending = false;

  static const _types = [
    ('enemy_sighted', 'Enemy Sighted', Color(0xFFef4444)),
    ('suspicious_activity', 'Suspicious Activity', Color(0xFFf97316)),
    ('incident', 'Incident', Color(0xFFf59e0b)),
    ('medical', 'Medical', Color(0xFF22c55e)),
    ('request_support', 'Request Support', Color(0xFF3b82f6)),
    ('all_clear', 'All Clear', Color(0xFF6b7280)),
  ];

  static const _severities = [
    ('low', 'LOW', Color(0xFF22c55e)),
    ('medium', 'MEDIUM', Color(0xFFf59e0b)),
    ('high', 'HIGH', Color(0xFFf97316)),
    ('critical', 'CRITICAL', Color(0xFFef4444)),
  ];

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF150808),
        border: Border(top: BorderSide(color: Color(0xFF4a0808), width: 1)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFef4444), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PATROL REPORT — ${widget.assignment.zoneName}',
                  style: const TextStyle(
                    color: Color(0xFFef4444),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
              GestureDetector(onTap: widget.onClose, child: const Icon(Icons.close, color: Color(0xFF6b7280), size: 20)),
            ],
          ),
          const SizedBox(height: 14),

          // Report type
          const Text('REPORT TYPE', style: TextStyle(color: Color(0xFF6b7280), fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _types.map((t) {
              final isSelected = _reportType == t.$1;
              return GestureDetector(
                onTap: () => setState(() => _reportType = t.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected ? t.$3.withValues(alpha: 0.2) : Colors.transparent,
                    border: Border.all(color: isSelected ? t.$3 : const Color(0xFF2a1a1a)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    t.$2,
                    style: TextStyle(
                      color: isSelected ? t.$3 : const Color(0xFF4b5563),
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Severity
          const Text('SEVERITY', style: TextStyle(color: Color(0xFF6b7280), fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 6),
          Row(
            children: _severities.map((s) {
              final isSelected = _severity == s.$1;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _severity = s.$1),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? s.$3.withValues(alpha: 0.2) : Colors.transparent,
                      border: Border.all(color: isSelected ? s.$3 : const Color(0xFF2a1a1a)),
                    ),
                    child: Text(
                      s.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isSelected ? s.$3 : const Color(0xFF4b5563),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Description
          const Text('DESCRIPTION', style: TextStyle(color: Color(0xFF6b7280), fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            maxLines: 3,
            style: const TextStyle(color: Color(0xFFd1fae5), fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Describe what you observed…',
              hintStyle: TextStyle(color: Color(0xFF374151), fontSize: 12),
              filled: true,
              fillColor: Color(0xFF0a0808),
              border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2a1a1a)), borderRadius: BorderRadius.zero),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFef4444)), borderRadius: BorderRadius.zero),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2a1a1a)), borderRadius: BorderRadius.zero),
              contentPadding: EdgeInsets.all(12),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending || _descController.text.trim().isEmpty ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFb91c1c),
                disabledBackgroundColor: const Color(0xFF450a0a),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('SEND REPORT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_descController.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final locProvider = context.read<LocationProvider>();
      await context.read<ZoneProvider>().sendPatrolReport(
        zoneId: widget.assignment.zoneId,
        reportType: _reportType,
        description: _descController.text.trim(),
        latitude: locProvider.current?.lat ?? widget.assignment.pointLat,
        longitude: locProvider.current?.lng ?? widget.assignment.pointLon,
        severity: _severity,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patrol report sent'), backgroundColor: Color(0xFF052e16)),
        );
        widget.onClose();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade900),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
