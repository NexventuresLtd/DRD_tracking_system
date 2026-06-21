import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../providers/route_provider.dart';
import '../../providers/message_provider.dart';
import '../../services/api_service.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';

class CommanderHome extends StatefulWidget {
  const CommanderHome({super.key});

  @override
  State<CommanderHome> createState() => _CommanderHomeState();
}

class _CommanderHomeState extends State<CommanderHome> {
  int _currentIndex = 0;
  final ApiService _apiService = ApiService();
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _locations = [];
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageProvider>().initialize();
    });
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoadingStats = true);

    try {
      // Fetch all data in parallel
      final results = await Future.wait([
        _apiService.get('/users?size=1'),
        _apiService.get('/teams'),
        _apiService.get('/routes'),
        _apiService.get('/events/stats?days=1'),
        _apiService.get('/locations'),
        _apiService.get('/users?role=field_unit&size=500'),
      ]);

      final users = results[0] as Map<String, dynamic>?;
      final teams = results[1] as List<dynamic>?;
      final routes = results[2] as List<dynamic>?;
      final eventStats = results[3] as Map<String, dynamic>?;
      final locs = (results[4] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      final allUsersPage = results[5] as Map<String, dynamic>?;
      final allFieldUnits =
          (allUsersPage?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // Merge GPS records with all field units so status counts include
      // soldiers who haven't sent a location update yet.
      final merged = List<Map<String, dynamic>>.from(locs);
      final seenIds = locs.map((l) => l['user_id'] as String?).toSet();
      for (final u in allFieldUnits) {
        final uid = u['id'] as String?;
        if (uid == null || seenIds.contains(uid)) continue;
        merged.add({'user_id': uid, 'status': 'offline'});
      }

      if (mounted) {
        setState(() {
          _stats = {
            'totalUsers': users?['total'] ?? 0,
            'totalTeams': teams?.length ?? 0,
            'activeRoutes':
                routes?.where((r) => r['is_active'] == true).length ?? 0,
            'todayEvents': eventStats?['total_events'] ?? 0,
          };
          _locations = merged;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
        _stats = {
          'totalUsers': 0,
          'totalTeams': 0,
          'activeRoutes': 0,
          'todayEvents': 0,
        };
        _locations = [];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    final pages = [
      _buildDashboard(user),
      _buildTeamsOverview(),
      _buildRoutesOverview(),
      _buildAlertsView(),
    ];

    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('COMMAND CENTER'),
        actions: [
          Consumer<MessageProvider>(
            builder: (context, msgProvider, _) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.message),
                    onPressed: () => _showMessagesDialog(context),
                  ),
                  if (msgProvider.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
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
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            tooltip: 'Settings & Permissions',
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
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 1) {
            Navigator.pushNamed(context, '/commander/teams');
          } else if (index == 2) {
            Navigator.pushNamed(context, '/commander/routes');
          } else if (index == 3) {
            Navigator.pushNamed(context, '/commander/tracking');
          } else {
            setState(() => _currentIndex = index);
          }
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Teams'),
          BottomNavigationBarItem(icon: Icon(Icons.route), label: 'Routes'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Track'),
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
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome message
            Text(
              'Welcome, Commander ${user?.fullName ?? ""}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'System status: ${_isLoadingStats ? "Loading..." : "Operational"}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Stats Grid
            if (_isLoadingStats)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Units',
                      '${_stats['totalUsers']}',
                      DRDTheme.primaryColor,
                      Icons.people,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Teams',
                      '${_stats['totalTeams']}',
                      DRDTheme.successColor,
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
                    '${_stats['activeRoutes']}',
                    DRDTheme.warningColor,
                    Icons.route,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Today Events',
                    '${_stats['todayEvents']}',
                    DRDTheme.dangerColor,
                    Icons.notifications,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Live Status
            _buildLiveStatus(),
            const SizedBox(height: 24),

            // Quick Navigation
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
            _buildNavCard(
              'Team Management',
              'View and manage teams',
              Icons.group,
              DRDTheme.primaryColor,
              () {
                setState(() => _currentIndex = 1);
              },
            ),
            const SizedBox(height: 8),
            _buildNavCard(
              'Route Planning',
              'Create and assign routes',
              Icons.route,
              DRDTheme.warningColor,
              () {
                setState(() => _currentIndex = 2);
              },
            ),
            const SizedBox(height: 8),
            _buildNavCard(
              'Live Tracking',
              'Monitor field units in real-time',
              Icons.location_on,
              DRDTheme.successColor,
              () {
                Navigator.pushNamed(context, '/commander/tracking');
              },
            ),
            const SizedBox(height: 8),
            _buildNavCard(
              'Message All Units',
              'Send broadcast message',
              Icons.campaign,
              DRDTheme.infoColor,
              () {
                _showBroadcastDialog(context);
              },
            ),

            const SizedBox(height: 24),

            // Recent Activity
            const Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            _buildRecentActivity(),
          ],
        ),
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
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Icon(icon, color: color.withValues(alpha: 0.5), size: 24),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavCard(
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
              child: Icon(icon, color: color, size: 24),
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
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamsOverview() {
    return Consumer<TeamProvider>(
      builder: (context, teamProvider, _) {
        if (teamProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (teamProvider.teams.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.group, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No teams found',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => teamProvider.fetchTeams(),
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

        return RefreshIndicator(
          onRefresh: () => teamProvider.fetchTeams(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: teamProvider.teams.length,
            itemBuilder: (context, index) {
              final team = teamProvider.teams[index];
              final color =
                  DRDTheme.teamColors[team['name']] ?? DRDTheme.primaryColor;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
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
                    'Code: ${team['code']} | ${team['member_count'] ?? 0} members',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildTeamAction('Members', Icons.people, () {
                                teamProvider.fetchTeamMembers(team['id']);
                              }),
                              _buildTeamAction('Assign Route', Icons.route, () {
                                Navigator.pushNamed(
                                  context,
                                  '/commander/routes',
                                );
                              }),
                              _buildTeamAction('Message', Icons.message, () {
                                _showTeamMessageDialog(context, team);
                              }),
                              _buildTeamAction('Track', Icons.location_on, () {
                                Navigator.pushNamed(
                                  context,
                                  '/commander/tracking',
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTeamAction(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DRDTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: DRDTheme.primaryColor, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutesOverview() {
    return Consumer<RouteProvider>(
      builder: (context, routeProvider, _) {
        if (routeProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (routeProvider.routes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.route, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No routes created',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showCreateRouteDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Create Route'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DRDTheme.warningColor,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => routeProvider.fetchRoutes(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: routeProvider.routes.length,
            itemBuilder: (context, index) {
              final route = routeProvider.routes[index];
              final color = Color(
                int.parse(
                  route['color']?.replaceFirst('#', '0xFF') ?? '0xFF3B82F6',
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
                    child: Icon(Icons.route, color: color),
                  ),
                  title: Text(
                    route['name'] ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${route['waypoints']?.length ?? 0} waypoints | ${route['assigned_team_name'] ?? "Unassigned"}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: DRDTheme.warningColor,
                          size: 20,
                        ),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: DRDTheme.dangerColor,
                          size: 20,
                        ),
                        onPressed: () => _deleteRoute(context, route['id']),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAlertsView() {
    return Consumer<MessageProvider>(
      builder: (context, msgProvider, _) {
        return RefreshIndicator(
          onRefresh: () => msgProvider.fetchMessages(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: msgProvider.messages.length,
            itemBuilder: (context, index) {
              final msg = msgProvider.messages[index];
              final isPriority =
                  msg.priority == 'urgent' || msg.priority == 'high';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isPriority
                    ? DRDTheme.dangerColor.withValues(alpha: 0.1)
                    : DRDTheme.surfaceColor,
                child: ListTile(
                  leading: Icon(
                    isPriority ? Icons.warning : Icons.info,
                    color: isPriority
                        ? DRDTheme.dangerColor
                        : DRDTheme.primaryColor,
                  ),
                  title: Text(
                    msg.content,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                  ),
                  subtitle: Text(
                    '${msg.fromUserName ?? "System"} • ${_formatTime(msg.createdAt)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                  trailing: msg.isRead
                      ? null
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: DRDTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                  onTap: () => msgProvider.markAsRead(msg.id),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildLiveStatus() {
    final now = DateTime.now();
    int active = 0, stale = 0, offline = 0;

    for (final loc in _locations) {
      final recordedAt = DateTime.tryParse(loc['recorded_at']?.toString() ?? '');
      if (recordedAt == null) continue;

      final elapsed = now.difference(recordedAt).inSeconds;
      if (elapsed > 90) {
        offline++;
      } else if (elapsed > 30) {
        stale++;
      } else {
        active++;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LIVE SOLDIER STATUS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusIndicator('ACTIVE', active, DRDTheme.successColor),
                _buildStatusIndicator('STALE', stale, DRDTheme.warningColor),
                _buildStatusIndicator('OFFLINE', offline, DRDTheme.dangerColor),
              ],
            ),
            if (_locations.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/commander/tracking');
                },
                icon: const Icon(Icons.location_on),
                label: const Text('View on Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DRDTheme.primaryColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    return FutureBuilder<dynamic>(
      future: _apiService.get('/events?size=5'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const Text(
            'No recent activity',
            style: TextStyle(color: Colors.grey),
          );
        }

        final events = (snapshot.data['items'] as List?) ?? [];

        return Column(
          children: events.map((event) {
            return ListTile(
              dense: true,
              leading: Icon(
                _getEventIcon(event['event_type']),
                color: _getEventColor(event['event_type']),
                size: 20,
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
      default:
        return Icons.info;
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
      default:
        return DRDTheme.primaryColor;
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showMessagesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('Messages', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Consumer<MessageProvider>(
            builder: (context, msgProvider, _) {
              return ListView.builder(
                itemCount: msgProvider.messages.length,
                itemBuilder: (context, index) {
                  final msg = msgProvider.messages[index];
                  return ListTile(
                    title: Text(
                      msg.content,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      msg.fromUserName ?? 'Unknown',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                },
              );
            },
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

  void _showBroadcastDialog(BuildContext context) {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Broadcast sent!'),
                    backgroundColor: DRDTheme.successColor,
                  ),
                );
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

  void _showTeamMessageDialog(BuildContext context, Map<String, dynamic> team) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: Text(
          'Message ${team['name']}',
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
                ).sendMessage(content: controller.text, toTeamId: team['id']);
                Navigator.pop(context);
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

  void _showCreateRouteDialog(BuildContext context) {
    Navigator.pushNamed(context, '/commander/routes');
  }

  void _deleteRoute(BuildContext context, String routeId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text(
          'Delete Route',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this route?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final apiService = ApiService();
              final nav = Navigator.of(context);
              final routeProvider = Provider.of<RouteProvider>(context, listen: false);
              await apiService.delete('/routes/$routeId');
              if (mounted) {
                nav.pop();
                routeProvider.fetchRoutes();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DRDTheme.dangerColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
                    _buildQuickAction(
                      'Create Route',
                      Icons.route,
                      DRDTheme.warningColor,
                      () {
                        Navigator.pop(context);
                        setState(() => _currentIndex = 2);
                      },
                    ),
                    _buildQuickAction(
                      'Add Team',
                      Icons.group_add,
                      DRDTheme.successColor,
                      () {
                        Navigator.pop(context);
                        setState(() => _currentIndex = 1);
                      },
                    ),
                    _buildQuickAction(
                      'Broadcast',
                      Icons.campaign,
                      DRDTheme.infoColor,
                      () {
                        Navigator.pop(context);
                        _showBroadcastDialog(context);
                      },
                    ),
                    _buildQuickAction(
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

  Widget _buildQuickAction(
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
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
