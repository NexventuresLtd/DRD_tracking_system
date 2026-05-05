import 'dart:async';
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

class FieldTeamTracking extends StatefulWidget {
  const FieldTeamTracking({super.key});

  @override
  State<FieldTeamTracking> createState() => _FieldTeamTrackingState();
}

class _FieldTeamTrackingState extends State<FieldTeamTracking> {
  final MapController _mapCtrl = MapController();
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  List<Map<String, dynamic>> _teamMembers = [];
  List<Map<String, dynamic>> _teamRoutes = [];
  WebSocketChannel? _locWs;
  Timer? _refreshTimer;
  bool _loading = true;
  Map<String, dynamic>? _selected;
  LatLng? _initialCenter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTeamData();
      _connectWS();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadTeamData());
  }

  Future<void> _loadTeamData() async {
    if (!mounted) return;
    try {
      final user = context.read<AuthProvider>().user;
      if (user?.teamName == null) return;

      final teamId = user!.teamId;
      if (teamId == null) return;

      final results = await Future.wait([
        _api.get('/locations?team_id=$teamId'),
        _api.get('/routes?team_id=$teamId&is_active=true'),
      ]);

      if (!mounted) return;

      final List<Map<String, dynamic>> teamLocations = (results[0] is List)
          ? List<Map<String, dynamic>>.from(results[0] as List)
          : [];

      final List<Map<String, dynamic>> teamRoutes = (results[1] is List)
          ? List<Map<String, dynamic>>.from(results[1] as List)
          : [];

      LatLng? initialCenter;
      if (teamLocations.isNotEmpty) {
        final firstLoc = teamLocations.firstWhere(
          (l) => l['latitude'] != null && l['longitude'] != null,
          orElse: () => <String, dynamic>{},
        );
        if (firstLoc.isNotEmpty) {
          initialCenter = LatLng(firstLoc['latitude'] as double, firstLoc['longitude'] as double);
        }
      }
      initialCenter ??= LatLng(AppConstants.defaultLat, AppConstants.defaultLng);

      setState(() {
        _teamMembers = teamLocations;
        _teamRoutes = teamRoutes;
        _initialCenter = initialCenter;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading team data: $e');
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

            final user = context.read<AuthProvider>().user;
            final senderTeam = d['team'] as String?;
            if (senderTeam != user?.teamName) return;

            setState(() {
              final idx = _teamMembers.indexWhere((l) => l['user_id'] == uid);
              if (idx >= 0) {
                _teamMembers[idx] = {..._teamMembers[idx], ...d};
                if (_selected?['user_id'] == uid) _selected = _teamMembers[idx];
              } else {
                _teamMembers.add(Map<String, dynamic>.from(d));
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
    } catch (e) {
      debugPrint('WS connection error: $e');
      Future.delayed(const Duration(seconds: 3), _connectWS);
    }
  }

  void _flyToMember(Map<String, dynamic> member) {
    final lat = member['latitude'] as double?;
    final lng = member['longitude'] as double?;
    if (lat != null && lng != null) {
      _mapCtrl.move(LatLng(lat, lng), 15);
    }
    setState(() => _selected = member);
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return 'Unknown';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'Now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Unknown';
    }
  }

  Color _getStatusColor(String? status, String? lastUpdate) {
    if (status == 'active') return DRDTheme.successColor;
    if (status == 'stale') return DRDTheme.warningColor;
    return DRDTheme.dangerColor;
  }

  Color _hexColor(dynamic hex) {
    if (hex == null) return DRDTheme.primaryColor;
    String hexStr = hex.toString().replaceAll('#', '');
    if (hexStr.length == 6) hexStr = 'FF$hexStr';
    return Color(int.parse('0x$hexStr'));
  }

  List<Polyline> _buildRouteLines() {
    final lines = <Polyline>[];
    for (final route in _teamRoutes) {
      final waypoints = route['waypoints'] as List? ?? [];
      if (waypoints.length < 2) continue;

      final routeColor = _hexColor(route['color']);
      lines.add(Polyline(
        points: waypoints
            .map((wp) => LatLng(
                (wp['latitude'] as num).toDouble(),
                (wp['longitude'] as num).toDouble()))
            .toList(),
        color: routeColor,
        strokeWidth: 2.5,
      ));
    }
    return lines;
  }

  List<Marker> _buildRouteWaypoints() {
    final markers = <Marker>[];
    for (final route in _teamRoutes) {
      final waypoints = route['waypoints'] as List? ?? [];
      final routeColor = _hexColor(route['color']);

      for (int i = 0; i < waypoints.length; i++) {
        final wp = waypoints[i];
        final lat = (wp['latitude'] as num?)?.toDouble();
        final lng = (wp['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final isStart = i == 0;
        markers.add(Marker(
          point: LatLng(lat, lng),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isStart ? routeColor : Colors.white,
              border: Border.all(color: routeColor, width: 2),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: isStart ? Colors.white : routeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ));
      }
    }
    return markers;
  }

  @override
  void dispose() {
    _locWs?.sink.close();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _teamMembers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No team members online', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _initialCenter ?? LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
                    initialZoom: 13,
                    onMapReady: () {},
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    PolylineLayer(polylines: _buildRouteLines()),
                    MarkerLayer(markers: _buildRouteWaypoints()),
                    MarkerLayer(
                      markers: _teamMembers.map((member) {
                        final lat = member['latitude'] as double?;
                        final lng = member['longitude'] as double?;
                        if (lat == null || lng == null) return null;

                        final isSelected = _selected?['user_id'] == member['user_id'];
                        final status = member['status'] as String? ?? 'offline';
                        final statusColor = _getStatusColor(status, member['last_update']);

                        return Marker(
                          point: LatLng(lat, lng),
                          child: GestureDetector(
                            onTap: () => _flyToMember(member),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                border: Border.all(
                                  color: isSelected ? Colors.yellow : Colors.transparent,
                                  width: isSelected ? 3 : 0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              width: isSelected ? 48 : 40,
                              height: isSelected ? 48 : 40,
                              child: Center(
                                child: Text(
                                  (member['name'] as String? ?? '?').substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).whereType<Marker>().toList(),
                    ),
                  ],
                ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _selected == null
                ? const SizedBox.shrink()
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getStatusColor(
                                    _selected!['status'] as String?,
                                    _selected!['last_update'] as String?,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    (_selected!['name'] as String? ?? '?').substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selected!['name'] as String? ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Last update: ${_formatTime(_selected!['last_update'] as String?)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white24, height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInfoChip(
                                'Speed',
                                '${((_selected!['speed'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} km/h',
                              ),
                              _buildInfoChip(
                                'Heading',
                                '${(_selected!['heading'] as num?)?.toInt() ?? 0}°',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TEAM: ${context.read<AuthProvider>().user?.teamName ?? "UNKNOWN"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  if (_teamRoutes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: _teamRoutes.map((route) {
                            final color = _hexColor(route['color']);
                            final waypoints = (route['waypoints'] as List? ?? []).length;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: color, width: 1.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: color,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            route['name'] ?? 'Route',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '$waypoints waypoints',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
