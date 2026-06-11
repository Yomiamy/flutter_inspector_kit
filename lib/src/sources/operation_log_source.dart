import '../inspectors/database_inspector.dart';
import '../models/database_browser_source.dart';

/// A [DatabaseBrowserSource] that wraps a [DatabaseInspector]
/// to present its operation log history as virtual database tables.
class OperationLogSource implements DatabaseBrowserSource {
  OperationLogSource(this._inspector);

  final DatabaseInspector _inspector;

  @override
  String get name => 'Operation log';

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    final entries = _inspector.entries;
    final tableCounts = <String, int>{};

    for (final entry in entries) {
      tableCounts[entry.tableName] = (tableCounts[entry.tableName] ?? 0) + 1;
    }

    final sortedNames = tableCounts.keys.toList()..sort();
    return sortedNames
        .map(
          (name) => DatabaseTableInfo(name: name, rowCount: tableCounts[name]),
        )
        .toList();
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final entries = _inspector.getEntriesByTable(tableName);
    if (entries.isEmpty) {
      return const DatabaseTablePage(
        columns: ['#time', '#op', '#rows'],
        rows: [],
        totalRows: 0,
      );
    }

    // Determine the columns by scanning oldest-first to keep order stable
    final oldestFirst = entries.reversed.toList();
    final dataKeys = <String>{};
    for (final entry in oldestFirst) {
      if (entry.data != null) {
        dataKeys.addAll(entry.data!.keys);
      }
    }

    final columns = ['#time', '#op', '#rows', ...dataKeys];

    // Paginate entries (which are newest-first)
    final totalRows = entries.length;
    final start = offset.clamp(0, totalRows);
    final end = (offset + limit).clamp(0, totalRows);
    final paginatedEntries = entries.sublist(start, end);

    final List<List<Object?>> rows = [];
    for (final entry in paginatedEntries) {
      final row = <Object?>[
        entry.timestamp.toIso8601String(),
        entry.operation.name,
        entry.affectedRows,
      ];
      for (final key in dataKeys) {
        row.add(entry.data?[key]);
      }
      rows.add(row);
    }

    return DatabaseTablePage(
      columns: columns,
      rows: rows,
      totalRows: totalRows,
    );
  }
}
