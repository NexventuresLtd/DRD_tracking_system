import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';
import '../config/environment.dart';

typedef WsHandler = void Function(Map<String, dynamic> msg);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final Map<String, List<WsHandler>> _handlers = {};
  bool _connected = false;
  String? _currentPath;
  Timer? _reconnectTimer;

  bool get connected => _connected;

  void on(String type, WsHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  void off(String type, WsHandler handler) {
    _handlers[type]?.remove(handler);
  }

  Future<void> connect(String path) async {
    if (_connected && _currentPath == path) return;
    await disconnect();
    final token = WebSocketService._storage.accessToken;
    if (token == null) return;

    _currentPath = path;
    final wsBase = EnvironmentConfig.wsBaseUrl;
    final uri = Uri.parse('$wsBase$path?token=${Uri.encodeComponent(token)}');

    try {
      _channel = WebSocketChannel.connect(uri);
      _connected = true;
      _sub = _channel!.stream.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          final type = msg['type'] as String?;
          if (type != null) {
            for (final handler in List<WsHandler>.from(_handlers[type] ?? [])) {
              handler(msg);
            }
          }
        },
        onDone: () {
          _connected = false;
          _scheduleReconnect();
        },
        onError: (_) {
          _connected = false;
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _connected = false;
    }
  }

  void send(Map<String, dynamic> msg) {
    if (_connected) _channel?.sink.add(jsonEncode(msg));
  }

  // Forward a message directly to registered handlers without requiring a WS connection.
  // Used by PushNotificationService to bridge its own WS into the handler registry.
  void dispatch(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type != null) {
      for (final handler in List<WsHandler>.from(_handlers[type] ?? [])) {
        handler(msg);
      }
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    await _channel?.sink.close();
    _connected = false;
    _currentPath = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_currentPath != null) connect(_currentPath!);
    });
  }

  static final _storage = StorageService();
}
