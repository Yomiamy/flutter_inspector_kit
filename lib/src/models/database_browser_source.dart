import 'package:flutter/foundation.dart';

/// An abstract interface representing a browseable database source.
abstract class DatabaseBrowserSource {
  /// The user-facing name of the source, e.g., 'Operation log', 'app.db'.
  String get name;

  /// Lists all tables in this database source.
  Future<List<DatabaseTableInfo>> listTables();

  /// Fetches a page of rows from the specified [tableName].
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  });
}

/// Metadata about a database table.
@immutable
class DatabaseTableInfo {
  const DatabaseTableInfo({required this.name, this.rowCount});

  /// The table name.
  final String name;

  /// The total row count in the table, or null if unavailable.
  final int? rowCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseTableInfo &&
        other.name == name &&
        other.rowCount == rowCount;
  }

  @override
  int get hashCode => Object.hash(name, rowCount);

  @override
  String toString() => 'DatabaseTableInfo($name, rows: $rowCount)';
}

/// A page of rows returned from a database table query.
@immutable
class DatabaseTablePage {
  const DatabaseTablePage({
    required this.columns,
    required this.rows,
    this.totalRows,
  });

  /// The column headers.
  final List<String> columns;

  /// The row data, where each row is a list of cell values matching [columns].
  final List<List<Object?>> rows;

  /// The total rows in the table, or null if unavailable.
  final int? totalRows;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DatabaseTablePage) return false;
    if (other.totalRows != totalRows) return false;
    if (!listEquals(other.columns, columns)) return false;
    if (other.rows.length != rows.length) return false;
    for (var i = 0; i < rows.length; i++) {
      if (!listEquals(other.rows[i], rows[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(columns),
    Object.hashAll(rows.map((row) => Object.hashAll(row))),
    totalRows,
  );

  @override
  String toString() =>
      'DatabaseTablePage(columns: $columns, rows: ${rows.length}, total: $totalRows)';
}
