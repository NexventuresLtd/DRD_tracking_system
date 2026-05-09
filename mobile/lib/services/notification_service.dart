import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  Future<void> showNewRoute(String routeName, String teamName) async {
    await _show(
      id: 1001,
      title: '📍 New Mission Assigned',
      body: '$routeName — tap to view your route in the tactical map.',
      channelId: 'routes',
      channelName: 'Mission Routes',
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  Future<void> showLiveRequest(String soldierName, String teamName) async {
    await _show(
      id: 1002,
      title: '🔴 LIVE: $soldierName',
      body: '$soldierName from $teamName is requesting a live video feed.',
      channelId: 'live',
      channelName: 'Live Feeds',
      importance: Importance.max,
      priority: Priority.max,
    );
  }

  Future<void> showTeammateNotification(String message, {int id = 1003}) async {
    await _show(
      id: id,
      title: '📡 Team Alert',
      body: message,
      channelId: 'team',
      channelName: 'Team Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required Importance importance,
    required Priority priority,
  }) async {
    if (!_initialized) await init();
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: importance,
          priority: priority,
          enableVibration: true,
          playSound: true,
          color: const Color(0xFF3B82F6),
          ledColor: const Color(0xFF3B82F6),
          ledOnMs: 300,
          ledOffMs: 1000,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}

