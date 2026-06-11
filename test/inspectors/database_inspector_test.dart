import 'package:flutter_inspector_kit/src/inspectors/database_inspector.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseInspector', () {
    late DatabaseInspector inspector;

    setUp(() {
      inspector = DatabaseInspector(bufferCapacity: 3);
    });

    test('adds database entries and returns newest first', () {
      final entry1 = DatabaseEntry(
        operation: DatabaseOperation.insert,
        tableName: 'users',
      );
      final entry2 = DatabaseEntry(
        operation: DatabaseOperation.query,
        tableName: 'posts',
      );

      inspector.add(entry1);
      inspector.add(entry2);

      expect(inspector.entries, [entry2, entry1]);
    });

    test('filters by operation', () {
      final entry1 = DatabaseEntry(
        operation: DatabaseOperation.insert,
        tableName: 'users',
      );
      final entry2 = DatabaseEntry(
        operation: DatabaseOperation.query,
        tableName: 'posts',
      );
      inspector.add(entry1);
      inspector.add(entry2);

      final result = inspector.getEntriesByOperation(DatabaseOperation.insert);
      expect(result, [entry1]);
    });

    test('filters by table name', () {
      final entry1 = DatabaseEntry(
        operation: DatabaseOperation.insert,
        tableName: 'users',
      );
      final entry2 = DatabaseEntry(
        operation: DatabaseOperation.query,
        tableName: 'posts',
      );
      inspector.add(entry1);
      inspector.add(entry2);

      final result = inspector.getEntriesByTable('posts');
      expect(result, [entry2]);
    });

    test('clears buffer', () {
      inspector.add(
        DatabaseEntry(operation: DatabaseOperation.insert, tableName: 'users'),
      );
      inspector.clear();
      expect(inspector.entries, isEmpty);
    });
  });
}
