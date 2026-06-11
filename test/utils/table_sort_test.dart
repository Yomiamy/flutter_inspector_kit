import 'package:flutter_inspector_kit/src/utils/table_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareCells', () {
    test('compares numbers correctly', () {
      expect(compareCells(5, 10), isNegative);
      expect(compareCells(10, 5), isPositive);
      expect(compareCells(5, 5), equals(0));
      expect(compareCells(9, 10.5), isNegative);
    });

    test('compares strings correctly', () {
      expect(compareCells('apple', 'banana'), isNegative);
      expect(compareCells('banana', 'apple'), isPositive);
      expect(compareCells('apple', 'apple'), equals(0));
    });

    test('compares mixed types as string representation', () {
      expect(
        compareCells(5, '10'),
        isPositive,
      ); // '5'.compareTo('10') is positive
      expect(compareCells(5, '5'), equals(0));
    });

    test('treats null as maximum', () {
      expect(compareCells(null, 100), isPositive);
      expect(compareCells(100, null), isNegative);
      expect(compareCells(null, null), equals(0));
    });
  });

  group('sortRows', () {
    final rows = [
      [2, 'banana'],
      [null, 'cherry'],
      [1, 'apple'],
      [3, null],
    ];

    test('sorts ascending on number column with null last', () {
      final sorted = sortRows(rows, 0, true);
      expect(sorted, [
        [1, 'apple'],
        [2, 'banana'],
        [3, null],
        [null, 'cherry'],
      ]);
      // Ensure immutability
      expect(rows[0][0], equals(2));
    });

    test('sorts descending on number column with null last', () {
      final sorted = sortRows(rows, 0, false);
      expect(sorted, [
        [3, null],
        [2, 'banana'],
        [1, 'apple'],
        [null, 'cherry'],
      ]);
    });

    test('sorts ascending on string column with null last', () {
      final sorted = sortRows(rows, 1, true);
      expect(sorted, [
        [1, 'apple'],
        [2, 'banana'],
        [null, 'cherry'],
        [3, null],
      ]);
    });

    test('sorts descending on string column with null last', () {
      final sorted = sortRows(rows, 1, false);
      expect(sorted, [
        [null, 'cherry'],
        [2, 'banana'],
        [1, 'apple'],
        [3, null],
      ]);
    });
  });

  group('cellPreview', () {
    test('renders null as NULL', () {
      expect(cellPreview(null), equals('NULL'));
    });

    test('renders short values without truncation', () {
      expect(cellPreview('hello'), equals('hello'));
      expect(cellPreview(123), equals('123'));
    });

    test('truncates long values and appends ellipsis', () {
      final longStr = 'a' * 105;
      final preview = cellPreview(longStr, maxLength: 100);
      expect(preview.length, equals(101)); // 100 chars + 1 ellipsis char
      expect(preview.endsWith('…'), isTrue);
      expect(preview.substring(0, 100), equals('a' * 100));
    });

    test('handles boundary lengths', () {
      expect(cellPreview('a' * 99, maxLength: 100).length, equals(99));
      expect(cellPreview('a' * 100, maxLength: 100).length, equals(100));
      expect(cellPreview('a' * 101, maxLength: 100).length, equals(101));
    });
  });
}
