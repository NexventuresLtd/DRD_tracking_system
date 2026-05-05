import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';

class TeamManagement extends StatefulWidget {
  const TeamManagement({super.key});

  @override
  State<TeamManagement> createState() => _TeamManagementState();
}

class _TeamManagementState extends State<TeamManagement> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _allUsers = [];
  bool _loading = true;
  String? _expandedTeamId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.get('/teams'),
        // Fetch all non-admin users eligible for team assignment (field_unit + operator)
        _api.get('/users?size=500&is_active=true'),
      ]);
      if (!mounted) return;
      final usersData = results[1] as Map<String, dynamic>?;
      final rawUsers = (usersData?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _teams = (results[0] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // Show all active users so commander can assign anyone to a team
        _allUsers = rawUsers;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DRDTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('TEAM MANAGEMENT', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: _loadData),
          IconButton(
            icon: const Icon(Icons.add, color: DRDTheme.successColor),
            tooltip: 'Create Team',
            onPressed: () => _showCreateTeamDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DRDTheme.primaryColor))
          : _teams.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: DRDTheme.primaryColor,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _teams.length,
                    itemBuilder: (_, i) => _teamCard(_teams[i]),
                  ),
                ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.group_off, color: Colors.white24, size: 48),
      const SizedBox(height: 12),
      const Text('No teams yet', style: TextStyle(color: Colors.white38, fontSize: 14)),
      const SizedBox(height: 8),
      ElevatedButton.icon(
        onPressed: _showCreateTeamDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create First Team'),
        style: ElevatedButton.styleFrom(backgroundColor: DRDTheme.primaryColor),
      ),
    ]),
  );

  Widget _teamCard(Map<String, dynamic> team) {
    final teamId = team['id'] as String? ?? '';
    final name = team['name'] as String? ?? 'Team';
    final code = team['code'] as String? ?? '';
    final colorHex = team['color'] as String? ?? '#3b82f6';
    final color = _hexColor(colorHex);
    final members = (team['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final memberCount = team['member_count'] as int? ?? members.length;
    final isExpanded = _expandedTeamId == teamId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: DRDTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expandedTeamId = isExpanded ? null : teamId),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18), border: Border.all(color: color, width: 2)),
                    child: Center(child: Text(code.isNotEmpty ? code[0] : name[0], style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('CODE: $code  ·  $memberCount members', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ])),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _iconBtn(Icons.person_add_outlined, Colors.white54, () => _showAddMemberDialog(teamId, name, members)),
                    _iconBtn(Icons.edit_outlined, Colors.white38, () => _showEditTeamDialog(team)),
                    _iconBtn(Icons.delete_outline, DRDTheme.dangerColor.withValues(alpha: 0.7), () => _confirmDelete(team)),
                  ]),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),

          // Members list (expanded)
          if (isExpanded) ...[
            Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No members assigned', style: TextStyle(color: Colors.white38, fontSize: 12)),
              )
            else
              ...members.map((m) => _memberTile(m, teamId, color)),
            // Add member button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: GestureDetector(
                onTap: () => _showAddMemberDialog(teamId, name, members),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.25), style: BorderStyle.solid),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.person_add_outlined, color: color, size: 14),
                    const SizedBox(width: 6),
                    Text('ADD MEMBER', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> m, String teamId, Color teamColor) {
    final userId = m['user_id']?.toString() ?? '';
    final name = m['user_name'] as String? ?? 'Unknown';
    final role = m['role'] as String? ?? 'support';
    final roleColors = {
      'lead': DRDTheme.warningColor, 'medic': DRDTheme.dangerColor,
      'scout': DRDTheme.infoColor, 'sniper': DRDTheme.accentColor,
      'support': Colors.white54,
    };
    final roleColor = roleColors[role] ?? Colors.white54;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: teamColor.withValues(alpha: 0.12), border: Border.all(color: teamColor.withValues(alpha: 0.4))),
            child: Center(child: Text(
              name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join(),
              style: TextStyle(color: teamColor, fontSize: 11, fontWeight: FontWeight.bold),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
              child: Text(role.toUpperCase(), style: TextStyle(color: roleColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ])),
          GestureDetector(
            onTap: () => _removeMember(teamId, userId, name),
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: DRDTheme.dangerColor.withValues(alpha: 0.1), shape: BoxShape.circle, border: Border.all(color: DRDTheme.dangerColor.withValues(alpha: 0.25))),
              child: const Icon(Icons.person_remove_outlined, color: DRDTheme.dangerColor, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => IconButton(
    icon: Icon(icon, color: color, size: 18),
    onPressed: onTap,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    padding: EdgeInsets.zero,
  );

  // ── Dialogs ──────────────────────────────────────────────────────────────────

  void _showCreateTeamDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String color = '#3b82f6';
    final presets = ['#22c55e', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#3b82f6', '#f97316', '#ec4899'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('Create Team', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _dialogField('Team Name', nameCtrl, 'Team Alpha'),
          const SizedBox(height: 10),
          _dialogField('Code', codeCtrl, 'ALPHA'),
          const SizedBox(height: 12),
          const Text('Team Color', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: presets.map((c) => GestureDetector(
            onTap: () => setSt(() => color = c),
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hexColor(c),
                border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2),
              ),
            ),
          )).toList()),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
              final nav = Navigator.of(ctx);
              await _api.post('/teams', {'name': nameCtrl.text.trim(), 'code': codeCtrl.text.trim().toUpperCase(), 'color': color});
              if (mounted) { nav.pop(); _loadData(); }
            },
            child: const Text('CREATE', style: TextStyle(color: DRDTheme.successColor, fontWeight: FontWeight.bold)),
          ),
        ],
      )),
    );
  }

  void _showEditTeamDialog(Map<String, dynamic> team) {
    final nameCtrl = TextEditingController(text: team['name'] as String? ?? '');
    final teamId = team['id']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('Edit Team', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: _dialogField('Team Name', nameCtrl, ''),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await _api.put('/teams/$teamId', {'name': nameCtrl.text.trim()});
              if (mounted) { nav.pop(); _loadData(); }
            },
            child: const Text('SAVE', style: TextStyle(color: DRDTheme.primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Role metadata used throughout the screen
  static const _roleInfo = {
    'field_unit':  {'label': 'Soldier',     'color': 0xFF22C55E, 'desc': 'Deployed soldier — GPS tracking, SOS, marks'},
    'operator':    {'label': 'Operator',    'color': 0xFF3B82F6, 'desc': 'Manages tasks, monitors missions'},
    'commander':   {'label': 'Commander',   'color': 0xFF8B5CF6, 'desc': 'Full control — routes, teams, broadcast'},
    'admin':       {'label': 'Admin',       'color': 0xFFF97316, 'desc': 'System admin — user management'},
    'super_admin': {'label': 'Super Admin', 'color': 0xFFEF4444, 'desc': 'All permissions'},
    'viewer':      {'label': 'Viewer',      'color': 0xFF94A3B8, 'desc': 'Read-only — cannot interact'},
  };

  void _showAddMemberDialog(String teamId, String teamName, List<Map<String, dynamic>> existing) {
    final existingIds = existing.map((m) => m['user_id']?.toString() ?? '').toSet();

    // Sort: soldiers first, then alphabetically
    final available = _allUsers
        .where((u) => !existingIds.contains(u['id']?.toString() ?? ''))
        .toList()
      ..sort((a, b) {
        final aIsField = (a['role'] ?? '') == 'field_unit' ? 0 : 1;
        final bIsField = (b['role'] ?? '') == 'field_unit' ? 0 : 1;
        if (aIsField != bIsField) return aIsField - bIsField;
        return (a['full_name'] ?? a['username'] ?? '').toString()
            .compareTo((b['full_name'] ?? b['username'] ?? '').toString());
      });

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All users are already in this team'),
          backgroundColor: DRDTheme.warningColor,
        ),
      );
      return;
    }

    String? selectedUserId;
    String selectedRole = 'support';
    String search = '';
    final roles = ['lead', 'medic', 'scout', 'support', 'sniper'];
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final filtered = available.where((u) {
            if (search.isEmpty) return true;
            final name = '${u['full_name'] ?? u['username'] ?? ''}'.toLowerCase();
            final role = '${u['role'] ?? ''}'.toLowerCase();
            return name.contains(search) || role.contains(search);
          }).toList();

          return AlertDialog(
            backgroundColor: DRDTheme.surfaceColor,
            contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add to $teamName',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${available.length} available',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (v) => setSt(() => search = v.toLowerCase()),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _inputDeco('Search by name or role…'),
                    ),
                  ),

                  // Count hint
                  if (search.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFF22C55E))),
                          const SizedBox(width: 6),
                          Text(
                            '${available.where((u) => u['role'] == 'field_unit').length} available soldiers  ·  ${available.length} total',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                    ),

                  // Soldier list
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No users match search', style: TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final u = filtered[i];
                              final uid = u['id']?.toString() ?? '';
                              final name = u['full_name'] as String? ?? u['username'] as String? ?? '—';
                              final role = u['role'] as String? ?? 'field_unit';
                              final info = _roleInfo[role] ?? _roleInfo['field_unit']!;
                              final roleColor = Color(info['color'] as int);
                              final isSelected = selectedUserId == uid;

                              return GestureDetector(
                                onTap: () => setSt(() => selectedUserId = uid),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? DRDTheme.primaryColor.withValues(alpha: 0.2)
                                        : DRDTheme.backgroundColor.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? DRDTheme.primaryColor : Colors.white.withValues(alpha: 0.06),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Avatar
                                      Container(
                                        width: 32, height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: roleColor.withValues(alpha: 0.15),
                                          border: Border.all(color: roleColor.withValues(alpha: 0.5)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
                                            style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Name + role
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isSelected ? Colors.white : Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: roleColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                (info['label'] as String).toUpperCase(),
                                                style: TextStyle(color: roleColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Selection indicator
                                      if (isSelected)
                                        const Icon(Icons.check_circle, color: DRDTheme.primaryColor, size: 18),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Team role picker
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ASSIGN ROLE IN TEAM', style: TextStyle(color: Colors.white38, fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6, runSpacing: 4,
                          children: roles.map((r) {
                            final isActive = selectedRole == r;
                            return GestureDetector(
                              onTap: () => setSt(() => selectedRole = r),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isActive ? DRDTheme.successColor.withValues(alpha: 0.2) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isActive ? DRDTheme.successColor : Colors.white24),
                                ),
                                child: Text(
                                  r.toUpperCase(),
                                  style: TextStyle(
                                    color: isActive ? DRDTheme.successColor : Colors.white38,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: DRDTheme.successColor),
                onPressed: selectedUserId == null
                    ? null
                    : () async {
                        final nav = Navigator.of(ctx);
                        await _api.post('/teams/$teamId/members', {
                          'user_id': selectedUserId,
                          'role': selectedRole,
                        });
                        if (mounted) {
                          nav.pop();
                          _loadData();
                        }
                      },
                child: const Text('ADD TO TEAM', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _removeMember(String teamId, String userId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('Remove Member', style: TextStyle(color: Colors.white, fontSize: 14)),
        content: Text('Remove $name from this team?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('REMOVE', style: TextStyle(color: DRDTheme.dangerColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm == true) {
      await _api.delete('/teams/$teamId/members/$userId');
      _loadData();
    }
  }

  void _confirmDelete(Map<String, dynamic> team) async {
    final name = team['name'] as String? ?? 'this team';
    final id = team['id']?.toString() ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DRDTheme.surfaceColor,
        title: const Text('Delete Team', style: TextStyle(color: DRDTheme.dangerColor, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Text('Delete "$name"? This cannot be undone.', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('DELETE', style: TextStyle(color: DRDTheme.dangerColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm == true) {
      await _api.delete('/teams/$id');
      _loadData();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _dialogField(String label, TextEditingController ctrl, String hint) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: _inputDeco(label).copyWith(hintText: hint),
  );

  InputDecoration _inputDeco(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white38, fontSize: 11),
    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
    filled: true,
    fillColor: DRDTheme.backgroundColor.withValues(alpha: 0.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: DRDTheme.primaryColor)),
  );

  Color _hexColor(String? v) {
    if (v != null && v.startsWith('#')) {
      try { return Color(int.parse(v.replaceFirst('#', '0xFF'))); } catch (_) {}
    }
    return DRDTheme.primaryColor;
  }
}
