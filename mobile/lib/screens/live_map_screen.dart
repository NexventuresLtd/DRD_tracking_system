import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/coordinate_service.dart';

class LiveUser {
  final String userId;
  double lat;
  double lng;
  String status;
  String? fullName;

  LiveUser({required this.userId, required this.lat, required this.lng, required this.status, this.fullName});
}

const _statusColors = {
  'active': Color(0xFF22C55E),
  'stale':  Color(0xFFF59E0B),
  'offline': Color(0xFF6B7280),
};

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});
  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapCtrl = MapController();
  final Map<String, LiveUser> _users = {};
  final _ws = WebSocketService();
  bool _loading = true;
  String _coordMode = 'GPS';

  @override
  void initState() {
    super.initState();
    _loadLiveLocations();
    _connectWS();
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
            fullName: (m['user'] as Map?)? ['full_name'] as String?,
          );
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
    _ws.off('location_update', _onLocation);
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

  @override
  Widget build(BuildContext context) {
    final myId = context.select<AuthProvider, String?>((a) => a.user?.id);
    final myLoc = context.watch<LocationProvider>().current;

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
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
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
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),
          Positioned(
            bottom: 16,
            left: 16,
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
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              children: [
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _StringExt on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
