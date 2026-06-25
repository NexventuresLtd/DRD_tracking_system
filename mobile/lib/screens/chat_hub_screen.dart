import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/auth_provider.dart';
import '../providers/team_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../config/environment.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String content;
  final String senderId;
  final String? senderName;
  final DateTime sentAt;
  final String messageType; // "text" | "image"

  const ChatMessage({
    required this.id,
    required this.content,
    required this.senderId,
    this.senderName,
    required this.sentAt,
    this.messageType = 'text',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final sender = j['sender'] as Map<String, dynamic>?;
    return ChatMessage(
      id: j['id'] as String,
      content: j['content'] as String,
      senderId: j['sender_id'] as String,
      senderName: sender?['full_name'] as String? ?? sender?['username'] as String?,
      sentAt: DateTime.tryParse(j['sent_at'] as String? ?? j['created_at'] as String? ?? '') ?? DateTime.now(),
      messageType: j['message_type'] as String? ?? 'text',
    );
  }
}

class _ChannelMeta {
  final String type;       // "global" | "team" | "dm"
  final String id;         // channel id
  final String name;
  final String? lastContent;
  final String? lastSender;
  final DateTime? lastAt;
  final int unreadCount;

  const _ChannelMeta({
    required this.type,
    required this.id,
    required this.name,
    this.lastContent,
    this.lastSender,
    this.lastAt,
    this.unreadCount = 0,
  });

  factory _ChannelMeta.fromJson(Map<String, dynamic> j) {
    final last = j['last_message'] as Map<String, dynamic>?;
    return _ChannelMeta(
      type: j['type'] as String? ?? 'global',
      id: j['id'] as String,
      name: j['name'] as String,
      lastContent: last?['content'] as String?,
      lastSender: last?['sender_name'] as String?,
      lastAt: last != null ? DateTime.tryParse(last['sent_at'] as String? ?? '') : null,
      unreadCount: j['unread_count'] as int? ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main screen: channel list (WhatsApp-home style) → taps into chat view
// ─────────────────────────────────────────────────────────────────────────────

class ChatHubScreen extends StatefulWidget {
  const ChatHubScreen({super.key});

  @override
  State<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends State<ChatHubScreen> {
  // null = showing channel list; non-null = inside a channel chat
  _ChannelMeta? _activeChannel;

  List<_ChannelMeta> _channelMetas = [];
  bool _metaLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    setState(() => _metaLoading = true);
    try {
      final data = await ApiService().get('/messages/channels-meta');
      if (data is List) {
        setState(() {
          _channelMetas = data
              .map((e) => _ChannelMeta.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {
      // fall back gracefully — channels will show without meta
    } finally {
      if (mounted) setState(() => _metaLoading = false);
    }
  }

  // Build channel list from provider data + any server-provided meta
  List<_ChannelMeta> _buildChannels(List<TeamData> teams) {
    // Start with what server gave us (or defaults)
    final Map<String, _ChannelMeta> byId = {
      for (final m in _channelMetas) m.id: m,
    };

    final channels = <_ChannelMeta>[];

    // Global channel
    channels.add(byId['global'] ?? const _ChannelMeta(type: 'global', id: 'global', name: 'Global Channel'));

    // Emergency channel
    channels.add(byId['emergency'] ?? const _ChannelMeta(type: 'global', id: 'emergency', name: 'Emergency'));

    // Team channels
    for (final team in teams) {
      final channelId = 'team:${team.id}';
      channels.add(byId[channelId] ?? _ChannelMeta(type: 'team', id: channelId, name: team.name));
    }

    return channels;
  }

  void _openChannel(_ChannelMeta meta) {
    setState(() => _activeChannel = meta);
  }

  void _goBack() {
    setState(() => _activeChannel = null);
    _loadMeta(); // refresh unread counts
  }

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamProvider>().teams;

    if (_activeChannel != null) {
      return _ChatView(
        channel: _activeChannel!,
        onBack: _goBack,
      );
    }

    // Channel list view
    final channels = _buildChannels(teams);

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Comms', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF9CA3AF)),
            onPressed: _loadMeta,
          ),
        ],
      ),
      body: _metaLoading && _channelMetas.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : RefreshIndicator(
              color: const Color(0xFF2563EB),
              backgroundColor: const Color(0xFF1F2937),
              onRefresh: _loadMeta,
              child: ListView(
              children: [
                // Channels section
                _SectionHeader(label: 'Channels'),
                ...channels.map((ch) => _ChannelTile(
                      channel: ch,
                      onTap: () => _openChannel(ch),
                    )),

                // People / DM section
                if (teams.isNotEmpty) ...[
                  _SectionHeader(label: 'People'),
                  _buildTeamMemberSection(teams),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildTeamMemberSection(List<TeamData> teams) {
    // For now show team names as DM entry points
    // Real implementation would fetch team members
    return _TeamMembersDM(teams: teams, onOpenDM: _openChannel);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team members DM widget (fetches members per team)
// ─────────────────────────────────────────────────────────────────────────────

class _TeamMembersDM extends StatefulWidget {
  final List<TeamData> teams;
  final void Function(_ChannelMeta) onOpenDM;

  const _TeamMembersDM({required this.teams, required this.onOpenDM});

  @override
  State<_TeamMembersDM> createState() => _TeamMembersDMState();
}

class _TeamMembersDMState extends State<_TeamMembersDM> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = false;
  bool _expanded = false;

  Future<void> _loadMembers() async {
    if (widget.teams.isEmpty) return;
    setState(() => _loading = true);
    final seen = <String>{};
    final all = <Map<String, dynamic>>[];
    for (final team in widget.teams) {
      try {
        final data = await ApiService().get('/teams/${team.id}/members');
        if (data is List) {
          for (final m in data) {
            final member = m as Map<String, dynamic>;
            final userId = member['user_id'] as String? ?? member['id'] as String?;
            if (userId != null && !seen.contains(userId)) {
              seen.add(userId);
              all.add(member);
            }
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() { _members = all; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded && _members.isEmpty) _loadMembers();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.people_outline, color: Color(0xFF6B7280), size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Team Members', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF6B7280),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: Color(0xFF2563EB), strokeWidth: 2),
            )
          else if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No members found', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
            )
          else
            ..._members.map((m) {
              final userId = m['user_id'] as String? ?? m['id'] as String? ?? '';
              final userName = m['full_name'] as String? ?? m['username'] as String? ?? 'User';
              final myId = context.read<AuthProvider>().user?.id ?? '';
              if (userId == myId) return const SizedBox.shrink();
              return _ChannelTile(
                channel: _ChannelMeta(
                  type: 'dm',
                  id: 'dm:$userId',
                  name: userName,
                ),
                onTap: () => widget.onOpenDM(_ChannelMeta(
                  type: 'dm',
                  id: 'dm:$userId',
                  name: userName,
                )),
              );
            }),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Channel tile
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelTile extends StatelessWidget {
  final _ChannelMeta channel;
  final VoidCallback onTap;

  const _ChannelTile({required this.channel, required this.onTap});

  IconData get _icon {
    switch (channel.type) {
      case 'dm':
        return Icons.person_outline;
      case 'team':
        return Icons.people_outline;
      default:
        return Icons.public;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = channel.unreadCount > 0;
    final subtitle = channel.lastContent != null
        ? (channel.lastSender != null ? '${channel.lastSender}: ${channel.lastContent}' : channel.lastContent!)
        : 'No messages yet';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF111827), width: 0.5)),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _avatarColor(channel.type),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: hasUnread ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right column: time + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (channel.lastAt != null)
                  Text(
                    _formatDate(channel.lastAt!),
                    style: TextStyle(
                      color: hasUnread ? const Color(0xFF2563EB) : const Color(0xFF6B7280),
                      fontSize: 11,
                    ),
                  ),
                const SizedBox(height: 4),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      channel.unreadCount > 99 ? '99+' : '${channel.unreadCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _avatarColor(String type) {
    switch (type) {
      case 'dm':
        return const Color(0xFF7C3AED);
      case 'team':
        return const Color(0xFF1D4ED8);
      default:
        return const Color(0xFF065F46);
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    if (msgDay == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (today.difference(msgDay).inDays == 1) {
      return 'Yesterday';
    }
    return '${dt.day}/${dt.month}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat view (full-screen within the navigator stack)
// ─────────────────────────────────────────────────────────────────────────────

class _ChatView extends StatefulWidget {
  final _ChannelMeta channel;
  final VoidCallback onBack;

  const _ChatView({required this.channel, required this.onBack});

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();

  // Dedicated per-chat WebSocket (not the app-wide singleton)
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  Timer? _wsReconnectTimer;

  List<ChatMessage> _messages = [];
  bool _loading = false;
  bool _sending = false;

  String get _channelId => widget.channel.id;
  String get _postChannel => _channelId;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectWS();
  }

  @override
  void dispose() {
    _wsReconnectTimer?.cancel();
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final encodedId = Uri.encodeComponent(_channelId);
      final data = await ApiService().get('/messages/channels/$encodedId') as List<dynamic>;
      setState(() {
        _messages = data
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
      // show empty state
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _connectWS() {
    _wsReconnectTimer?.cancel();
    _wsSub?.cancel();
    _wsChannel?.sink.close();

    final token = StorageService().accessToken;
    if (token == null) return;

    final wsBase = EnvironmentConfig.wsBaseUrl;
    final encodedChannel = Uri.encodeComponent(_channelId);
    final uri = Uri.parse('$wsBase/ws/messages/$encodedChannel?token=${Uri.encodeComponent(token)}');

    try {
      _wsChannel = WebSocketChannel.connect(uri);
      _wsSub = _wsChannel!.stream.listen(
        _onWsData,
        onDone: _scheduleWsReconnect,
        onError: (_) => _scheduleWsReconnect(),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleWsReconnect();
    }
  }

  void _scheduleWsReconnect() {
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _connectWS();
    });
  }

  void _onWsData(dynamic data) {
    if (!mounted) return;
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      if (msg['type'] == 'new_message') {
        _onWsMessage(msg);
      }
    } catch (_) {}
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final raw = (msg['message'] ?? msg) as Map<String, dynamic>?;
    if (raw == null || !raw.containsKey('id')) return;
    final incomingId = raw['id'] as String?;
    // Deduplicate — sender receives their own message back from the server
    if (incomingId != null && _messages.any((m) => m.id == incomingId)) return;
    setState(() => _messages.add(ChatMessage.fromJson(raw)));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText(String text) async {
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    setState(() => _sending = true);
    try {
      await ApiService().post('/messages', {
        'content': text.trim(),
        'channel': _postChannel,
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1F2937),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final picked = await _picker.pickImage(source: choice, imageQuality: 75);
    if (picked == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final res = await ApiService().uploadFile('/evidence', File(picked.path), 'file');
      final url = res['url'] as String? ?? res['file_url'] as String?;
      if (url == null) throw Exception('No URL returned');
      await ApiService().post('/messages', {
        'content': '[IMAGE] $url',
        'channel': _postChannel,
        'message_type': 'image',
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final myId = context.select<AuthProvider, String?>((a) => a.user?.id);
    final isDM = widget.channel.type == 'dm';

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _channelAvatarColor(widget.channel.type),
                shape: BoxShape.circle,
              ),
              child: Icon(_channelIcon(widget.channel.type), color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.channel.name,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
                : RefreshIndicator(
                    onRefresh: _loadMessages,
                    color: const Color(0xFF2563EB),
                    backgroundColor: const Color(0xFF1F2937),
                    child: _messages.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  'No messages yet\nPull down to refresh',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                          final msg = _messages[i];
                          final isMe = msg.senderId == myId;
                          final prevMsg = i > 0 ? _messages[i - 1] : null;
                          final nextMsg = i < _messages.length - 1 ? _messages[i + 1] : null;
                          // Group messages from same sender
                          final isFirstInGroup = prevMsg == null || prevMsg.senderId != msg.senderId;
                          final isLastInGroup = nextMsg == null || nextMsg.senderId != msg.senderId;
                          return _MessageBubble(
                            message: msg,
                            isMe: isMe,
                            isDM: isDM,
                            isFirstInGroup: isFirstInGroup,
                            isLastInGroup: isLastInGroup,
                            onJoinCall: (roomId) {
                              Navigator.pushNamed(context, '/video-call', arguments: {
                                'roomId': roomId,
                                'roomTitle': '${widget.channel.name} Call',
                              });
                            },
                          );
                        },
                      ),
                  ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1F2937))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Attachment button
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Color(0xFF6B7280)),
                    onPressed: _sending ? null : _pickAndSendImage,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                  // Text input
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sending ? null : _sendText,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                        filled: true,
                        fillColor: const Color(0xFF111827),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Send button
                  GestureDetector(
                    onTap: _sending ? null : () => _sendText(_inputCtrl.text),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _sending ? const Color(0xFF374151) : const Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _channelIcon(String type) {
    switch (type) {
      case 'dm':
        return Icons.person;
      case 'team':
        return Icons.people;
      default:
        return Icons.public;
    }
  }

  Color _channelAvatarColor(String type) {
    switch (type) {
      case 'dm':
        return const Color(0xFF7C3AED);
      case 'team':
        return const Color(0xFF1D4ED8);
      default:
        return const Color(0xFF065F46);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isDM;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final void Function(String roomId) onJoinCall;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.isDM,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.onJoinCall,
  });

  bool get _isVideoCall => message.content.startsWith('\u{1F4F9} Video call started. Join:');
  bool get _isImage => message.content.startsWith('[IMAGE]');

  String? get _videoCallRoomId {
    if (!_isVideoCall) return null;
    final parts = message.content.split('Join: ');
    if (parts.length < 2) return null;
    return parts[1].trim();
  }

  String? get _imageUrl {
    if (!_isImage) return null;
    return message.content.replaceFirst('[IMAGE] ', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isMe ? const Radius.circular(16) : Radius.circular(isLastInGroup ? 4 : 16),
      bottomRight: isMe ? Radius.circular(isLastInGroup ? 4 : 16) : const Radius.circular(16),
    );

    Widget content;

    if (_isVideoCall) {
      final roomId = _videoCallRoomId;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam, color: Color(0xFF60A5FA), size: 16),
              SizedBox(width: 6),
              Text('Video call started', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          if (roomId != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => onJoinCall(roomId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Join Call', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(_formatTime(message.sentAt), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
        ],
      );
    } else if (_isImage) {
      final url = _imageUrl;
      content = Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMe && !isDM && isFirstInGroup && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.senderName!,
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                EnvironmentConfig.resolveUrl(url),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Color(0xFF6B7280), size: 48),
              ),
            )
          else
            const Icon(Icons.image, color: Color(0xFF6B7280), size: 48),
          const SizedBox(height: 4),
          Text(_formatTime(message.sentAt), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMe && !isDM && isFirstInGroup && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.senderName!,
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          Text(message.content, style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 4),
          Text(_formatTime(message.sentAt), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: isLastInGroup ? 8 : 2,
        top: isFirstInGroup && !isMe ? 2 : 0,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar placeholder for non-me, last in group
          if (!isMe) ...[
            SizedBox(
              width: 28,
              child: isLastInGroup
                  ? Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0xFF374151),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: Color(0xFF9CA3AF), size: 14),
                    )
                  : null,
            ),
            const SizedBox(width: 4),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF2563EB) : const Color(0xFF1F2937),
                borderRadius: radius,
              ),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
