import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';

enum QueuedOpType { location, message, sos }

class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  Database? _db;
  StreamSubscription? _connectSub;
  bool _flushing = false;

  Future<void> init() async {
    final dbPath = p.join(await getDatabasesPath(), 'drd_offline_queue.db');
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          endpoint TEXT NOT NULL,
          body TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    });

    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet) flushQueue();
    });
  }

  Future<void> dispose() async {
    await _connectSub?.cancel();
    await _db?.close();
  }

  Future<void> enqueue(QueuedOpType type, String endpoint, Map<String, dynamic> body) async {
    if (_db == null) return;
    await _db!.insert('queue', {
      'type': type.name,
      'endpoint': endpoint,
      'body': jsonEncode(body),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> queueLocation(double lat, double lng, {double? alt, double? speed, double? heading}) async {
    await enqueue(QueuedOpType.location, '/locations', {
      'latitude': lat,
      'longitude': lng,
      if (alt != null) 'altitude': alt,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> queueMessage(String content, String channel) async {
    await enqueue(QueuedOpType.message, '/messages', {'content': content, 'channel': channel});
  }

  Future<void> queueSOS({double? lat, double? lng, String? message}) async {
    await enqueue(QueuedOpType.sos, '/sos', {
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
      if (message != null) 'message': message,
    });
  }

  Future<int> get pendingCount async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery('SELECT COUNT(*) as c FROM queue');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> flushQueue() async {
    if (_db == null || _flushing) return;
    _flushing = true;
    try {
      final rows = await _db!.query('queue', orderBy: 'created_at ASC', limit: 50);
      if (rows.isEmpty) return;

      final api = ApiService();
      for (final row in rows) {
        final id = row['id'] as int;
        final endpoint = row['endpoint'] as String;
        final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
        try {
          await api.post(endpoint, body);
          await _db!.delete('queue', where: 'id = ?', whereArgs: [id]);
        } on ApiException catch (e) {
          if (e.statusCode >= 400 && e.statusCode < 500) {
            // Client error (bad data) — drop it
            await _db!.delete('queue', where: 'id = ?', whereArgs: [id]);
          } else {
            // Server error / network — stop flushing, retry later
            break;
          }
        } catch (_) {
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> clearQueue() async {
    await _db?.delete('queue');
  }
}
