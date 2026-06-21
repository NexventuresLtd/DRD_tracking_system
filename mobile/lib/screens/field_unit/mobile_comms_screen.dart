import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/message_provider.dart';
import '../../models/message_model.dart';
import '../../services/api_service.dart';

// ─── Entry point: conversation list ─────────────────────────────────────────

class MobileCommsScreen extends StatefulWidget {
  const MobileCommsScreen({super.key});

  @override
  State<MobileCommsScreen> createState() => _MobileCommsScreenState();
}

class _MobileCommsScreenState extends State<MobileCommsScreen> {
  final ApiService _api = ApiService();
  List<_Contact> _contacts = [];
  bool _loadingContacts = true;
  String? _myId;
  String? _myTeamId;
  String? _myTeamName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ensure MessageProvider is live — safe to call even if already connected
      final mp = context.read<MessageProvider>();
      if (!mp.isConnected) mp.initialize();
      _loadContacts();
    });
  }

  Future<void> _loadContacts() async {
    final auth = context.read<AuthProvider>().user;
    _myId = auth?.id ?? '';
    _myTeamId = auth?.teamId;
    _myTeamName = auth?.teamName ?? 'Team';

    final contacts = <_Contact>[];

    if (_myTeamId != null && _myTeamId!.isNotEmpty) {
      // Group chat always first
      contacts.add(_Contact(
        id: _myTeamId!,
        name: _myTeamName!,
        isGroup: true,
      ));

      // Fetch team members
      try {
        final team = await _api.get('/teams/$_myTeamId');
        if (team is Map<String, dynamic>) {
          final leadId = team['lead_id']?.toString();
          final rawMembers = (team['members'] as List?) ?? [];

          // Leads go first, then everyone else — all except me
          final leads = <_Contact>[];
          final others = <_Contact>[];

          for (final raw in rawMembers) {
            final m = raw as Map<String, dynamic>;
            final uid = m['user_id']?.toString() ?? '';
            if (uid.isEmpty || uid == _myId) continue;
            final contact = _Contact(
              id: uid,
              name: m['user_name']?.toString() ??
                  m['username']?.toString() ??
                  'Team member',
              isGroup: false,
              role: m['role']?.toString(),
              isLead: uid == leadId,
            );
            if (uid == leadId) {
              leads.add(contact);
            } else {
              others.add(contact);
            }
          }
          contacts.addAll(leads);
          contacts.addAll(others);
        }
      } catch (e) {
        debugPrint('MobileCommsScreen._loadContacts error: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _loadingContacts = false;
    });
  }

  List<MessageModel> _convMessages(
      MessageProvider mp, _Contact contact) {
    final msgs = mp.messages.where((m) {
      if (contact.isGroup) {
        return m.toTeamId == contact.id;
      }
      final fromThem = m.fromUserId == contact.id;
      final toThem = m.toUserId == contact.id && m.fromUserId == _myId;
      return fromThem || toThem;
    }).toList();
    msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return msgs;
  }

  int _unread(MessageProvider mp, _Contact contact) {
    return mp.messages.where((m) {
      if (contact.isGroup) {
        return m.toTeamId == contact.id &&
            m.fromUserId != _myId &&
            !m.isRead;
      }
      return m.fromUserId == contact.id && !m.isRead;
    }).length;
  }

  void _openChat(_Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChatScreen(
          contact: contact,
          myId: _myId ?? '',
          myTeamId: _myTeamId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white70, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.chat_bubble_outline,
                color: DRDTheme.primaryColor, size: 18),
            SizedBox(width: 8),
            Text(
              'COMMS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          Consumer<MessageProvider>(
            builder: (context, mp, child) => mp.isConnected
                ? const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: Row(
                      children: [
                        CircleAvatar(
                            radius: 4,
                            backgroundColor: Color(0xFF10B981)),
                        SizedBox(width: 4),
                        Text('LIVE',
                            style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1)),
                      ],
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: Row(
                      children: [
                        CircleAvatar(
                            radius: 4, backgroundColor: Colors.orange),
                        SizedBox(width: 4),
                        Text('OFFLINE',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      body: _loadingContacts
          ? const Center(
              child: CircularProgressIndicator(color: DRDTheme.primaryColor))
          : _contacts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(height: 12),
                      const Text('No team assigned yet',
                          style: TextStyle(color: Colors.white38)),
                      const SizedBox(height: 6),
                      const Text('Ask your coordinator to add you to a team',
                          style: TextStyle(
                              color: Colors.white24, fontSize: 11)),
                    ],
                  ),
                )
              : Consumer<MessageProvider>(
                  builder: (context, mp, child) => RefreshIndicator(
                    onRefresh: mp.fetchMessages,
                    color: DRDTheme.primaryColor,
                    backgroundColor: const Color(0xFF1E293B),
                    child: ListView.separated(
                      itemCount: _contacts.length,
                      separatorBuilder: (ctx, i) => const Divider(
                          height: 1,
                          color: Color(0xFF1E2A3B),
                          indent: 70),
                      itemBuilder: (_, i) {
                        final contact = _contacts[i];
                        final msgs = _convMessages(mp, contact);
                        final last = msgs.isEmpty ? null : msgs.last;
                        final unread = _unread(mp, contact);
                        return _ConvTile(
                          contact: contact,
                          lastMsg: last,
                          myId: _myId ?? '',
                          unreadCount: unread,
                          onTap: () => _openChat(contact),
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}

// ─── Conversation tile ───────────────────────────────────────────────────────

class _ConvTile extends StatelessWidget {
  final _Contact contact;
  final MessageModel? lastMsg;
  final String myId;
  final int unreadCount;
  final VoidCallback onTap;

  const _ConvTile({
    required this.contact,
    required this.lastMsg,
    required this.myId,
    required this.unreadCount,
    required this.onTap,
  });

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    if (local.day == now.day &&
        local.month == now.month &&
        local.year == now.year) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    final initials = contact.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final avatarColor = contact.isGroup
        ? const Color(0xFF10B981)
        : const Color(0xFF3B82F6);

    String lastText = 'No messages yet';
    if (lastMsg != null) {
      final fromMe = lastMsg!.fromUserId == myId;
      lastText = fromMe ? 'You: ${lastMsg!.content}' : lastMsg!.content;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: avatarColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                    color: avatarColor.withValues(alpha: 0.45), width: 1.5),
              ),
              child: contact.isGroup
                  ? const Icon(Icons.group,
                      color: Color(0xFF10B981), size: 22)
                  : Center(
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: TextStyle(
                          color: avatarColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                contact.name,
                                style: TextStyle(
                                  color: unreadCount > 0
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: unreadCount > 0
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (contact.isLead) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: const Color(0xFFF59E0B)
                                          .withValues(alpha: 0.5)),
                                ),
                                child: const Text(
                                  'LEAD',
                                  style: TextStyle(
                                    color: Color(0xFFF59E0B),
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (lastMsg != null)
                        Text(
                          _fmt(lastMsg!.createdAt),
                          style: TextStyle(
                            color: unreadCount > 0
                                ? DRDTheme.primaryColor
                                : Colors.white30,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastText,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? Colors.white60
                                : Colors.white30,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: DRDTheme.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
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
      ),
    );
  }
}

// ─── Chat screen ─────────────────────────────────────────────────────────────

class _ChatScreen extends StatefulWidget {
  final _Contact contact;
  final String myId;
  final String? myTeamId;

  const _ChatScreen({
    required this.contact,
    required this.myId,
    this.myTeamId,
  });

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _priority = 'normal';
  bool _sending = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<MessageModel> _filteredMessages(List<MessageModel> all) {
    final msgs = all.where((m) {
      if (widget.contact.isGroup) {
        return m.toTeamId == widget.contact.id;
      }
      final fromThem = m.fromUserId == widget.contact.id;
      final toThem =
          m.toUserId == widget.contact.id && m.fromUserId == widget.myId;
      return fromThem || toThem;
    }).toList();
    msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return msgs;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _textCtrl.clear();

    final mp = context.read<MessageProvider>();
    await mp.sendMessage(
      content: text,
      toUserId: widget.contact.isGroup ? null : widget.contact.id,
      toTeamId: widget.contact.isGroup ? widget.contact.id : null,
      toAll: false,
      priority: _priority,
    );

    setState(() => _sending = false);
    _scrollToBottom();
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'urgent':
        return const Color(0xFFEF4444);
      case 'high':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF64748B);
      default:
        return DRDTheme.primaryColor;
    }
  }

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.contact.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white70, size: 18),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.contact.isGroup
                    ? const Color(0xFF10B981).withValues(alpha: 0.18)
                    : const Color(0xFF3B82F6).withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.contact.isGroup
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : const Color(0xFF3B82F6).withValues(alpha: 0.4),
                ),
              ),
              child: widget.contact.isGroup
                  ? const Icon(Icons.group,
                      color: Color(0xFF10B981), size: 18)
                  : Center(
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: const TextStyle(
                          color: Color(0xFF3B82F6),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contact.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.contact.isGroup
                        ? 'Team channel'
                        : widget.contact.role != null
                            ? widget.contact.role!
                            : 'Team member',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: Consumer<MessageProvider>(
              builder: (context, mp, child) {
                final msgs = _filteredMessages(mp.messages);
                if (msgs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 40,
                            color: Colors.white.withValues(alpha: 0.1)),
                        const SizedBox(height: 10),
                        Text(
                          'Start the conversation',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final msg = msgs[i];
                    final fromMe = msg.fromUserId == widget.myId;
                    final prev = i > 0 ? msgs[i - 1] : null;
                    final showSender = !fromMe &&
                        (prev == null ||
                            prev.fromUserId != msg.fromUserId);

                    final initials2 = (msg.fromUserName ?? '?')
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0].toUpperCase())
                        .join();

                    final pColor = _priorityColor(msg.priority);

                    return Padding(
                      padding: EdgeInsets.only(
                          top: showSender ? 10 : 2, bottom: 1),
                      child: Row(
                        mainAxisAlignment: fromMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Avatar for others
                          if (!fromMe) ...[
                            SizedBox(
                              width: 30,
                              child: showSender
                                  ? Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B82F6)
                                            .withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          initials2,
                                          style: const TextStyle(
                                            color: Color(0xFF3B82F6),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 6),
                          ],

                          // Bubble
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.68,
                            ),
                            child: Column(
                              crossAxisAlignment: fromMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (showSender && !fromMe)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 4, bottom: 3),
                                    child: Text(
                                      msg.fromUserName ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                      11, 8, 11, 8),
                                  decoration: BoxDecoration(
                                    color: fromMe
                                        ? const Color(0xFF1D4ED8)
                                            .withValues(alpha: 0.55)
                                        : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft: fromMe
                                          ? const Radius.circular(14)
                                          : const Radius.circular(3),
                                      bottomRight: fromMe
                                          ? const Radius.circular(3)
                                          : const Radius.circular(14),
                                    ),
                                    border: Border.all(
                                      color: fromMe
                                          ? const Color(0xFF3B82F6)
                                              .withValues(alpha: 0.3)
                                          : Colors.white
                                              .withValues(alpha: 0.06),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: fromMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (msg.priority != 'normal')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 4),
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1),
                                            decoration: BoxDecoration(
                                              color: pColor
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              msg.priority.toUpperCase(),
                                              style: TextStyle(
                                                color: pColor,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Text(
                                        msg.content,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _fmtTime(msg.createdAt),
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.4),
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (fromMe) const SizedBox(width: 6),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Priority selector
          Container(
            color: const Color(0xFF0A1628),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                for (final p in ['normal', 'high', 'urgent', 'low'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _priority = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _priority == p
                              ? _priorityColor(p).withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _priority == p
                                ? _priorityColor(p)
                                : Colors.white12,
                            width: _priority == p ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          p[0].toUpperCase() + p.substring(1),
                          style: TextStyle(
                            color: _priority == p
                                ? _priorityColor(p)
                                : Colors.white30,
                            fontSize: 10,
                            fontWeight: _priority == p
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Input row
          Container(
            color: const Color(0xFF0A1628),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: _textCtrl,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText:
                            'Message ${widget.contact.name.toLowerCase()}…',
                        hintStyle: const TextStyle(
                            color: Colors.white24, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : _send,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _sending
                          ? Colors.white12
                          : DRDTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white54),
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Contact data model ───────────────────────────────────────────────────────

class _Contact {
  final String id;
  final String name;
  final bool isGroup;
  final String? role;
  final bool isLead;

  const _Contact({
    required this.id,
    required this.name,
    required this.isGroup,
    this.role,
    this.isLead = false,
  });
}
