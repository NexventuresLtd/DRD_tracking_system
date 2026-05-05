import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../models/message_model.dart';

class MessageProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storage = StorageService();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;

  List<MessageModel> _messages = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  bool _isConnected = false;

  List<MessageModel> get messages => _messages;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;

  /// Call after login to load history and start live feed
  Future<void> initialize() async {
    await fetchMessages();
    await _connectWS();
  }

  Future<void> fetchMessages() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.get('/messages?size=50');
      if (response is Map) {
        final items = response['items'] as List? ?? [];
        _messages = items.map((m) => MessageModel.fromJson(m as Map<String, dynamic>)).toList();
        _unreadCount = response['unread_count'] as int? ?? 0;
      } else if (response is List) {
        _messages = response.map((m) => MessageModel.fromJson(m as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('fetchMessages error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _connectWS() async {
    final token = await _storage.getToken();
    if (token == null) return;
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(
        Uri.parse('${AppConstants.wsUrl}/messages?token=$token'),
      );
      _isConnected = true;
      notifyListeners();

      _channel!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            final payload = data['data'] ?? data;
            if (payload is Map<String, dynamic>) {
              final msg = MessageModel.fromJson(payload);
              // Prepend if not already in list
              if (!_messages.any((m) => m.id == msg.id)) {
                _messages.insert(0, msg);
                if (!msg.isRead) _unreadCount++;
                notifyListeners();
              }
            }
          } catch (_) {}
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onError: (_) {
          _isConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('WS connect error: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _connectWS);
  }

  Future<bool> sendMessage({
    required String content,
    String? toUserId,
    String? toTeamId,
    bool toAll = false,
    String priority = 'normal',
  }) async {
    if (content.trim().isEmpty) return false;
    try {
      final data = <String, dynamic>{
        'content': content.trim(),
        'to_all': toAll,
        'priority': priority,
      };
      if (toUserId != null) data['to_user_id'] = toUserId;
      if (toTeamId != null) data['to_team_id'] = toTeamId;

      final response = await _apiService.post('/messages', data);
      if (response != null) {
        final msg = MessageModel.fromJson(response as Map<String, dynamic>);
        _messages.insert(0, msg);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('sendMessage error: $e');
    }
    return false;
  }

  Future<void> markAllAsRead() async {
    try {
      await _apiService.put('/messages/read-all');
      for (final m in _messages) { m.isRead = true; }
      _unreadCount = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAsRead(String messageId) async {
    try {
      await _apiService.put('/messages/$messageId/read');
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx >= 0 && !_messages[idx].isRead) {
        _messages[idx].isRead = true;
        _unreadCount = (_unreadCount - 1).clamp(0, 9999);
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
