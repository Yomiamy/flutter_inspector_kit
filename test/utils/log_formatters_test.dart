import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/utils/log_formatters.dart';

void main() {
  group('buildLogPlainText', () {
    test('formats complete entry with all sections', () {
      final timestamp = DateTime(2026, 6, 20, 10, 30, 45);
      final entry = LogEntry(
        message: 'Test error occurred',
        level: LogLevel.error,
        stackTrace: 'Frame 0: testFunction\nFrame 1: main',
        data: {'key1': 'value1', 'key2': 'value2'},
        timestamp: timestamp,
      );

      final result = buildLogPlainText(entry);

      expect(result, contains('=== General ==='));
      expect(result, contains('Message: Test error occurred'));
      expect(result, contains('Level: error'));
      expect(result, contains('Timestamp: 2026-06-20T10:30:45.000'));
      expect(result, contains('=== Stack Trace ==='));
      expect(result, contains('Frame 0: testFunction'));
      expect(result, contains('Frame 1: main'));
      expect(result, contains('=== Data ==='));
      expect(result, contains('key1: value1'));
      expect(result, contains('key2: value2'));
    });

    test('handles null stack trace with (none)', () {
      final entry = LogEntry(
        message: 'Info log',
        level: LogLevel.info,
        stackTrace: null,
      );

      final result = buildLogPlainText(entry);

      expect(result, contains('=== Stack Trace ==='));
      expect(result, contains('(none)'));
      expect(result, isNot(contains('null')));
    });

    test('handles empty stack trace with (none)', () {
      final entry = LogEntry(
        message: 'Info log',
        level: LogLevel.info,
        stackTrace: '',
      );

      final result = buildLogPlainText(entry);

      expect(result, contains('=== Stack Trace ==='));
      expect(result, contains('(none)'));
    });

    test('handles null data with (none)', () {
      final entry = LogEntry(
        message: 'Debug log',
        level: LogLevel.debug,
        data: null,
      );

      final result = buildLogPlainText(entry);

      expect(result, contains('=== Data ==='));
      expect(result, contains('(none)'));
      expect(result, isNot(contains('null')));
    });

    test('handles empty data map with (none)', () {
      final entry = LogEntry(
        message: 'Warning log',
        level: LogLevel.warning,
        data: {},
      );

      final result = buildLogPlainText(entry);

      expect(result, contains('=== Data ==='));
      expect(result, contains('(none)'));
    });

    test('does not have trailing newlines', () {
      final entry = LogEntry(
        message: 'Test message',
        level: LogLevel.verbose,
      );

      final result = buildLogPlainText(entry);

      expect(result, isNot(endsWith('\n')));
    });

    test('formats all log levels correctly', () {
      for (final level in LogLevel.values) {
        final entry = LogEntry(
          message: 'Test',
          level: level,
        );

        final result = buildLogPlainText(entry);

        expect(result, contains('Level: ${level.name}'));
      }
    });

    test('preserves data value types in output', () {
      final entry = LogEntry(
        message: 'Complex data',
        level: LogLevel.info,
        data: {
          'string': 'text',
          'number': 42,
          'boolean': true,
          'null_value': null,
        },
      );

      final result = buildLogPlainText(entry);

      expect(result, contains('string: text'));
      expect(result, contains('number: 42'));
      expect(result, contains('boolean: true'));
      expect(result, contains('null_value: null'));
    });

    test('formats multi-line stack traces correctly', () {
      final stackTrace = '''Frame 0: method1
Frame 1: method2
Frame 2: method3''';
      final entry = LogEntry(
        message: 'Error',
        level: LogLevel.error,
        stackTrace: stackTrace,
      );

      final result = buildLogPlainText(entry);

      expect(result, contains('Frame 0: method1'));
      expect(result, contains('Frame 1: method2'));
      expect(result, contains('Frame 2: method3'));
    });

    test('minimal entry with only required fields', () {
      final entry = LogEntry(message: 'Simple log');

      final result = buildLogPlainText(entry);

      expect(result, contains('=== General ==='));
      expect(result, contains('Message: Simple log'));
      expect(result, contains('Level: info'));
      expect(result, contains('=== Stack Trace ==='));
      expect(result, contains('(none)'));
      expect(result, contains('=== Data ==='));
      expect(result, contains('(none)'));
      expect(result, isNot(endsWith('\n')));
    });
  });
}
