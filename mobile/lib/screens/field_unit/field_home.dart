import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/message_provider.dart';
import '../../services/api_service.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../widgets/status_indicator.dart';
import 'field_map_screen.dart';
import 'field_squad_view.dart';
import 'live_feed_screen.dart';

class FieldHome extends StatefulWidget {
  const FieldHome({super.key});

  @override
  State<FieldHome> createState() => _FieldHomeState();
}

class _FieldHomeState extends State<FieldHome> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final ApiService _apiService = ApiService();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? _currentMission;
  List<Map<String, dynamic>> _teamRoutes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user?.id != null) {
        context.read<LocationProvider>()
            .initialize(user!.id, teamId: user.teamId)
            .then((_) => _checkLocationStatus());
      }
      // Load messages and connect real-time messaging
      context.read<MessageProvider>().initialize();
      // Load team routes for Intel tab
      _loadCurrentMission();
    });
  }

  Future<void> _checkLocationStatus() async {
    if (mounted) {
      final locProvider = context.read<LocationProvider>();
      if (!locProvider.locationEnabled) {
        _showLocationDisabledDialog();
      }
    }
  }

  void _showLocationDisabledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Disabled'),
        content: const Text(
          'Location services are required to operate in this system. '
          'Please enable location services to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _checkLocationStatus();
            },
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCurrentMission() async {
    try {
      final user = Provider.of<AuthProvider>(context, listen: false).user;
      if (user == null) return;

      // Load routes assigned to the team
      final teamId = user.teamId;
      if (teamId == null) return;
      final routes = await _apiService.get('/routes?team_id=$teamId&is_active=true');
      if (routes is List && routes.isNotEmpty) {
        // Get all routes for the team
        final routeList = List<Map<String, dynamic>>.from(routes);

        // First, try to find a route assigned to this specific user
        final userRoute = routeList.firstWhere(
          (r) => (r['assigned_to'] as List?)?.contains(user.id) ?? false,
          orElse: () => <String, dynamic>{},
        );

        // If no user-specific route, show the first team route
        final missionToShow = userRoute.isNotEmpty ? userRoute : (routeList.isNotEmpty ? routeList.first : null);

        if (mounted) {
          setState(() {
            _teamRoutes = routeList;
            if (missionToShow != null) _currentMission = missionToShow;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading mission: $e');
    }
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    final pages = [
      _buildDashboard(user),
      const FieldMapScreen(),
      _buildMissionView(),
      const FieldSquadView(),
      _buildMessagesView(),
      _buildProfileView(user),
    ];

    return Consumer<LocationProvider>(
      builder: (context, locProvider, _) {
        final isLocationDisabled = !locProvider.locationEnabled;

        return Scaffold(
          backgroundColor: DRDTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A1628),
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DRDTheme.primaryColor.withValues(alpha: 0.15),
                    border: Border.all(color: DRDTheme.primaryColor.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.shield_outlined, size: 14, color: DRDTheme.primaryColor),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'drd_tracking',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    if (user?.teamName != null)
                      Text(
                        user!.teamName!.toUpperCase(),
                        style: TextStyle(
                          color: DRDTheme.primaryColor.withValues(alpha: 0.8),
                          fontSize: 9,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              if (isLocationDisabled)
                IconButton(
                  icon: const Icon(Icons.location_off, color: DRDTheme.dangerColor, size: 20),
                  onPressed: _checkLocationStatus,
                  tooltip: 'Location disabled - tap to retry',
                ),
              // Standalone LIVE button — start live feed from anywhere in the app
              IconButton(
                icon: const Icon(Icons.videocam_rounded, color: Color(0xFFEF4444), size: 22),
                tooltip: 'Start Live Feed',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LiveFeedScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                tooltip: 'Sign out',
                onPressed: () async {
                  // Cache before async gap
                  final nav = Navigator.of(context);
                  final loc = context.read<LocationProvider>();
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
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.4)))),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444)))),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    await loc.stopTracking();
                    await authProvider.logout();
                    if (mounted) nav.pushReplacementNamed('/login');
                  }
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              pages[_currentIndex],
              if (isLocationDisabled)
                Container(
                  color: Colors.black.withValues(alpha:0.5),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_off,
                          color: DRDTheme.dangerColor,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Location Services Disabled',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please enable location services to continue',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _checkLocationStatus,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DRDTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: isLocationDisabled
              ? null
              : BottomNavigationBar(
                  currentIndex: _currentIndex == 4 ? 5 : (_currentIndex == 5 ? 6 : _currentIndex),
                  onTap: (index) {
                    if (index == 4) {
                      Navigator.pushNamed(context, '/field/sos');
                    } else if (index < 4) {
                      setState(() => _currentIndex = index);
                    } else if (index == 5) {
                      setState(() => _currentIndex = 4);
                    } else if (index == 6) {
                      setState(() => _currentIndex = 5);
                    }
                  },
                  type: BottomNavigationBarType.fixed,
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Status'),
                    BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.assignment),
                      label: 'Intel',
                    ),
                    BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Squad'),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.emergency),
                      label: 'SOS',
                    ),
                    BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Comms'),
                    BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildDashboard(dynamic user) {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadCurrentMission();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  DRDTheme.teamColors[user?.teamName] ??
                                  DRDTheme.primaryColor,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              user?.fullName.substring(0, 2).toUpperCase() ??
                                  '?',
                              style: TextStyle(
                                color:
                                    DRDTheme.teamColors[user?.teamName] ??
                                    DRDTheme.primaryColor,
                                fontWeight: FontWeight.bold,
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
                                user?.fullName ?? 'Unknown',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${user?.teamName ?? "No Team"} • ${user?.teamRole?.toUpperCase() ?? ""}',
                                style: TextStyle(
                                  color:
                                      DRDTheme.teamColors[user?.teamName] ??
                                      Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Consumer<LocationProvider>(
                          builder: (_, loc, _) => SizedBox(
                            width: 60,
                            child: Column(
                              children: [
                                StatusIndicator(
                                  status: loc.isTracking ? 'active' : 'offline',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  loc.isTracking ? 'LIVE' : 'OFF',
                                  style: TextStyle(
                                    color: loc.isTracking
                                        ? DRDTheme.successColor
                                        : DRDTheme.dangerColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Consumer<LocationProvider>(
                      builder: (_, loc, _) => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildInfoItem(
                            'Speed',
                            '${loc.speed.toStringAsFixed(1)} km/h',
                          ),
                          _buildInfoItem(
                            'Heading',
                            '${loc.heading.toStringAsFixed(0)}°',
                          ),
                          _buildInfoItem(
                            'Alt',
                            '${loc.altitude.toStringAsFixed(0)} m',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Current Mission
            if (_currentMission != null) ...[
              const Text(
                'CURRENT MISSION',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: DRDTheme.warningColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.assignment,
                      color: DRDTheme.warningColor,
                    ),
                  ),
                  title: Text(
                    _currentMission!['name'] ?? 'Mission',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${_currentMission!['waypoints']?.length ?? 0} waypoints',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.5),
                      fontSize: 12,
                    ),
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => setState(() => _currentIndex = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DRDTheme.warningColor,
                    ),
                    child: const Text('VIEW'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Quick Actions
            const Text(
              'QUICK ACTIONS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    'Check In',
                    Icons.check_circle,
                    DRDTheme.successColor,
                    () {
                      Navigator.pushNamed(context, '/field/checkin');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    'Navigate',
                    Icons.navigation,
                    DRDTheme.primaryColor,
                    () {
                      Navigator.pushNamed(context, '/field/navigation');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    'Report',
                    Icons.report,
                    DRDTheme.warningColor,
                    () {
                      _showReportDialog();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    'SOS',
                    Icons.sos,
                    DRDTheme.dangerColor,
                    () {
                      Navigator.pushNamed(context, '/field/sos');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionView() {
    // Show all team routes if available, otherwise show current mission
    final routesToDisplay = _teamRoutes.isNotEmpty ? _teamRoutes : (_currentMission != null ? [_currentMission!] : []);

    if (routesToDisplay.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No active missions',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadCurrentMission,
              icon: const Icon(Icons.refresh),
              label: const Text('Check for missions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DRDTheme.primaryColor,
              ),
            ),
          ],
        ),
      );
    }

    // Show first route in detail, others in a list
    final primaryRoute = routesToDisplay.first;
    final waypoints = (primaryRoute['waypoints'] as List?) ?? [];
    final assignedTeam = (primaryRoute['assigned_team'] as List?) ?? [];

    return Column(
      children: [
        // Mission Info
        Container(
          padding: const EdgeInsets.all(16),
          color: DRDTheme.surfaceColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primaryRoute['name'] ?? 'Mission',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                primaryRoute['description'] ?? 'No description',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              // Team Assignment Info
              if (assignedTeam.isNotEmpty) ...[
                const Text(
                  'ASSIGNED TEAM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: assignedTeam.map<Widget>((member) {
                    final name = member['name'] as String? ?? 'Unknown';
                    final initials = name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: DRDTheme.primaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: DRDTheme.primaryColor, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: DRDTheme.primaryColor,
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ] else
                Text(
                  'No team assigned',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),

        // Map with route
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: waypoints.isNotEmpty
                  ? LatLng(waypoints[0]['latitude'], waypoints[0]['longitude'])
                  : (() {
                      final loc = context.read<LocationProvider>();
                      return loc.hasRealFix
                          ? LatLng(loc.latitude, loc.longitude)
                          : LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
                    })(),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.drd.fieldops',
              ),
              if (waypoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: waypoints
                          .map((wp) => LatLng(wp['latitude'], wp['longitude']))
                          .toList(),
                      color: DRDTheme.warningColor,
                      strokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: waypoints.map((wp) {
                  return Marker(
                    point: LatLng(wp['latitude'], wp['longitude']),
                    width: 30,
                    height: 30,
                    child: const Icon(
                      Icons.location_on,
                      color: DRDTheme.warningColor,
                      size: 30,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessagesView() {
    final myId = context.read<AuthProvider>().user?.id ?? '';
    return Consumer<MessageProvider>(
      builder: (context, msgProvider, _) {
        // Scroll to latest message whenever messages change
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });

        // Show messages oldest-first for chat layout
        final sorted = [...msgProvider.messages]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        return Column(
          children: [
            // Connection status bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: msgProvider.isConnected ? DRDTheme.successColor.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
              child: Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: msgProvider.isConnected ? DRDTheme.successColor : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    msgProvider.isConnected ? 'LIVE' : 'Reconnecting...',
                    style: TextStyle(
                      fontSize: 10,
                      color: msgProvider.isConnected ? DRDTheme.successColor : Colors.red,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.white54),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: msgProvider.fetchMessages,
                  ),
                ],
              ),
            ),

            // Messages list
            Expanded(
              child: msgProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : sorted.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.message_outlined, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('No messages yet', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 12),
                          TextButton(onPressed: msgProvider.fetchMessages, child: const Text('Refresh')),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: sorted.length,
                      itemBuilder: (context, index) {
                        final msg = sorted[index];
                        final isOwn = msg.fromUserId == myId;
                        return GestureDetector(
                          onTap: () => !msg.isRead ? msgProvider.markAsRead(msg.id) : null,
                          child: Align(
                            alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isOwn ? DRDTheme.primaryColor : DRDTheme.surfaceColor,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: Radius.circular(isOwn ? 12 : 0),
                                  bottomRight: Radius.circular(isOwn ? 0 : 12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isOwn)
                                    Text(
                                      msg.fromUserName ?? 'Unknown',
                                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  if (!isOwn) const SizedBox(height: 2),
                                  Text(msg.content, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _fmtTime(msg.createdAt),
                                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Input bar
            SafeArea(
              top: false,
              child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              color: DRDTheme.surfaceColor,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _doSendMessage(context),
                      decoration: InputDecoration(
                        hintText: 'Message all...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.07),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: DRDTheme.primaryColor,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: () => _doSendMessage(context),
                    ),
                  ),
                ],
              ),
            ),
            ),  // SafeArea
          ],
        );
      },
    );
  }

  void _doSendMessage(BuildContext context) {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    context.read<MessageProvider>().sendMessage(content: text, toAll: true);
  }

  String _fmtTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }

  Widget _buildProfileView(dynamic user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: DRDTheme.primaryColor,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        user?.fullName.substring(0, 2).toUpperCase() ?? '?',
                        style: const TextStyle(
                          color: DRDTheme.primaryColor,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.fullName ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(color: Colors.white.withValues(alpha:0.6)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Info Cards
          _buildInfoCard(
            'Role',
            (user?.role ?? '').toUpperCase(),
            Icons.shield,
            DRDTheme.primaryColor,
          ),
          _buildInfoCard(
            'Team',
            user?.teamName ?? 'No Team',
            Icons.group,
            DRDTheme.successColor,
          ),
          _buildInfoCard(
            'Position',
            'Soldier',
            Icons.person_pin,
            DRDTheme.warningColor,
          ),
          Consumer<LocationProvider>(
            builder: (_, loc, _) => _buildInfoCard(
              'Status',
              loc.isTracking ? 'ACTIVE' : 'STANDBY',
              Icons.wifi,
              loc.isTracking ? DRDTheme.successColor : DRDTheme.dangerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha:0.6), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: DRDTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha:0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha:0.5), fontSize: 11),
        ),
      ),
    );
  }

  void _showReportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text(
          'Submit Report',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Describe your situation...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha:0.4)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _apiService.post('/events', {
                  'event_type': 'UPDATE',
                  'description': controller.text,
                  'severity': 'low',
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Report submitted!'),
                    backgroundColor: DRDTheme.successColor,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DRDTheme.primaryColor,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
