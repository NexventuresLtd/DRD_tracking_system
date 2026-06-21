import 'package:flutter/material.dart';
import '../../config/theme.dart';

typedef CommsSendFn = void Function(
  String? toUserId,
  String? toTeamId,
  bool toAll,
  String content,
  String priority,
);

class CommsScreen extends StatefulWidget {
  final String myId;
  final String myName;
  final String? myTeamId;
  final String? coordinatorId;
  final String coordinatorName;
  final List<Map<String, dynamic>> contacts;
  final List<Map<String, dynamic>> messages;
  final bool sending;
  final CommsSendFn onSend;

  const CommsScreen({
    super.key,
    required this.myId,
    required this.myName,
    this.myTeamId,
    this.coordinatorId,
    required this.coordinatorName,
    required this.contacts,
    required this.messages,
    required this.sending,
    required this.onSend,
  });

  @override
  State<CommsScreen> createState() => _CommsScreenState();
}

class _CommsScreenState extends State<CommsScreen> {
  String? _chatWithId;
  String _chatWithName = '';
  bool _isTeamChat = false;
  String _priority = 'normal';
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(CommsScreen old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length && _chatWithId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // All unique contacts including coordinator
  List<Map<String, dynamic>> get _allContacts {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];

    // Coordinator first (if set and not self)
    if (widget.coordinatorId != null &&
        widget.coordinatorId != widget.myId) {
      seen.add(widget.coordinatorId!);
      result.add({
        'user_id': widget.coordinatorId,
        'name': widget.coordinatorName,
        '_isCoordinator': true,
      });
    }

    // Team members
    for (final c in widget.contacts) {
      final id = c['user_id'] as String? ?? '';
      if (id.isEmpty || id == widget.myId || seen.contains(id)) continue;
      seen.add(id);
      result.add(c);
    }

    return result;
  }

  List<Map<String, dynamic>> _convMessages(String contactId,
      {bool isTeam = false}) {
    final filtered = widget.messages.where((m) {
      final fromMe = m['from_user_id'] == widget.myId;
      final fromThem = m['from_user_id'] == contactId;
      if (isTeam) {
        return m['to_team_id'] == contactId;
      }
      return fromThem || (fromMe && m['to_user_id'] == contactId);
    }).toList();
    filtered.sort((a, b) {
      final at =
          DateTime.tryParse(a['created_at'] as String? ?? '') ?? DateTime(0);
      final bt =
          DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime(0);
      return at.compareTo(bt);
    });
    return filtered;
  }

  Map<String, dynamic>? _lastMsg(String contactId, {bool isTeam = false}) {
    final msgs = _convMessages(contactId, isTeam: isTeam);
    return msgs.isEmpty ? null : msgs.last;
  }

  int _unread(String contactId, {bool isTeam = false}) {
    return widget.messages.where((m) {
      final fromOther = m['from_user_id'] != widget.myId;
      if (isTeam) {
        return m['to_team_id'] == contactId &&
            fromOther &&
            m['is_read'] == false;
      }
      return m['from_user_id'] == contactId && m['is_read'] == false;
    }).length;
  }

  void _openChat(String id, String name, {bool isTeam = false}) {
    setState(() {
      _chatWithId = id;
      _chatWithName = name;
      _isTeamChat = isTeam;
      _priority = 'normal';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final content = _textCtrl.text.trim();
    if (content.isEmpty || _chatWithId == null) return;
    widget.onSend(
      _isTeamChat ? null : _chatWithId,
      _isTeamChat ? _chatWithId : null,
      false,
      content,
      _priority,
    );
    _textCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_chatWithId != null) return _buildChatView();
    return _buildConversationList();
  }

  // ── Conversation list ───────────────────────────────────────────────────────

  Widget _buildConversationList() {
    final contacts = _allContacts;
    final hasTeam =
        widget.myTeamId != null && widget.myTeamId!.isNotEmpty;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: const Color(0xFF0D1117),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline,
                  color: DRDTheme.primaryColor, size: 18),
              const SizedBox(width: 8),
              const Text(
                'COMMS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (widget.messages.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: DRDTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.messages.length} msgs',
                    style: const TextStyle(
                        color: DRDTheme.primaryColor, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Team channel row
        if (hasTeam) ...[
          _buildConvTile(
            id: widget.myTeamId!,
            name: 'Team Channel',
            subtitle: 'Message all team members',
            isTeam: true,
            avatarIcon: Icons.group,
            avatarColor: const Color(0xFF10B981),
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),
        ],

        // Contacts
        Expanded(
          child: contacts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline,
                          size: 36,
                          color: Colors.white.withValues(alpha: 0.12)),
                      const SizedBox(height: 10),
                      const Text('No contacts yet',
                          style:
                              TextStyle(color: Colors.white30, fontSize: 12)),
                      const Text('Join a team to see members here',
                          style:
                              TextStyle(color: Colors.white12, fontSize: 10)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (context, i) =>
                      const Divider(height: 1, color: Color(0xFF1E293B)),
                  itemBuilder: (_, i) {
                    final c = contacts[i];
                    final id = c['user_id'] as String? ?? '';
                    final name =
                        (c['name'] ?? c['user_name'] ?? 'Unknown') as String;
                    final isCoord = c['_isCoordinator'] == true;
                    return _buildConvTile(
                      id: id,
                      name: name,
                      subtitle: isCoord ? 'Coordinator' : 'Team member',
                      avatarColor: isCoord
                          ? const Color(0xFF6366F1)
                          : const Color(0xFF3B82F6),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConvTile({
    required String id,
    required String name,
    String subtitle = '',
    bool isTeam = false,
    IconData? avatarIcon,
    Color avatarColor = const Color(0xFF3B82F6),
  }) {
    final last = _lastMsg(id, isTeam: isTeam);
    final unread = _unread(id, isTeam: isTeam);
    final lastText = last != null
        ? (last['from_user_id'] == widget.myId
            ? 'You: ${last['content']}'
            : last['content'] as String? ?? '')
        : subtitle;
    final lastTime = last != null
        ? _fmtTime(DateTime.tryParse(last['created_at'] as String? ?? ''))
        : '';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return InkWell(
      onTap: () => _openChat(id, name, isTeam: isTeam),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: avatarColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                    color: avatarColor.withValues(alpha: 0.4), width: 1.5),
              ),
              child: avatarIcon != null
                  ? Icon(avatarIcon, color: avatarColor, size: 20)
                  : Center(
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: TextStyle(
                          color: avatarColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
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
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastTime.isNotEmpty)
                        Text(
                          lastTime,
                          style: TextStyle(
                            color: unread > 0
                                ? DRDTheme.primaryColor
                                : Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastText,
                          style: TextStyle(
                            color: unread > 0
                                ? Colors.white70
                                : Colors.white38,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: DRDTheme.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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

  // ── Chat view ───────────────────────────────────────────────────────────────

  Widget _buildChatView() {
    final msgs = _convMessages(_chatWithId!, isTeam: _isTeamChat);
    const priorityColors = {
      'urgent': Color(0xFFEF4444),
      'high': Color(0xFFF59E0B),
      'normal': Color(0xFF3B82F6),
      'low': Color(0xFF64748B),
    };

    return Column(
      children: [
        // Chat header with back button
        Container(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          color: const Color(0xFF0D1117),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white70, size: 16),
                onPressed: () => setState(() => _chatWithId = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _isTeamChat
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFF3B82F6).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isTeamChat
                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                        : const Color(0xFF3B82F6).withValues(alpha: 0.5),
                  ),
                ),
                child: _isTeamChat
                    ? const Icon(Icons.group,
                        color: Color(0xFF10B981), size: 16)
                    : Center(
                        child: Text(
                          _chatWithName
                              .split(' ')
                              .where((w) => w.isNotEmpty)
                              .take(2)
                              .map((w) => w[0].toUpperCase())
                              .join(),
                          style: const TextStyle(
                            color: Color(0xFF3B82F6),
                            fontSize: 11,
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
                      _chatWithName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _isTeamChat ? 'Team channel' : 'Direct message',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 32,
                          color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 8),
                      Text(
                        'No messages yet',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final msg = msgs[i];
                    final fromMe = msg['from_user_id'] == widget.myId;
                    final content = msg['content'] as String? ?? '';
                    final sender =
                        msg['from_user_name'] as String? ?? 'Unknown';
                    final priority =
                        msg['priority'] as String? ?? 'normal';
                    final pColor = priorityColors[priority] ??
                        const Color(0xFF3B82F6);
                    final msgTime = DateTime.tryParse(
                            msg['created_at'] as String? ?? '')
                        ?.toLocal();
                    final timeStr = msgTime != null
                        ? '${msgTime.hour.toString().padLeft(2, '0')}:${msgTime.minute.toString().padLeft(2, '0')}'
                        : '';

                    final prev = i > 0 ? msgs[i - 1] : null;
                    final showSender = !fromMe &&
                        (prev == null ||
                            prev['from_user_id'] != msg['from_user_id']);

                    final initials = sender
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0].toUpperCase())
                        .join();

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
                              width: 28,
                              child: showSender
                                  ? Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B82F6)
                                            .withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          initials.isEmpty ? '?' : initials,
                                          style: const TextStyle(
                                            color: Color(0xFF3B82F6),
                                            fontSize: 9,
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
                                  MediaQuery.of(context).size.width * 0.65,
                            ),
                            child: Column(
                              crossAxisAlignment: fromMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (showSender && !fromMe)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(left: 4, bottom: 2),
                                    child: Text(
                                      sender,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                      10, 7, 10, 7),
                                  decoration: BoxDecoration(
                                    color: fromMe
                                        ? const Color(0xFF1D4ED8)
                                            .withValues(alpha: 0.5)
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
                                          : Colors.white.withValues(alpha: 0.06),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: fromMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (priority != 'normal')
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: pColor
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              priority.toUpperCase(),
                                              style: TextStyle(
                                                color: pColor,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Text(
                                        content,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          color:
                                              Colors.white.withValues(alpha: 0.4),
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
                ),
        ),

        // Priority selector
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          color: const Color(0xFF0D1117),
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
                            ? _priorityColor(p).withValues(alpha: 0.25)
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
                              : Colors.white38,
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
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          color: const Color(0xFF0D1117),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _textCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message ${_chatWithName.toLowerCase()}…',
                      hintStyle: const TextStyle(
                          color: Colors.white24, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.sending ? null : _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.sending
                        ? Colors.white12
                        : DRDTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: widget.sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white54),
                          ),
                        )
                      : const Icon(Icons.send,
                          color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.day == now.day &&
        local.month == now.month &&
        local.year == now.year) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}/${local.month}';
  }
}
