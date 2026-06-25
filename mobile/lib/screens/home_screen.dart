import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/team_provider.dart';
import '../providers/connectivity_provider.dart';
import '../models/user.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeamProvider>().loadTeams();
    });
  }

  Future<void> _refresh() async {
    await context.read<TeamProvider>().loadTeams();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, User?>((a) => a.user);

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF22C55E),
          backgroundColor: const Color(0xFF0F172A),
          onRefresh: _refresh,
          child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: const Color(0xFF0F172A),
              pinned: true,
              title: Row(
                children: [
                  Image.asset(
                    'lib/assets/images/logo1.png',
                    height: 32,
                    errorBuilder: (ctx, err, st) => const Icon(Icons.security, color: Color(0xFF22c55e), size: 28),
                  ),
                  const SizedBox(width: 10),
                  const Text('DRD OPERATIONS', style: TextStyle(color: Color(0xFF22c55e), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'monospace')),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Color(0xFF9CA3AF)),
                  onPressed: () => Navigator.pushNamed(context, '/notifications'),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/profile'),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Center(
                      child: Text(
                        user?.fullName.substring(0, 1).toUpperCase() ?? '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GreetingCard(user: user),
                    const SizedBox(height: 20),
                    _QuickActions(),
                    const SizedBox(height: 20),
                    _TeamsSection(),
                    const SizedBox(height: 20),
                    _StatusCard(),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  final User? user;
  const _GreetingCard({this.user});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting, ${user?.fullName.split(' ').first ?? 'Operator'}',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.role.displayName ?? '',
                  style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Text(
                user?.fullName.substring(0, 1).toUpperCase() ?? '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _actions = [
    {'icon': Icons.live_tv,                'label': 'Live Feed', 'route': '/live', 'color': Color(0xFFDC2626), 'bleAllowed': false},
    {'icon': Icons.warning_amber_outlined, 'label': 'SOS',       'route': '/sos',  'color': Color(0xFFB91C1C), 'bleAllowed': true},
  ];

  void _onTap(BuildContext context, Map<String, Object> action) {
    final conn = context.read<ConnectivityProvider>();
    final allowed = conn.online || (action['bleAllowed'] == true && conn.isBleOnly);
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        content: Row(children: [
          const Icon(Icons.wifi_off, color: Color(0xFF60A5FA), size: 16),
          const SizedBox(width: 8),
          Text('${action['label']} requires an internet connection.',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    Navigator.pushNamed(context, action['route'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Access', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        Row(
          children: _actions.asMap().entries.map((entry) {
            final i = entry.key;
            final a = entry.value;
            final bleAllowed = a['bleAllowed'] == true;
            final available = conn.online || (bleAllowed && conn.isBleOnly);
            final color = available ? a['color'] as Color : const Color(0xFF374151);

            return Expanded(
              child: GestureDetector(
                onTap: () => _onTap(context, a),
                child: Container(
                  margin: EdgeInsets.only(right: i < _actions.length - 1 ? 10 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: available ? const Color(0xFF1F2937) : const Color(0xFF1F2937).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Opacity(
                    opacity: available ? 1.0 : 0.4,
                    child: Column(children: [
                      Icon(a['icon'] as IconData, color: color, size: 24),
                      const SizedBox(height: 6),
                      Text(a['label'] as String,
                          style: TextStyle(color: available ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280), fontSize: 11)),
                      if (!available && conn.isBleOnly) ...[
                        const SizedBox(height: 3),
                        const Text('WiFi only', style: TextStyle(color: Color(0xFF374151), fontSize: 9, letterSpacing: 0.5)),
                      ],
                    ]),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TeamsSection extends StatelessWidget {
  const _TeamsSection();

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityProvider>();
    if (!conn.online) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Teams', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1F2937).withValues(alpha: 0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.wifi_off, color: Color(0xFF374151), size: 16),
              SizedBox(width: 8),
              Text('Teams require internet connection', style: TextStyle(color: Color(0xFF4B5563), fontSize: 12)),
            ]),
          ),
        ],
      );
    }

    final teams = context.watch<TeamProvider>().teams;
    final loading = context.watch<TeamProvider>().loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('My Teams', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/teams'),
              child: const Text('View all', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)))
        else if (teams.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: const Center(child: Text('No teams assigned', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13))),
          )
        else
          ...teams.take(3).map((t) => GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/teams/${t.id}'),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1F2937)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(int.parse(t.color.replaceFirst('#', 'FF'), radix: 16)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(t.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            Text('${t.memberCount} member${t.memberCount != 1 ? 's' : ''}',
                                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFF374151), size: 20),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('System Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          ...['Backend API', 'WebSocket', 'Database'].map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Color(0xFF22C55E), size: 8),
                    const SizedBox(width: 8),
                    Text(s, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

