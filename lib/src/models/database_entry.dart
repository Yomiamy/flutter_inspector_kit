import 'package:flutter/foundation.dart';

import 'database_operation.dart';
import 'timestamped_entry.dart';

/// An immutable record of a database operation, displayed in the Database tab.
@immutable
class DatabaseEntry implements TimestampedEntry {
  /// Creates a database entry. [timestamp] defaults to the moment of creation.
  DatabaseEntry({
    required this.operation,
    required this.tableName,
    this.data,
    this.affectedRows,
    this.activeRoute,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// When the operation was recorded.
  @override
  final DateTime timestamp;

  /// The kind of operation.
  final DatabaseOperation operation;

  /// The affected table name.
  final String tableName;

  /// Optional structured payload (row data, query result summary, etc.).
  final Map<String, dynamic>? data;

  /// Optional number of affected rows.
  final int? affectedRows;

  /// The route the user was on when this operation ran, in
  /// [NavigatorEntry.routeLabel] format.
  ///
  /// Recorded at write time rather than derived later: it is what anchors this
  /// entry to a user-facing context on the merged timeline. Null when the
  /// navigator stack was empty (e.g. before the first route was pushed).
  final String? activeRoute;

  /// Returns a copy of this entry with the given fields replaced.
  DatabaseEntry copyWith({
    DateTime? timestamp,
    DatabaseOperation? operation,
    String? tableName,
    Map<String, dynamic>? data,
    int? affectedRows,
    String? activeRoute,
  }) {
    return DatabaseEntry(
      timestamp: timestamp ?? this.timestamp,
      operation: operation ?? this.operation,
      tableName: tableName ?? this.tableName,
      data: data ?? this.data,
      affectedRows: affectedRows ?? this.affectedRows,
      activeRoute: activeRoute ?? this.activeRoute,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DatabaseEntry &&
        other.timestamp == timestamp &&
        other.operation == operation &&
        other.tableName == tableName &&
        mapEquals(other.data, data) &&
        other.affectedRows == affectedRows &&
        other.activeRoute == activeRoute;
  }

  @override
  int get hashCode => Object.hash(
    timestamp,
    operation,
    tableName,
    data,
    affectedRows,
    activeRoute,
  );

  @override
  String toString() =>
      'DatabaseEntry(${operation.name}, $tableName, rows: $affectedRows)';
}
