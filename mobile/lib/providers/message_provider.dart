import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class MessageData {
  final String id;
  final String content;
  final String senderId;
  final String channel;
  final DateTime sentAt;

  const MessageData({
    required this.id,
    required this.content,
    required this.senderId,
    required this.channel,
    required this.sentAt,
  });

  factory MessageData.fromJson(Map<String, dynamic> j) => MessageData(
        id: j['id'] as String,
        content: j['content'] as String,
        senderId: j['sender_id'] as String,
        channel: j['channel'] as String? ?? 'global',
        sentAt: DateTime.parse(j['sent_at'] as String),
      );
}

class MessageProvider extends ChangeNotifier {
  final Map<String, List<MessageData>> _channels = {};

  List<MessageData> getChannel(String channel) => _channels[channel] ?? [];

  final _api = ApiService();

  Future<void> loadGlobal() async {
    try {
      final data = await _api.get('/messages/channels/global') as List<dynamic>;
      _channels['global'] = data
          .map((e) => MessageData.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  void addMessage(MessageData msg) {
    _channels.putIfAbsent(msg.channel, () => []).add(msg);
    notifyListeners();
  }
}
