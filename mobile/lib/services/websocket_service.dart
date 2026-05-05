import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isConnected = false;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;

  void connect(String token) {
    try {
      final wsUrl = '${AppConstants.wsUrl}/messages?token=$token';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          final message = jsonDecode(data);
          _messageController.add(message);
        },
        onDone: () {
          _isConnected = false;
          // Auto-reconnect
          Future.delayed(const Duration(seconds: 5), () => connect(token));
        },
        onError: (error) {
          _isConnected = false;
          debugPrint('WebSocket Error: $error');
        },
      );
    } catch (e) {
      debugPrint('WebSocket Connection Error: $e');
      _isConnected = false;
    }
  }

  void sendMessage(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}