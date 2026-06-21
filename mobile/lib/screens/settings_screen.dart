import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  Map<String, PermissionStatus> _statuses = {};
  bool _loading = true;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check permissions when returning from system settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final s = await _statusAllPermissions();
    if (mounted) setState(() { _statuses = s; _loading = false; });
  }

  static Future<Map<String, PermissionStatus>> _statusAllPermissions() async {
    return {
      'locationAlways': await Permission.locationAlways.status,
      'locationWhenInUse': await Permission.locationWhenInUse.status,
      'camera': await Permission.camera.status,
      'microphone': await Permission.microphone.status,
      'photos': await Permission.photos.status,
      'notification': await Permission.notification.status,
    };
  }

  Future<void> _request(Permission perm) async {
    final status = await perm.request();
    if (mounted && (status.isPermanentlyDenied || status.isDenied)) {
      await openAppSettings();
    }
    await _refresh();
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final api = ApiService();
      final result = await api.uploadAvatar(picked.path);
      if (result != null && result['profile_picture_url'] != null && mounted) {
        await context.read<AuthProvider>().loadUserInfo();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo updated'), backgroundColor: Color(0xFF16A34A)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  static const _permDefs = [
    {
      'key': 'locationAlways',
      'icon': Icons.gps_fixed,
      'title': 'GPS — Always On',
      'desc': 'Required to send your coordinates to command while the app is in the background.',
      'perm': Permission.locationAlways,
      'critical': true,
    },
    {
      'key': 'locationWhenInUse',
      'icon': Icons.location_on_outlined,
      'title': 'GPS — While In Use',
      'desc': 'Basic location access needed when the app is open.',
      'perm': Permission.locationWhenInUse,
      'critical': true,
    },
    {
      'key': 'camera',
      'icon': Icons.camera_alt_outlined,
      'title': 'Camera',
      'desc': 'Capture evidence photos and stream live video to command.',
      'perm': Permission.camera,
      'critical': false,
    },
    {
      'key': 'microphone',
      'icon': Icons.mic_none_rounded,
      'title': 'Microphone',
      'desc': 'Audio in live feed broadcasts to command.',
      'perm': Permission.microphone,
      'critical': false,
    },
    {
      'key': 'photos',
      'icon': Icons.photo_library_outlined,
      'title': 'Photo Library',
      'desc': 'Attach existing photos as field evidence.',
      'perm': Permission.photos,
      'critical': false,
    },
    {
      'key': 'notification',
      'icon': Icons.notifications_outlined,
      'title': 'Notifications',
      'desc': 'Receive alerts, messages, and incoming route assignments from command.',
      'perm': Permission.notification,
      'critical': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final granted = _statuses.values.where((s) => s.isGranted).length;
    final total = _statuses.length;

    return Scaffold(
      backgroundColor: const Color(0xFF060D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF94A3B8)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.settings_outlined, size: 16, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(width: 10),
            const Text(
              'SETTINGS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF64748B)),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1E293B)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF3B82F6),
                strokeWidth: 2,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                // Profile section
                _buildProfileSection(context),
                const SizedBox(height: 24),

                // Status summary banner
                _buildSummaryCard(granted, total),
                const SizedBox(height: 24),

                // Section header
                _sectionHeader('PERMISSIONS', Icons.lock_outline),
                const SizedBox(height: 12),

                // Permission cards
                ..._permDefs.map((def) {
                  // Skip photos on Android — use storage/media instead
                  if (Platform.isAndroid && def['key'] == 'photos') return const SizedBox.shrink();
                  final status = _statuses[def['key'] as String];
                  return _PermissionCard(
                    icon: def['icon'] as IconData,
                    title: def['title'] as String,
                    desc: def['desc'] as String,
                    critical: def['critical'] as bool,
                    status: status,
                    onFix: () => _request(def['perm'] as Permission),
                  );
                }),

                const SizedBox(height: 24),
                _sectionHeader('APPLICATION', Icons.info_outline),
                const SizedBox(height: 12),
                _AppInfoCard(),

                const SizedBox(height: 24),
                _sectionHeader('TROUBLESHOOTING', Icons.build_circle_outlined),
                const SizedBox(height: 12),
                _buildTroubleshootRow(
                  icon: Icons.settings_applications_outlined,
                  label: 'Open App System Settings',
                  desc: 'Manually review all permissions in device settings',
                  onTap: () => openAppSettings(),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final photoUrl = user?.profilePictureUrl;
    final name = user?.fullName.isNotEmpty == true ? user!.fullName : (user?.username ?? 'User');
    final initials = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showPhotoPicker(context),
            child: Stack(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF3B82F6), width: 2),
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(photoUrl, fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => _initialsAvatar(initials))
                        : _initialsAvatar(initials),
                  ),
                ),
                if (_uploadingPhoto)
                  Positioned.fill(child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                    child: const Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
                  )),
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
                Text(
                  (user?.role ?? '').toUpperCase().replaceAll('_', ' '),
                  style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2, fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _showPhotoPicker(context),
                  child: const Text('CHANGE PHOTO', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontFamily: 'Poppins')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(String initials) => Container(
    color: const Color(0xFF1E3A5F),
    alignment: Alignment.center,
    child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
  );

  void _showPhotoPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3B82F6)),
                title: const Text('Take Photo', style: TextStyle(color: Colors.white, fontFamily: 'Poppins')),
                onTap: () { Navigator.pop(context); _pickAndUploadPhoto(ImageSource.camera); },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF3B82F6)),
                title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white, fontFamily: 'Poppins')),
                onTap: () { Navigator.pop(context); _pickAndUploadPhoto(ImageSource.gallery); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(int granted, int total) {
    final allGood = granted == total;
    final color = allGood ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              allGood ? Icons.verified_outlined : Icons.warning_amber_outlined,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allGood ? 'All Systems Authorized' : 'Action Required',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$granted of $total permissions granted',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
          // Progress arc
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: total > 0 ? granted / total : 0,
                  strokeWidth: 3,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '$granted/$total',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 13, color: const Color(0xFF475569)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF475569),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: const Color(0xFF1E293B))),
      ],
    );
  }

  Widget _buildTroubleshootRow({
    required IconData icon,
    required String label,
    required String desc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1C2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF64748B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins')),
                  Text(desc,
                      style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                          fontFamily: 'Poppins')),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF475569)),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool critical;
  final PermissionStatus? status;
  final VoidCallback onFix;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.critical,
    required this.status,
    required this.onFix,
  });

  @override
  Widget build(BuildContext context) {
    final granted = status?.isGranted ?? false;
    final statusColor = granted ? const Color(0xFF22C55E) : (critical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
    final statusLabel = granted ? 'GRANTED' : (status?.isPermanentlyDenied == true ? 'BLOCKED' : 'DENIED');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: granted ? const Color(0xFF1E293B) : statusColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (granted ? const Color(0xFF22C55E) : const Color(0xFF475569)).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18,
                color: granted ? const Color(0xFF22C55E) : const Color(0xFF64748B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                    if (critical && !granted)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('CRITICAL',
                            style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Poppins',
                                letterSpacing: 0.5)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 10, fontFamily: 'Poppins')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            granted ? Icons.check_circle_outline : Icons.cancel_outlined,
                            size: 9,
                            color: statusColor,
                          ),
                          const SizedBox(width: 3),
                          Text(statusLabel,
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Poppins',
                                  letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (!granted)
                      GestureDetector(
                        onTap: onFix,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'FIX',
                            style: TextStyle(
                              color: Color(0xFF3B82F6),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                              letterSpacing: 0.5,
                            ),
                          ),
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
  }
}

class _AppInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          _infoRow('Application', 'DRD Field Coordination System'),
          _infoRow('Platform', Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS' : 'Other'),
          _infoRow('Background GPS', Platform.isAndroid ? 'Foreground Service' : 'Always Allow'),
          _infoRow('Location Interval', '5 seconds (heartbeat)'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontFamily: 'Poppins')),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
  }
}
