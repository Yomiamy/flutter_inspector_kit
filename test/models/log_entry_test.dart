import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogEntry', () {
    final fixedTime = DateTime(2026, 6, 9, 12, 0, 0);

    test('constructs with defaults', () {
      final entry = LogEntry(message: 'hello', timestamp: fixedTime);
      expect(entry.message, 'hello');
      expect(entry.level, LogLevel.info);
      expect(entry.stackTrace, isNull);
      expect(entry.data, isNull);
      expect(entry.timestamp, fixedTime);
    });

    test('defaults timestamp to now when omitted', () {
      final before = DateTime.now();
      final entry = LogEntry(message: 'x');
      final after = DateTime.now();
      expect(
        entry.timestamp.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        entry.timestamp.isAfter(after.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('copyWith replaces only given fields', () {
      final entry = LogEntry(
        message: 'a',
        level: LogLevel.warning,
        timestamp: fixedTime,
      );
      final copy = entry.copyWith(message: 'b');
      expect(copy.message, 'b');
      expect(copy.level, LogLevel.warning);
      expect(copy.timestamp, fixedTime);
    });

    test('equality and hashCode', () {
      final a = LogEntry(
        message: 'a',
        level: LogLevel.error,
        timestamp: fixedTime,
        data: const {'k': 'v'},
      );
      final b = LogEntry(
        message: 'a',
        level: LogLevel.error,
        timestamp: fixedTime,
        data: const {'k': 'v'},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains level and message', () {
      final entry = LogEntry(
        message: 'boom',
        level: LogLevel.error,
        timestamp: fixedTime,
      );
      expect(entry.toString(), contains('error'));
      expect(entry.toString(), contains('boom'));
    });
  });
}
