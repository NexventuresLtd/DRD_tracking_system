import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';

class FieldMapScreen extends StatefulWidget {
  const FieldMapScreen({super.key});

  @override
  State<FieldMapScreen> createState() => _FieldMapScreenState();
}

class _FieldMapScreenState extends State<FieldMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _teamLocations = [];
  List<Map<String, dynamic>> _activeRoutes = [];
  List<Map<String, dynamic>> _pois = [];
  Map<String, dynamic>? _selectedRoute;
  bool _mapReady = false;
  Timer? _refreshTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // POI type config: type key → (emoji, display label)
  static const Map<String, _PoiMeta> _poiMeta = {
    'checkpoint':  _PoiMeta('🔵', 'Checkpoint'),
    'hazard':      _PoiMeta('⚠️',  'Hazard'),
    'medical':     _PoiMeta('🏥', 'Medical'),
    'shelter':     _PoiMeta('⛺', 'Shelter'),
    'observation': _PoiMeta('👁️',  'Observation'),
  };

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    // Delay first load until after first frame so providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMapData();
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMapData(),
    );
  }

  Future<void> _loadMapData() async {
    if (!mounted) return;
    final teamId = context.read<AuthProvider>().user?.teamId;

    try {
      final results = await Future.wait([
        _apiService.get(
          teamId != null ? '/locations?team_id=$teamId' : '/locations',
        ),
        _apiService.get('/routes'),
        _apiService.get('/pois'),
      ]);

      if (mounted) {
        setState(() {
          _teamLocations =
              (results[0] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
          _activeRoutes =
              (results[1] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
          _pois =
              (results[2] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ── POI creation bottom sheet ────────────────────────────────────────────

  void _showCreatePoiSheet(LatLng latLng) {
    String selectedType = 'checkpoint';
    final nameController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DRDTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'New Point of Interest',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 16),

                  // Type chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _poiMeta.entries.map((entry) {
                      final isSelected = selectedType == entry.key;
                      return ChoiceChip(
                        label: Text(
                          '${entry.value.emoji} ${entry.value.label}',
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: DRDTheme.primaryColor,
                        backgroundColor: DRDTheme.surfaceColor,
                        side: BorderSide(
                          color: isSelected
                              ? DRDTheme.primaryColor
                              : Colors.white24,
                        ),
                        onSelected: (_) =>
                            setSheetState(() => selectedType = entry.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Name field
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'POI name',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mark button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) return;
                              final nav = Navigator.of(sheetCtx);
                              final messenger = ScaffoldMessenger.of(context);

                              setSheetState(() => isSubmitting = true);
                              try {
                                final result = await _apiService.post(
                                  '/pois',
                                  {
                                    'name': name,
                                    'poi_type': selectedType,
                                    'latitude': latLng.latitude,
                                    'longitude': latLng.longitude,
                                    'visible_to_all': true,
                                  },
                                );

                                if (!mounted) return;

                                final newPoi =
                                    result is Map<String, dynamic>
                                        ? result
                                        : {
                                            'name': name,
                                            'poi_type': selectedType,
                                            'latitude': latLng.latitude,
                                            'longitude': latLng.longitude,
                                            'visible_to_all': true,
                                          };

                                setState(() => _pois = [..._pois, newPoi]);
                                if (!mounted) return;
                                nav.pop();
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ POI marked — visible on web dashboard'),
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              } catch (_) {
                                setSheetState(() => isSubmitting = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to create POI'),
                                      backgroundColor: Colors.red,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DRDTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Mark',
                              style: TextStyle(fontWeight: FontWeight.bold),
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

  // ── POI marker layer ─────────────────────────────────────────────────────

  List<Marker> _buildPoiMarkers() {
    final markers = <Marker>[];
    for (final poi in _pois) {
      final lat = (poi['latitude'] as num?)?.toDouble();
      final lng = (poi['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final type = poi['poi_type'] as String? ?? 'checkpoint';
      final meta = _poiMeta[type] ?? _poiMeta['checkpoint']!;
      final name = poi['name'] as String? ?? type;

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 90,
          height: 56,
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${meta.emoji} $name'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(meta.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocationProvider>(
      builder: (context, locProvider, _) {
        final myPos = LatLng(locProvider.latitude, locProvider.longitude);
        final myId = context.read<AuthProvider>().user?.id;

        return Stack(
          children: [
            // ── Map ──────────────────────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: myPos,
                initialZoom: AppConstants.defaultZoom,
                onMapReady: () => setState(() => _mapReady = true),
                onLongPress: (tapPos, latLng) =>
                    _showCreatePoiSheet(latLng),
              ),
              children: [
                // OSM base tiles
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.drd.fieldops',
                ),

                // Active route polylines
                PolylineLayer(polylines: [
                  ..._buildRoutePolylines(),
                  ..._buildApproachPolylines(myPos),
                ]),

                // Waypoint markers
                MarkerLayer(markers: _buildWaypointMarkers()),

                // POI markers
                MarkerLayer(markers: _buildPoiMarkers()),

                // Team member markers (excluding self)
                MarkerLayer(markers: _buildTeamMarkers(myId)),

                // Own position with pulse + heading
                MarkerLayer(
                  markers: [
                    Marker(
                      point: myPos,
                      width: 72,
                      height: 72,
                      child: _buildOwnMarker(locProvider),
                    ),
                  ],
                ),
              ],
            ),

            // ── Top-left status HUD ──────────────────────────────────────
            Positioned(top: 8, left: 8, child: _buildStatusHud(locProvider)),

            // ── Team count badge ─────────────────────────────────────────
            Positioned(top: 8, right: 8, child: _buildTeamBadge()),

            // ── Logout button — bottom left, clearly visible ─────────────
            Positioned(
              bottom: 96,
              left: 16,
              child: _buildLogoutButton(),
            ),

            // ── Active route summary ────────────────────────────────────
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              child: SafeArea(
                bottom: false,
                child: Container(
                  margin: const EdgeInsets.only(top: 60),
                  child: _buildRouteHud(myPos),
                ),
              ),
            ),

            // ── FABs (center + refresh) ──────────────────────────────────
            Positioned(
              bottom: 56,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFab(
                    tag: 'center_self',
                    icon: Icons.my_location,
                    color: DRDTheme.primaryColor,
                    tooltip: 'Center on me',
                    onTap: () {
                      if (_mapReady) {
                        _mapController.move(myPos, 16);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildFab(
                    tag: 'refresh_map',
                    icon: Icons.refresh,
                    color: DRDTheme.surfaceColor,
                    tooltip: 'Refresh',
                    onTap: _loadMapData,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Builder helpers ──────────────────────────────────────────────────────

  Widget _buildOwnMarker(LocationProvider loc) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, _) {
        final t = _pulseAnimation.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring
            Container(
              width: 72 * t,
              height: 72 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: DRDTheme.primaryColor.withValues(alpha: 0.4 * (1 - t)),
                  width: 2,
                ),
              ),
            ),
            // Inner solid circle
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DRDTheme.primaryColor.withValues(alpha: 0.25),
                border: Border.all(color: DRDTheme.primaryColor, width: 2.5),
              ),
            ),
            // Heading arrow
            Transform.rotate(
              angle: loc.heading * pi / 180,
              child: const Icon(
                Icons.navigation,
                color: DRDTheme.primaryColor,
                size: 22,
              ),
            ),
          ],
        );
      },
    );
  }

  List<Marker> _buildTeamMarkers(String? myId) {
    return _teamLocations
        .where((loc) => loc['user_id'] != myId)
        .map((loc) {
          final statusColor =
              DRDTheme.statusColors[loc['status'] as String?] ?? Colors.grey;
          final rawName = loc['user_name'] as String? ?? '?';
          final initials = rawName
              .split(' ')
              .where((w) => w.isNotEmpty)
              .take(2)
              .map((w) => w[0])
              .join();

          final lat = (loc['latitude'] as num?)?.toDouble();
          final lng = (loc['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;

          return Marker(
            point: LatLng(lat, lng),
            width: 52,
            height: 68,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Solid circle with initials
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DRDTheme.primaryColor,
                    border: Border.all(color: statusColor, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: DRDTheme.primaryColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                // Name label below
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    rawName.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  List<Polyline> _buildRoutePolylines() {
    final polylines = <Polyline>[];
    for (final route in _activeRoutes) {
      final wps = route['waypoints'] as List<dynamic>?;
      if (wps == null || wps.length < 2) continue;
      final isActive = route['is_active'] != false;
      final color = isActive ? _parseColor(route['color']) : Colors.white54;
      polylines.add(
        Polyline(
          points: wps
              .map(
                (wp) => LatLng(
                  (wp['latitude'] as num).toDouble(),
                  (wp['longitude'] as num).toDouble(),
                ),
              )
              .toList(),
          color: color,
          strokeWidth: isActive ? 3.0 : 2.5,
        ),
      );
    }
    return polylines;
  }

  List<Marker> _buildWaypointMarkers() {
    final markers = <Marker>[];
    for (final route in _activeRoutes) {
      final wps = route['waypoints'] as List<dynamic>?;
      if (wps == null) continue;
      final color = _parseColor(route['color']);
      final isSelected = _selectedRoute?['id'] == route['id'];
      for (int i = 0; i < wps.length; i++) {
        final wp = wps[i] as Map<String, dynamic>;
        final lat = (wp['latitude'] as num?)?.toDouble();
        final lng = (wp['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final isFirst = i == 0;
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: isFirst ? 32 : 14,
            height: isFirst ? 32 : 14,
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedRoute = route);
                _showRouteDetail(route);
              },
              child: isFirst
                  ? Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(
                          color: isSelected ? Colors.yellow : Colors.white,
                          width: isSelected ? 3 : 2,
                        ),
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)],
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  void _showRouteDetail(Map<String, dynamic> route) {
    final wps = (route['waypoints'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final routeColor = _parseColor(route['color']);
    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: routeColor)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    route['name'] as String? ?? 'Route',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DRDTheme.successColor.withValues(alpha: 0.2),
                    border: Border.all(color: DRDTheme.successColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('ACTIVE', style: TextStyle(color: DRDTheme.successColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if ((route['description'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(route['description'] as String, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            Text('${wps.length} waypoints', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            ...wps.asMap().entries.map((e) {
              final i = e.key;
              final wp = e.value;
              final label = wp['label'] as String? ?? 'Waypoint ${i + 1}';
              final lat = (wp['latitude'] as num?)?.toDouble();
              final lng = (wp['longitude'] as num?)?.toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: routeColor),
                      child: Center(
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13))),
                    if (lat != null && lng != null)
                      Text(
                        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // Fly map to first waypoint
                  if (wps.isNotEmpty) {
                    final lat = (wps.first['latitude'] as num?)?.toDouble();
                    final lng = (wps.first['longitude'] as num?)?.toDouble();
                    if (lat != null && lng != null && _mapReady) {
                      _mapController.move(LatLng(lat, lng), 15);
                    }
                  }
                },
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate to Route'),
                style: ElevatedButton.styleFrom(backgroundColor: DRDTheme.primaryColor),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() => setState(() => _selectedRoute = null));
  }

  List<Polyline> _buildApproachPolylines(LatLng myPos) {
    // Draw approach line to the selected route, or the first active route
    final route = _selectedRoute ??
        (_activeRoutes.isEmpty
            ? null
            : _activeRoutes.firstWhere((r) => r['is_active'] != false, orElse: () => _activeRoutes.first));
    if (route == null) return const [];
    final target = _routeFirstWaypoint(route);
    if (target == null) return const [];
    // Dashed approach line: simulate with short segments
    final pts = _dashLine(myPos, target, dashLengthM: 40, gapLengthM: 20);
    return pts.map((seg) => Polyline(
      points: seg,
      color: Colors.amberAccent.withValues(alpha: 0.75),
      strokeWidth: 2.5,
    )).toList();
  }

  LatLng? _routeFirstWaypoint(Map<String, dynamic> route) {
    final wps = route['waypoints'] as List<dynamic>?;
    if (wps == null || wps.isEmpty) return null;
    final first = wps.first as Map<String, dynamic>;
    final lat = (first['latitude'] as num?)?.toDouble();
    final lng = (first['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _routeTarget(Map<String, dynamic> route) {
    final wps = route['waypoints'] as List<dynamic>?;
    if (wps == null || wps.isEmpty) return null;
    final last = wps.last as Map<String, dynamic>;
    final lat = (last['latitude'] as num?)?.toDouble();
    final lng = (last['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  double? _routeDistanceKm(LatLng myPos) {
    if (_activeRoutes.isEmpty) return null;
    final route = _activeRoutes.firstWhere(
      (item) => item['is_active'] != false,
      orElse: () => _activeRoutes.first,
    );
    final target = _routeTarget(route);
    if (target == null) return null;
    return _distanceKm(myPos.latitude, myPos.longitude, target.latitude, target.longitude);
  }

  Map<String, dynamic>? _closestTeamMateToTarget() {
    if (_activeRoutes.isEmpty || _teamLocations.isEmpty) return null;
    final route = _activeRoutes.firstWhere(
      (item) => item['is_active'] != false,
      orElse: () => _activeRoutes.first,
    );
    final target = _routeTarget(route);
    if (target == null) return null;

    Map<String, dynamic>? best;
    double? bestDistance;
    for (final member in _teamLocations) {
      final lat = (member['latitude'] as num?)?.toDouble();
      final lng = (member['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final distance = _distanceKm(lat, lng, target.latitude, target.longitude);
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        best = member;
      }
    }
    return best == null ? null : {...best, 'distance_km': bestDistance};
  }

  /// Splits [a]→[b] into alternating dash/gap segments (returns only dash segments).
  List<List<LatLng>> _dashLine(LatLng a, LatLng b,
      {double dashLengthM = 40, double gapLengthM = 20}) {
    final totalM = _distanceKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
    if (totalM == 0) return [];
    final segLen = dashLengthM + gapLengthM;
    final dLat = b.latitude - a.latitude;
    final dLng = b.longitude - a.longitude;
    final List<List<LatLng>> result = [];
    double traveled = 0;
    while (traveled < totalM) {
      final t0 = traveled / totalM;
      final t1 = ((traveled + dashLengthM) / totalM).clamp(0.0, 1.0);
      result.add([
        LatLng(a.latitude + dLat * t0, a.longitude + dLng * t0),
        LatLng(a.latitude + dLat * t1, a.longitude + dLng * t1),
      ]);
      traveled += segLen;
    }
    return result;
  }

  double _distanceKm(double aLat, double aLng, double bLat, double bLng) {
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

  Widget _buildRouteHud(LatLng myPos) {
    if (_activeRoutes.isEmpty) {
      return const SizedBox.shrink();
    }

    final route = _activeRoutes.firstWhere(
      (item) => item['is_active'] != false,
      orElse: () => _activeRoutes.first,
    );
    final target = _routeTarget(route);
    final distance = _routeDistanceKm(myPos);
    final nearest = _closestTeamMateToTarget();
    final routeName = route['name'] as String? ?? 'Active route';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route, color: DRDTheme.primaryColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  routeName,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            target == null
                ? 'No destination'
                : 'Target ${target.latitude.toStringAsFixed(4)}, ${target.longitude.toStringAsFixed(4)}',
            style: const TextStyle(color: Colors.white60, fontSize: 10),
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

  Widget _buildStatusHud(LocationProvider loc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live / offline indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: loc.isTracking
                      ? DRDTheme.successColor
                      : DRDTheme.dangerColor,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                loc.isTracking ? 'LIVE' : 'NO GPS',
                style: TextStyle(
                  color: loc.isTracking
                      ? DRDTheme.successColor
                      : DRDTheme.dangerColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _hudRow(Icons.speed, '${loc.speed.toStringAsFixed(1)} km/h'),
          _hudRow(Icons.explore, 'HDG ${loc.heading.toStringAsFixed(0)}°'),
          _hudRow(Icons.landscape, 'ALT ${loc.altitude.toStringAsFixed(0)} m'),
          _hudRow(Icons.battery_std, '${loc.batteryLevel}%'),
          if (loc.pendingCount > 0) ...[
            const SizedBox(height: 4),
            _hudRow(
              Icons.cloud_queue,
              '${loc.pendingCount} queued',
              color: DRDTheme.warningColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _hudRow(IconData icon, String text, {Color? color}) {
    final c = color ?? Colors.white70;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: c, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTeamBadge() {
    final active = _teamLocations.where((l) => l['status'] == 'active').length;
    final total = _teamLocations.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$active/$total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'ACTIVE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0F1C2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                SizedBox(width: 8),
                Text('Sign Out', style: TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
            content: Text(
              'End your field session and sign out?',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444))),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          await context.read<AuthProvider>().logout();
          if (mounted) Navigator.pushReplacementNamed(context, '/login');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1C2E).withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 14),
            SizedBox(width: 5),
            Text(
              'LOGOUT',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab({
    required String tag,
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return FloatingActionButton.small(
      heroTag: tag,
      onPressed: onTap,
      backgroundColor: color,
      tooltip: tooltip,
      child: Icon(
        icon,
        color: color == DRDTheme.surfaceColor ? Colors.white : Colors.white,
        size: 20,
      ),
    );
  }

  Color _parseColor(dynamic value) {
    if (value is String && value.startsWith('#')) {
      try {
        return Color(int.parse(value.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return DRDTheme.warningColor;
  }
}

// Tiny immutable value type for POI display metadata.
class _PoiMeta {
  final String emoji;
  final String label;
  const _PoiMeta(this.emoji, this.label);
}
