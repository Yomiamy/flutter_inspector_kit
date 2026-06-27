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
  });
}
