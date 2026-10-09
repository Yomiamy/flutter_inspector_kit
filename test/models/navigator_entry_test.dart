import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigatorEntry implements TimestampedEntry', () {
    final fixedTime = DateTime(2026, 6, 26, 14, 30, 1, 123);

    test('is a TimestampedEntry', () {
      final entry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
      );
      expect(entry, isA<TimestampedEntry>());
    });

    test('displayTime formats as HH:mm:ss.mmm', () {
      final entry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
      );
      expect(entry.displayTime, '14:30:01.123');
    });

    test('routingParams defaults to null and can be supplied', () {
      final entry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        routingParams: {'id': '42'},
      );
      expect(entry.routingParams, {'id': '42'});
    });

    test('copyWith updates routingParams', () {
      final entry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        routingParams: {'tab': 'one'},
      );
      final copied = entry.copyWith(routingParams: {'tab': 'two'});
      expect(copied.routingParams, {'tab': 'two'});
    });

    test('operator == and hashCode compare routingParams correctly', () {
      final entryA = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
        routingParams: {'a': '1'},
      );
      final entryB = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
        routingParams: {'a': '1'},
      );
      final entryC = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
        routingParams: {'a': '2'},
      );

      expect(entryA, equals(entryB));
      expect(entryA.hashCode, equals(entryB.hashCode));
      expect(entryA, isNot(equals(entryC)));
    });
  });
}
