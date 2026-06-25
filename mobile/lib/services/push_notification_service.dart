import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';
import 'navigation_state.dart';
import 'api_service.dart';
import 'websocket_service.dart';
import '../config/environment.dart';
import '../main.dart' show navigatorKey;
import '../screens/live_session_screen.dart';

// ── Android notification channels ─────────────────────────────────────────────

const _chSos = AndroidNotificationChannel(
  'sos',
  'SOS Alerts',
  description: 'Immediate SOS distress signals from field personnel',
  importance: Importance.max,
  playSound: true,
  enableLights: true,
  ledColor: Color(0xFFDC2626),
);

const _chMissions = AndroidNotificationChannel(
  'missions',
  'Missions',
  description: 'Mission assignments and status updates',
  importance: Importance.high,
  playSound: true,
);

const _chMessages = AndroidNotificationChannel(
  'messages',
  'Messages',
  description: 'Incoming comms from teammates and commanders',
  importance: Importance.high,
  playSound: true,
);

const _chGeneral = AndroidNotificationChannel(
  'general',
  'General',
  description: 'General operational updates',
  importance: Importance.defaultImportance,
);

// ── Service ───────────────────────────────────────────────────────────────────

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();
  PushNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _storage = StorageService();

  WebSocketChannel? _eventsChannel;
  WebSocketChannel? _notifsChannel;
  StreamSubscription? _eventsSub;
  StreamSubscription? _notifsSub;
  Timer? _eventsReconnect;
  Timer? _notifsReconnect;
  Timer? _tokenRefreshTimer;

  bool _initialized = false;
  int _notifId = 100;
  String? _currentUserId;

  // Called once at app start (before user logs in — safe to call multiple times)
  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onTap,
    );

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final ch in [_chSos, _chMissions, _chMessages, _chGeneral]) {
        await android?.createNotificationChannel(ch);
      }
    }

    _initialized = true;
  }

  // Call this after a successful login with the authenticated user's id
  Future<void> connectForUser(String userId) async {
    if (!_initialized) await initialize();
    _currentUserId = userId;
    await _connectEvents();
    await _connectPersonal(userId);
    // Proactively refresh the token every 25 min so the WS never dies from expiry
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 25), (_) async {
      await ApiService().tryRefresh();
      if (_eventsChannel == null) await _connectEvents();
      if (_notifsChannel == null) await _connectPersonal(userId);
    });
  }

  Future<void> disconnect() async {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _currentUserId = null;
    _eventsReconnect?.cancel();
    _notifsReconnect?.cancel();
    await _eventsSub?.cancel();
    await _notifsSub?.cancel();
    await _eventsChannel?.sink.close();
    await _notifsChannel?.sink.close();
    _eventsChannel = null;
    _notifsChannel = null;
  }

  // ── Event WebSocket (/ws/events) ─────────────────────────────────────────

  Future<void> _connectEvents() async {
    _eventsReconnect?.cancel();
    await _eventsSub?.cancel();
    await _eventsChannel?.sink.close();

    final token = _storage.accessToken;
    if (token == null) return;

    final uri = Uri.parse(
        '${EnvironmentConfig.wsBaseUrl}/ws/events?token=${Uri.encodeComponent(token)}');
    try {
      _eventsChannel = WebSocketChannel.connect(uri);
      _eventsSub = _eventsChannel!.stream.listen(
        (raw) => _handleEvent(jsonDecode(raw as String) as Map<String, dynamic>),
        onDone: _scheduleEventsReconnect,
        onError: (_) => _scheduleEventsReconnect(),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleEventsReconnect();
    }
  }

  void _scheduleEventsReconnect() {
    _eventsReconnect?.cancel();
    _eventsReconnect = Timer(const Duration(seconds: 5), _connectEvents);
  }

  // ── Personal notification WebSocket (/ws/notifications/{userId}) ──────────

  Future<void> _connectPersonal(String userId) async {
    _notifsReconnect?.cancel();
    await _notifsSub?.cancel();
    await _notifsChannel?.sink.close();

    final token = _storage.accessToken;
    if (token == null) return;

    final uri = Uri.parse(
        '${EnvironmentConfig.wsBaseUrl}/ws/notifications/$userId?token=${Uri.encodeComponent(token)}');
    try {
      _notifsChannel = WebSocketChannel.connect(uri);
      _notifsSub = _notifsChannel!.stream.listen(
        (raw) => _handleEvent(jsonDecode(raw as String) as Map<String, dynamic>),
        onDone: () => _scheduleNotifsReconnect(userId),
        onError: (_) => _scheduleNotifsReconnect(userId),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleNotifsReconnect(userId);
    }
  }

  void _scheduleNotifsReconnect(String userId) {
    _notifsReconnect?.cancel();
    _notifsReconnect = Timer(const Duration(seconds: 5), () => _connectPersonal(userId));
  }

  // ── Message handler ────────────────────────────────────────────────────────

  void _handleEvent(Map<String, dynamic> msg) {
    // Forward every event to WebSocketService so screen-level handlers fire.
    WebSocketService().dispatch(msg);
    final type = msg['type'] as String? ?? '';
    switch (type) {
      case 'sos_alert':
        _show(
          id: 1000,
          channelId: 'sos',
          title: '🚨 SOS — ${msg['user_name'] ?? 'Unknown'}',
          body: (msg['message'] as String?)?.isNotEmpty == true
              ? msg['message'] as String
              : 'Soldier needs immediate assistance',
          importance: Importance.max,
          priority: Priority.max,
        );
      case 'sos_acknowledged':
        _show(
          id: 1001,
          channelId: 'sos',
          title: 'SOS Acknowledged',
          body: '${msg['acknowledged_by'] ?? 'Command'} responded to the alert',
          importance: Importance.high,
          priority: Priority.high,
        );
      case 'notification':
        final notifType = msg['notif_type'] as String? ?? 'general';
        _show(
          id: _nextId(),
          channelId: _channelFor(notifType),
          title: msg['title'] as String? ?? 'DRD Operations',
          body: msg['body'] as String?,
          importance: _importanceFor(notifType),
          priority: _priorityFor(notifType),
        );
      case 'new_message':
        _show(
          id: _nextId(),
          channelId: 'messages',
          title: msg['sender_name'] as String? ?? 'New message',
          body: msg['content'] as String? ?? 'You have a new message',
          importance: Importance.high,
          priority: Priority.high,
        );
      case 'live_session_invite':
        final session = msg['session'] as Map<String, dynamic>?;
        final sessionTitle = session?['title'] as String? ?? msg['title'] as String? ?? 'Live Briefing';
        final sessionId = session?['id'] as String? ?? msg['ref_id'] as String?;
        _show(
          id: _nextId(),
          channelId: 'missions',
          title: '📡 LIVE: $sessionTitle',
          body: msg['body'] as String? ?? 'You have been invited to join a live session',
          importance: Importance.max,
          priority: Priority.high,
          payload: sessionId != null ? 'live_session:$sessionId' : null,
        );
        if (sessionId != null) _onLiveInvite?.call(sessionId, sessionTitle);
      case 'mission_debrief_started':
        final debriefSessionId = msg['session_id'] as String?;
        final debriefTitle = msg['title'] as String? ?? 'DEBRIEF CALL';
        if (debriefSessionId != null) {
          _show(
            id: _nextId(),
            channelId: 'missions',
            title: '📡 DEBRIEF: $debriefTitle',
            body: 'Tap to join the mission debrief call',
            importance: Importance.max,
            priority: Priority.high,
            payload: 'live_session:$debriefSessionId',
          );
          _onLiveInvite?.call(debriefSessionId, debriefTitle);
        }
    }
  }

  void Function(String sessionId, String title)? _onLiveInvite;

  void setLiveInviteCallback(void Function(String, String) cb) => _onLiveInvite = cb;
  void clearLiveInviteCallback() => _onLiveInvite = null;

  // ── Local notification helpers ─────────────────────────────────────────────

  Future<void> _show({
    required int id,
    required String channelId,
    required String title,
    String? body,
    String? payload,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelName(channelId),
          importance: importance,
          priority: priority,
          playSound: true,
          enableLights: channelId == 'sos',
          color: channelId == 'sos' ? const Color(0xFFDC2626) : const Color(0xFF22C55E),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel:
              channelId == 'sos' ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
        ),
      ),
      payload: payload,
    );
  }

  // Show a notification directly from app code (e.g. after SOS button press confirmation)
  Future<void> showLocal({
    required String title,
    String? body,
    String channel = 'general',
  }) =>
      _show(
        id: _nextId(),
        channelId: channel,
        title: title,
        body: body,
        importance: _importanceFor(channel),
        priority: _priorityFor(channel),
      );

  int _nextId() => _notifId++;

  String _channelFor(String notifType) {
    if (notifType.contains('mission')) return 'missions';
    if (notifType.contains('message')) return 'messages';
    if (notifType.contains('sos')) return 'sos';
    return 'general';
  }

  String _channelName(String channelId) {
    switch (channelId) {
      case 'sos':
        return 'SOS Alerts';
      case 'missions':
        return 'Missions';
      case 'messages':
        return 'Messages';
      default:
        return 'General';
    }
  }

  Importance _importanceFor(String channel) {
    switch (channel) {
      case 'sos':
        return Importance.max;
      case 'missions':
      case 'messages':
        return Importance.high;
      default:
        return Importance.defaultImportance;
    }
  }

  Priority _priorityFor(String channel) {
    switch (channel) {
      case 'sos':
        return Priority.max;
      case 'missions':
      case 'messages':
        return Priority.high;
      default:
        return Priority.defaultPriority;
    }
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (payload != null && payload.startsWith('live_session:')) {
      final sessionId = payload.substring('live_session:'.length);
      LiveSessionScreen.pendingJoinSessionId = sessionId;
      nav.pushNamed('/live');
    } else if (payload != null && payload.startsWith('mission:')) {
      appTabNotifier.value = 2;
      nav.pushNamedAndRemoveUntil('/home', (r) => false);
    } else {
      nav.pushNamed('/notifications');
    }
  }
}
