import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/notifications/alert_throttler.dart';
import 'package:flutter_inspector_kit/src/notifications/network_notifier.dart';
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

  group('showOrUpdate throttler wiring (T3)', () {
    // These tests verify that AlertThrottler is properly wired into
    // showOrUpdate by observing shouldAlert() state through a test-injected
    // throttler. The notifier stays unavailable (no init) so the _plugin.show
    // path is never hit — we only care that the throttler guard is placed
    // AFTER the _available guard, meaning unavailability must NOT consume the
    // throttle window.

    test('unavailable: showOrUpdate does not consume a throttle slot', () async {
      // A fresh throttler: first shouldAlert() call must still return true
      // after showOrUpdate is called on an unavailable notifier.
      DateTime fakeNow = DateTime(2026, 1, 1);
      final throttler = AlertThrottler(now: () => fakeNow);
      final notifier = NetworkNotifier(throttler: throttler);
      // _available is false — no init()
      await notifier.showOrUpdate(
        NetworkEntry(method: 'GET', url: '/test', statusCode: 200),
        1,
      );
      // Throttler state must be untouched: first shouldAlert() still true.
      expect(throttler.shouldAlert(), isTrue,
          reason: 'unavailable guard must fire before throttler.shouldAlert()');
    });

    // The following tests exercise the throttler logic paths that are visible
    // from the outside: a fake throttler with a controlled clock is injected.
    // Because _available remains false, _plugin.show is never called, so we
    // cannot observe whether buildDetails used alert:true or alert:false
    // directly here. The correctness of the alert/silent mapping is already
    // covered by the buildDetails group above. What we verify here is only
    // that the guard ordering is correct (unavailable ⇒ no throttle slot
    // consumed).
    //
    // Full integration of throttler→details is deliberately left to T4
    // real-device verification per the plan's mock-free convention.
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
