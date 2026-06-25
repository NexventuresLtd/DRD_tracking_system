import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import '../services/api_service.dart';
import '../config/environment.dart';

class TeamMember {
  final String id;
  final String fullName;
  final String username;
  final String email;
  final String? phone;
  final String role;
  final bool isActive;
  final String? avatarUrl;

  const TeamMember({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    this.phone,
    required this.role,
    required this.isActive,
    this.avatarUrl,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    // Server returns TeamMemberResponse: { id, user_id, role_in_team, user: {...} }
    final u = j['user'] as Map<String, dynamic>? ?? j;
    return TeamMember(
      id: (u['id'] ?? j['user_id'] ?? j['id']) as String,
      fullName: u['full_name'] as String? ?? u['username'] as String? ?? 'Unknown',
      username: u['username'] as String? ?? '',
      email: u['email'] as String? ?? '',
      phone: u['phone'] as String?,
      role: u['role'] as String? ?? j['role_in_team'] as String? ?? 'field_user',
      isActive: u['is_active'] as bool? ?? false,
      avatarUrl: u['avatar_url'] as String?,
    );
  }

  String get roleLabel {
    switch (role) {
      case 'operations_coordinator': return 'Coordinator';
      case 'planning_officer': return 'Planning Officer';
      case 'team_leader': return 'Team Leader';
      default: return 'Field User';
    }
  }
}

class TeamDetailScreen extends StatefulWidget {
  final String teamId;
  const TeamDetailScreen({super.key, required this.teamId});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final _api = ApiService();
  List<TeamMember> _members = [];
  bool _loading = true;
  String? _teamName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await _api.get('/teams/${widget.teamId}') as Map<String, dynamic>;
      final members = (data['members'] as List<dynamic>? ?? [])
          .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _teamName = data['name'] as String?;
          _members = members;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_teamName ?? 'Team', style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: RefreshIndicator(
          color: const Color(0xFF22C55E),
          backgroundColor: const Color(0xFF0F172A),
          onRefresh: _load,
          child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
          : _members.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 200),
                    Center(child: Text('No members found', style: TextStyle(color: Color(0xFF6B7280)))),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _members.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _MemberTile(member: _members[i]),
                ),
        ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final TeamMember member;
  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showMemberSheet(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1F2937)),
        ),
        child: Row(
          children: [
            _Avatar(member: member),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(member.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))),
                      if (member.role == 'team_leader')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF854D0E), borderRadius: BorderRadius.circular(4)),
                          child: const Text('LEADER', style: TextStyle(color: Color(0xFFFDE68A), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(member.roleLabel, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                ],
              ),
            ),
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: member.isActive ? const Color(0xFF22C55E) : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MemberSheet(member: member),
    );
  }
}

class _MemberSheet extends StatelessWidget {
  final TeamMember member;
  const _MemberSheet({required this.member});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          _Avatar(member: member, size: 56),
          const SizedBox(height: 12),
          Text(member.fullName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('@${member.username}', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 4),
          Text(member.roleLabel, style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: member.isActive ? const Color(0xFF22C55E) : const Color(0xFF374151)),
              ),
              const SizedBox(width: 6),
              Text(member.isActive ? 'Online' : 'Offline', style: TextStyle(color: member.isActive ? const Color(0xFF22C55E) : const Color(0xFF6B7280), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message',
                  color: const Color(0xFF2563EB),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/comms', arguments: {'recipient_id': member.id, 'recipient_name': member.fullName});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.call_outlined,
                  label: member.isActive ? 'Call' : 'Offline',
                  color: member.isActive ? const Color(0xFF16A34A) : const Color(0xFF374151),
                  onTap: member.isActive && member.phone != null
                      ? () async {
                          Navigator.pop(context);
                          final uri = Uri(scheme: 'tel', path: member.phone);
                          if (await launcher.canLaunchUrl(uri)) launcher.launchUrl(uri);
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final TeamMember member;
  final double size;
  const _Avatar({required this.member, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (member.avatarUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(EnvironmentConfig.resolveUrl(member.avatarUrl!), width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _fallback()),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(size / 2)),
        child: Center(
          child: Text(member.fullName.isNotEmpty ? member.fullName[0].toUpperCase() : '?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.4)),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: onTap != null ? color.withValues(alpha: 0.15) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onTap != null ? color.withValues(alpha: 0.4) : const Color(0xFF1F2937)),
        ),
        child: Column(
          children: [
            Icon(icon, color: onTap != null ? color : const Color(0xFF374151), size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: onTap != null ? color : const Color(0xFF374151), fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
