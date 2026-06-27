import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseEntry', () {
    final fixedTime = DateTime(2026, 6, 27, 14, 30, 1, 123);

    test('implements TimestampedEntry', () {
      final entry = DatabaseEntry(
        operation: DatabaseOperation.query,
        tableName: 'users',
        timestamp: fixedTime,
      );
      expect(entry, isA<TimestampedEntry>());
    });

    test('displayTime returns HH:mm:ss.mmm format', () {
      final entry = DatabaseEntry(
        operation: DatabaseOperation.query,
        tableName: 'users',
        timestamp: fixedTime,
      );
      // fixedTime = DateTime(2026, 6, 27, 14, 30, 1, 123) → 14:30:01.123
      expect(entry.displayTime, '14:30:01.123');
    });

    test('displayTime pads single-digit components', () {
      final entry = DatabaseEntry(
        operation: DatabaseOperation.insert,
        tableName: 'orders',
        timestamp: DateTime(2026, 1, 1, 9, 5, 3, 7),
      );
      expect(entry.displayTime, '09:05:03.007');
    });
  });
}
