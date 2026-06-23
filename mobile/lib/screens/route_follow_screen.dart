import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../services/api_service.dart';
import '../services/coordinate_service.dart';

class RouteWp {
  final double lat;
  final double lng;
  final String? name;
  const RouteWp({required this.lat, required this.lng, this.name});
  factory RouteWp.fromJson(Map<String, dynamic> j) => RouteWp(
        lat: (j['latitude'] as num).toDouble(),
        lng: (j['longitude'] as num).toDouble(),
        name: j['name'] as String?,
      );
}

class RouteFollowScreen extends StatefulWidget {
  final String routeId;
  final String routeName;
  const RouteFollowScreen({super.key, required this.routeId, required this.routeName});
  @override
  State<RouteFollowScreen> createState() => _RouteFollowScreenState();
}

class _RouteFollowScreenState extends State<RouteFollowScreen> {
  final MapController _mapCtrl = MapController();
  List<RouteWp> _waypoints = [];
  int _current = 0;
  bool _loading = true;
  bool _finished = false;
  Timer? _posTimer;
  static const _arrivalRadius = 30.0;

  @override
  void initState() {
    super.initState();
    _loadRoute();
    _posTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkArrival());
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    try {
      final data = await ApiService().get('/routes/${widget.routeId}') as Map<String, dynamic>;
      final wps = (data['waypoints'] as List<dynamic>? ?? [])
          .map((w) => RouteWp.fromJson(w as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() { _waypoints = wps; _loading = false; });
      if (wps.isNotEmpty) {
        _mapCtrl.move(LatLng(wps[0].lat, wps[0].lng), 15);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _checkArrival() {
    if (_finished || _waypoints.isEmpty) return;
    final loc = context.read<LocationProvider>().current;
    if (loc == null) return;
    final wp = _waypoints[_current];
    final dist = CoordinateService.distanceMeters(loc.lat, loc.lng, wp.lat, wp.lng);
    if (dist <= _arrivalRadius) {
      if (_current < _waypoints.length - 1) {
        setState(() => _current++);
        _mapCtrl.move(LatLng(_waypoints[_current].lat, _waypoints[_current].lng), 15);
      } else {
        setState(() => _finished = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationProvider>().current;
    final hasWps = _waypoints.isNotEmpty;
    final target = hasWps && !_finished ? _waypoints[_current] : null;

    double? distance;
    double? bearing;
    if (loc != null && target != null) {
      distance = CoordinateService.distanceMeters(loc.lat, loc.lng, target.lat, target.lng);
      bearing = CoordinateService.bearingDegrees(loc.lat, loc.lng, target.lat, target.lng);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.routeName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            if (!_loading && hasWps)
              Text(
                _finished ? 'Route complete' : 'WP ${_current + 1}/${_waypoints.length}',
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11),
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : Column(
              children: [
                if (!_finished && target != null) _buildHUD(target, distance, bearing),
                if (_finished)
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF166534).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF22C55E)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 24),
                        SizedBox(width: 10),
                        Text('Route complete!', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                  ),
                Expanded(
                  child: FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: loc != null ? LatLng(loc.lat, loc.lng) : const LatLng(-1.9441, 30.0619),
                      initialZoom: 15,
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', subdomains: const ['a', 'b', 'c']),
                      if (_waypoints.length >= 2)
                        PolylineLayer(polylines: [
                          Polyline(
                            points: _waypoints.map((w) => LatLng(w.lat, w.lng)).toList(),
                            color: const Color(0xFF2563EB),
                            strokeWidth: 3,
                          ),
                          if (_current > 0)
                            Polyline(
                              points: _waypoints.take(_current + 1).map((w) => LatLng(w.lat, w.lng)).toList(),
                              color: const Color(0xFF22C55E),
                              strokeWidth: 3,
                            ),
                        ]),
                      MarkerLayer(
                        markers: [
                          ..._waypoints.asMap().entries.map((e) {
                            final passed = e.key < _current;
                            final isCurrent = e.key == _current;
                            return Marker(
                              point: LatLng(e.value.lat, e.value.lng),
                              width: isCurrent ? 20 : 14,
                              height: isCurrent ? 20 : 14,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: passed ? const Color(0xFF22C55E) : isCurrent ? const Color(0xFF2563EB) : const Color(0xFF374151),
                                  border: Border.all(color: Colors.white, width: isCurrent ? 2 : 1),
                                ),
                              ),
                            );
                          }),
                          if (loc != null)
                            Marker(
                              point: LatLng(loc.lat, loc.lng),
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFF59E0B),
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), blurRadius: 8)],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _waypoints.asMap().entries.map((e) {
                        final passed = e.key < _current;
                        final isCurrent = e.key == _current;
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isCurrent ? const Color(0xFF1D4ED8) : passed ? const Color(0xFF166534).withValues(alpha: 0.3) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent ? const Color(0xFF3B82F6) : passed ? const Color(0xFF22C55E) : const Color(0xFF1F2937),
                            ),
                          ),
                          child: Text(
                            e.value.name ?? 'WP${e.key + 1}',
                            style: TextStyle(
                              color: isCurrent ? Colors.white : passed ? const Color(0xFF22C55E) : const Color(0xFF6B7280),
                              fontSize: 11,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHUD(RouteWp target, double? distance, double? bearing) {
    final distStr = distance == null
        ? '—'
        : distance < 1000
            ? '${distance.round()}m'
            : '${(distance / 1000).toStringAsFixed(1)}km';

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1D4ED8)),
      ),
      child: Row(
        children: [
          if (bearing != null)
            Transform.rotate(
              angle: bearing * math.pi / 180,
              child: const Icon(Icons.navigation, color: Color(0xFF60A5FA), size: 40),
            )
          else
            const Icon(Icons.navigation, color: Color(0xFF374151), size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name ?? 'Waypoint ${_current + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '${target.lat.toStringAsFixed(5)}, ${target.lng.toStringAsFixed(5)}',
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distStr, style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.w900, fontSize: 22)),
              if (bearing != null)
                Text('${bearing.round()}°', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
