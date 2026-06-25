import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../config/environment.dart';

// ── Role permissions map ───────────────────────────────────────────────────────
const _rolePermissions = {
  'operations_coordinator': [
    'Full system administration',
    'Create & manage missions',
    'Add & manage facilities',
    'Create & assign zones',
    'View all personnel locations',
    'Issue briefings & notifications',
    'Access analytics & reports',
  ],
  'planning_officer': [
    'Create & manage missions',
    'Add facilities (if granted)',
    'Create & assign zones',
    'View team locations',
    'Issue briefings',
  ],
  'team_leader': [
    'Manage team members',
    'View assigned zones & missions',
    'Assign zone points to members',
    'Access team comms',
    'Submit patrol reports',
  ],
  'field_user': [
    'View assigned zone & route',
    'Submit location updates',
    'Send patrol reports',
    'Access global & team comms',
    'Trigger SOS alert',
  ],
};

const _roleColors = {
  'operations_coordinator': Color(0xFFEF4444),
  'planning_officer':       Color(0xFFF59E0B),
  'team_leader':            Color(0xFF22C55E),
  'field_user':             Color(0xFF4ADE80),
};

const _roleLabels = {
  'operations_coordinator': 'COORDINATOR',
  'planning_officer':       'PLANNING OFFICER',
  'team_leader':            'TEAM LEADER',
  'field_user':             'FIELD USER',
};

// ── Main screen ───────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, User?>((a) => a.user);
    final roleColor = _roleColors[user?.role.apiValue] ?? const Color(0xFF22C55E);
    final roleLabel = _roleLabels[user?.role.apiValue] ?? (user?.role.apiValue.toUpperCase() ?? '');

    return Scaffold(
      backgroundColor: const Color(0xFF030903),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060D06),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF9CA3AF)),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFF16A34A),
          labelColor: const Color(0xFF22C55E),
          unselectedLabelColor: const Color(0xFF4B5563),
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
          tabs: const [
            Tab(text: 'PROFILE'),
            Tab(text: 'SECURITY'),
            Tab(text: 'PERMISSIONS'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Identity card (always visible)
          _IdentityCard(user: user, roleColor: roleColor, roleLabel: roleLabel),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _ProfileTab(user: user),
                const _SecurityTab(),
                _PermissionsTab(user: user, roleColor: roleColor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Identity card ─────────────────────────────────────────────────────────────

class _IdentityCard extends StatefulWidget {
  final User? user;
  final Color roleColor;
  final String roleLabel;

  const _IdentityCard({this.user, required this.roleColor, required this.roleLabel});

  @override
  State<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends State<_IdentityCard> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 512);
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final auth = context.read<AuthProvider>();
      final result = await ApiService().uploadFile(
        '/users/${auth.user!.id}/avatar',
        File(picked.path),
        'file',
      );
      final rawUrl = result['avatar_url'] as String?;
      if (rawUrl != null && mounted) {
        await auth.updateUser(auth.user!.copyWith(avatarUrl: EnvironmentConfig.resolveUrl(rawUrl)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to upload photo'),
          backgroundColor: Color(0xFF7F1D1D),
        ));
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final roleColor = widget.roleColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF060D06),
        border: Border(bottom: BorderSide(color: Color(0xFF0A1F0A))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploading ? null : _pickAndUpload,
            child: Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: roleColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: _uploading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22C55E)),
                        )
                      : ClipOval(
                          child: user?.avatarUrl != null
                              ? Image.network(EnvironmentConfig.resolveUrl(user!.avatarUrl!), fit: BoxFit.cover, errorBuilder: (_, __, st) => _initials(user, roleColor))
                              : _initials(user, roleColor),
                        ),
                ),
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.fullName ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text('@${user?.username ?? ''}', style: const TextStyle(color: Color(0xFF4B5563), fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.16),
              border: Border.all(color: roleColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              widget.roleLabel,
              style: TextStyle(
                color: roleColor,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials(User? user, Color color) => Center(
    child: Text(
      user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : '?',
      style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold),
    ),
  );
}

// ── Profile tab ───────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  final User? user;
  const _ProfileTab({this.user});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.user?.fullName ?? '';
    _phoneCtrl.text = widget.user?.phone ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final auth = context.read<AuthProvider>();
      final data = await ApiService().get('/users/${auth.user!.id}');
      await auth.updateUser(User.fromJson(data as Map<String, dynamic>));
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      final data = await ApiService().put('/users/${auth.user!.id}', {
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      await auth.updateUser(User.fromJson(data));
      if (mounted) setState(() => _editing = false);
      if (mounted) _showSnack('Profile updated', success: true);
    } catch (_) {
      if (mounted) _showSnack('Failed to update profile');
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF060D06),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Color(0xFF7F1D1D))),
        title: const Text('Disconnect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Color(0xFF9CA3AF))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await auth.logout();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: success ? const Color(0xFF16A34A) : const Color(0xFF7F1D1D),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, User?>((a) => a.user);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF22C55E),
      backgroundColor: const Color(0xFF060D06),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Section(
              title: 'Account Details',
            trailing: _editing
                ? _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22C55E)))
                    : TextButton(onPressed: _save, child: const Text('SAVE', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)))
                : TextButton(onPressed: () => setState(() => _editing = true), child: const Text('EDIT', style: TextStyle(color: Color(0xFF4B5563), fontSize: 12, letterSpacing: 1))),
            children: [
              _InfoRow(label: 'Email', value: user?.email ?? '—'),
              if (_editing) ...[
                const SizedBox(height: 8),
                _EditField(controller: _nameCtrl, label: 'Full Name'),
                const SizedBox(height: 10),
                _EditField(controller: _phoneCtrl, label: 'Phone', keyboardType: TextInputType.phone),
              ] else ...[
                _InfoRow(label: 'Full Name', value: user?.fullName ?? '—'),
                _InfoRow(label: 'Phone', value: user?.phone?.isNotEmpty == true ? user!.phone! : 'Not set'),
              ],
              _InfoRow(label: 'Status', value: user?.isActive == true ? '● Active' : '○ Inactive', valueColor: user?.isActive == true ? const Color(0xFF22C55E) : const Color(0xFF6B7280)),
              _InfoRow(label: 'Verified', value: user?.isVerified == true ? 'Yes' : 'No'),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Notification Preferences',
            children: const [
              _TogglePref(label: 'Mission Briefings', desc: 'Receive mission assignment notifications', initialValue: true),
              _TogglePref(label: 'Zone Assignments', desc: 'Updates when assigned to patrol zones', initialValue: true),
              _TogglePref(label: 'SOS Alerts', desc: 'Critical distress alerts from team', initialValue: true),
              _TogglePref(label: 'Team Messages', desc: 'New messages in team channels', initialValue: false),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Color(0xFFEF4444), size: 18),
              label: const Text('Disconnect', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF7F1D1D)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
    );
  }
}

// ── Security tab ──────────────────────────────────────────────────────────────

class _SecurityTab extends StatefulWidget {
  const _SecurityTab();

  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    setState(() { _error = null; _success = false; });

    if (_newCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      await ApiService().post('/users/${auth.user!.id}/change-password', {
        'current_password': _currentCtrl.text,
        'new_password': _newCtrl.text,
      });
      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
      if (mounted) setState(() => _success = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed. Check current password.');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _Section(
            title: 'Change Password',
            children: [
              if (_success) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF052E16),
                    border: Border.all(color: const Color(0x6616A34A)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 18),
                      SizedBox(width: 10),
                      Text('Password updated successfully', style: TextStyle(color: Color(0xFF22C55E), fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x337F1D1D),
                    border: Border.all(color: const Color(0x667F1D1D)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12)),
                ),
              ],
              _PasswordField(controller: _currentCtrl, label: 'Current Password', show: _showCurrent, onToggle: () => setState(() => _showCurrent = !_showCurrent)),
              const SizedBox(height: 12),
              _PasswordField(controller: _newCtrl, label: 'New Password', show: _showNew, onToggle: () => setState(() => _showNew = !_showNew)),
              const SizedBox(height: 12),
              _PasswordField(controller: _confirmCtrl, label: 'Confirm New Password', show: _showNew, onToggle: null),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _loading ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    disabledBackgroundColor: const Color(0xFF374151),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('UPDATE PASSWORD', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Security Status',
            children: [
              _InfoRow(label: '2FA / OTP', value: '● Active', valueColor: const Color(0xFF22C55E)),
              _InfoRow(label: 'Session', value: 'Authenticated'),
              _InfoRow(label: 'Channel', value: 'TLS Encrypted', valueColor: const Color(0xFF22C55E)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Permissions tab ───────────────────────────────────────────────────────────

class _PermissionsTab extends StatelessWidget {
  final User? user;
  final Color roleColor;

  const _PermissionsTab({this.user, required this.roleColor});

  @override
  Widget build(BuildContext context) {
    final perms = _rolePermissions[user?.role.apiValue ?? 'field_user'] ?? [];
    final roleLabel = _roleLabels[user?.role.apiValue] ?? (user?.role.displayName ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.12),
              border: Border.all(color: roleColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CURRENT ACCESS LEVEL', style: TextStyle(color: roleColor.withValues(alpha: 0.6), fontSize: 8, letterSpacing: 3, fontFamily: 'monospace')),
                const SizedBox(height: 6),
                Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Granted Permissions',
            children: perms.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: roleColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p, style: const TextStyle(color: Color(0xFFD1FAE5), fontSize: 13)),
                  ),
                ],
              ),
            )).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF030903),
              border: Border(left: BorderSide(color: Color(0xFF16A34A), width: 2)),
            ),
            child: const Text(
              'Contact your operations coordinator to request elevated access.',
              style: TextStyle(color: Color(0xFF4B5563), fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  const _Section({required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF060D06),
        border: Border.all(color: const Color(0xFF0A1F0A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                trailing ?? const SizedBox.shrink(),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF0A1F0A)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          Text(value, style: TextStyle(color: valueColor ?? const Color(0xFFD1D5DB), fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  const _EditField({required this.controller, required this.label, this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            filled: true, fillColor: const Color(0xFF040804),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF1F2D1F))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF1F2D1F))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF16A34A))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool show;
  final VoidCallback? onToggle;

  const _PasswordField({required this.controller, required this.label, required this.show, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: !show,
          style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2),
          decoration: InputDecoration(
            filled: true, fillColor: const Color(0xFF040804),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF1F2D1F))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF1F2D1F))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFF16A34A))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: onToggle != null
                ? IconButton(
                    icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFF4B5563), size: 18),
                    onPressed: onToggle,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _TogglePref extends StatefulWidget {
  final String label;
  final String desc;
  final bool initialValue;

  const _TogglePref({required this.label, required this.desc, required this.initialValue});

  @override
  State<_TogglePref> createState() => _TogglePrefState();
}

class _TogglePrefState extends State<_TogglePref> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
                Text(widget.desc, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: _value,
            onChanged: (v) => setState(() => _value = v),
            activeThumbColor: const Color(0xFF16A34A),
            activeTrackColor: const Color(0xFF052E16),
            inactiveThumbColor: const Color(0xFF374151),
            inactiveTrackColor: const Color(0xFF111827),
          ),
        ],
      ),
    );
  }
}
