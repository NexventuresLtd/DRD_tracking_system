import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../providers/location_provider.dart';

class FieldOperations extends StatefulWidget {
  const FieldOperations({super.key});

  @override
  State<FieldOperations> createState() => _FieldOperationsState();
}

class _FieldOperationsState extends State<FieldOperations> {
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _missions = [];
  List<Map<String, dynamic>> _zones = [];
  bool _isLoading = true;
  bool _mapReady = false;
  bool _centeredOnUser = false;
  final String _filterStatus = 'all';
  LocationProvider? _locProvider;

  @override
  void initState() {
    super.initState();
    _loadOperations();
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

  @override
  void dispose() {
    _locProvider?.removeListener(_autoCenter);
    super.dispose();
  }

  Future<void> _loadOperations() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _apiService.get('/routes?is_active=true'),
        _apiService.get('/zones'),
      ]);

      if (mounted) {
        setState(() {
          _missions =
              (results[0] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
          _zones =
              (results[1] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('FIELD OPERATIONS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOperations,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateOperationDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'MISSIONS'),
                      Tab(text: 'ZONES'),
                      Tab(text: 'MAP'),
                    ],
                    labelColor: DRDTheme.primaryColor,
                    unselectedLabelColor: Colors.grey,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildMissionsList(),
                        _buildZonesList(),
                        _buildOperationsMap(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateOperationDialog,
        backgroundColor: DRDTheme.warningColor,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMissionsList() {
    final filteredMissions = _filterStatus == 'all'
        ? _missions
        : _missions.where((m) => m['status'] == _filterStatus).toList();

    if (filteredMissions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No active missions',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredMissions.length,
      itemBuilder: (context, index) {
        final mission = filteredMissions[index];
        final color = Color(
          int.parse(
            mission['color']?.replaceFirst('#', '0xFF') ?? '0xFF3B82F6',
          ),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(Icons.route, color: color),
            ),
            title: Text(
              mission['name'] ?? 'Mission',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${mission['waypoints']?.length ?? 0} waypoints',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                if (mission['assigned_team_name'] != null)
                  Text(
                    mission['assigned_team_name'],
                    style: TextStyle(color: color, fontSize: 11),
                  ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: (() {
                            final wp = mission['waypoints']?.first;
                            if (wp != null) {
                              return LatLng(wp['latitude'], wp['longitude']);
                            }
                            final loc = context.read<LocationProvider>();
                            return loc.hasRealFix
                                ? LatLng(loc.latitude, loc.longitude)
                                : LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
                          })(),
                          initialZoom: 13,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'com.drd.fieldops',
                          ),
                          if ((mission['waypoints'] as List?)!.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: (mission['waypoints'] as List)
                                      .map(
                                        (wp) => LatLng(
                                          wp['latitude'],
                                          wp['longitude'],
                                        ),
                                      )
                                      .toList(),
                                  color: color,
                                  strokeWidth: 3,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _editMission(mission),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DRDTheme.warningColor,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _completeMission(mission['id']),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Complete'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DRDTheme.successColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildZonesList() {
    if (_zones.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hexagon, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No zones defined',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _zones.length,
      itemBuilder: (context, index) {
        final zone = _zones[index];
        final color = Color(
          int.parse(zone['color']?.replaceFirst('#', '0xFF') ?? '0xFFEC4899'),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: color,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: const Icon(Icons.hexagon, color: DRDTheme.accentColor),
            ),
            title: Text(
              zone['name'] ?? 'Zone',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Type: ${zone['zone_type'] ?? "N/A"}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: zone['is_active'] == true
                    ? DRDTheme.successColor.withValues(alpha: 0.1)
                    : DRDTheme.dangerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                zone['is_active'] == true ? 'ACTIVE' : 'INACTIVE',
                style: TextStyle(
                  color: zone['is_active'] == true
                      ? DRDTheme.successColor
                      : DRDTheme.dangerColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOperationsMap() {
    return FlutterMap(
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
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.drd.fieldops',
        ),
        // Mission routes
        PolylineLayer(
          polylines: _missions
              .where((m) => (m['waypoints'] as List?)!.length >= 2)
              .map((mission) {
                final color = Color(
                  int.parse(
                    mission['color']?.replaceFirst('#', '0xFF') ?? '0xFF3B82F6',
                  ),
                );
                return Polyline(
                  points: (mission['waypoints'] as List)
                      .map((wp) => LatLng(wp['latitude'], wp['longitude']))
                      .toList(),
                  color: color,
                  strokeWidth: 3,
                );
              })
              .toList(),
        ),
        // Zone polygons
        PolygonLayer(
          polygons: _zones.map((zone) {
            final color = Color(
              int.parse(
                zone['color']?.replaceFirst('#', '0xFF') ?? '0xFFEC4899',
              ),
            );
            return Polygon(
              points:
                  (zone['coordinates'] as List?)
                      ?.map(
                        (coord) =>
                            LatLng(coord['latitude'], coord['longitude']),
                      )
                      .toList() ??
                  [],
              color: color.withValues(alpha: 0.1),
              borderColor: color,
              borderStrokeWidth: 2,
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showCreateOperationDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            final nameController = TextEditingController();
            final descriptionController = TextEditingController();

            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CREATE OPERATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Operation Name',
                      labelStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: DRDTheme.backgroundColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Description',
                      labelStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: DRDTheme.backgroundColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (nameController.text.isNotEmpty) {
                          final nav = Navigator.of(context);
                          await _apiService.post('/routes', {
                            'name': nameController.text,
                            'description': descriptionController.text,
                            'waypoints': [],
                            'visible_to_all': true,
                          });
                          nav.pop();
                          _loadOperations();
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('CREATE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DRDTheme.warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editMission(Map<String, dynamic> mission) async {
    // Navigate to edit screen or show edit dialog
    _showSuccess('Editing mission: ${mission['name']}');
  }

  Future<void> _completeMission(String missionId) async {
    try {
      await _apiService.put('/routes/$missionId', {'is_active': false});
      _showSuccess('Mission completed!');
      _loadOperations();
    } catch (e) {
      _showError('Failed to complete mission');
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: DRDTheme.successColor),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: DRDTheme.dangerColor),
    );
  }
}
