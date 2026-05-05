import 'dart:async';
import 'dart:math';

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';

import '../../services/api_service.dart';
import '../../services/storage_service.dart';

enum CmdMapType { tactical, standard, satellite, terrain, hybrid }

const _cmdTiles = <CmdMapType, Map<String, dynamic>>{
  CmdMapType.tactical: {
    'url': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    'subs': ['a', 'b', 'c', 'd'],
    'label': 'TACTICAL',
  },
  CmdMapType.standard: {
    'url': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'label': '2D MAP',
  },
  CmdMapType.satellite: {
    'url': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'label': 'SATELLITE',
  },
  CmdMapType.terrain: {
    'url': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    'label': 'TERRAIN',
  },
  CmdMapType.hybrid: {
    'url': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'overlay': 'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
    'label': 'HYBRID',
  },
};

class LiveTracking extends StatefulWidget {
  const LiveTracking({super.key});

  @override
  State<LiveTracking> createState() => _LiveTrackingState();
}

class _LiveTrackingState extends State<LiveTracking> with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  CmdMapType _mapType = CmdMapType.tactical;
  List<Map<String, dynamic>> _allLocations = [];
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _followSessions = [];
  Map<String, dynamic>? _selected;
  bool _mapReady = false;
  bool _loading = true;
  String _teamFilter = 'ALL';
  List<String> _teamNames = [];
  LatLng? _initialCenter;

  Timer? _refreshTimer;
  WebSocketChannel? _locWs;
  WebSocketChannel? _evtWs;
  late AnimationController _pulseCtrl;
  final TextEditingController _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _connectWS();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    try {
      final results = await Future.wait([
        _api.get('/locations'),
        _api.get('/routes?is_active=true'),
        _api.get('/teams'),
        _api.get('/route-follow-sessions?status=active'),
      ]);
      if (!mounted) return;
      final locs = (results[0] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final routes = (results[1] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final teams = (results[2] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final sessions = (results[3] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final names = teams.map((t) => t['name'] as String? ?? '').where((n) => n.isNotEmpty).toList();

      // Set initial center to first active location, or default
      LatLng? initialCenter;
      if (locs.isNotEmpty) {
        final firstLoc = locs.firstWhere(
          (l) => l['latitude'] != null && l['longitude'] != null,
          orElse: () => {},
        );
        if (firstLoc.isNotEmpty) {
          initialCenter = LatLng(firstLoc['latitude'], firstLoc['longitude']);
        }
      }
      initialCenter ??= LatLng(AppConstants.defaultLat, AppConstants.defaultLng);

      setState(() {
        _allLocations = locs;
        _routes = routes;
        _followSessions = sessions;
        _teamNames = names;
        _initialCenter = initialCenter;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _initialCenter = LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
          _loading = false;
        });
      }
    }
  }

  void _connectWS() async {
    final token = await _storage.getToken();
    if (token == null) return;
    try {
      _locWs = WebSocketChannel.connect(Uri.parse('${AppConstants.wsUrl}/locations?token=$token'));
      _locWs!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            final d = (data['data'] ?? data) as Map<String, dynamic>;
            final uid = d['user_id'] as String?;
            if (uid == null || !mounted) return;

            setState(() {
              final idx = _allLocations.indexWhere((l) => l['user_id'] == uid);
              if (idx >= 0) {
                _allLocations[idx] = {..._allLocations[idx], ...d};
                if (_selected?['user_id'] == uid) _selected = _allLocations[idx];
              } else {
                _allLocations.add(Map<String, dynamic>.from(d));
              }
            });
          } catch (e) {
            debugPrint('WS parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('WS error: $error');
          _locWs?.sink.close();
          _locWs = null;
          Future.delayed(const Duration(seconds: 3), _connectWS);
        },
        onDone: () {
          debugPrint('WS closed');
          _locWs = null;
          if (mounted) {
            Future.delayed(const Duration(seconds: 3), _connectWS);
          }
        },
      );

      _evtWs = WebSocketChannel.connect(Uri.parse('${AppConstants.wsUrl}/events?token=$token'));
      _evtWs!.stream.listen((raw) {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          final payload = (data['data'] ?? data) as Map<String, dynamic>;
          final eventType = (payload['event_type'] ?? payload['type'] ?? '').toString().toUpperCase();
          if (eventType == 'ROUTE' || eventType == 'ZONE' || eventType == 'POI' || eventType.startsWith('ROUTE_FOLLOW')) {
            _loadData();
          }
        } catch (_) {}
      }, onError: (_) {
        _evtWs?.sink.close();
        _evtWs = null;
      }, onDone: () {
        _evtWs = null;
      });
    } catch (e) {
      debugPrint('WS connection error: $e');
      Future.delayed(const Duration(seconds: 3), _connectWS);
    }
  }

  List<Map<String, dynamic>> get _filtered =>
      _teamFilter == 'ALL' ? _allLocations : _allLocations.where((l) => l['team_name'] == _teamFilter).toList();

  int get _active => _allLocations.where((l) => l['status'] == 'active').length;
  int get _stale => _allLocations.where((l) => l['status'] == 'stale').length;
  int get _offline => _allLocations.where((l) => l['status'] == 'offline').length;

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _refreshTimer?.cancel();
    _locWs?.sink.close();
    _evtWs?.sink.close();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      body: Stack(
        children: [
          _buildMap(),
          if (!_mapReady || _loading)
            Container(
              color: DRDTheme.backgroundColor,
              child: const Center(child: CircularProgressIndicator(color: DRDTheme.primaryColor)),
            ),
          if (_mapReady) ...[
            Positioned(
              top: topPad + 8,
              left: 52,
              right: 0,
              child: _buildMapTypeBar(),
            ),
            Positioned(
              top: topPad + 8,
              left: 8,
              child: _backBtn(),
            ),
            Positioned(top: topPad + 54, left: 10, child: _buildStatsHud()),
            Positioned(top: topPad + 54, right: 10, child: _buildTeamFilter()),
            Positioned(top: topPad + 128, left: 10, right: 10, child: _buildRoutePanel()),
            Positioned(
              bottom: _selected != null ? 290 : 24,
              right: 12,
              child: _buildNavFabs(),
            ),
            if (_selected != null)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildSelectedPanel()),
          ],
        ],
      ),
    );
  }

  Widget _backBtn() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: DRDTheme.surfaceColor.withValues(alpha: 0.95),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
        ),
        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 14),
      ),
    );
  }

  Widget _buildMap() {
    final tile = _cmdTiles[_mapType]!;
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _initialCenter ?? LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
        initialZoom: AppConstants.defaultZoom,
        onMapReady: () => setState(() => _mapReady = true),
        onTap: (_, _) => setState(() => _selected = null),
      ),
      children: [
        TileLayer(
          urlTemplate: tile['url'] as String,
          subdomains: (tile['subs'] as List?)?.cast<String>() ?? const [],
          userAgentPackageName: 'com.drd.fieldops',
        ),
        if (_mapType == CmdMapType.hybrid && tile['overlay'] != null)
          TileLayer(urlTemplate: tile['overlay'] as String, userAgentPackageName: 'com.drd.fieldops'),
        PolylineLayer(polylines: [..._routeLines(), ..._routeApproachLines()]),
        MarkerLayer(markers: _waypointMarkers()),
        MarkerLayer(markers: _unitMarkers()),
      ],
    );
  }

  List<Polyline> _routeLines() {
    final lines = <Polyline>[];
    final source = _followSessions.isNotEmpty ? _followSessions : _routes;
    for (final r in source) {
      final wps = (r['waypoints_snapshot'] as List?) ?? (r['waypoints'] as List?);
      if (wps == null || wps.length < 2) continue;
      lines.add(Polyline(
        points: wps.map((wp) => LatLng((wp['latitude'] as num).toDouble(), (wp['longitude'] as num).toDouble())).toList(),
        color: _hexColor(r['route_color_snapshot'] ?? r['color']),
        strokeWidth: 2.5,
      ));
    }
    return lines;
  }

  List<Marker> _waypointMarkers() {
    final markers = <Marker>[];
    final source = _followSessions.isNotEmpty ? _followSessions : _routes;
    for (final r in source) {
      final wps = (r['waypoints_snapshot'] as List?) ?? (r['waypoints'] as List?);
      if (wps == null) continue;
      final color = _hexColor(r['route_color_snapshot'] ?? r['color']);
      for (final wp in wps) {
        final lat = (wp['latitude'] as num?)?.toDouble();
        final lng = (wp['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        markers.add(Marker(
          point: LatLng(lat, lng), width: 12, height: 12,
          child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: Colors.white, width: 1.5))),
        ));
      }
    }
    return markers;
  }

  List<Marker> _unitMarkers() {
    return _filtered.map((l) {
      final lat = (l['latitude'] as num?)?.toDouble();
      final lng = (l['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final status = l['status'] as String? ?? 'offline';
      final statusColor = DRDTheme.statusColors[status] ?? Colors.grey;
      final name = l['user_name'] as String? ?? '?';
      final initials = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
      final isSelected = _selected?['user_id'] == l['user_id'];
      final hasFlag = l['flag'] != null;

      return Marker(
        point: LatLng(lat, lng), width: 60, height: 72,
        child: GestureDetector(
          onTap: () { setState(() => _selected = l); _mapCtrl.move(LatLng(lat, lng), 16); },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: DRDTheme.surfaceColor.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(4),
                border: isSelected ? Border.all(color: DRDTheme.primaryColor, width: 1) : null,
              ),
              child: Text(initials, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 2),
            Stack(clipBehavior: Clip.none, children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, _) {
                  final t = isSelected ? _pulseCtrl.value : 0.0;
                  return Container(
                    width: 36 + 20 * t, height: 36 + 20 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: statusColor.withValues(alpha: 0.4 * (1 - t)), width: 2),
                    ),
                  );
                },
              ),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(alpha: 0.18),
                  border: Border.all(color: statusColor, width: isSelected ? 3 : 2),
                ),
                child: Center(child: Transform.rotate(
                  angle: ((l['heading'] as num?)?.toDouble() ?? 0) * pi / 180,
                  child: Icon(Icons.navigation, color: statusColor, size: 18),
                )),
              ),
              if (hasFlag)
                Positioned(
                  top: -4, right: -4,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(color: DRDTheme.dangerColor, shape: BoxShape.circle, border: Border.all(color: DRDTheme.backgroundColor, width: 1.5)),
                    child: const Center(child: Text('!', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
                  ),
                ),
            ]),
          ]),
        ),
      );
    }).whereType<Marker>().toList();
  }

  Widget _buildMapTypeBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _cmdTiles.entries.map((e) {
          final active = _mapType == e.key;
          return GestureDetector(
            onTap: () => setState(() => _mapType = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: active ? DRDTheme.primaryColor : DRDTheme.surfaceColor.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? DRDTheme.primaryColor : Colors.white.withValues(alpha: 0.1)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
              ),
              child: Text(
                e.value['label'] as String,
                style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsHud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text('FORCE', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        _statRow(DRDTheme.successColor, 'ACT', _active),
        _statRow(DRDTheme.warningColor, 'STL', _stale),
        _statRow(DRDTheme.dangerColor, 'OFF', _offline),
        _statRow(Colors.white60, 'TOT', _allLocations.length),
      ]),
    );
  }

  Widget _statRow(Color color, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9.5)),
        const SizedBox(width: 5),
        Text('$count', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildTeamFilter() {
    final teams = ['ALL', ..._teamNames];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
        children: teams.map((team) => GestureDetector(
          onTap: () => setState(() => _teamFilter = team),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              team == 'ALL' ? 'ALL' : team.replaceAll('Team ', ''),
              style: TextStyle(
                color: _teamFilter == team ? DRDTheme.primaryColor : Colors.white38,
                fontSize: 9.5, fontWeight: _teamFilter == team ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildNavFabs() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _fab('center', Icons.center_focus_strong, DRDTheme.primaryColor, () {
        if (_allLocations.isNotEmpty) {
          final l = _allLocations.first;
          final lat = (l['latitude'] as num?)?.toDouble();
          final lng = (l['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) _mapCtrl.move(LatLng(lat, lng), 13);
        }
      }),
      const SizedBox(height: 6),
      _fab('zin', Icons.add, DRDTheme.surfaceColor, () { if (_mapReady) _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom + 1); }),
      const SizedBox(height: 6),
      _fab('zout', Icons.remove, DRDTheme.surfaceColor, () { if (_mapReady) _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom - 1); }),
      const SizedBox(height: 6),
      _fab('ref', Icons.refresh, DRDTheme.surfaceColor, _loadData),
    ]);
  }

  Widget _buildSelectedPanel() {
    final l = _selected!;
    final status = l['status'] as String? ?? 'offline';
    final statusColor = DRDTheme.statusColors[status] ?? Colors.grey;
    final name = l['user_name'] as String? ?? 'Unknown';
    final team = l['team_name'] as String?;
    final flag = l['flag'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor.withValues(alpha: 0.15), border: Border.all(color: statusColor, width: 2)),
                child: Center(child: Text(
                  name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join(),
                  style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.bold),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Wrap(spacing: 5, children: [
                  _tag(status.toUpperCase(), statusColor),
                  if (team != null) _tag(team, Colors.white38),
                  if (flag != null) _tag('FLAG ${flag.toUpperCase()}', DRDTheme.dangerColor),
                ]),
              ])),
              IconButton(icon: const Icon(Icons.close, color: Colors.white38, size: 18), onPressed: () => setState(() => _selected = null)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 4, children: [
              _chip(Icons.location_on_outlined, '${(l['latitude'] as num?)?.toStringAsFixed(4) ?? "—"}, ${(l['longitude'] as num?)?.toStringAsFixed(4) ?? "—"}'),
              _chip(Icons.speed_outlined, '${(l['speed'] as num?)?.toStringAsFixed(1) ?? "0.0"} km/h'),
              _chip(Icons.explore_outlined, 'HDG ${(l['heading'] as num?)?.toStringAsFixed(0) ?? "0"}°'),
              if (l['battery_level'] != null) _chip(Icons.battery_std_outlined, '${l['battery_level']}%'),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _pill(Icons.chat_bubble_outline, 'MESSAGE', DRDTheme.primaryColor, () => _showMessageDialog(l))),
              const SizedBox(width: 8),
              Expanded(child: _pill(Icons.gps_fixed, 'CENTER', DRDTheme.successColor, () {
                final lat = (l['latitude'] as num?)?.toDouble();
                final lng = (l['longitude'] as num?)?.toDouble();
                if (lat != null && lng != null) _mapCtrl.move(LatLng(lat, lng), 17);
              })),
              const SizedBox(width: 8),
              Expanded(child: _pill(Icons.warning_amber_rounded, 'ALERT', DRDTheme.dangerColor, () => _sendAlert(l))),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
    child: Text(text, style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
  );

  Widget _chip(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 11, color: Colors.white38), const SizedBox(width: 3),
    Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10)),
  ]);

  Widget _pill(IconData icon, String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 13, color: color), const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    ),
  );

  void _showMessageDialog(Map<String, dynamic> unit) {
    final name = unit['user_name'] as String? ?? 'Unit';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: Text('Message $name', style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: _msgCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Type message…', hintStyle: TextStyle(color: Colors.white38)),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              if (_msgCtrl.text.trim().isEmpty) return;
              await _api.post('/messages', {'to_user_id': unit['user_id'], 'to_all': false, 'content': _msgCtrl.text.trim(), 'priority': 'normal'});
              _msgCtrl.clear();
              {if (mounted) Navigator.pop(context);}
            },
            child: const Text('SEND', style: TextStyle(color: DRDTheme.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _sendAlert(Map<String, dynamic> unit) async {
    final name = unit['user_name'] as String? ?? 'Unit';
    await _api.post('/messages', {
      'to_user_id': unit['user_id'], 'to_all': false,
      'content': 'ALERT from Command: Acknowledge your position immediately.',
      'priority': 'urgent',
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alert sent to $name'), backgroundColor: DRDTheme.warningColor),
      );
    }
  }

  List<Polyline> _routeApproachLines() {
    if (!_mapReady) return const [];
    final source = _followSessions.isNotEmpty ? _followSessions : _routes;
    if (source.isEmpty) return const [];
    final route = source.first;
    final target = _routeTarget(route);
    if (target == null) return const [];
    final user = context.read<AuthProvider>().user;
    final myPosition = user == null
        ? null
        : _allLocations.firstWhere(
            (loc) => loc['user_id'] == user.id,
            orElse: () => <String, dynamic>{},
          );
    final lat = (myPosition?['latitude'] as num?)?.toDouble();
    final lng = (myPosition?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return const [];
    return [
      Polyline(
        points: [LatLng(lat, lng), target],
        color: Colors.white.withValues(alpha: 0.35),
        strokeWidth: 2,
      ),
    ];
  }

  LatLng? _routeTarget(Map<String, dynamic> route) {
    final wps = (route['waypoints_snapshot'] as List?) ?? (route['waypoints'] as List?);
    if (wps == null || wps.isEmpty) return null;
    final last = wps.last as Map<String, dynamic>;
    final lat = (last['latitude'] as num?)?.toDouble();
    final lng = (last['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  double? _distanceKm(double aLat, double aLng, double bLat, double bLng) {
    const radius = 6371.0;
    final dLat = (bLat - aLat) * pi / 180;
    final dLng = (bLng - aLng) * pi / 180;
    final lat1 = aLat * pi / 180;
    final lat2 = bLat * pi / 180;
    final sinLat = sin(dLat / 2);
    final sinLng = sin(dLng / 2);
    final a = sinLat * sinLat + cos(lat1) * cos(lat2) * sinLng * sinLng;
    return 2 * radius * asin(min(1, sqrt(a)));
  }

  String _formatDistance(double? km) {
    if (km == null || km.isNaN) return 'Distance unavailable';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  double? _routeDistanceToTarget() {
    final source = _followSessions.isNotEmpty ? _followSessions : _routes;
    if (source.isEmpty || _allLocations.isEmpty) return null;
    final target = _routeTarget(source.first);
    if (target == null) return null;
    final user = context.read<AuthProvider>().user;
    if (user == null) return null;
    final myPosition = _allLocations.cast<Map<String, dynamic>>().firstWhere(
      (loc) => loc['user_id'] == user.id,
      orElse: () => <String, dynamic>{},
    );
    final lat = (myPosition['latitude'] as num?)?.toDouble();
    final lng = (myPosition['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return _distanceKm(lat, lng, target.latitude, target.longitude);
  }

  Map<String, dynamic>? _closestTeamMemberToTarget() {
    final source = _followSessions.isNotEmpty ? _followSessions : _routes;
    if (source.isEmpty || _allLocations.isEmpty) return null;
    final target = _routeTarget(source.first);
    if (target == null) return null;

    Map<String, dynamic>? best;
    double? bestDistance;
    for (final member in _allLocations) {
      final lat = (member['latitude'] as num?)?.toDouble();
      final lng = (member['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final distance = _distanceKm(lat, lng, target.latitude, target.longitude);
      if (distance == null) continue;
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        best = member;
      }
    }
    return best == null ? null : {...best, 'distance_km': bestDistance};
  }

  Future<void> _completeRoute(String routeId) async {
    try {
      final activeSession = _followSessions.cast<Map<String, dynamic>>().firstWhere(
        (session) => session['route_id'] == routeId,
        orElse: () => <String, dynamic>{},
      );
      if (activeSession.isEmpty) return;

      await _api.completeRouteFollow(activeSession['id'] as String, {
        'completion_note': 'Confirmed by commander',
      });
      if (mounted) {
        setState(() {
          _followSessions = _followSessions.where((session) => session['id'] != activeSession['id']).toList();
        });
      }
      await _loadData();
    } catch (_) {}
  }

  Widget _buildRoutePanel() {
    final activeSessions = _followSessions.where((session) => session['status'] == 'active').toList();
    final session = activeSessions.isNotEmpty ? activeSessions.first : null;
    final route = session == null ? null : session;
    final target = route == null ? null : _routeTarget(route);
    final nearest = _closestTeamMemberToTarget();
    final distance = _routeDistanceToTarget();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8)],
      ),
      child: activeSessions.isEmpty
          ? const Text(
              'No active follow sessions',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alt_route, color: DRDTheme.primaryColor, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        route?['route_name_snapshot'] as String? ?? 'Active route',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: route == null ? null : () => _completeRoute(route['route_id'] as String),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.greenAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('DONE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Progress: ${(route?['progress_percent'] as num?)?.toStringAsFixed(0) ?? '0'}%',
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  'Target: ${target?.latitude.toStringAsFixed(4) ?? '--'}, ${target?.longitude.toStringAsFixed(4) ?? '--'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  'You to target: ${_formatDistance(distance)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  nearest == null
                      ? 'Nearest teammate: unavailable'
                      : 'Nearest teammate: ${nearest['user_name'] ?? 'Unknown'} · ${_formatDistance(nearest['distance_km'] as double?)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
    );
  }

  Widget _fab(String tag, IconData icon, Color bg, VoidCallback onTap) => FloatingActionButton.small(
    heroTag: 'lt_$tag', onPressed: onTap, backgroundColor: bg,
    child: Icon(icon, color: Colors.white, size: 18),
  );

  Color _hexColor(dynamic v) {
    if (v is String && v.startsWith('#')) {
      try { return Color(int.parse(v.replaceFirst('#', '0xFF'))); } catch (_) {}
    }
    return DRDTheme.warningColor;
  }
}
