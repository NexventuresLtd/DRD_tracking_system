import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/user_model.dart';

class ViewerHome extends StatefulWidget {
  const ViewerHome({super.key});

  @override
  State<ViewerHome> createState() => _ViewerHomeState();
}

class _ViewerHomeState extends State<ViewerHome> {
  int _currentIndex = 0;
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  bool _mapReady = false;
  bool _centeredOnUser = false;
  final MapController _mapController = MapController();
  LocationProvider? _locProvider;

  @override
  void initState() {
    super.initState();
    _loadViewerData();
    Future.delayed(const Duration(seconds: 15), _autoRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locProvider = context.read<LocationProvider>();
      _locProvider!.addListener(_autoCenter);
    });
  }

  void _autoCenter() {
    if (!mounted || _centeredOnUser) return;
    final loc = _locProvider;
    if (loc != null && loc.hasRealFix && _mapReady) {
      _centeredOnUser = true;
      _mapController.move(LatLng(loc.latitude, loc.longitude), 13.0);
    }
  }

  Future<void> _loadViewerData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _apiService.get('/locations'),
        _apiService.get('/teams'),
        _apiService.get('/routes?is_active=true'),
        _apiService.get('/events?size=20'),
      ]);

      if (mounted) {
        setState(() {
          _locations =
              (results[0] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
          _teams =
              (results[1] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
          _routes =
              (results[2] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
          _events =
              (results[3]?['items'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _autoRefresh() {
    if (mounted) {
      _loadViewerData();
      Future.delayed(const Duration(seconds: 15), _autoRefresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    final pages = [
      _buildOverview(user),
      _buildMapView(),
      _buildTeamStatus(),
      _buildActivityFeed(),
    ];

    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('MISSION OVERVIEW'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadViewerData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final nav = Navigator.of(context);
              await context.read<LocationProvider>().stopTracking();
              await authProvider.logout();
              if (mounted) nav.pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Teams'),
          BottomNavigationBarItem(
            icon: Icon(Icons.timeline),
            label: 'Activity',
          ),
        ],
      ),
    );
  }

  Widget _buildOverview(UserModel? user) {
    final activeCount = _locations.where((l) => l['status'] == 'active').length;
    final teamsCount = _teams.length;
    final routesCount = _routes.length;

    return RefreshIndicator(
      onRefresh: _loadViewerData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.visibility,
                  color: DRDTheme.primaryColor,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VIEWER MODE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'Monitoring operations...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stats Overview
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Active Units',
                    '$activeCount',
                    DRDTheme.successColor,
                    Icons.person,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Teams',
                    '$teamsCount',
                    DRDTheme.primaryColor,
                    Icons.group_work,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Active Routes',
                    '$routesCount',
                    DRDTheme.warningColor,
                    Icons.route,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Events Today',
                    '${_events.length}',
                    DRDTheme.infoColor,
                    Icons.notifications,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Live Map Preview
            const Text(
              'LIVE POSITIONS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: (() {
                      final loc = context.read<LocationProvider>();
                      return loc.hasRealFix
                          ? LatLng(loc.latitude, loc.longitude)
                          : LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
                    })(),
                    initialZoom: 12,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.drd.fieldops',
                    ),
                    MarkerLayer(
                      markers: _locations.map((loc) {
                        final color =
                            DRDTheme.statusColors[loc['status']] ?? Colors.grey;
                        return Marker(
                          point: LatLng(
                            loc['latitude'] ?? AppConstants.defaultLat,
                            loc['longitude'] ?? AppConstants.defaultLng,
                          ),
                          width: 28,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.3),
                              border: Border.all(color: color, width: 2),
                            ),
                            child: Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    // Route lines
                    PolylineLayer(
                      polylines: _routes
                          .where((r) => (r['waypoints'] as List?)!.length >= 2)
                          .map((route) {
                            final color = Color(
                              int.parse(
                                route['color']?.replaceFirst('#', '0xFF') ??
                                    '0xFF3B82F6',
                              ),
                            );
                            return Polyline(
                              points: (route['waypoints'] as List)
                                  .map(
                                    (wp) =>
                                        LatLng(wp['latitude'], wp['longitude']),
                                  )
                                  .toList(),
                              color: color.withValues(alpha: 0.5),
                              strokeWidth: 2,
                              isDotted: true,
                            );
                          })
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Team Quick View
            const Text(
              'TEAM STATUS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            ..._teams.take(3).map((team) => _buildTeamCard(team)),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: (() {
              final loc = context.read<LocationProvider>();
              return loc.hasRealFix
                  ? LatLng(loc.latitude, loc.longitude)
                  : LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
            })(),
            initialZoom: 13,
            onMapReady: () { setState(() => _mapReady = true); _autoCenter(); },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.drd.fieldops',
            ),
            // Unit markers
            MarkerLayer(
              markers: _locations.map((loc) {
                final color =
                    DRDTheme.statusColors[loc['status']] ?? Colors.grey;
                final teamColor =
                    DRDTheme.teamColors[loc['team_name']] ??
                    DRDTheme.primaryColor;

                return Marker(
                  point: LatLng(
                    loc['latitude'] ?? AppConstants.defaultLat,
                    loc['longitude'] ?? AppConstants.defaultLng,
                  ),
                  width: 36,
                  height: 36,
                  child: GestureDetector(
                    onTap: () => _showUnitInfo(loc),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: DRDTheme.surfaceColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            loc['user_name'] ?? '?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: teamColor.withValues(alpha: 0.3),
                            border: Border.all(color: color, width: 2.5),
                          ),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            // Route lines
            PolylineLayer(
              polylines: _routes
                  .where((r) => (r['waypoints'] as List?)!.length >= 2)
                  .map((route) {
                    final color = Color(
                      int.parse(
                        route['color']?.replaceFirst('#', '0xFF') ??
                            '0xFF3B82F6',
                      ),
                    );
                    return Polyline(
                      points: (route['waypoints'] as List)
                          .map((wp) => LatLng(wp['latitude'], wp['longitude']))
                          .toList(),
                      color: color,
                      strokeWidth: 2.5,
                    );
                  })
                  .toList(),
            ),
          ],
        ),
        // Legend
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DRDTheme.surfaceColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLegendItem('Active', DRDTheme.successColor),
                _buildLegendItem('Stale', DRDTheme.warningColor),
                _buildLegendItem('Offline', DRDTheme.dangerColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamStatus() {
    if (_teams.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No teams available', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _teams.length,
      itemBuilder: (context, index) {
        final team = _teams[index];
        final teamColor =
            DRDTheme.teamColors[team['name']] ?? DRDTheme.primaryColor;
        final teamUnits = _locations
            .where((l) => l['team_name'] == team['name'])
            .toList();
        final activeUnits = teamUnits
            .where((u) => u['status'] == 'active')
            .length;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: teamColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: teamColor, width: 2),
              ),
              child: Center(
                child: Text(
                  team['code']?.toString().substring(0, 2).toUpperCase() ?? '?',
                  style: TextStyle(
                    color: teamColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            title: Text(
              team['name'] ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '$activeUnits/${teamUnits.length} active | ${team['member_count'] ?? 0} members',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
            children: [
              if (teamUnits.isNotEmpty)
                ...teamUnits.map(
                  (unit) => ListTile(
                    dense: true,
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            DRDTheme.statusColors[unit['status']] ??
                            Colors.grey,
                      ),
                    ),
                    title: Text(
                      unit['user_name'] ?? 'Unknown',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    subtitle: Text(
                      '${unit['speed']?.toStringAsFixed(1) ?? "0"} km/h • ${unit['battery_level'] ?? "?"}%',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              if (teamUnits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No units deployed',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivityFeed() {
    if (_events.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No recent activity', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        final eventColor = _getEventColor(event['event_type']);

        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: eventColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getEventIcon(event['event_type']),
                color: eventColor,
                size: 18,
              ),
            ),
            title: Text(
              event['description'] ?? 'Event',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            subtitle: Row(
              children: [
                if (event['team_name'] != null)
                  Text(
                    event['team_name'],
                    style: TextStyle(
                      color:
                          DRDTheme.teamColors[event['team_name']] ??
                          Colors.grey,
                      fontSize: 10,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(DateTime.parse(event['created_at'])),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: eventColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                event['event_type'] ?? 'INFO',
                style: TextStyle(
                  color: eventColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Icon(icon, color: color.withValues(alpha: 0.5), size: 20),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamCard(Map<String, dynamic> team) {
    final teamColor =
        DRDTheme.teamColors[team['name']] ?? DRDTheme.primaryColor;
    final teamUnits = _locations
        .where((l) => l['team_name'] == team['name'])
        .toList();
    final activeUnits = teamUnits.where((u) => u['status'] == 'active').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: teamColor),
        ),
        title: Text(
          team['name'] ?? 'Unknown',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        trailing: Text(
          '$activeUnits/${teamUnits.length} active',
          style: TextStyle(
            color: activeUnits > 0 ? DRDTheme.successColor : Colors.grey,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  IconData _getEventIcon(String? type) {
    switch (type) {
      case 'UPDATE':
        return Icons.update;
      case 'OFFLINE':
        return Icons.wifi_off;
      case 'ONLINE':
        return Icons.wifi;
      case 'FLAG':
        return Icons.flag;
      case 'ROUTE':
        return Icons.route;
      case 'MESSAGE':
        return Icons.message;
      case 'ALERT':
        return Icons.warning;
      case 'POI':
        return Icons.location_on;
      case 'ZONE':
        return Icons.hexagon;
      default:
        return Icons.info_outline;
    }
  }

  Color _getEventColor(String? type) {
    switch (type) {
      case 'UPDATE':
        return DRDTheme.successColor;
      case 'OFFLINE':
        return DRDTheme.dangerColor;
      case 'ONLINE':
        return DRDTheme.successColor;
      case 'FLAG':
        return DRDTheme.accentColor;
      case 'ROUTE':
        return DRDTheme.infoColor;
      case 'ALERT':
        return DRDTheme.dangerColor;
      case 'POI':
        return DRDTheme.warningColor;
      case 'ZONE':
        return DRDTheme.accentColor;
      default:
        return DRDTheme.primaryColor;
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showUnitInfo(Map<String, dynamic> unit) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit['user_name'] ?? 'Unknown Unit',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildInfoRow('Team', unit['team_name'] ?? 'N/A'),
              _buildInfoRow('Status', unit['status'] ?? 'N/A'),
              _buildInfoRow(
                'Speed',
                '${unit['speed']?.toStringAsFixed(1) ?? "0"} km/h',
              ),
              _buildInfoRow(
                'Position',
                '${unit['latitude']?.toStringAsFixed(4)}, ${unit['longitude']?.toStringAsFixed(4)}',
              ),
              _buildInfoRow('Battery', '${unit['battery_level'] ?? "N/A"}%'),
              _buildInfoRow(
                'Last Update',
                _formatTime(
                  DateTime.parse(
                    unit['recorded_at'] ?? DateTime.now().toIso8601String(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locProvider?.removeListener(_autoCenter);
    super.dispose();
  }
}
