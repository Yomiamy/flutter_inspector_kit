import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:sqflite/sqflite.dart';

/// A reference implementation of [DatabaseBrowserSource] for SQLite databases.
///
/// You can copy this code directly into your app to browse SQLite tables.
class SqfliteBrowserSource implements DatabaseBrowserSource {
  SqfliteBrowserSource(this._db, {this.name = 'SQLite database'});

  final Database _db;

  @override
  final String name;

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    // Select all user tables from sqlite_master
    final List<Map<String, Object?>> tables = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    final List<DatabaseTableInfo> result = [];
    for (final table in tables) {
      final name = table['name'] as String;
      // Fetch the row count for each table
      final countResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM "$name"',
      );
      final rowCount = Sqflite.firstIntValue(countResult);
      result.add(DatabaseTableInfo(name: name, rowCount: rowCount));
    }
    return result;
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    // Fetch total rows count
    final countResult = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM "$tableName"',
    );
    final totalRows = Sqflite.firstIntValue(countResult) ?? 0;

    // Fetch the page of rows
    final List<Map<String, Object?>> queryResult = await _db.rawQuery(
      'SELECT * FROM "$tableName" LIMIT ? OFFSET ?',
      [limit, offset],
    );

    if (queryResult.isEmpty) {
      // If the result is empty, retrieve columns using table_info PRAGMA
      // to still display the schema columns in the UI.
      final tableInfo = await _db.rawQuery('PRAGMA table_info("$tableName")');
      final columns = tableInfo.map((info) => info['name'] as String).toList();
      return DatabaseTablePage(
        columns: columns,
        rows: const [],
        totalRows: totalRows,
      );
    }

    final columns = queryResult.first.keys.toList();
    final rows = queryResult.map((map) {
      return columns.map((col) => map[col]).toList();
    }).toList();

    return DatabaseTablePage(
      columns: columns,
      rows: rows,
      totalRows: totalRows,
    );
  }
}
