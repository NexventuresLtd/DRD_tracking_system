import 'package:flutter/material.dart';
import '../services/api_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class NotifData {
  final String id;
  final String type;
  final String title;
  final String? body;
  final bool isRead;
  final String priority;
  final DateTime createdAt;

  const NotifData({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    required this.isRead,
    required this.priority,
    required this.createdAt,
  });

  NotifData copyWith({bool? isRead}) => NotifData(
        id: id,
        type: type,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        priority: priority,
        createdAt: createdAt,
      );

  factory NotifData.fromJson(Map<String, dynamic> j) => NotifData(
        id: j['id']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString(),
        isRead: j['is_read'] == true,
        priority: j['priority']?.toString() ?? 'normal',
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotifData> _notifs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await ApiService().get('/notifications');
      final list = raw is List ? raw : [];
      final parsed = <NotifData>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          try {
            parsed.add(NotifData.fromJson(item));
          } catch (_) {}
        }
      }
      if (mounted) setState(() { _notifs = parsed; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _markRead(String id) async {
    ApiService().put('/notifications/$id/read', {}).catchError((_) => <String, dynamic>{});
    setState(() {
      _notifs = _notifs.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList();
    });
  }

  Future<void> _markAllRead() async {
    ApiService().put('/notifications/read-all', {}).catchError((_) => <String, dynamic>{});
    setState(() {
      _notifs = _notifs.map((n) => n.copyWith(isRead: true)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (unread > 0)
              Text(
                '$unread unread',
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11),
              ),
          ],
        ),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF9CA3AF)),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F2937)),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, color: Color(0xFF374151), size: 56),
            SizedBox(height: 12),
            Text('No notifications', style: TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF22C55E),
      backgroundColor: const Color(0xFF1F2937),
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _notifs.length,
        itemBuilder: (_, i) => _NotifCard(
          notif: _notifs[i],
          onTap: () { if (!_notifs[i].isRead) _markRead(_notifs[i].id); },
        ),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  final NotifData notif;
  final VoidCallback onTap;

  const _NotifCard({required this.notif, required this.onTap});

  Color get _accentColor {
    switch (notif.priority) {
      case 'critical': return const Color(0xFFEF4444);
      case 'high':     return const Color(0xFFF97316);
      case 'low':      return const Color(0xFF6B7280);
      default:         return const Color(0xFF3B82F6);
    }
  }

  IconData get _icon {
    switch (notif.type) {
      case 'sos_alert':
      case 'sos_acknowledged': return Icons.emergency;
      case 'mission_assigned':
      case 'mission_updated':
      case 'mission_completed':
      case 'mission_approved': return Icons.assignment;
      case 'new_message':      return Icons.chat_bubble;
      case 'team_joined':
      case 'team_updated':     return Icons.group;
      case 'live_session_invite': return Icons.videocam;
      default:                 return Icons.notifications;
    }
  }

  String get _fallbackTitle {
    switch (notif.type) {
      case 'mission_assigned':  return 'Mission Assigned';
      case 'mission_updated':   return 'Mission Updated';
      case 'mission_completed': return 'Mission Completed';
      case 'mission_approved':  return 'Mission Approved';
      case 'sos_alert':         return 'SOS Alert';
      case 'sos_acknowledged':  return 'SOS Acknowledged';
      case 'new_message':       return 'New Message';
      case 'team_joined':       return 'Team Update';
      case 'live_session_invite': return 'Live Session Invite';
      default:                  return 'Notification';
    }
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1)   return '${diff.inMinutes}m ago';
    if (diff.inDays < 1)    return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final title = notif.title.isNotEmpty ? notif.title : _fallbackTitle;
    final accent = _accentColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: notif.isRead ? const Color(0xFF111827) : const Color(0xFF1A2744),
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: accent, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: accent, size: 20),
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
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (!notif.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8, top: 2),
                            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    if (notif.body != null && notif.body!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notif.body!,
                        style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _formatDate(notif.createdAt),
                      style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
