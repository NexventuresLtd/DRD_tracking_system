import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/route_provider.dart';
import '../../providers/message_provider.dart';
import '../../services/api_service.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/user_model.dart';

class OperatorHome extends StatefulWidget {
  const OperatorHome({super.key});

  @override
  State<OperatorHome> createState() => _OperatorHomeState();
}

class _OperatorHomeState extends State<OperatorHome> {
  int _currentIndex = 0;
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _activeUnits = [];
  List<Map<String, dynamic>> _pendingTasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOperatorData();
    // Auto-refresh every 10 seconds
    Future.delayed(const Duration(seconds: 10), _autoRefresh);
  }

  Future<void> _loadOperatorData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _apiService.get('/locations'),
        _apiService.get('/routes?is_active=true'),
        _apiService.get('/events?size=10'),
      ]);

      final locations = results[0] as List<dynamic>? ?? [];
      final routes = results[1] as List<dynamic>? ?? [];

      if (mounted) {
        setState(() {
          _activeUnits = locations.cast<Map<String, dynamic>>();
          _pendingTasks = routes.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showError('Failed to load data: $e');
    }
  }

  void _autoRefresh() {
    if (mounted) {
      _loadOperatorData();
      Future.delayed(const Duration(seconds: 10), _autoRefresh);
    }
  }

  Future<void> _assignTask(String unitId, String routeId) async {
    try {
      await _apiService.post('/routes/$routeId/assign', {'user_id': unitId});

      if (mounted) {
        _showSuccess('Task assigned successfully');
        _loadOperatorData();
      }
    } catch (e) {
      _showError('Failed to assign task');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: DRDTheme.dangerColor),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: DRDTheme.successColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    final pages = [
      _buildDashboard(user),
      _buildUnitManagement(),
      _buildTaskManagement(),
      _buildReports(),
    ];

    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('OPERATIONS CENTER'),
        actions: [
          Consumer<MessageProvider>(
            builder: (context, msgProvider, _) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.message),
                    onPressed: () => _showMessages(context),
                  ),
                  if (msgProvider.unreadCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: DRDTheme.dangerColor,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${msgProvider.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOperatorData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final nav = Navigator.of(context);
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
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_search),
            label: 'Units',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Tasks'),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment),
            label: 'Reports',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickActions(context),
        backgroundColor: DRDTheme.primaryColor,
        child: const Icon(Icons.flash_on),
      ),
    );
  }

  Widget _buildDashboard(UserModel? user) {
    final activeCount = _activeUnits
        .where((u) => u['status'] == 'active')
        .length;
    final staleCount = _activeUnits.where((u) => u['status'] == 'stale').length;
    final offlineCount = _activeUnits
        .where((u) => u['status'] == 'offline')
        .length;
    final sosCount = _activeUnits.where((u) => u['flag_type'] == 'help').length;

    return RefreshIndicator(
      onRefresh: _loadOperatorData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome
            Text(
              'Operator ${user?.fullName ?? ""}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last updated: ${DateTime.now().toString().substring(11, 19)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),

            // Status Grid
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Active',
                    '$activeCount',
                    DRDTheme.successColor,
                    Icons.check_circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Stale',
                    '$staleCount',
                    DRDTheme.warningColor,
                    Icons.access_time,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Offline',
                    '$offlineCount',
                    DRDTheme.dangerColor,
                    Icons.wifi_off,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'SOS',
                    '$sosCount',
                    DRDTheme.dangerColor,
                    Icons.sos,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Active Units Map Preview
            const Text(
              'UNIT LOCATIONS',
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
                    initialCenter: LatLng(
                      AppConstants.defaultLat,
                      AppConstants.defaultLng,
                    ),
                    initialZoom: 12,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.drd.fieldops',
                    ),
                    MarkerLayer(
                      markers: _activeUnits.map((unit) {
                        final color =
                            DRDTheme.statusColors[unit['status']] ??
                            Colors.grey;
                        return Marker(
                          point: LatLng(
                            unit['latitude'] ?? AppConstants.defaultLat,
                            unit['longitude'] ?? AppConstants.defaultLng,
                          ),
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.3),
                              border: Border.all(color: color, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                (unit['user_name'] ?? '?').substring(0, 1),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

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
                    'Message All',
                    Icons.campaign,
                    DRDTheme.infoColor,
                    () => _showBroadcastDialog(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    'Create Task',
                    Icons.add_task,
                    DRDTheme.warningColor,
                    () => _showCreateTaskDialog(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    'Status Report',
                    Icons.description,
                    DRDTheme.primaryColor,
                    () {},
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    'Alert Units',
                    Icons.warning,
                    DRDTheme.dangerColor,
                    () => _showBroadcastDialog(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Recent Alerts
            const Text(
              'RECENT ALERTS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            _buildRecentAlerts(),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitManagement() {
    if (_activeUnits.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No units available',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _activeUnits.length,
      itemBuilder: (context, index) {
        final unit = _activeUnits[index];
        final statusColor =
            DRDTheme.statusColors[unit['status']] ?? Colors.grey;
        final teamColor =
            DRDTheme.teamColors[unit['team_name']] ?? DRDTheme.primaryColor;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: unit['status'] == 'active'
                    ? [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            title: Text(
              unit['user_name'] ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit['team_name'] ?? 'No Team',
                  style: TextStyle(color: teamColor, fontSize: 11),
                ),
                Text(
                  'Speed: ${unit['speed']?.toStringAsFixed(1) ?? "0"} km/h',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildUnitActionButton(
                  Icons.message,
                  DRDTheme.primaryColor,
                  () {
                    _showMessageUnitDialog(unit);
                  },
                ),
                _buildUnitActionButton(
                  Icons.assignment,
                  DRDTheme.warningColor,
                  () {
                    _showAssignTaskDialog(unit);
                  },
                ),
                _buildUnitActionButton(
                  Icons.location_on,
                  DRDTheme.successColor,
                  () {
                    _showUnitLocation(unit);
                  },
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildUnitDetail(
                      'Position',
                      '${unit['latitude']?.toStringAsFixed(4)}, ${unit['longitude']?.toStringAsFixed(4)}',
                    ),
                    _buildUnitDetail(
                      'Altitude',
                      '${unit['altitude']?.toStringAsFixed(0) ?? "N/A"}m',
                    ),
                    _buildUnitDetail(
                      'Heading',
                      '${unit['heading']?.toStringAsFixed(0) ?? "0"}°',
                    ),
                    _buildUnitDetail(
                      'Battery',
                      '${unit['battery_level'] ?? "N/A"}%',
                    ),
                    _buildUnitDetail(
                      'Last Update',
                      _formatTime(
                        DateTime.parse(
                          unit['recorded_at'] ??
                              DateTime.now().toIso8601String(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showMessageUnitDialog(unit),
                          icon: const Icon(Icons.message, size: 16),
                          label: const Text('Message'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DRDTheme.primaryColor,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showAssignTaskDialog(unit),
                          icon: const Icon(Icons.assignment, size: 16),
                          label: const Text('Assign Task'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DRDTheme.warningColor,
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

  Widget _buildTaskManagement() {
    return Consumer<RouteProvider>(
      builder: (context, routeProvider, _) {
        if (routeProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_pendingTasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.assignment, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No pending tasks',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadOperatorData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DRDTheme.primaryColor,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _pendingTasks.length,
          itemBuilder: (context, index) {
            final task = _pendingTasks[index];
            final color = Color(
              int.parse(
                task['color']?.replaceFirst('#', '0xFF') ?? '0xFF3B82F6',
              ),
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
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(Icons.route, color: color, size: 20),
                ),
                title: Text(
                  task['name'] ?? 'Unknown Task',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${task['waypoints']?.length ?? 0} waypoints | ${task['assigned_team_name'] ?? "Unassigned"}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                trailing: PopupMenuButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: const Text('Assign to Unit'),
                      onTap: () {
                        // Show unit selection
                        _showAssignToUnitDialog(task);
                      },
                    ),
                    PopupMenuItem(
                      child: const Text('View Details'),
                      onTap: () {
                        _showTaskDetails(task);
                      },
                    ),
                    PopupMenuItem(
                      child: const Text(
                        'Cancel Task',
                        style: TextStyle(color: DRDTheme.dangerColor),
                      ),
                      onTap: () {
                        _cancelTask(task['id']);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReports() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GENERATE REPORTS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          _buildReportCard(
            'Unit Status Report',
            'Current status of all field units',
            Icons.people,
            DRDTheme.primaryColor,
            () async {
              await _generateReport('unit_status');
            },
          ),
          const SizedBox(height: 8),
          _buildReportCard(
            'Movement Report',
            'Unit movement and tracking data',
            Icons.directions_walk,
            DRDTheme.successColor,
            () async {
              await _generateReport('movement');
            },
          ),
          const SizedBox(height: 8),
          _buildReportCard(
            'Incident Report',
            'All incidents, flags, and SOS events',
            Icons.warning,
            DRDTheme.dangerColor,
            () async {
              await _generateReport('incidents');
            },
          ),
          const SizedBox(height: 8),
          _buildReportCard(
            'Task Completion',
            'Task assignment and completion rates',
            Icons.assignment_turned_in,
            DRDTheme.warningColor,
            () async {
              await _generateReport('tasks');
            },
          ),
          const SizedBox(height: 8),
          _buildReportCard(
            'Communication Log',
            'All messages and broadcasts',
            Icons.message,
            DRDTheme.infoColor,
            () async {
              await _generateReport('communications');
            },
          ),
          const SizedBox(height: 8),
          _buildReportCard(
            'Sensor Data',
            'Accelerometer and gyroscope data',
            Icons.sensors,
            DRDTheme.accentColor,
            () async {
              await _generateReport('sensors');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Icon(icon, color: color.withValues(alpha: 0.5), size: 22),
            ],
          ),
          const SizedBox(height: 4),
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

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: DRDTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitActionButton(
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _buildUnitDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAlerts() {
    return FutureBuilder<dynamic>(
      future: _apiService.get('/events?size=5&severity=high'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Text(
            'No recent alerts',
            style: TextStyle(color: Colors.grey),
          );
        }

        final events = (snapshot.data['items'] as List?) ?? [];
        if (events.isEmpty) {
          return const Text(
            'No recent alerts',
            style: TextStyle(color: Colors.grey),
          );
        }

        return Column(
          children: events.map((event) {
            return ListTile(
              dense: true,
              leading: Icon(
                event['severity'] == 'high' ? Icons.warning : Icons.info,
                color: event['severity'] == 'high'
                    ? DRDTheme.dangerColor
                    : DRDTheme.warningColor,
                size: 18,
              ),
              title: Text(
                event['description'] ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              subtitle: Text(
                _formatTime(DateTime.parse(event['created_at'])),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildReportCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DRDTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Generate', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessages(BuildContext context) {
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
            return Consumer<MessageProvider>(
              builder: (context, msgProvider, _) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'MESSAGES',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          TextButton(
                            onPressed: () => msgProvider.markAllAsRead(),
                            child: const Text('Mark All Read'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: msgProvider.messages.isEmpty
                          ? const Center(
                              child: Text(
                                'No messages',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: msgProvider.messages.length,
                              itemBuilder: (context, index) {
                                final msg = msgProvider.messages[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: DRDTheme.primaryColor
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                      (msg.fromUserName ?? '?')
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: DRDTheme.primaryColor,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    msg.content,
                                    style: const TextStyle(color: Colors.white),
                                    maxLines: 2,
                                  ),
                                  subtitle: Text(
                                    '${msg.fromUserName} • ${_formatTime(msg.createdAt)}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 11,
                                    ),
                                  ),
                                  onTap: () => msgProvider.markAsRead(msg.id),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showBroadcastDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text(
          'Broadcast Message',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter broadcast message...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: DRDTheme.backgroundColor,
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
                Provider.of<MessageProvider>(
                  context,
                  listen: false,
                ).sendMessage(
                  content: controller.text,
                  toAll: true,
                  priority: 'high',
                );
                Navigator.pop(context);
                _showSuccess('Broadcast sent!');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DRDTheme.primaryColor,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showMessageUnitDialog(Map<String, dynamic> unit) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: Text(
          'Message ${unit['user_name']}',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter message...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: DRDTheme.backgroundColor,
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
                Provider.of<MessageProvider>(
                  context,
                  listen: false,
                ).sendMessage(
                  content: controller.text,
                  toUserId: unit['user_id'],
                );
                Navigator.pop(context);
                _showSuccess('Message sent to ${unit['user_name']}');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DRDTheme.primaryColor,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showAssignTaskDialog(Map<String, dynamic> unit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: Text(
          'Assign Task to ${unit['user_name']}',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _pendingTasks.isEmpty
              ? const Center(
                  child: Text(
                    'No tasks available',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _pendingTasks.length,
                  itemBuilder: (context, index) {
                    final task = _pendingTasks[index];
                    return ListTile(
                      title: Text(
                        task['name'] ?? 'Task',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${task['waypoints']?.length ?? 0} waypoints',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _assignTask(unit['user_id'], task['id']);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showAssignToUnitDialog(Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: Text(
          'Assign: ${task['name']}',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _activeUnits.isEmpty
              ? const Center(
                  child: Text(
                    'No units available',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _activeUnits.length,
                  itemBuilder: (context, index) {
                    final unit = _activeUnits[index];
                    final statusColor =
                        DRDTheme.statusColors[unit['status']] ?? Colors.grey;
                    return ListTile(
                      leading: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      title: Text(
                        unit['user_name'] ?? 'Unknown',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        unit['team_name'] ?? '',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _assignTask(unit['user_id'], task['id']);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showUnitLocation(Map<String, dynamic> unit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: Text(
          unit['user_name'] ?? 'Unit Location',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(
                unit['latitude'] ?? AppConstants.defaultLat,
                unit['longitude'] ?? AppConstants.defaultLng,
              ),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.drd.fieldops',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      unit['latitude'] ?? AppConstants.defaultLat,
                      unit['longitude'] ?? AppConstants.defaultLng,
                    ),
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.person_pin_circle,
                      color: DRDTheme.primaryColor,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTaskDetails(Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: Text(
          task['name'] ?? 'Task Details',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTaskDetailRow('Description', task['description'] ?? 'N/A'),
            _buildTaskDetailRow(
              'Waypoints',
              '${task['waypoints']?.length ?? 0}',
            ),
            _buildTaskDetailRow(
              'Assigned To',
              task['assigned_team_name'] ?? 'Unassigned',
            ),
            _buildTaskDetailRow(
              'Created',
              _formatTime(
                DateTime.parse(
                  task['created_at'] ?? DateTime.now().toIso8601String(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateTaskDialog() {
    Navigator.pushNamed(context, '/operator/operations');
  }

  Future<void> _cancelTask(String taskId) async {
    try {
      await _apiService.put('/routes/$taskId', {'is_active': false});
      _showSuccess('Task cancelled');
      _loadOperatorData();
    } catch (e) {
      _showError('Failed to cancel task');
    }
  }

  Future<void> _generateReport(String reportType) async {
    _showSuccess('Generating $reportType report...');
    // In production, call report generation endpoint
    await Future.delayed(const Duration(seconds: 2));
    _showSuccess('Report generated successfully!');
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DRDTheme.surfaceColor,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'QUICK ACTIONS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildQuickActionBtn(
                      'Message All',
                      Icons.campaign,
                      DRDTheme.infoColor,
                      () {
                        Navigator.pop(context);
                        _showBroadcastDialog();
                      },
                    ),
                    _buildQuickActionBtn(
                      'Create Task',
                      Icons.add_task,
                      DRDTheme.warningColor,
                      () {
                        Navigator.pop(context);
                        _showCreateTaskDialog();
                      },
                    ),
                    _buildQuickActionBtn(
                      'Refresh',
                      Icons.refresh,
                      DRDTheme.successColor,
                      () {
                        Navigator.pop(context);
                        _loadOperatorData();
                      },
                    ),
                    _buildQuickActionBtn(
                      'Export',
                      Icons.download,
                      DRDTheme.accentColor,
                      () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    super.dispose();
  }
}
