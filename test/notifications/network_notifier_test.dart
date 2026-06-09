import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_inspector/src/notifications/network_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkNotifier (degraded / not initialised)', () {
    test('is unavailable before init', () {
      final notifier = NetworkNotifier();
      expect(notifier.isAvailable, isFalse);
    });

    test('showOrUpdate is a safe no-op when unavailable', () async {
      final notifier = NetworkNotifier();
      // No init() called -> _available is false -> must not throw.
      await expectLater(
        notifier.showOrUpdate(
          NetworkEntry(method: 'GET', url: '/x', statusCode: 200),
          1,
        ),
        completes,
      );
    });

    test('cancel is a safe no-op when unavailable', () async {
      final notifier = NetworkNotifier();
      await expectLater(notifier.cancel(), completes);
    });
  });
}
