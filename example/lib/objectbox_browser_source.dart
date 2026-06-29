import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:objectbox/objectbox.dart';

import 'objectbox.g.dart';
import 'objectbox_entities.dart';

/// A reference implementation of [DatabaseBrowserSource] for ObjectBox.
///
/// You can copy this code directly into your app to browse ObjectBox data.
///
/// Why this looks different from the sqflite source: a relational DB exposes a
/// dynamic schema (`SELECT *` returns column names for free). ObjectBox is a
/// strongly-typed object store with NO runtime schema reflection — so YOU
/// describe the schema, by registering one [_EntityAdapter] per entity type.
class ObjectBoxBrowserSource implements DatabaseBrowserSource {
  ObjectBoxBrowserSource(this._store, {this.name = 'ObjectBox database'});

  final Store _store;

  @override
  final String name;

  /// The "schema you write yourself": each entity type maps to its columns,
  /// a row count, and a function that flattens an object into a row.
  late final Map<String, _EntityAdapter> _adapters = {
    'Note': _EntityAdapter(
      columns: const ['id', 'title', 'body'],
      count: () => _store.box<Note>().count(),
      fetch: (limit, offset) => _store
          .box<Note>()
          .getAll()
          .skip(offset)
          .take(limit)
          .map((n) => [n.id, n.title, n.body])
          .toList(),
    ),
    'Tag': _EntityAdapter(
      columns: const ['id', 'label'],
      count: () => _store.box<Tag>().count(),
      fetch: (limit, offset) => _store
          .box<Tag>()
          .getAll()
          .skip(offset)
          .take(limit)
          .map((t) => [t.id, t.label])
          .toList(),
    ),
  };

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    return _adapters.entries
        .map((e) => DatabaseTableInfo(name: e.key, rowCount: e.value.count()))
        .toList();
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final adapter = _adapters[tableName];
    if (adapter == null) {
      // Unknown table — return an empty page rather than throwing, so the UI
      // degrades gracefully.
      return const DatabaseTablePage(columns: [], rows: [], totalRows: 0);
    }
    // NOTE: For production / large tables, replace getAll().skip().take() with
    // box.query().build()..offset = offset..limit = limit; then .find().
    // getAll() loads everything into memory — fine for this demo's tiny data.
    return DatabaseTablePage(
      columns: adapter.columns,
      rows: adapter.fetch(limit, offset),
      totalRows: adapter.count(),
    );
  }
}

/// Binds one entity type to the way it should appear as a browsable table.
class _EntityAdapter {
  _EntityAdapter({
    required this.columns,
    required this.count,
    required this.fetch,
  });

  final List<String> columns;
  final int Function() count;
  final List<List<Object?>> Function(int limit, int offset) fetch;
}
