import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/team_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, User?>((a) => a.user);

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: const Color(0xFF0F172A),
              pinned: true,
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.security, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('DRD System', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Color(0xFF9CA3AF)),
                  onPressed: () {},
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
      bottomNavigationBar: _BottomNav(),
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
  final _actions = const [
    {'icon': Icons.map_outlined, 'label': 'Live Map', 'route': '/map', 'color': Color(0xFF2563EB)},
    {'icon': Icons.people_outline, 'label': 'Teams', 'route': '/teams', 'color': Color(0xFF059669)},
    {'icon': Icons.chat_bubble_outline, 'label': 'Comms', 'route': '/comms', 'color': Color(0xFF7C3AED)},
    {'icon': Icons.warning_amber_outlined, 'label': 'SOS', 'route': '/sos', 'color': Color(0xFFDC2626)},
  ];

  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Access', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        Row(
          children: _actions.map((a) {
            return Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, a['route'] as String),
                child: Container(
                  margin: EdgeInsets.only(right: a == _actions.last ? 0 : 10),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1F2937)),
                  ),
                  child: Column(
                    children: [
                      Icon(a['icon'] as IconData, color: a['color'] as Color, size: 24),
                      const SizedBox(height: 6),
                      Text(a['label'] as String, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11)),
                    ],
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
          ...teams.take(3).map((t) => Container(
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

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.home_outlined, label: 'Home', onTap: () {}),
          _NavItem(icon: Icons.map_outlined, label: 'Map', onTap: () => Navigator.pushNamed(context, '/map')),
          _NavItem(icon: Icons.chat_bubble_outline, label: 'Comms', onTap: () => Navigator.pushNamed(context, '/comms')),
          _NavItem(icon: Icons.person_outline, label: 'Profile', onTap: () => Navigator.pushNamed(context, '/profile')),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF6B7280), size: 22),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
