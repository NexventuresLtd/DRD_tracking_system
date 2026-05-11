import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';

class RoutePlanning extends StatefulWidget {
  const RoutePlanning({super.key});

  @override
  State<RoutePlanning> createState() => _RoutePlanningState();
}

class _RoutePlanningState extends State<RoutePlanning> {
  final MapController _mapCtrl = MapController();
  final ApiService _api = ApiService();

  // ── State ────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _teams = [];
  List<LatLng> _pendingWaypoints = [];
  bool _drawMode = false;
  bool _mapReady = false;
  bool _loading = true;
  String _mapTile = 'tactical';
  int _viewTab = 0; // 0=Map 1=Routes

  final Map<String, String> _tileUrls = {
    'tactical': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    '2D': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'satellite': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/routes?is_active=true'),
        _api.get('/teams'),
      ]);
      if (!mounted) return;
      setState(() {
        _routes = (results[0] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _teams = (results[1] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      body: Column(children: [
        // Custom app bar
        Container(
          padding: EdgeInsets.fromLTRB(8, topPad + 8, 8, 8),
          color: DRDTheme.surfaceColor,
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 16),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ROUTE PLANNING',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
            // Tab toggle
            Flexible(child: _tabToggle()),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
              onPressed: _loadData,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ]),
        ),

        // Content
        Expanded(child: _viewTab == 0 ? _buildMapView(topPad) : _buildRoutesList()),
      ]),
    );
  }

  Widget _tabToggle() {
    return Container(
      decoration: BoxDecoration(
        color: DRDTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _tabBtn(0, Icons.map_outlined, 'MAP'),
        _tabBtn(1, Icons.list_alt_outlined, 'ROUTES'),
      ]),
    );
  }

  Widget _tabBtn(int idx, IconData icon, String label) {
    final active = _viewTab == idx;
    return GestureDetector(
      onTap: () => setState(() => _viewTab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? DRDTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: active ? Colors.white : Colors.white38),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 9.5, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  // ── Map View ─────────────────────────────────────────────────────────────────

  Widget _buildMapView(double topPad) {
    final tileUrl = _tileUrls[_mapTile] ?? _tileUrls['tactical']!;
    return Stack(children: [
      // Map
      FlutterMap(
        mapController: _mapCtrl,
        options: MapOptions(
          initialCenter: (() {
            final loc = context.read<LocationProvider>();
            return loc.hasRealFix
                ? LatLng(loc.latitude, loc.longitude)
                : LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
          })(),
          initialZoom: AppConstants.defaultZoom,
          onMapReady: () => setState(() => _mapReady = true),
          onTap: (_, point) {
            if (_drawMode) setState(() => _pendingWaypoints.add(point));
          },
        ),
        children: [
          TileLayer(
            urlTemplate: tileUrl,
            subdomains: _mapTile == 'tactical' ? ['a', 'b', 'c', 'd'] : [],
            userAgentPackageName: 'com.drd.fieldops',
          ),
          // Existing routes
          PolylineLayer(polylines: [
            ..._routes.map((r) {
              final wps = r['waypoints'] as List?;
              if (wps == null || wps.length < 2) return null;
              return Polyline(
                points: wps.map((wp) => LatLng((wp['latitude'] as num).toDouble(), (wp['longitude'] as num).toDouble())).toList(),
                color: _hexColor(r['color']).withValues(alpha: 0.7),
                strokeWidth: 2.5,
              );
            }).whereType<Polyline>(),
            // Pending route preview
            if (_pendingWaypoints.length >= 2)
              Polyline(points: _pendingWaypoints, color: DRDTheme.primaryColor, strokeWidth: 3, isDotted: true),
          ]),
          // Existing waypoints
          MarkerLayer(markers: [
            ..._routes.expand((r) {
              final wps = r['waypoints'] as List?;
              if (wps == null) return <Marker>[];
              final color = _hexColor(r['color']);
              return wps.map((wp) {
                final lat = (wp['latitude'] as num?)?.toDouble();
                final lng = (wp['longitude'] as num?)?.toDouble();
                if (lat == null || lng == null) return null;
                return Marker(
                  point: LatLng(lat, lng), width: 12, height: 12,
                  child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: Colors.white, width: 1.5))),
                );
              }).whereType<Marker>();
            }),
            // Pending waypoints
            ..._pendingWaypoints.asMap().entries.map((e) {
              final isFirst = e.key == 0;
              final isLast = e.key == _pendingWaypoints.length - 1;
              return Marker(
                point: e.value, width: 22, height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst ? DRDTheme.successColor : isLast ? DRDTheme.dangerColor : DRDTheme.primaryColor,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
                ),
              );
            }),
          ]),
        ],
      ),

      if (_mapReady) ...[
        // Map type selector
        Positioned(
          top: 10, left: 8, right: 8,
          child: Row(children: _tileUrls.keys.map((k) {
            final active = _mapTile == k;
            return GestureDetector(
              onTap: () => setState(() => _mapTile = k),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? DRDTheme.primaryColor : DRDTheme.surfaceColor.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: active ? DRDTheme.primaryColor : Colors.white.withValues(alpha: 0.1)),
                ),
                child: Text(k.toUpperCase(), style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 9.5, fontWeight: FontWeight.bold)),
              ),
            );
          }).toList()),
        ),

        // Draw mode banner
        if (_drawMode)
          Positioned(
            top: 48, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: DRDTheme.primaryColor.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: DRDTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 8)],
              ),
              child: Row(children: [
                const Icon(Icons.touch_app, color: Colors.white, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'TAP MAP TO ADD WAYPOINTS  (${_pendingWaypoints.length} placed)',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                )),
                if (_pendingWaypoints.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() { _pendingWaypoints.removeLast(); }),
                    child: const Icon(Icons.undo, color: Colors.white70, size: 16),
                  ),
              ]),
            ),
          ),

        // FABs
        Positioned(
          bottom: 80, right: 12,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(
              heroTag: 'rp_center', backgroundColor: DRDTheme.surfaceColor,
              onPressed: () {
                final loc = context.read<LocationProvider>();
                final center = loc.hasRealFix
                    ? LatLng(loc.latitude, loc.longitude)
                    : LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
                _mapCtrl.move(center, AppConstants.defaultZoom);
              },
              child: const Icon(Icons.center_focus_strong, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 6),
            FloatingActionButton.small(
              heroTag: 'rp_zin', backgroundColor: DRDTheme.surfaceColor,
              onPressed: () { if (_mapReady) _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom + 1); },
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 6),
            FloatingActionButton.small(
              heroTag: 'rp_zout', backgroundColor: DRDTheme.surfaceColor,
              onPressed: () { if (_mapReady) _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom - 1); },
              child: const Icon(Icons.remove, color: Colors.white, size: 18),
            ),
          ]),
        ),

        // Bottom toolbar
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: DRDTheme.surfaceColor.withValues(alpha: 0.96),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
            ),
            child: _drawMode ? _drawModeToolbar() : _defaultToolbar(),
          ),
        ),
      ],
    ]);
  }

  Widget _defaultToolbar() {
    return Row(children: [
      Expanded(child: _toolBtn(Icons.route, 'DRAW ROUTE', DRDTheme.primaryColor, () {
        setState(() { _drawMode = true; _pendingWaypoints = []; });
      })),
      const SizedBox(width: 10),
      Expanded(child: _toolBtn(Icons.alt_route, 'DRAW ZONE', DRDTheme.accentColor, () {
        setState(() { _drawMode = true; _pendingWaypoints = []; });
      })),
    ]);
  }

  Widget _drawModeToolbar() {
    return Row(children: [
      Expanded(child: _toolBtn(Icons.cancel_outlined, 'CANCEL', Colors.white38, () {
        setState(() { _drawMode = false; _pendingWaypoints = []; });
      })),
      const SizedBox(width: 10),
      Expanded(child: _toolBtn(
        Icons.check_circle_outline, 'SAVE ROUTE', DRDTheme.successColor,
        _pendingWaypoints.length >= 2 ? () => _showSaveRouteDialog() : null,
      )),
    ]);
  }

  Widget _toolBtn(IconData icon, String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: onTap != null ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: onTap != null ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: onTap != null ? color : Colors.white24),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: onTap != null ? color : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
        ]),
      ),
    );
  }

  // ── Routes List ───────────────────────────────────────────────────────────────

  Widget _buildRoutesList() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: DRDTheme.primaryColor));
    if (_routes.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.alt_route, color: Colors.white24, size: 48),
        const SizedBox(height: 12),
        const Text('No routes yet', style: TextStyle(color: Colors.white38, fontSize: 14)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () { setState(() { _viewTab = 0; _drawMode = true; _pendingWaypoints = []; }); },
          icon: const Icon(Icons.route),
          label: const Text('Draw First Route'),
          style: ElevatedButton.styleFrom(backgroundColor: DRDTheme.primaryColor),
        ),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: DRDTheme.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _routes.length,
        itemBuilder: (_, i) => _routeCard(_routes[i]),
      ),
    );
  }

  Widget _routeCard(Map<String, dynamic> route) {
    final name = route['name'] as String? ?? 'Route';
    final color = _hexColor(route['color']);
    final isZone = route['is_zone'] == true;
    final teamName = route['assigned_team_name'] as String?;
    final wps = (route['waypoints'] as List?)?.length ?? 0;
    final id = route['id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(width: 4, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Row(children: [
            _routeTag(isZone ? 'ZONE' : 'ROUTE', isZone ? DRDTheme.accentColor : DRDTheme.primaryColor),
            const SizedBox(width: 6),
            _routeTag('$wps WPT', Colors.white38),
            if (teamName != null) ...[const SizedBox(width: 6), _routeTag(teamName.replaceAll('Team ', ''), color)],
          ]),
        ])),
        Row(mainAxisSize: MainAxisSize.min, children: [
          // Show on map
          IconButton(
            icon: const Icon(Icons.map_outlined, color: Colors.white38, size: 18),
            onPressed: () {
              setState(() => _viewTab = 0);
              final wpsData = route['waypoints'] as List?;
              if (wpsData != null && wpsData.isNotEmpty && _mapReady) {
                final lat = (wpsData.first['latitude'] as num?)?.toDouble();
                final lng = (wpsData.first['longitude'] as num?)?.toDouble();
                if (lat != null && lng != null) _mapCtrl.move(LatLng(lat, lng), 14);
              }
            },
          ),
          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline, color: DRDTheme.dangerColor.withValues(alpha: 0.7), size: 18),
            onPressed: () => _deleteRoute(id, name),
          ),
        ]),
      ]),
    );
  }

  Widget _routeTag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
    child: Text(text, style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
  );

  // ── Dialogs ──────────────────────────────────────────────────────────────────

  void _showSaveRouteDialog() {
    final nameCtrl = TextEditingController(text: 'Route ${_routes.length + 1}');
    String? selectedTeamId;
    String color = '#3b82f6';
    bool isZone = false;
    final colors = ['#3b82f6', '#22c55e', '#ef4444', '#f59e0b', '#8b5cf6', '#06b6d4', '#f97316', '#ec4899'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('Save Route', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: nameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDeco('Route Name'),
          ),
          const SizedBox(height: 12),
          if (_teams.isNotEmpty) ...[
            const Text('Assign to Team (optional)', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              GestureDetector(
                onTap: () => setSt(() => selectedTeamId = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selectedTeamId == null ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selectedTeamId == null ? Colors.white54 : Colors.white24),
                  ),
                  child: Text('All', style: TextStyle(color: selectedTeamId == null ? Colors.white : Colors.white38, fontSize: 9.5, fontWeight: FontWeight.bold)),
                ),
              ),
              ..._teams.map((t) {
                final id = t['id']?.toString() ?? '';
                final tName = t['name'] as String? ?? '';
                final tColor = _hexColor(t['color']);
                final isActive = selectedTeamId == id;
                return GestureDetector(
                  onTap: () => setSt(() => selectedTeamId = id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive ? tColor.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isActive ? tColor : Colors.white24),
                    ),
                    child: Text(tName.replaceAll('Team ', ''), style: TextStyle(color: isActive ? tColor : Colors.white38, fontSize: 9.5, fontWeight: FontWeight.bold)),
                  ),
                );
              }),
            ]),
            const SizedBox(height: 12),
          ],
          Row(children: [
            const Text('Mark as Zone', style: TextStyle(color: Colors.white54, fontSize: 11)),
            const Spacer(),
            Switch(value: isZone, onChanged: (v) => setSt(() => isZone = v), activeThumbColor: DRDTheme.accentColor),
          ]),
          const SizedBox(height: 8),
          const Text('Color', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: colors.map((c) => GestureDetector(
            onTap: () => setSt(() => color = c),
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _hexColor(c), border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2)),
            ),
          )).toList()),
          const SizedBox(height: 8),
          Text('${_pendingWaypoints.length} waypoints', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final waypoints = _pendingWaypoints.asMap().entries.map((e) => {
                'latitude': e.value.latitude,
                'longitude': e.value.longitude,
                'label': 'WP${e.key + 1}',
                'sequence_order': e.key,
              }).toList();
              await _api.post('/routes', {
                'name': nameCtrl.text.trim().isEmpty ? 'Route ${_routes.length + 1}' : nameCtrl.text.trim(),
                'color': color,
                'is_zone': isZone,
                'meeting_point': false,
                'visible_to_all': selectedTeamId == null,
                if (selectedTeamId != null) 'visible_to_teams': [selectedTeamId],
                'assigned_team_id': ?selectedTeamId,
                'waypoints': waypoints,
              });
              if (!mounted) return;
              nav.pop();
              setState(() { _drawMode = false; _pendingWaypoints = []; });
              _loadData();
            },
            child: const Text('SAVE', style: TextStyle(color: DRDTheme.successColor, fontWeight: FontWeight.bold)),
          ),
        ],
      )),
    );
  }

  void _deleteRoute(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('Delete Route', style: TextStyle(color: DRDTheme.dangerColor, fontSize: 14)),
        content: Text('Delete "$name"?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('DELETE', style: TextStyle(color: DRDTheme.dangerColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _api.delete('/routes/$id');
      _loadData();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  InputDecoration _inputDeco(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white38, fontSize: 11),
    filled: true,
    fillColor: DRDTheme.backgroundColor.withValues(alpha: 0.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: DRDTheme.primaryColor)),
  );

  Color _hexColor(dynamic v) {
    if (v is String && v.startsWith('#')) {
      try { return Color(int.parse(v.replaceFirst('#', '0xFF'))); } catch (_) {}
    }
    return DRDTheme.primaryColor;
  }
}
