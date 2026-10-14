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

    test('queryParams defaults to null and can be supplied', () {
      final entry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        queryParams: {'id': '42'},
      );
      expect(entry.queryParams, {'id': '42'});
    });

    test('copyWith updates queryParams', () {
      final entry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        queryParams: {'tab': 'one'},
      );
      final copied = entry.copyWith(queryParams: {'tab': 'two'});
      expect(copied.queryParams, {'tab': 'two'});
    });

    test('operator == and hashCode compare queryParams correctly', () {
      final entryA = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
        queryParams: {'a': '1'},
      );
      final entryB = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
        queryParams: {'a': '1'},
      );
      final entryC = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        timestamp: fixedTime,
        queryParams: {'a': '2'},
      );

      expect(entryA, equals(entryB));
      expect(entryA.hashCode, equals(entryB.hashCode));
      expect(entryA, isNot(equals(entryC)));
    });

    test('queryParams and argParams are distinct fields', () {
      final asQuery = NavigatorEntry(
        action: NavigatorAction.push,
        timestamp: fixedTime,
        queryParams: {'id': '1'},
      );
      final asArgs = NavigatorEntry(
        action: NavigatorAction.push,
        timestamp: fixedTime,
        argParams: {'id': '1'},
      );

      expect(asQuery, isNot(equals(asArgs)));
      expect(asArgs.copyWith(action: NavigatorAction.pop).argParams, {
        'id': '1',
      });
      expect(() => asArgs.argParams?['id'] = '2', throwsUnsupportedError);
    });

    test('queryParams cannot be modified externally', () {
      final map = {'id': '42'};
      final entry = NavigatorEntry(
        action: NavigatorAction.push,
        routeName: '/home',
        queryParams: map,
      );
      map['id'] = '99';
      expect(entry.queryParams?['id'], '42');
      expect(() => entry.queryParams?['id'] = '100', throwsUnsupportedError);
    });
  });
}
