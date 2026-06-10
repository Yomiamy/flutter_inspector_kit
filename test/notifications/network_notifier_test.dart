import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_inspector/src/notifications/network_notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

    // Note: init() drives the real flutter_local_notifications plugin, which
    // needs a platform binding and cannot be initialised in a plain unit test
    // (it throws LateInitializationError). Its permission-request behaviour is
    // verified manually via the example app, not here, to avoid mocking the
    // entire plugin chain — kept out in line with this package's mock-free
    // test style.
  });

  group('buildDetails', () {
    group('alert: true (heads-up state)', () {
      late NotificationDetails details;

      setUp(() {
        details = NetworkNotifier.buildDetails(alert: true);
      });

      test('android importance is high', () {
        expect(details.android!.importance, equals(Importance.high));
      });

      test('android priority is high', () {
        expect(details.android!.priority, equals(Priority.high));
      });

      test('android onlyAlertOnce is false (re-alerts on each show)', () {
        expect(details.android!.onlyAlertOnce, isFalse);
      });

      test('android silent is false (heads-up visible)', () {
        expect(details.android!.silent, isFalse);
      });

      test('android ongoing is true', () {
        expect(details.android!.ongoing, isTrue);
      });

      test('android playSound is false (silent heads-up)', () {
        expect(details.android!.playSound, isFalse);
      });

      test('android channelId is flutter_inspector_network_v2', () {
        expect(details.android!.channelId, equals('flutter_inspector_network_v2'));
      });

      test('iOS presentBanner is true (foreground banner)', () {
        expect(details.iOS!.presentBanner, isTrue);
      });

      test('iOS presentList is true (stays in notification centre)', () {
        expect(details.iOS!.presentList, isTrue);
      });

      test('iOS presentSound is false (no sound)', () {
        expect(details.iOS!.presentSound, isFalse);
      });
    });

    group('alert: false (silent/throttled state)', () {
      late NotificationDetails details;

      setUp(() {
        details = NetworkNotifier.buildDetails(alert: false);
      });

      test('android importance is still high (channel level unchanged)', () {
        expect(details.android!.importance, equals(Importance.high));
      });

      test('android priority is still high', () {
        expect(details.android!.priority, equals(Priority.high));
      });

      test('android onlyAlertOnce is true (suppress re-alert)', () {
        expect(details.android!.onlyAlertOnce, isTrue);
      });

      test('android silent is true (double-guard suppress heads-up)', () {
        expect(details.android!.silent, isTrue);
      });

      test('android ongoing is true', () {
        expect(details.android!.ongoing, isTrue);
      });

      test('android playSound is false', () {
        expect(details.android!.playSound, isFalse);
      });

      test('android channelId is flutter_inspector_network_v2', () {
        expect(details.android!.channelId, equals('flutter_inspector_network_v2'));
      });

      test('iOS presentBanner is false (no banner when throttled)', () {
        expect(details.iOS!.presentBanner, isFalse);
      });

      test('iOS presentList is true (still appears in notification centre)', () {
        expect(details.iOS!.presentList, isTrue);
      });

      test('iOS presentSound is false', () {
        expect(details.iOS!.presentSound, isFalse);
      });
    });
  });
}
