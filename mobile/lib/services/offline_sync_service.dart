import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Persists location updates in a local SQLite queue when the network is
/// unavailable and exposes [flush] to drain the queue when back online.
class OfflineSyncService {
  static Database? _db;

  Future<Database> get _database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'drd_offline.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE location_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          retries INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
  }

  Future<void> enqueue(String userId, Map<String, dynamic> payload) async {
    final db = await _database;
    await db.insert('location_queue', {
      'user_id': userId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'retries': 0,
    });
  }

  /// Sends all queued entries using [postFn].
  /// Returns the number of entries still pending after the flush.
  Future<int> flush(Future<bool> Function(Map<String, dynamic>) postFn) async {
    final db = await _database;
    final rows = await db.query('location_queue', orderBy: 'id ASC', limit: 50);
    for (final row in rows) {
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final ok = await postFn(payload);
      if (ok) {
        await db.delete(
          'location_queue',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      } else {
        final retries = (row['retries'] as int) + 1;
        if (retries >= 5) {
          // Give up on entries that repeatedly fail to avoid infinite growth.
          await db.delete(
            'location_queue',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else {
          await db.update(
            'location_queue',
            {'retries': retries},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    }
    return await getPendingCount();
  }

  Future<int> getPendingCount() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM location_queue',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> clearAll() async {
    final db = await _database;
    await db.delete('location_queue');
  }
}
