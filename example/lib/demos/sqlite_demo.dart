import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:sqflite/sqflite.dart';

import '../db/sqlite/sqflite_browser_source.dart';

/// Demonstrates browsing a SQLite (sqflite) database in the inspector.
///
/// Owns the database handle and registration state so the host UI doesn't have
/// to. Call [seed] from a button, [dispose] from the State's dispose().
class SqliteDemo {
  SqliteDemo(this._inspector);

  final FlutterInspector _inspector;
  bool _registered = false;
  Database? _db;

  /// The seed rows shared by both demo tables. One row has a null email and one
  /// a null age, to exercise the inspector's null rendering.
  static const List<Map<String, Object?>> _seedRows = [
    {'id': 1, 'name': 'Alice', 'email': 'alice@example.com', 'age': 30},
    {'id': 2, 'name': 'Bob', 'email': null, 'age': 25},
    {'id': 3, 'name': 'Carol', 'email': 'carol@example.com', 'age': null},
  ];

  /// Opens demo.db, seeds it if empty, and registers it with the inspector.
  ///
  /// Returns a status message for the caller to surface (e.g. via SnackBar).
  /// Idempotent: a second call after a successful registration is a no-op.
  Future<String?> seed() async {
    if (_registered) return null;
    try {
      final databasesPath = await getDatabasesPath();
      final path = '$databasesPath/demo.db';

      // version 2 added the `member` table. Both onCreate (fresh install) and
      // onUpgrade (existing demo.db from v1, which only had `users`) build the
      // tables via the same IF NOT EXISTS statements, so a device with an old
      // single-table db still gets `member` instead of failing on query.
      _db = await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          await _createTable(db, 'users');
          await _createTable(db, 'member');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createTable(db, 'member');
        },
      );

      await _seedTableIfEmpty('users');
      await _seedTableIfEmpty('member');

      if (_db != null) {
        _inspector.registerDatabaseSource(
          SqfliteBrowserSource(_db!, name: 'demo.db'),
        );
        _registered = true;
      }
      return 'SQLite demo.db initialized and registered!';
    } catch (e) {
      return 'SQLite seeding failed: $e';
    }
  }

  Future<void> _createTable(Database db, String table) {
    return db.execute(
      'CREATE TABLE IF NOT EXISTS $table '
      '(id INTEGER PRIMARY KEY, name TEXT, email TEXT, age INTEGER)',
    );
  }

  Future<void> _seedTableIfEmpty(String table) async {
    final result = await _db?.rawQuery('SELECT COUNT(*) as count FROM $table');
    final count = Sqflite.firstIntValue(result ?? []) ?? 0;
    if (count > 0) return;
    for (final row in _seedRows) {
      await _db?.insert(table, row);
    }
  }

  void dispose() {
    _db?.close();
  }
}
