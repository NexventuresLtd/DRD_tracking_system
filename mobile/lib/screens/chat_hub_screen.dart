import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/team_provider.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ChatMessage {
  final String id;
  final String content;
  final String senderId;
  final DateTime sentAt;
  ChatMessage({required this.id, required this.content, required this.senderId, required this.sentAt});
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        content: j['content'] as String,
        senderId: j['sender_id'] as String,
        sentAt: DateTime.parse(j['sent_at'] as String),
      );
}

class ChatHubScreen extends StatefulWidget {
  const ChatHubScreen({super.key});
  @override
  State<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends State<ChatHubScreen> {
  String _activeChannel = 'global';
  String _activeLabel = 'Global';
  List<ChatMessage> _messages = [];
  bool _loading = false;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _ws = WebSocketService();

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectWS();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _ws.off('new_message', _onMessage);
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService().get('/messages/channels/$_activeChannel') as List<dynamic>;
      setState(() {
        _messages = data.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _connectWS() {
    _ws.off('new_message', _onMessage);
    _ws.on('new_message', _onMessage);
    _ws.connect('/ws/messages/${Uri.encodeComponent(_activeChannel)}');
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final raw = msg['message'] as Map<String, dynamic>?;
    if (raw != null) {
      setState(() => _messages.add(ChatMessage.fromJson(raw)));
      _scrollToBottom();
    }
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

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    try {
      await ApiService().post('/messages', {'content': text, 'channel': _activeChannel});
    } catch (_) {}
  }

  void _switchChannel(String channel, String label) {
    setState(() {
      _activeChannel = channel;
      _activeLabel = label;
      _messages = [];
    });
    _loadMessages();
    _connectWS();
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.select<AuthProvider, String?>((a) => a.user?.id);
    final teams = context.watch<TeamProvider>().teams;

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(_activeLabel, style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<void>(
            icon: const Icon(Icons.swap_horiz, color: Color(0xFF9CA3AF)),
            color: const Color(0xFF1F2937),
            itemBuilder: (_) => [
              _channelItem('global', 'Global', Icons.public),
              ...teams.map((t) => _channelItem('team:${t.id}', t.name, Icons.people)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet', style: TextStyle(color: Color(0xFF6B7280))))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg = _messages[i];
                          final isMe = msg.senderId == myId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMe ? const Color(0xFF2563EB) : const Color(0xFF1F2937),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                                        bottomRight: Radius.circular(isMe ? 4 : 16),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                        Text(msg.content, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTime(msg.sentAt),
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1F2937))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        hintStyle: const TextStyle(color: Color(0xFF4B5563)),
                        filled: true,
                        fillColor: const Color(0xFF111827),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
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

  PopupMenuItem<void> _channelItem(String channel, String label, IconData icon) {
    return PopupMenuItem(
      onTap: () => _switchChannel(channel, label),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF9CA3AF), size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
