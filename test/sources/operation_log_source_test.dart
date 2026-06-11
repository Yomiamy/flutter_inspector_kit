import 'package:flutter_inspector_kit/src/inspectors/database_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/sources/operation_log_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OperationLogSource', () {
    late DatabaseInspector inspector;
    late OperationLogSource source;

    setUp(() {
      inspector = DatabaseInspector();
      source = OperationLogSource(inspector);
    });

    test('name is Operation log', () {
      expect(source.name, equals('Operation log'));
    });

    test('listTables returns empty list when no entries', () async {
      final tables = await source.listTables();
      expect(tables, isEmpty);
    });

    test(
      'listTables groups and sorts tables alphabetically with row counts',
      () async {
        inspector.add(
          DatabaseEntry(
            operation: DatabaseOperation.insert,
            tableName: 'users',
          ),
        );
        inspector.add(
          DatabaseEntry(
            operation: DatabaseOperation.insert,
            tableName: 'posts',
          ),
        );
        inspector.add(
          DatabaseEntry(
            operation: DatabaseOperation.update,
            tableName: 'users',
          ),
        );

        final tables = await source.listTables();
        expect(tables.length, equals(2));
        expect(tables[0].name, equals('posts'));
        expect(tables[0].rowCount, equals(1));
        expect(tables[1].name, equals('users'));
        expect(tables[1].rowCount, equals(2));
      },
    );

    test(
      'fetchRows for non-existent table returns empty page with metadata columns',
      () async {
        final page = await source.fetchRows('non-existent');
        expect(page.columns, equals(['#time', '#op', '#rows']));
        expect(page.rows, isEmpty);
        expect(page.totalRows, equals(0));
      },
    );

    test(
      'fetchRows builds columns union based on oldest-first first appearance',
      () async {
        // Oldest entry (first added): has 'id' and 'name'
        final entry1 = DatabaseEntry(
          operation: DatabaseOperation.insert,
          tableName: 'users',
          data: {'id': 1, 'name': 'Alice'},
          timestamp: DateTime(2026, 6, 11, 10, 0),
        );
        // Middle entry: has 'name' and 'age'
        final entry2 = DatabaseEntry(
          operation: DatabaseOperation.insert,
          tableName: 'users',
          data: {'name': 'Bob', 'age': 25},
          timestamp: DateTime(2026, 6, 11, 10, 5),
        );
        // Newest entry: has 'email'
        final entry3 = DatabaseEntry(
          operation: DatabaseOperation.update,
          tableName: 'users',
          data: {'email': 'carol@example.com'},
          timestamp: DateTime(2026, 6, 11, 10, 10),
        );

        // We add them. Remember RingBuffer outputs newest first.
        // But we determine column union order by scanning oldest-first (entry1 -> entry2 -> entry3).
        // Order of appearance:
        // entry1: 'id', 'name'
        // entry2: 'age' (name already seen)
        // entry3: 'email'
        // Final columns: '#time', '#op', '#rows', 'id', 'name', 'age', 'email'
        inspector.add(entry1);
        inspector.add(entry2);
        inspector.add(entry3);

        final page = await source.fetchRows('users');
        expect(
          page.columns,
          equals(['#time', '#op', '#rows', 'id', 'name', 'age', 'email']),
        );
      },
    );

    test(
      'fetchRows returns rows newest first and fills missing keys with null',
      () async {
        final time1 = DateTime(2026, 6, 11, 10, 0);
        final time2 = DateTime(2026, 6, 11, 10, 5);

        final entry1 = DatabaseEntry(
          operation: DatabaseOperation.insert,
          tableName: 'users',
          data: {'id': 1, 'name': 'Alice'},
          affectedRows: 1,
          timestamp: time1,
        );
        final entry2 = DatabaseEntry(
          operation: DatabaseOperation.update,
          tableName: 'users',
          data: {'name': 'Bob', 'age': 25},
          affectedRows: 2,
          timestamp: time2,
        );

        inspector.add(entry1);
        inspector.add(entry2);

        // Columns should be: '#time', '#op', '#rows', 'id', 'name', 'age'
        final page = await source.fetchRows('users');

        expect(page.rows.length, equals(2));
        // First row (newest: entry2)
        expect(
          page.rows[0],
          equals([
            time2.toIso8601String(),
            'update',
            2,
            null, // id is missing
            'Bob',
            25,
          ]),
        );
        // Second row (oldest: entry1)
        expect(
          page.rows[1],
          equals([
            time1.toIso8601String(),
            'insert',
            1,
            1,
            'Alice',
            null, // age is missing
          ]),
        );
        expect(page.totalRows, equals(2));
      },
    );

    test('fetchRows supports pagination (limit and offset)', () async {
      for (var i = 1; i <= 5; i++) {
        inspector.add(
          DatabaseEntry(
            operation: DatabaseOperation.insert,
            tableName: 'users',
            data: {'id': i},
            timestamp: DateTime(2026, 6, 11, 10, i),
          ),
        );
      }

      // 5 entries: id=5 (newest) down to id=1 (oldest)
      // fetch with limit 2, offset 1 should give id=4 and id=3
      final page = await source.fetchRows('users', limit: 2, offset: 1);
      expect(page.totalRows, equals(5));
      expect(page.rows.length, equals(2));
      // Index of 'id' column is 3 (after #time, #op, #rows)
      expect(page.rows[0][3], equals(4));
      expect(page.rows[1][3], equals(3));
    });
  });
}
