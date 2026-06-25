import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/coordinate_service.dart';
import '../services/navigation_state.dart';
import 'live_session_screen.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class LiveUser {
  final String userId;
  double lat;
  double lng;
  String status;
  String? fullName;

  LiveUser({required this.userId, required this.lat, required this.lng, required this.status, this.fullName});
}

class MapMark {
  final String? id; // server-assigned UUID (null for pending)
  final LatLng point;
  final String type;
  final String? note;
  final String? evidenceUrl; // optional uploaded image URL
  final DateTime? createdAt;
  MapMark({this.id, required this.point, required this.type, this.note, this.evidenceUrl, this.createdAt});
}

const _statusColors = {
  'active': Color(0xFF22C55E),
  'stale':  Color(0xFFF59E0B),
  'offline': Color(0xFF6B7280),
};

const _markTypes = [
  {'type': 'safe',       'label': 'Safe Zone',      'icon': Icons.verified_outlined,      'color': Color(0xFF22C55E)},
  {'type': 'enemy',      'label': 'Enemy Contact',   'icon': Icons.dangerous_outlined,     'color': Color(0xFFDC2626)},
  {'type': 'checkpoint', 'label': 'Checkpoint',      'icon': Icons.flag_outlined,          'color': Color(0xFF3B82F6)},
  {'type': 'ambush',     'label': 'Ambush Risk',     'icon': Icons.warning_amber_outlined, 'color': Color(0xFFF59E0B)},
  {'type': 'medic',      'label': 'Medical Point',   'icon': Icons.local_hospital_outlined,'color': Color(0xFFEC4899)},
  {'type': 'supply',     'label': 'Supply Drop',     'icon': Icons.inventory_2_outlined,   'color': Color(0xFF8B5CF6)},
  {'type': 'cover',      'label': 'Cover Position',  'icon': Icons.shield_outlined,        'color': Color(0xFF0EA5E9)},
  {'type': 'exit',       'label': 'Exit Route',      'icon': Icons.directions_run,         'color': Color(0xFF14B8A6)},
];

const _markIcons = {
  'safe':       Icons.verified_outlined,
  'enemy':      Icons.dangerous_outlined,
  'checkpoint': Icons.flag_outlined,
  'ambush':     Icons.warning_amber_outlined,
  'medic':      Icons.local_hospital_outlined,
  'supply':     Icons.inventory_2_outlined,
  'cover':      Icons.shield_outlined,
  'exit':       Icons.directions_run,
};

const _markColors = {
  'safe':       Color(0xFF22C55E),
  'enemy':      Color(0xFFDC2626),
  'checkpoint': Color(0xFF3B82F6),
  'ambush':     Color(0xFFF59E0B),
  'medic':      Color(0xFFEC4899),
  'supply':     Color(0xFF8B5CF6),
  'cover':      Color(0xFF0EA5E9),
  'exit':       Color(0xFF14B8A6),
};

const _markColorHex = {
  'safe':       '#22c55e',
  'enemy':      '#dc2626',
  'checkpoint': '#3b82f6',
  'ambush':     '#f59e0b',
  'medic':      '#ec4899',
  'supply':     '#8b5cf6',
  'cover':      '#0ea5e9',
  'exit':       '#14b8a6',
};

// ── Mission layer palette (one color per mission, cycles) ─────────────────────
const _missionPalette = [
  Color(0xFF3B82F6), // blue
  Color(0xFFF59E0B), // amber
  Color(0xFFEC4899), // pink
  Color(0xFF8B5CF6), // violet
  Color(0xFF14B8A6), // teal
  Color(0xFFEF4444), // red
  Color(0xFF10B981), // emerald
  Color(0xFF6366F1), // indigo
];

// ── Tile layer presets ────────────────────────────────────────────────────────

const _tilePresets = {
  'Dark': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
  'Satellite': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  'Terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
  'Street': 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
};

// ── Screen ────────────────────────────────────────────────────────────────────

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  /// Set before switching to the map tab to auto-enable that mission's layer.
  static String? pendingMissionId;

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapCtrl = MapController();
  final Map<String, LiveUser> _users = {};
  final _ws = WebSocketService();
  final List<MapMark> _marks = [];
  bool _loading = true;
  String _coordMode = 'GPS';
  String _tileName = 'Dark';
  // 'today' | 'week' | 'month' | 'all'  — applies to marks AND mission history
  String _mapFilter = 'today';

  // ── Layer data ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _facilities = [];
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _routes = [];
  List<List<LatLng>> _drawnRoutePoints = [];

  // ── Layer visibility toggles ────────────────────────────────────────────────
  bool _showZones = true;
  bool _showRoutes = true;
  bool _showFacilities = true;

  // ── Mission layers ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _missionLayers = [];
  bool _showMissions = true;
  bool _loadingMissions = false;
  final Map<String, bool> _missionVisible = {};

  // ── Objective focus + navigation ────────────────────────────────────────────
  // 'missionId:objId' when a single objective is focused; null = show all
  String? _focusedObjKey;
  List<LatLng> _navPolyline = [];

  // ── Objectives legend ───────────────────────────────────────────────────────
  bool _showLegend = false;

  @override
  void initState() {
    super.initState();
    appTabNotifier.addListener(_onTabChanged);
    _loadLiveLocations();
    _loadPois();
    _connectWS();
    // Wait for base layers before mission cross-ref so zone/route/facility lookups succeed
    Future.wait([_loadFacilities(), _loadZones(), _loadRoutes()])
        .then((_) => _loadMissionLayers());
    // Stay in sync when objectives/missions change from another screen or WS push
    WebSocketService().on('objective_completed', _onWsMissionEvent);
    WebSocketService().on('mission_completed', _onWsMissionEvent);
    WebSocketService().on('mission_active', _onWsMissionEvent);
    WebSocketService().on('mission_updated', _onWsMissionEvent);
  }

  void _onWsMissionEvent(Map<String, dynamic> _) {
    if (mounted) _loadMissionLayers();
  }

  void _onTabChanged() {
    if (appTabNotifier.value != 1) return;
    // Always refresh when the user switches to the map tab so completed
    // objectives are immediately reflected (no stale active indicators).
    final pending = LiveMapScreen.pendingMissionId;
    if (pending != null) {
      LiveMapScreen.pendingMissionId = null;
      if (mounted) setState(() => _missionVisible[pending] = true);
    }
    _loadMissionLayers();
    _loadPois();
  }

  Future<void> _loadFacilities() async {
    try {
      final data = await ApiService().get('/posts?published_only=true') as List<dynamic>;
      if (!mounted) return;
      setState(() => _facilities = data.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _loadZones() async {
    try {
      final data = await ApiService().get('/zones') as List<dynamic>;
      if (!mounted) return;
      setState(() => _zones = data.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Future<void> _loadRoutes() async {
    try {
      final data = await ApiService().get('/routes') as List<dynamic>;
      if (!mounted) return;
      setState(() => _routes = data.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  // ── Mission layer loading ──────────────────────────────────────────────────

  Color _missionColor(int idx) => _missionPalette[idx % _missionPalette.length];

  Future<void> _loadMissionLayers() async {
    if (_loadingMissions) return;
    if (mounted) setState(() => _loadingMissions = true);
    try {
      final data = await ApiService().get('/missions?my_missions=true') as List<dynamic>;
      final missions = data.cast<Map<String, dynamic>>();

      final today = DateTime.now();

      const activeGroup = {
        'approved', 'assigned', 'pending_acknowledgement', 'briefing',
        'active', 'deploying', 'extraction', 'awaiting_review',
      };

      final filtered = _mapFilter == 'all'
          ? missions.where((m) {
              final s = m['status'] as String? ?? '';
              return s != 'archived' && s != 'completed';
            }).toList()
          : missions.where((m) {
              final status = m['status'] as String? ?? '';
              if (status == 'archived') return false;
              if (activeGroup.contains(status)) return true;
              final startStr = m['start_date'] as String?;
              if (startStr == null) return _mapFilter == 'today' ? false : true;
              final start = DateTime.tryParse(startStr);
              if (start == null) return true;
              final endStr = m['end_date'] as String?;
              final end = endStr != null ? DateTime.tryParse(endStr) : null;
              final notYetEnded = end == null || end.isAfter(DateTime.now());
              if (_mapFilter == 'today') {
                final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);
                return start.isBefore(todayEnd) && notYetEnded;
              } else if (_mapFilter == 'week') {
                return start.isAfter(today.subtract(const Duration(days: 7))) && notYetEnded;
              } else {
                // month
                return start.isAfter(today.subtract(const Duration(days: 30))) && notYetEnded;
              }
            }).toList();

      final enriched = <Map<String, dynamic>>[];
      for (final m in filtered) {
        // Fetch all resources for this mission via the dedicated endpoint
        // (bypasses team/role filters on zone/route/facility list endpoints)
        var zones = <Map<String, dynamic>>[];
        var routes = <Map<String, dynamic>>[];
        var facilities = <Map<String, dynamic>>[];
        try {
          final res = await ApiService().get('/missions/${m['id']}/resources') as Map<String, dynamic>;
          zones = (res['zones'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          routes = (res['routes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          facilities = (res['facilities'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        } catch (_) {}

        enriched.add({...m, '_zones': zones, '_routes': routes, '_facilities': facilities});
        _missionVisible.putIfAbsent(m['id'] as String, () => true);
      }

      if (mounted) {
        setState(() {
          _missionLayers = enriched;
          _loadingMissions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMissions = false);
    }
  }

  // ── Mission map helpers ────────────────────────────────────────────────────

  List<LatLng> _missionZonePoints(Map<String, dynamic> zone) {
    if (zone['is_circle'] == true) {
      final lat = (zone['center_lat'] as num?)?.toDouble();
      final lng = (zone['center_lng'] as num?)?.toDouble();
      final radius = (zone['radius'] as num?)?.toDouble() ?? 100;
      if (lat == null || lng == null) return [];
      const steps = 36;
      const r = 6371000.0;
      return List.generate(steps, (i) {
        final angle = 2 * math.pi * i / steps;
        final dLat = (radius / r) * (180 / math.pi) * math.cos(angle);
        final dLng = (radius / (r * math.cos(lat * math.pi / 180))) * (180 / math.pi) * math.sin(angle);
        return LatLng(lat + dLat, lng + dLng);
      });
    }
    try {
      final polyPts = zone['polygon_points'] as Map<String, dynamic>?;
      if (polyPts == null) return [];
      final rawList = polyPts['points'] as List?
          ?? (polyPts['coordinates'] as List?)?.first as List?;
      if (rawList == null || rawList.isEmpty) return [];
      return rawList.map((pt) {
        final pair = pt as List;
        return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList();
    } catch (_) {
      return [];
    }
  }

  List<LatLng> _missionRoutePoints(Map<String, dynamic> route) {
    try {
      final wps = (route['waypoints'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      return wps.map((w) {
        final lat = ((w['latitude'] ?? w['lat']) as num?)?.toDouble();
        final lng = ((w['longitude'] ?? w['lng']) as num?)?.toDouble();
        return (lat != null && lng != null) ? LatLng(lat, lng) : null;
      }).whereType<LatLng>().toList();
    } catch (_) {
      return [];
    }
  }

  void _showMissionPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MissionLayerPanel(
        missions: _missionLayers,
        visibilityMap: _missionVisible,
        showMissions: _showMissions,
        mapFilter: _mapFilter,
        loadingMissions: _loadingMissions,
        missionColor: _missionColor,
        onToggleAll: (v) {
          setState(() => _showMissions = v);
          Navigator.pop(context);
        },
        onToggleMission: (id, v) => setState(() => _missionVisible[id] = v),
        onMapFilter: (f) {
          setState(() => _mapFilter = f);
          Navigator.pop(context);
          _loadMissionLayers();
        },
        onRefresh: () {
          Navigator.pop(context);
          _loadMissionLayers();
        },
      ),
    );
  }

  Color _parseHexColor(String hex, double defaultAlpha) {
    final h = hex.replaceFirst('#', '');
    try {
      if (h.length == 8) {
        return Color(int.parse(h, radix: 16));
      } else if (h.length == 6) {
        return Color((defaultAlpha * 255).round() << 24 | int.parse(h, radix: 16));
      }
    } catch (_) {}
    return const Color(0x4D6366F1);
  }

  void _onFacilityTap(Map<String, dynamic> facility) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A100A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FacilitySheet(
        facility: facility,
        routes: _routes,
        onRouteSelected: (routeId) {
          Navigator.pop(context);
          _focusRoute(routeId);
        },
      ),
    );
  }

  void _focusRoute(String routeId) {
    final route = _routes.firstWhere((r) => r['id'] == routeId, orElse: () => {});
    if (route.isEmpty) return;
    final waypoints = (route['waypoints'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    if (waypoints.isEmpty) return;
    final points = waypoints
        .map((w) => LatLng((w['latitude'] as num).toDouble(), (w['longitude'] as num).toDouble()))
        .toList();
    setState(() {
      _drawnRoutePoints = [points];
    });
    if (points.isNotEmpty) {
      _mapCtrl.move(points.first, 14);
    }
  }

  Future<void> _loadLiveLocations() async {
    try {
      final data = await ApiService().get('/locations/live') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        for (final d in data) {
          final m = d as Map<String, dynamic>;
          final uid = m['user_id'] as String;
          _users[uid] = LiveUser(
            userId: uid,
            lat: (m['latitude'] as num).toDouble(),
            lng: (m['longitude'] as num).toDouble(),
            status: m['status'] as String? ?? 'offline',
            fullName: (m['user'] as Map?)?['full_name'] as String?,
          );
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPois() async {
    try {
      final data = await ApiService().get('/pois') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        // Keep marks that are still being saved (no server id yet) to avoid a
        // race condition where _loadPois fires before _saveMark completes.
        final pending = _marks.where((m) => m.id == null).toList();
        _marks.clear();
        for (final d in data) {
          final m = d as Map<String, dynamic>;
          _marks.add(MapMark(
            id: m['id'] as String?,
            point: LatLng(
              (m['latitude'] as num).toDouble(),
              (m['longitude'] as num).toDouble(),
            ),
            type: m['poi_type'] as String? ?? 'general',
            note: m['description'] as String?,
            createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'] as String) : null,
          ));
        }
        _marks.addAll(pending);
      });
    } catch (_) {}
  }

  List<MapMark> get _filteredMarks {
    if (_mapFilter == 'all') return _marks;
    final now = DateTime.now();
    final DateTime cutoff;
    if (_mapFilter == 'week') {
      cutoff = now.subtract(const Duration(days: 7));
    } else if (_mapFilter == 'month') {
      cutoff = now.subtract(const Duration(days: 30));
    } else {
      cutoff = DateTime(now.year, now.month, now.day);
    }
    return _marks.where((m) {
      // Marks without a timestamp were just created this session — always show them.
      if (m.createdAt == null) return true;
      return m.createdAt!.isAfter(cutoff);
    }).toList();
  }

  Future<void> _clearAllMarks() async {
    final toDelete = _marks.where((m) => m.id != null).map((m) => m.id!).toList();
    setState(() => _marks.clear());
    for (final id in toDelete) {
      try { await ApiService().delete('/pois/$id'); } catch (_) {}
    }
  }

  Future<void> _saveMark(MapMark mark) async {
    try {
      final body = <String, dynamic>{
        'name': mark.type.capitalize(),
        'description': mark.note,
        'latitude': mark.point.latitude,
        'longitude': mark.point.longitude,
        'poi_type': mark.type,
        'color': _markColorHex[mark.type] ?? '#8b5cf6',
      };
      if (mark.evidenceUrl != null) {
        body['evidence_url'] = mark.evidenceUrl;
      }
      final res = await ApiService().post('/pois', body);
      // Replace the pending mark with the server-confirmed one (has id + createdAt)
      final serverId = res['id'] as String?;
      final serverCreatedAt = res['created_at'] != null
          ? DateTime.tryParse(res['created_at'] as String)
          : DateTime.now();
      if (mounted && serverId != null) {
        setState(() {
          final idx = _marks.indexWhere((m) => m.id == null && m.point == mark.point && m.type == mark.type);
          if (idx >= 0) {
            _marks[idx] = MapMark(
              id: serverId,
              point: mark.point,
              type: mark.type,
              note: mark.note,
              evidenceUrl: mark.evidenceUrl,
              createdAt: serverCreatedAt,
            );
          }
        });
      }
    } catch (_) {
      // Keep the local mark visible even if save fails
    }
  }

  void _connectWS() {
    final myId = context.read<AuthProvider>().user?.id;
    if (myId == null) return;
    _ws.on('location_update', _onLocation);
    _ws.connect('/ws/location/$myId');
  }

  void _onLocation(Map<String, dynamic> msg) {
    if (!mounted) return;
    final uid = msg['user_id'] as String?;
    if (uid == null) return;
    setState(() {
      _users[uid] = LiveUser(
        userId: uid,
        lat: (msg['lat'] as num).toDouble(),
        lng: (msg['lng'] as num).toDouble(),
        status: msg['status'] as String? ?? 'active',
        fullName: _users[uid]?.fullName,
      );
    });
  }

  @override
  void dispose() {
    appTabNotifier.removeListener(_onTabChanged);
    _ws.off('location_update', _onLocation);
    WebSocketService().off('objective_completed', _onWsMissionEvent);
    WebSocketService().off('mission_completed', _onWsMissionEvent);
    WebSocketService().off('mission_active', _onWsMissionEvent);
    WebSocketService().off('mission_updated', _onWsMissionEvent);
    super.dispose();
  }

  String _formatCoord(double lat, double lng) {
    switch (_coordMode) {
      case 'DMS':
        return '${CoordinateService.toDMS(lat, true)} ${CoordinateService.toDMS(lng, false)}';
      case 'MGRS':
        return CoordinateService.toMGRS(lat, lng);
      default:
        return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
  }

  List<Map<String, dynamic>> _getSortedObjectives(Map<String, dynamic> mission) {
    final objs = (mission['objectives'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .toList();
    objs.sort((a, b) => ((a['order_index'] as num?)?.toInt() ?? 0)
        .compareTo((b['order_index'] as num?)?.toInt() ?? 0));
    return objs;
  }

  // Returns the active mission layer (first in list), or null
  Map<String, dynamic>? get _activeMission =>
      _missionLayers.isEmpty ? null : _missionLayers.first;

  // Current (incomplete) objective for the active mission
  Map<String, dynamic>? get _currentObjective {
    final m = _activeMission;
    if (m == null) return null;
    final objs = (m['objectives'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
      ..sort((a, b) =>
          ((a['order_index'] as num?)?.toInt() ?? 0)
              .compareTo((b['order_index'] as num?)?.toInt() ?? 0));
    for (final o in objs) {
      if (o['is_completed'] != true) return o;
    }
    return null;
  }

  // Compute distance in metres between two LatLng points (Haversine)
  double _distanceM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * 3.14159265 / 180;
    final dLng = (b.longitude - a.longitude) * 3.14159265 / 180;
    final sinLat = dLat / 2;
    final sinLng = dLng / 2;
    final hav = sinLat * sinLat +
        (b.latitude * 3.14159265 / 180) * (a.latitude * 3.14159265 / 180) *
            sinLng * sinLng;
    return 2 * r * (hav < 1 ? hav : 1);
  }

  String _fmtDist(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  // Centroid of a list of points (for distance-to-zone)
  LatLng? _centroid(List<LatLng> pts) {
    if (pts.isEmpty) return null;
    final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lng);
  }

  // Target LatLng for the current objective (zone centre / route first waypoint / facility)
  LatLng? _currentObjectiveTarget() {
    final obj = _currentObjective;
    final m = _activeMission;
    if (obj == null || m == null) return null;

    final zoneId = obj['zone_id'] as String?;
    final routeId = obj['route_id'] as String?;
    final facilityId = obj['facility_id'] as String?;

    if (zoneId != null) {
      final zone = _zones.firstWhere((z) => z['id'] == zoneId, orElse: () => {});
      if (zone.isNotEmpty) {
        final pts = _missionZonePoints(zone);
        return _centroid(pts);
      }
    }
    if (routeId != null) {
      final route = _routes.firstWhere((r) => r['id'] == routeId, orElse: () => {});
      if (route.isNotEmpty) {
        final pts = _missionRoutePoints(route);
        return pts.isNotEmpty ? pts.first : null;
      }
    }
    if (facilityId != null) {
      final f = _facilities.firstWhere((f) => f['id'] == facilityId, orElse: () => {});
      if (f.isNotEmpty) {
        final lat = (f['latitude'] as num?)?.toDouble();
        final lng = (f['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }
    return null;
  }

  // Long-press → if active mission show action menu first, else show mark picker
  void _onLongPress(TapPosition tapPos, LatLng point) {
    final missionId = _activeMission?['id'] as String?;
    if (missionId != null) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _MissionMapActionSheet(
          point: point,
          coordText: _formatCoord(point.latitude, point.longitude),
          missionId: missionId,
          missionName: _activeMission?['name'] as String? ?? 'Mission',
          onMarkInstead: () {
            Navigator.pop(context);
            _showMarkPicker(point);
          },
          onSaved: () => Navigator.pop(context),
        ),
      );
    } else {
      _showMarkPicker(point);
    }
  }

  void _joinBriefing(String sessionId) {
    LiveSessionScreen.pendingJoinSessionId = sessionId;
    Navigator.pushNamed(context, '/live');
  }

  void _clearNavFocus() {
    setState(() {
      _focusedObjKey = null;
      _navPolyline = [];
    });
  }

  Future<void> _markObjectiveDone(Map<String, dynamic> obj, Map<String, dynamic> mission) async {
    final myLoc = context.read<LocationProvider>().current;
    try {
      await ApiService().post(
        '/missions/${mission['id']}/objectives/${obj['id']}/complete',
        {
          if (myLoc != null) 'latitude': myLoc.lat,
          if (myLoc != null) 'longitude': myLoc.lng,
        },
      );
      _clearNavFocus();
      await _loadMissionLayers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to mark objective done'), backgroundColor: Color(0xFF7F1D1D)),
        );
      }
    }
  }

  Future<void> _completeMission(Map<String, dynamic> mission) async {
    try {
      await ApiService().post('/missions/${mission['id']}/complete', {});
      _clearNavFocus();
      await _loadMissionLayers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mission completed!'), backgroundColor: Color(0xFF166534)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to complete mission'), backgroundColor: Color(0xFF7F1D1D)),
        );
      }
    }
  }

  // Creates alternating dash segments to simulate a dotted line on the map
  List<Polyline> _buildDashedPolylines(List<LatLng> pts, Color color, double strokeWidth) {
    if (pts.length < 2) return [];
    const dashDeg = 0.00009; // ~10 m in degrees latitude
    const gapDeg = 0.00006;
    final segments = <Polyline>[];
    for (int i = 0; i < pts.length - 1; i++) {
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final dx = p2.longitude - p1.longitude;
      final dy = p2.latitude - p1.latitude;
      final total = math.sqrt(dx * dx + dy * dy);
      if (total == 0) continue;
      double traveled = 0;
      bool drawing = true;
      while (traveled < total) {
        final segLen = drawing ? dashDeg : gapDeg;
        final end = math.min(traveled + segLen, total);
        final t1 = traveled / total;
        final t2 = end / total;
        if (drawing) {
          segments.add(Polyline(
            points: [
              LatLng(p1.latitude + dy * t1, p1.longitude + dx * t1),
              LatLng(p1.latitude + dy * t2, p1.longitude + dx * t2),
            ],
            color: color,
            strokeWidth: strokeWidth,
          ));
        }
        traveled = end;
        drawing = !drawing;
      }
    }
    return segments;
  }

  Future<void> _navigateToObjective(Map<String, dynamic> obj, Map<String, dynamic> mission) async {
    final myLoc = context.read<LocationProvider>().current;
    if (myLoc == null) return;

    final allZones = (mission['_zones'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final allRoutes = (mission['_routes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final allFacilities = (mission['_facilities'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final zoneId = obj['zone_id'] as String?;
    final routeId = obj['route_id'] as String?;
    final facilityId = obj['facility_id'] as String?;

    LatLng? target;
    if (zoneId != null) {
      final zone = allZones.firstWhere((z) => z['id'] == zoneId, orElse: () => {});
      if (zone.isNotEmpty) target = _centroid(_missionZonePoints(zone));
    } else if (routeId != null) {
      final route = allRoutes.firstWhere((r) => r['id'] == routeId, orElse: () => {});
      if (route.isNotEmpty) {
        final pts = _missionRoutePoints(route);
        if (pts.isNotEmpty) target = pts.first;
      }
    } else if (facilityId != null) {
      final f = allFacilities.firstWhere((f) => f['id'] == facilityId, orElse: () => {});
      if (f.isNotEmpty) {
        final lat = (f['latitude'] as num?)?.toDouble();
        final lng = (f['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) target = LatLng(lat, lng);
      }
    }

    if (target == null) return;

    final missionId = mission['id'] as String;
    final objId = obj['id'] as String? ?? '';

    // Set focus, close legend, move map immediately; road route fills in asynchronously
    setState(() {
      _focusedObjKey = '$missionId:$objId';
      _navPolyline = [LatLng(myLoc.lat, myLoc.lng), target!];
      _showLegend = false;
    });
    _mapCtrl.move(target, 14);

    // Fetch real road route from OSRM (no API key required)
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${myLoc.lng},${myLoc.lat};${target.longitude},${target.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        if (json['code'] == 'Ok') {
          final coords = ((json['routes'] as List?)?.first?['geometry']?['coordinates']) as List?;
          if (coords != null && coords.length >= 2) {
            final pts = coords
                .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList();
            if (mounted) setState(() => _navPolyline = pts);
          }
        }
      }
    } catch (_) {
      // Keep the straight-line fallback already set above
    }
  }

  void _showObjectiveSheet(Map<String, dynamic> obj, Map<String, dynamic> mission) {
    final orderNum = ((obj['order_index'] as num?)?.toInt() ?? 0) + 1;
    final title = (obj['title'] as String? ?? '').replaceFirst(
        RegExp(r'^\[(ZONE|ROUTE|FACILITY)\]\s*(\w[\w\s]*:\s*)?'), '').trim();
    final isCompleted = obj['is_completed'] == true;
    final objs = _getSortedObjectives(mission);
    final currentIdx = objs.indexWhere((o) => o['is_completed'] != true);
    final objIdx = objs.indexWhere((o) => o['id'] == obj['id']);
    final isCurrent = !isCompleted && objIdx == currentIdx;
    final status = isCompleted ? 'Completed' : isCurrent ? 'Current' : 'Pending';
    final statusColor = isCompleted
        ? const Color(0xFF6B7280)
        : isCurrent
            ? const Color(0xFF22C55E)
            : const Color(0xFF3B82F6);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                child: Center(
                  child: Text('$orderNum',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Objective $orderNum' : title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor, width: 1)),
                child: Text(status,
                    style: TextStyle(
                        color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              'Mission: ${mission['name'] ?? 'Unknown'}',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            if ((obj['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(obj['description'] as String,
                  style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.layers_clear_outlined, size: 16),
                  label: const Text('Show All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9CA3AF),
                    side: const BorderSide(color: Color(0xFF374151)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _clearNavFocus();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.directions, size: 16),
                  label: const Text('Show Route'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _navigateToObjective(obj, mission);
                  },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _showMarkPicker(LatLng point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A100A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MarkPicker(
        point: point,
        coordText: _formatCoord(point.latitude, point.longitude),
        onMark: (mark) {
          setState(() => _marks.add(mark));
          Navigator.pop(context);
          _saveMark(mark);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.select<AuthProvider, String?>((a) => a.user?.id);
    final myLoc = context.watch<LocationProvider>().current;
    final userRole = context.select<AuthProvider, UserRole?>((a) => a.user?.role);
    final tileUrl = _tilePresets[_tileName]!;

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: [
            const Text('Live Map', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF166534), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.circle, color: Color(0xFF22C55E), size: 8),
                  const SizedBox(width: 4),
                  Text('${_users.length} tracked', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Tile view picker
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers_outlined, color: Color(0xFF9CA3AF)),
            color: const Color(0xFF1F2937),
            onSelected: (v) => setState(() => _tileName = v),
            itemBuilder: (_) => _tilePresets.keys.map((name) => PopupMenuItem(
              value: name,
              child: Row(
                children: [
                  Icon(Icons.check, color: _tileName == name ? const Color(0xFF22C55E) : Colors.transparent, size: 16),
                  const SizedBox(width: 6),
                  Text(name, style: const TextStyle(color: Colors.white)),
                ],
              ),
            )).toList(),
          ),
          // Map layers toggle
          PopupMenuButton<String>(
            icon: Icon(
              Icons.tune,
              color: const Color(0xFF9CA3AF),
            ),
            color: const Color(0xFF1F2937),
            tooltip: 'Map Layers',
            onSelected: (v) {
              setState(() {
                if (v == 'zones') _showZones = !_showZones;
                if (v == 'routes') _showRoutes = !_showRoutes;
                if (v == 'facilities') _showFacilities = !_showFacilities;
              });
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'zones', child: Row(children: [
                Icon(Icons.pentagon_outlined, color: _showZones ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF), size: 16),
                const SizedBox(width: 8),
                Text('Zones', style: TextStyle(color: _showZones ? const Color(0xFF22C55E) : Colors.white)),
              ])),
              PopupMenuItem(value: 'routes', child: Row(children: [
                Icon(Icons.route, color: _showRoutes ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF), size: 16),
                const SizedBox(width: 8),
                Text('Routes', style: TextStyle(color: _showRoutes ? const Color(0xFF22C55E) : Colors.white)),
              ])),
              PopupMenuItem(value: 'facilities', child: Row(children: [
                Icon(Icons.domain, color: _showFacilities ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF), size: 16),
                const SizedBox(width: 8),
                Text('Facilities', style: TextStyle(color: _showFacilities ? const Color(0xFF22C55E) : Colors.white)),
              ])),
            ],
          ),
          // Marks history filter
          PopupMenuButton<String>(
            icon: Icon(
              _mapFilter == 'all' ? Icons.history : Icons.today,
              color: _mapFilter != 'today' ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
            ),
            tooltip: 'Filter marks by time',
            color: const Color(0xFF1F2937),
            onSelected: (v) {
              setState(() => _mapFilter = v);
              // Reload so the new filter applies to missions, zones, and marks
              _loadMissionLayers();
              _loadPois();
              if (v == 'all') {
                _loadFacilities();
                _loadZones();
                _loadRoutes();
              }
            },
            itemBuilder: (_) => [
              for (final item in [
                ('today', 'Today'),
                ('week', 'Last Week'),
                ('month', 'Last Month'),
                ('all', 'All Time'),
              ])
                PopupMenuItem<String>(
                  value: item.$1,
                  child: Row(children: [
                    Icon(Icons.check,
                        color: _mapFilter == item.$1
                            ? const Color(0xFF22C55E)
                            : Colors.transparent,
                        size: 16),
                    const SizedBox(width: 6),
                    Text(item.$2, style: const TextStyle(color: Colors.white)),
                  ]),
                ),
            ],
          ),
          // Coord format picker
          PopupMenuButton<String>(
            icon: const Icon(Icons.grid_on, color: Color(0xFF9CA3AF)),
            color: const Color(0xFF1F2937),
            onSelected: (v) => setState(() => _coordMode = v),
            itemBuilder: (_) => ['GPS', 'DMS', 'MGRS']
                .map((m) => PopupMenuItem(value: m, child: Text(m, style: const TextStyle(color: Colors.white))))
                .toList(),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: myLoc != null ? LatLng(myLoc.lat, myLoc.lng) : const LatLng(-1.9441, 30.0619),
              initialZoom: 13,
              onLongPress: _onLongPress,
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.drd.operations',
              ),
              // Zone polygons (handles both polygon and circle zones)
              if (_showZones)
                PolygonLayer(
                  polygons: _zones
                      .where((z) => z['is_active'] == true)
                      .map((z) {
                        final pts = _missionZonePoints(z);
                        if (pts.isEmpty) return null;
                        final borderColor = _parseHexColor(z['color'] as String? ?? '#6366f1', 0.9);
                        final fillColor = _parseHexColor(z['fill_color'] as String? ?? '#6366f133', 0.3);
                        return Polygon(points: pts, color: fillColor, borderColor: borderColor, borderStrokeWidth: 2);
                      })
                      .whereType<Polygon>()
                      .toList(),
                ),
              // Mission zone polygons — all objectives, colored by order/status
              if (_showMissions)
                PolygonLayer(
                  polygons: _missionLayers.asMap().entries.expand<Polygon>((mEntry) {
                    final mIdx = mEntry.key;
                    final mission = mEntry.value;
                    final mId = mission['id'] as String;
                    if (_missionVisible[mId] == false) return [];
                    final objs = _getSortedObjectives(mission);
                    final currentIdx = objs.indexWhere((o) => o['is_completed'] != true);
                    final allZones = (mission['_zones'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
                    final mColor = _missionColor(mIdx);
                    return allZones.expand<Polygon>((zone) {
                      final zoneId = zone['id'] as String?;
                      final objIdx = objs.indexWhere((o) => o['zone_id'] == zoneId);
                      final obj = objIdx >= 0 ? objs[objIdx] : null;
                      final objId = obj?['id'] as String? ?? '';
                      // In focus mode, hide objectives that aren't focused
                      if (_focusedObjKey != null && _focusedObjKey != '$mId:$objId') return [];
                      final isCompleted = obj?['is_completed'] == true;
                      final isCurrent = obj != null && !isCompleted && objIdx == currentIdx;
                      final pts = _missionZonePoints(zone);
                      if (pts.isEmpty) return [];
                      final Color fill, border;
                      final double bw;
                      if (isCompleted) {
                        fill = const Color(0xFF6B7280).withValues(alpha: 0.1);
                        border = const Color(0xFF6B7280).withValues(alpha: 0.5);
                        bw = 1.5;
                      } else if (isCurrent) {
                        fill = const Color(0xFF22C55E).withValues(alpha: 0.2);
                        border = const Color(0xFF22C55E);
                        bw = 3;
                      } else {
                        fill = mColor.withValues(alpha: 0.1);
                        border = mColor.withValues(alpha: 0.7);
                        bw = 2;
                      }
                      return [Polygon(points: pts, color: fill, borderColor: border, borderStrokeWidth: bw)];
                    });
                  }).toList(),
                ),
              // Mission route polylines — all objectives, colored by order/status
              if (_showMissions)
                PolylineLayer(
                  polylines: _missionLayers.asMap().entries.expand<Polyline>((mEntry) {
                    final mIdx = mEntry.key;
                    final mission = mEntry.value;
                    final mId = mission['id'] as String;
                    if (_missionVisible[mId] == false) return [];
                    final objs = _getSortedObjectives(mission);
                    final currentIdx = objs.indexWhere((o) => o['is_completed'] != true);
                    final allRoutes = (mission['_routes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
                    final mColor = _missionColor(mIdx);
                    return allRoutes.expand<Polyline>((route) {
                      final routeId = route['id'] as String?;
                      final objIdx = objs.indexWhere((o) => o['route_id'] == routeId);
                      final obj = objIdx >= 0 ? objs[objIdx] : null;
                      final objId = obj?['id'] as String? ?? '';
                      if (_focusedObjKey != null && _focusedObjKey != '$mId:$objId') return [];
                      final isCompleted = obj?['is_completed'] == true;
                      final isCurrent = obj != null && !isCompleted && objIdx == currentIdx;
                      final pts = _missionRoutePoints(route);
                      if (pts.length < 2) return [];
                      final Color color;
                      final double sw;
                      if (isCompleted) {
                        color = const Color(0xFF6B7280).withValues(alpha: 0.5);
                        sw = 2;
                      } else if (isCurrent) {
                        color = const Color(0xFF22C55E);
                        sw = 4;
                      } else {
                        color = mColor.withValues(alpha: 0.85);
                        sw = 3;
                      }
                      return [Polyline(points: pts, color: color, strokeWidth: sw)];
                    });
                  }).toList(),
                ),
              // All route polylines
              if (_showRoutes)
                PolylineLayer(
                  polylines: _routes.expand<Polyline>((r) {
                    final pts = _missionRoutePoints(r);
                    if (pts.length < 2) return [];
                    final color = _parseHexColor(r['color'] as String? ?? '#3b82f6', 1.0);
                    return [Polyline(points: pts, color: color, strokeWidth: 3)];
                  }).toList(),
                ),
              // Focused/selected route highlight
              if (_showRoutes && _drawnRoutePoints.isNotEmpty)
                PolylineLayer(
                  polylines: _drawnRoutePoints.map((pts) => Polyline(
                    points: pts,
                    color: const Color(0xFF22C55E),
                    strokeWidth: 6,
                  )).toList(),
                ),
              // Navigation line: current location → focused objective (real road route)
              if (_navPolyline.length >= 2)
                PolylineLayer(
                  polylines: _buildDashedPolylines(
                    _navPolyline, const Color(0xFF60A5FA), 3.5),
                ),
              // Live users + field marks + facility markers
              MarkerLayer(
                markers: [
                  ..._users.values.map((u) {
                    final isMe = u.userId == myId;
                    final color = _statusColors[u.status] ?? const Color(0xFF6B7280);
                    return Marker(
                      point: LatLng(u.lat, u.lng),
                      width: isMe ? 24 : 18,
                      height: isMe ? 24 : 18,
                      child: Tooltip(
                        message: u.fullName ?? u.userId.substring(0, 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: isMe ? 1.0 : 0.6), width: isMe ? 3 : 2),
                            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (myLoc != null && !_users.containsKey(myId))
                    Marker(
                      point: LatLng(myLoc.lat, myLoc.lng),
                      width: 24, height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  // Field marks (filtered by time range)
                  ..._filteredMarks.map((mark) {
                    final color = _markColors[mark.type] ?? const Color(0xFF6B7280);
                    final icon = _markIcons[mark.type] ?? Icons.place;
                    return Marker(
                      point: mark.point,
                      width: 32, height: 32,
                      child: Tooltip(
                        message: mark.type.capitalize(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                          ),
                          child: Icon(icon, color: Colors.white, size: 16),
                        ),
                      ),
                    );
                  }),
                  // Mission objective badges — order numbers on zones, routes, facilities
                  if (_showMissions)
                    ..._missionLayers.asMap().entries.expand<Marker>((mEntry) {
                      final mIdx = mEntry.key;
                      final mission = mEntry.value;
                      final mId = mission['id'] as String;
                      if (_missionVisible[mId] == false) return [];
                      final objs = _getSortedObjectives(mission);
                      final currentIdx = objs.indexWhere((o) => o['is_completed'] != true);
                      final mColor = _missionColor(mIdx);
                      final allZones = (mission['_zones'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
                      final allRoutes = (mission['_routes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
                      final allFacilities = (mission['_facilities'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
                      final markers = <Marker>[];

                      for (final objEntry in objs.asMap().entries) {
                        final objIdx = objEntry.key;
                        final obj = objEntry.value;
                        final objId = obj['id'] as String? ?? '';
                        // In focus mode only show badge for the focused objective
                        if (_focusedObjKey != null && _focusedObjKey != '$mId:$objId') continue;
                        final isCompleted = obj['is_completed'] == true;
                        final isCurrent = !isCompleted && objIdx == currentIdx;
                        final orderNum = (obj['order_index'] as num?)?.toInt() ?? objIdx;
                        final label = '${orderNum + 1}';
                        final Color badgeColor;
                        if (isCompleted) {
                          badgeColor = const Color(0xFF6B7280);
                        } else if (isCurrent) {
                          badgeColor = const Color(0xFF22C55E);
                        } else {
                          badgeColor = mColor;
                        }

                        // Zone badge at centroid
                        final zoneId = obj['zone_id'] as String?;
                        if (zoneId != null) {
                          final zone = allZones.firstWhere((z) => z['id'] == zoneId, orElse: () => {});
                          if (zone.isNotEmpty) {
                            final pts = _missionZonePoints(zone);
                            final c = _centroid(pts);
                            if (c != null) {
                              markers.add(Marker(
                                point: c, width: 28, height: 28,
                                child: GestureDetector(
                                  onTap: () => _showObjectiveSheet(obj, mission),
                                  child: _OrderBadge(label: label, color: badgeColor, isDone: isCompleted),
                                ),
                              ));
                            }
                          }
                        }

                        // Route badge at midpoint
                        final routeId = obj['route_id'] as String?;
                        if (routeId != null) {
                          final route = allRoutes.firstWhere((r) => r['id'] == routeId, orElse: () => {});
                          if (route.isNotEmpty) {
                            final pts = _missionRoutePoints(route);
                            if (pts.isNotEmpty) {
                              final mid = pts[pts.length ~/ 2];
                              markers.add(Marker(
                                point: mid, width: 28, height: 28,
                                child: GestureDetector(
                                  onTap: () => _showObjectiveSheet(obj, mission),
                                  child: _OrderBadge(label: label, color: badgeColor, isDone: isCompleted),
                                ),
                              ));
                            }
                          }
                        }

                        // Facility badge
                        final facilityId = obj['facility_id'] as String?;
                        if (facilityId != null) {
                          final f = allFacilities.firstWhere((f) => f['id'] == facilityId, orElse: () => {});
                          if (f.isNotEmpty) {
                            final lat = (f['latitude'] as num?)?.toDouble();
                            final lng = (f['longitude'] as num?)?.toDouble();
                            if (lat != null && lng != null) {
                              markers.add(Marker(
                                point: LatLng(lat, lng),
                                width: isCurrent ? 44 : 36,
                                height: isCurrent ? 44 : 36,
                                child: GestureDetector(
                                  onTap: () => _showObjectiveSheet(obj, mission),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: isCurrent ? 44 : 36,
                                        height: isCurrent ? 44 : 36,
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(alpha: isCompleted ? 0.5 : 0.9),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                                        ),
                                        child: Icon(Icons.domain, color: Colors.white, size: isCurrent ? 20 : 16),
                                      ),
                                      Positioned(
                                        top: 0, right: 0,
                                        child: _OrderBadge(label: label, color: badgeColor, isDone: isCompleted, small: true),
                                      ),
                                    ],
                                  ),
                                ),
                              ));
                            }
                          }
                        }
                      }
                      return markers;
                    }),
                  // Facility markers
                  if (_showFacilities)
                    ..._facilities.map((f) {
                      final lat = (f['latitude'] as num?)?.toDouble();
                      final lng = (f['longitude'] as num?)?.toDouble();
                      if (lat == null || lng == null) return null;
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 36, height: 36,
                        child: GestureDetector(
                          onTap: () => _onFacilityTap(f),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                            ),
                            child: const Icon(Icons.domain, color: Colors.white, size: 18),
                          ),
                        ),
                      );
                    }).whereType<Marker>(),
                ],
              ),
            ],
          ),
          if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),

          // Distance banner — current objective
          if (!_loading && _activeMission != null && myLoc != null)
            Builder(builder: (_) {
              final target = _currentObjectiveTarget();
              final obj = _currentObjective;
              if (target == null || obj == null) return const SizedBox.shrink();
              final myLatLng = LatLng(myLoc.lat, myLoc.lng);
              final dist = _distanceM(myLatLng, target);
              final title = (obj['title'] as String? ?? '')
                  .replaceFirst(RegExp(r'^\[(ZONE|ROUTE|FACILITY)\]\s*(\w[\w\s]*:\s*)?'), '')
                  .trim();
              return Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xEE0F1F0F),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.navigation, color: Color(0xFF22C55E), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title.isEmpty ? 'Current Objective' : title,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _fmtDist(dist),
                        style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }),

          // Briefing banner — shown when active mission is in briefing state
          Builder(builder: (_) {
            final mission = _activeMission;
            if (mission == null) return const SizedBox.shrink();
            final status = mission['status'] as String? ?? '';
            if (status != 'briefing') return const SizedBox.shrink();
            final sessionId = mission['live_session_id'] as String?;
            if (sessionId == null) return const SizedBox.shrink();
            final hasDistBanner = _currentObjective != null && _currentObjectiveTarget() != null;
            return Positioned(
              top: hasDistBanner ? 48 : 8,
              left: 12, right: 12,
              child: GestureDetector(
                onTap: () => _joinBriefing(sessionId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xEE1E3A5F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF3B82F6), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam, color: Color(0xFF60A5FA), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'BRIEFING IN PROGRESS — ${mission['name'] ?? 'Mission'}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('JOIN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Mission management panel — Start/Mark Done/Complete Mission
          Builder(builder: (_) {
            final mission = _activeMission;
            if (mission == null || !_showMissions) return const SizedBox.shrink();
            final status = mission['status'] as String? ?? '';
            if (!{'active', 'deploying', 'extraction'}.contains(status)) return const SizedBox.shrink();
            final objs = _getSortedObjectives(mission);
            final currentIdx = objs.indexWhere((o) => o['is_completed'] != true);
            final currentObj = currentIdx >= 0 ? objs[currentIdx] : null;
            final doneCount = objs.where((o) => o['is_completed'] == true).length;
            final allDone = doneCount == objs.length && objs.isNotEmpty;
            final isLeaderOrAbove = userRole == UserRole.teamLeader ||
                userRole == UserRole.planningOfficer ||
                userRole == UserRole.operationsCoordinator;
            return Positioned(
              bottom: 90, left: 16, right: 70,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF00F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.flag, color: Color(0xFF3B82F6), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          mission['name'] as String? ?? 'Mission',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '$doneCount/${objs.length}',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                      ),
                    ]),
                    if (objs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: objs.isEmpty ? 0 : doneCount / objs.length,
                          minHeight: 4,
                          backgroundColor: const Color(0xFF1F2937),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                        ),
                      ),
                    ],
                    if (currentObj != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Next: ${((currentObj['title'] as String? ?? '').replaceFirst(RegExp(r'^\[(ZONE|ROUTE|FACILITY)\]\s*(\w[\w\s]*:\s*)?'), '').trim()).isNotEmpty ? (currentObj['title'] as String).replaceFirst(RegExp(r'^\[(ZONE|ROUTE|FACILITY)\]\s*(\w[\w\s]*:\s*)?'), '').trim() : 'Objective ${(currentObj['order_index'] as num? ?? 0).toInt() + 1}'}',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      if (currentObj != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.navigation, size: 14),
                            label: const Text('Start', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _navigateToObjective(currentObj, mission),
                          ),
                        ),
                      if (currentObj != null) const SizedBox(width: 8),
                      if (!allDone && currentObj != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check_circle_outline, size: 14),
                            label: const Text('Mark Done', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF166534),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _markObjectiveDone(currentObj, mission),
                          ),
                        ),
                      if (isLeaderOrAbove && allDone) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.task_alt, size: 14),
                            label: const Text('Complete Mission', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _completeMission(mission),
                          ),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            );
          }),

          // Status legend + coordinate display
          Positioned(
            bottom: 16, left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._statusColors.entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: e.value, size: 8),
                      const SizedBox(width: 6),
                      Text(
                        '${e.key.capitalize()} (${_users.values.where((u) => u.status == e.key).length})',
                        style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11),
                      ),
                    ],
                  ),
                )),
                if (myLoc != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatCoord(myLoc.lat, myLoc.lng),
                      style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
              ],
            ),
          ),

          // FABs
          Positioned(
            bottom: 16, right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'missions',
                  backgroundColor: _showMissions
                      ? const Color(0xFF1E3A5F)
                      : const Color(0xFF1F2937),
                  onPressed: _showMissionPanel,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.flag_outlined,
                          color: _showMissions ? const Color(0xFF60A5FA) : const Color(0xFF6B7280),
                          size: 20),
                      if (_missionLayers.isNotEmpty)
                        Positioned(
                          top: 0, right: 0,
                          child: Container(
                            width: 12, height: 12,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3B82F6),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${_missionLayers.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 7,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  backgroundColor: const Color(0xFF0F172A),
                  onPressed: () {
                    if (myLoc != null) _mapCtrl.move(LatLng(myLoc.lat, myLoc.lng), 14);
                  },
                  child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'refresh',
                  backgroundColor: const Color(0xFF0F172A),
                  onPressed: _loadLiveLocations,
                  child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                ),
                if (_marks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'clear_marks',
                    backgroundColor: const Color(0xFF7F1D1D),
                    onPressed: _clearAllMarks,
                    child: const Icon(Icons.clear, color: Colors.white, size: 20),
                  ),
                ],
                // Legend toggle — only when missions are loaded
                if (_missionLayers.isNotEmpty && _showMissions) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'legend',
                    backgroundColor: _showLegend
                        ? const Color(0xFF1E3A5F)
                        : const Color(0xFF0F172A),
                    onPressed: () => setState(() => _showLegend = !_showLegend),
                    child: Icon(Icons.list_alt,
                        color: _showLegend ? const Color(0xFF60A5FA) : const Color(0xFF9CA3AF),
                        size: 20),
                  ),
                ],
                // Clear nav focus button
                if (_focusedObjKey != null) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'clear_focus',
                    backgroundColor: const Color(0xFF7C3AED),
                    onPressed: _clearNavFocus,
                    child: const Icon(Icons.layers, color: Colors.white, size: 20),
                  ),
                ],
              ],
            ),
          ),

          // Objectives legend panel
          if (_showLegend && _showMissions && _missionLayers.isNotEmpty)
            Positioned(
              bottom: 16, left: 60, right: 60,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: const Color(0xF00F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Row(children: [
                        const Icon(Icons.flag_outlined, color: Color(0xFF60A5FA), size: 14),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text('Objectives',
                              style: TextStyle(color: Colors.white, fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _showLegend = false),
                          child: const Icon(Icons.close, color: Color(0xFF6B7280), size: 16),
                        ),
                      ]),
                    ),
                    const Divider(color: Color(0xFF1F2937), height: 1),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: _missionLayers.expand<Widget>((mission) {
                          if (_missionVisible[mission['id'] as String] == false) return [];
                          final objs = _getSortedObjectives(mission);
                          final currentIdx = objs.indexWhere((o) => o['is_completed'] != true);
                          return objs.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final obj = entry.value;
                            final objId = obj['id'] as String? ?? '';
                            final missionId = mission['id'] as String;
                            // In nav/route focus mode, hide objectives that aren't the focused one
                            if (_focusedObjKey != null && _focusedObjKey != '$missionId:$objId') {
                              return const SizedBox.shrink();
                            }
                            final isCompleted = obj['is_completed'] == true;
                            final isCurrent = !isCompleted && idx == currentIdx;
                            final orderNum = (obj['order_index'] as num?)?.toInt() ?? idx;
                            final rawTitle = (obj['title'] as String? ?? '').replaceFirst(
                                RegExp(r'^\[(ZONE|ROUTE|FACILITY)\]\s*(\w[\w\s]*:\s*)?'), '').trim();
                            final label = rawTitle.isEmpty ? 'Objective ${orderNum + 1}' : rawTitle;
                            final Color dotColor = isCompleted
                                ? const Color(0xFF6B7280)
                                : isCurrent
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFF3B82F6);
                            final isFocused = _focusedObjKey == '$missionId:$objId';
                            return GestureDetector(
                              onTap: () => _showObjectiveSheet(obj, mission),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                color: isFocused
                                    ? const Color(0xFF1E3A5F).withValues(alpha: 0.6)
                                    : Colors.transparent,
                                child: Row(children: [
                                  Container(
                                    width: 20, height: 20,
                                    decoration: BoxDecoration(
                                      color: dotColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: isCompleted
                                          ? const Icon(Icons.check, color: Colors.white, size: 11)
                                          : Text('${orderNum + 1}',
                                              style: const TextStyle(
                                                  color: Colors.white, fontSize: 9,
                                                  fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: isCompleted
                                            ? const Color(0xFF6B7280)
                                            : Colors.white,
                                        fontSize: 11,
                                        decoration: isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('NOW',
                                          style: TextStyle(color: Color(0xFF22C55E),
                                              fontSize: 8, fontWeight: FontWeight.bold)),
                                    ),
                                ]),
                              ),
                            );
                          });
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Tile label
          Positioned(
            top: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_tileName, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Objective order number badge ─────────────────────────────────────────────

class _OrderBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDone;
  final bool small;
  const _OrderBadge({required this.label, required this.color, required this.isDone, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 16.0 : 26.0;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: isDone ? const Color(0xFF374151) : color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: small ? 1 : 1.5),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: small ? 8 : 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Mark picker bottom sheet ──────────────────────────────────────────────────

class _MarkPicker extends StatefulWidget {
  final LatLng point;
  final String coordText;
  final void Function(MapMark) onMark;
  const _MarkPicker({required this.point, required this.coordText, required this.onMark});

  @override
  State<_MarkPicker> createState() => _MarkPickerState();
}

class _MarkPickerState extends State<_MarkPicker> {
  String? _selected;
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();

  String? _evidenceUrl;      // URL returned after successful upload
  File? _evidencePreview;    // local file for thumbnail preview
  bool _uploading = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<String?> _uploadEvidence(String filePath) async {
    try {
      final res = await ApiService().uploadFile('/evidence', File(filePath), 'file');
      return res['url'] as String? ?? res['file_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickEvidence() async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1F2937),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final picked = await _picker.pickImage(source: choice, imageQuality: 75);
    if (picked == null || !mounted) return;

    setState(() {
      _uploading = true;
      _evidencePreview = File(picked.path);
      _evidenceUrl = null;
    });

    final url = await _uploadEvidence(picked.path);
    if (!mounted) return;
    if (url != null) {
      setState(() { _evidenceUrl = url; _uploading = false; });
    } else {
      setState(() { _uploading = false; _evidencePreview = null; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evidence upload failed')),
      );
    }
  }

  void _clearEvidence() {
    setState(() { _evidenceUrl = null; _evidencePreview = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.place, color: Color(0xFF22C55E), size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Mark Point  ${widget.coordText}',
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              mainAxisSpacing: 8, crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: _markTypes.map((t) {
                final type = t['type'] as String;
                final color = t['color'] as Color;
                final icon = t['icon'] as IconData;
                final label = t['label'] as String;
                final sel = _selected == type;
                return GestureDetector(
                  onTap: () => setState(() => _selected = type),
                  child: Container(
                    decoration: BoxDecoration(
                      color: sel ? color.withValues(alpha: 0.2) : const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? color : const Color(0xFF374151), width: sel ? 2 : 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: color, size: 22),
                        const SizedBox(height: 4),
                        Text(label, style: TextStyle(color: sel ? color : const Color(0xFF9CA3AF), fontSize: 9), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_selected != null) ...[
              // Note field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _noteCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Optional note…',
                    hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF374151))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF374151))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF16A34A))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              // Evidence attachment
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _evidencePreview != null
                    ? Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _evidencePreview!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_uploading)
                                  const Row(children: [
                                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22C55E))),
                                    SizedBox(width: 8),
                                    Text('Uploading…', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                                  ])
                                else if (_evidenceUrl != null)
                                  const Row(children: [
                                    Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 14),
                                    SizedBox(width: 6),
                                    Text('Evidence attached', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
                                  ])
                                else
                                  const Text('Upload failed', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: _clearEvidence,
                                  child: const Text('Remove', style: TextStyle(color: Color(0xFF6B7280), fontSize: 11, decoration: TextDecoration.underline)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(Icons.attach_file, size: 16),
                        label: const Text('Attach Evidence', style: TextStyle(fontSize: 13)),
                        onPressed: _uploading ? null : _pickEvidence,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF9CA3AF),
                          side: const BorderSide(color: Color(0xFF374151)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
              ),
              // Place mark button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _uploading
                        ? null
                        : () => widget.onMark(MapMark(
                              point: widget.point,
                              type: _selected!,
                              note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                              evidenceUrl: _evidenceUrl,
                            )),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _markColors[_selected] ?? const Color(0xFF16A34A),
                      disabledBackgroundColor: const Color(0xFF374151),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _uploading ? 'Uploading evidence…' : 'Place ${_selected!.capitalize()} Mark',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

extension _StringExt on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// ── Mission Layer Panel ───────────────────────────────────────────────────────

class _MissionLayerPanel extends StatefulWidget {
  final List<Map<String, dynamic>> missions;
  final Map<String, bool> visibilityMap;
  final bool showMissions;
  final String mapFilter;
  final bool loadingMissions;
  final Color Function(int) missionColor;
  final void Function(bool) onToggleAll;
  final void Function(String, bool) onToggleMission;
  final void Function(String) onMapFilter;
  final VoidCallback onRefresh;

  const _MissionLayerPanel({
    required this.missions,
    required this.visibilityMap,
    required this.showMissions,
    required this.mapFilter,
    required this.loadingMissions,
    required this.missionColor,
    required this.onToggleAll,
    required this.onToggleMission,
    required this.onMapFilter,
    required this.onRefresh,
  });

  @override
  State<_MissionLayerPanel> createState() => _MissionLayerPanelState();
}

class _MissionLayerPanelState extends State<_MissionLayerPanel> {
  late Map<String, bool> _local;

  @override
  void initState() {
    super.initState();
    _local = Map.from(widget.visibilityMap);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF374151),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(children: [
              const Icon(Icons.flag_outlined, color: Color(0xFF60A5FA), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Mission Layers',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              // Refresh
              if (widget.loadingMissions)
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)))
              else
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF6B7280), size: 20),
                  onPressed: widget.onRefresh,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 8),
              // Master toggle
              Switch(
                value: widget.showMissions,
                onChanged: widget.onToggleAll,
                activeThumbColor: const Color(0xFF3B82F6),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),
          ),
          // History filter row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              _FilterChip(
                label: 'Today',
                selected: widget.mapFilter == 'today',
                onTap: () => widget.onMapFilter('today'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Last Week',
                selected: widget.mapFilter == 'week',
                onTap: () => widget.onMapFilter('week'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Last Month',
                selected: widget.mapFilter == 'month',
                onTap: () => widget.onMapFilter('month'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'All Time',
                selected: widget.mapFilter == 'all',
                onTap: () => widget.onMapFilter('all'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${widget.missions.length} mission${widget.missions.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
              ),
            ),
          ),
          const Divider(color: Color(0xFF1F2937), height: 1),
          // Mission list
          Expanded(
            child: widget.missions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.assignment_outlined, color: Color(0xFF374151), size: 40),
                        const SizedBox(height: 8),
                        Text(
                          widget.mapFilter == 'all' ? 'No missions found' : 'No missions in this period',
                          style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        if (widget.mapFilter != 'all')
                          GestureDetector(
                            onTap: () => widget.onMapFilter('all'),
                            child: const Text('Show all missions',
                                style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12,
                                    decoration: TextDecoration.underline)),
                          ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: widget.missions.length,
                    separatorBuilder: (_, x) => const Divider(
                        color: Color(0xFF1F2937), height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) {
                      final m = widget.missions[i];
                      final id = m['id'] as String;
                      final color = widget.missionColor(i);
                      final zones = (m['_zones'] as List?)?.length ?? 0;
                      final routes = (m['_routes'] as List?)?.length ?? 0;
                      final facilities = (m['_facilities'] as List?)?.length ?? 0;
                      final status = m['status'] as String? ?? '';
                      final startStr = m['start_date'] as String?;
                      final visible = _local[id] ?? true;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          // Color dot
                          Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['name'] as String? ?? 'Untitled',
                                  style: TextStyle(
                                    color: visible ? Colors.white : const Color(0xFF4B5563),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(children: [
                                  _LayerBadge(icon: Icons.pentagon_outlined, count: zones, color: color),
                                  _LayerBadge(icon: Icons.route, count: routes, color: color),
                                  _LayerBadge(icon: Icons.domain, count: facilities, color: color),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _statusBg(status),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(status.toUpperCase(),
                                        style: TextStyle(color: _statusColor(status), fontSize: 9,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  if (startStr != null) ...[
                                    const SizedBox(width: 6),
                                    Text(_fmtDate(startStr),
                                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10)),
                                  ],
                                ]),
                              ],
                            ),
                          ),
                          Switch(
                            value: visible,
                            onChanged: (v) {
                              setState(() => _local[id] = v);
                              widget.onToggleMission(id, v);
                            },
                            activeThumbColor: color,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ]),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'active': return const Color(0xFF052E16);
      case 'planned': return const Color(0xFF1E3A5F);
      case 'suspended': return const Color(0xFF451A03);
      default: return const Color(0xFF1F2937);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active': return const Color(0xFF86EFAC);
      case 'planned': return const Color(0xFF93C5FD);
      case 'suspended': return const Color(0xFFFBBF24);
      default: return const Color(0xFF6B7280);
    }
  }

  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}';
    } catch (_) {
      return '';
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF3B82F6) : const Color(0xFF374151),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF93C5FD) : const Color(0xFF6B7280),
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LayerBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  const _LayerBadge({required this.icon, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 2),
        Text('$count', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Facility bottom sheet ─────────────────────────────────────────────────────

class _FacilitySheet extends StatefulWidget {
  final Map<String, dynamic> facility;
  final List<Map<String, dynamic>> routes;
  final void Function(String routeId) onRouteSelected;

  const _FacilitySheet({
    required this.facility,
    required this.routes,
    required this.onRouteSelected,
  });

  @override
  State<_FacilitySheet> createState() => _FacilitySheetState();
}

class _FacilitySheetState extends State<_FacilitySheet> {
  bool _showingRoutes = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.facility;
    final name = f['name'] as String? ?? 'Facility';
    final type = (f['facility_type'] as String? ?? 'other').replaceAll('_', ' ');
    final status = f['status'] as String? ?? 'active';
    final notes = f['notes'] as String? ?? f['description'] as String?;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.domain, color: Color(0xFF22C55E), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF166534), borderRadius: BorderRadius.circular(8)),
              child: Text(status, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(type.capitalize(), style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 13)),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(notes, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          ],
          const SizedBox(height: 16),
          if (!_showingRoutes)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.route, size: 18),
                label: const Text('Show Routes to Here'),
                onPressed: () => setState(() => _showingRoutes = true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            )
          else ...[
            const Text('Select a route:', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (widget.routes.isEmpty)
              const Text('No routes available', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13))
            else
              ...widget.routes.take(5).map((r) {
                final rName = r['name'] as String? ?? 'Route';
                final rId = r['id'] as String;
                return GestureDetector(
                  onTap: () => widget.onRouteSelected(rId),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1D4ED8)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.route, color: Color(0xFF60A5FA), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(rName, style: const TextStyle(color: Colors.white, fontSize: 13))),
                      const Icon(Icons.arrow_forward_ios, color: Color(0xFF374151), size: 14),
                    ]),
                  ),
                );
              }),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Mission map action sheet ───────────────────────────────────────────────────

class _MissionMapActionSheet extends StatefulWidget {
  const _MissionMapActionSheet({
    required this.point,
    required this.coordText,
    required this.missionId,
    required this.missionName,
    required this.onMarkInstead,
    required this.onSaved,
  });

  final LatLng point;
  final String coordText;
  final String missionId;
  final String missionName;
  final VoidCallback onMarkInstead;
  final VoidCallback onSaved;

  @override
  State<_MissionMapActionSheet> createState() => _MissionMapActionSheetState();
}

class _MissionMapActionSheetState extends State<_MissionMapActionSheet> {
  bool _saving = false;

  Future<void> _createLinked(String type) async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'mission_id': widget.missionId,
        'latitude': widget.point.latitude,
        'longitude': widget.point.longitude,
        'description': 'Marked during mission: ${widget.missionName}',
      };
      String endpoint;
      switch (type) {
        case 'incident':
          endpoint = '/incidents';
          body['title'] = 'Incident at ${widget.coordText}';
          break;
        case 'evidence':
          endpoint = '/evidence';
          body['name'] = 'Evidence at ${widget.coordText}';
          break;
        default:
          endpoint = '/pois';
          body['name'] = 'POI at ${widget.coordText}';
          body['type'] = 'custom';
      }
      await ApiService().post(endpoint, body);
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF374151),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.flag, color: Color(0xFF22C55E), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.missionName,
                style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            widget.coordText,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 20),
          const Text('Link to mission as:', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (_saving)
            const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
          else ...[
            _ActionTile(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFF59E0B),
              label: 'Incident',
              description: 'Log an incident at this location',
              onTap: () => _createLinked('incident'),
            ),
            _ActionTile(
              icon: Icons.camera_alt_outlined,
              color: const Color(0xFF60A5FA),
              label: 'Evidence',
              description: 'Record evidence at this location',
              onTap: () => _createLinked('evidence'),
            ),
            _ActionTile(
              icon: Icons.place_outlined,
              color: const Color(0xFFEC4899),
              label: 'Point of Interest',
              description: 'Mark a notable location',
              onTap: () => _createLinked('poi'),
            ),
            const Divider(color: Color(0xFF1F2937), height: 24),
            _ActionTile(
              icon: Icons.push_pin_outlined,
              color: const Color(0xFF6B7280),
              label: 'Just a mark',
              description: 'Drop a pin without linking to mission',
              onTap: widget.onMarkInstead,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF374151)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFF374151), size: 18),
          ],
        ),
      ),
    );
  }
}
