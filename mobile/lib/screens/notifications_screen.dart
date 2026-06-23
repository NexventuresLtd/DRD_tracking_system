import 'package:flutter/material.dart';
import '../services/api_service.dart';

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

  factory NotifData.fromJson(Map<String, dynamic> j) => NotifData(
        id: j['id'] as String,
        type: j['type'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        isRead: j['is_read'] as bool? ?? false,
        priority: j['priority'] as String? ?? 'normal',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

const _priorityColors = {
  'critical': Color(0xFFEF4444),
  'high':     Color(0xFFF97316),
  'normal':   Color(0xFF3B82F6),
  'low':      Color(0xFF6B7280),
};

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotifData> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService().get('/notifications') as List<dynamic>;
      if (!mounted) return;
      setState(() => _notifs = data.map((e) => NotifData.fromJson(e as Map<String, dynamic>)).toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _markRead(String id) async {
    await ApiService().put('/notifications/$id/read', {}).catchError((_) => <String, dynamic>{});
    setState(() => _notifs = _notifs.map((n) => n.id == id ? NotifData(id: n.id, type: n.type, title: n.title, body: n.body, isRead: true, priority: n.priority, createdAt: n.createdAt) : n).toList());
  }

  Future<void> _markAllRead() async {
    await ApiService().put('/notifications/read-all', {}).catchError((_) => <String, dynamic>{});
    setState(() => _notifs = _notifs.map((n) => NotifData(id: n.id, type: n.type, title: n.title, body: n.body, isRead: true, priority: n.priority, createdAt: n.createdAt)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => !n.isRead).length;
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications', style: TextStyle(color: Colors.white, fontSize: 16)),
            if (unread > 0)
              Text('$unread unread', style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
            ),
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF9CA3AF)), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _notifs.isEmpty
              ? const Center(child: Text('No notifications', style: TextStyle(color: Color(0xFF6B7280))))
              : RefreshIndicator(
                  color: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFF1F2937),
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _notifs.length,
                    itemBuilder: (_, i) {
                      final n = _notifs[i];
                      final color = _priorityColors[n.priority] ?? _priorityColors['normal']!;
                      return GestureDetector(
                        onTap: () => !n.isRead ? _markRead(n.id) : null,
                        child: Opacity(
                          opacity: n.isRead ? 0.5 : 1.0,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border(
                                left: BorderSide(color: color, width: 3),
                                top: const BorderSide(color: Color(0xFF1F2937)),
                                right: const BorderSide(color: Color(0xFF1F2937)),
                                bottom: const BorderSide(color: Color(0xFF1F2937)),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  n.isRead ? Icons.circle_outlined : Icons.circle,
                                  color: n.isRead ? const Color(0xFF374151) : color,
                                  size: 10,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n.title, style: TextStyle(color: n.isRead ? const Color(0xFF9CA3AF) : Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                      if (n.body != null) ...[
                                        const SizedBox(height: 3),
                                        Text(n.body!, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDate(n.createdAt),
                                        style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
