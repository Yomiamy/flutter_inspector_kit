import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake implementation to test default parameters
class FakeDatabaseBrowserSource extends DatabaseBrowserSource {
  @override
  String get name => 'FakeSource';

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    return [];
  }

  // We capture the limit and offset passed to verify defaults
  int? lastLimit;
  int? lastOffset;

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    lastLimit = limit;
    lastOffset = offset;
    return DatabaseTablePage(columns: [], rows: []);
  }
}

void main() {
  group('DatabaseTableInfo', () {
    test('supports construction and equality', () {
      final info1 = DatabaseTableInfo(name: 'users', rowCount: 10);
      final info2 = DatabaseTableInfo(name: 'users', rowCount: 10);
      final info3 = DatabaseTableInfo(name: 'users', rowCount: null);
      final info4 = DatabaseTableInfo(name: 'posts', rowCount: 10);

      expect(info1, equals(info2));
      expect(info1.hashCode, equals(info2.hashCode));
      expect(info1, isNot(equals(info3)));
      expect(info1, isNot(equals(info4)));
      expect(info1.toString(), contains('users'));
    });
  });

  group('DatabaseTablePage', () {
    test('supports construction and equality', () {
      final page1 = DatabaseTablePage(
        columns: ['id', 'name'],
        rows: [
          [1, 'Alice'],
          [2, 'Bob'],
        ],
        totalRows: 2,
      );
      final page2 = DatabaseTablePage(
        columns: ['id', 'name'],
        rows: [
          [1, 'Alice'],
          [2, 'Bob'],
        ],
        totalRows: 2,
      );
      final page3 = DatabaseTablePage(
        columns: ['id', 'name'],
        rows: [
          [1, 'Alice'],
        ],
        totalRows: 2,
      );

      expect(page1, equals(page2));
      expect(page1.hashCode, equals(page2.hashCode));
      expect(page1, isNot(equals(page3)));
    });
  });

  group('DatabaseBrowserSource Interface', () {
    test('verifies default parameters of fetchRows', () async {
      final source = FakeDatabaseBrowserSource();
      await source.fetchRows('users');
      expect(source.lastLimit, equals(200));
      expect(source.lastOffset, equals(0));
    });
  });
}
