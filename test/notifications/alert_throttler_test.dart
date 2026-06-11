import 'package:flutter_inspector_kit/src/notifications/alert_throttler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlertThrottler', () {
    test('first shouldAlert() returns true', () {
      final throttler = AlertThrottler();
      expect(throttler.shouldAlert(), isTrue);
    });

    test('second shouldAlert() within window returns false', () {
      final throttler = AlertThrottler();
      throttler.shouldAlert();
      expect(throttler.shouldAlert(), isFalse);
    });

    test('shouldAlert() returns false within window (1.999 seconds)', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      var currentTime = now;
      final throttler = AlertThrottler(now: () => currentTime);

      expect(throttler.shouldAlert(), isTrue);
      currentTime = currentTime.add(const Duration(milliseconds: 1999));
      expect(throttler.shouldAlert(), isFalse);
    });

    test('shouldAlert() returns true after window (2+ seconds)', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      var currentTime = now;
      final throttler = AlertThrottler(now: () => currentTime);

      expect(throttler.shouldAlert(), isTrue);
      currentTime = currentTime.add(const Duration(milliseconds: 2000));
      expect(throttler.shouldAlert(), isTrue);
    });

    test('shouldAlert() returns true exactly at 2-second boundary', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      var currentTime = now;
      final throttler = AlertThrottler(now: () => currentTime);

      expect(throttler.shouldAlert(), isTrue);
      currentTime = currentTime.add(const Duration(seconds: 2));
      expect(throttler.shouldAlert(), isTrue);
    });

    test('burst of 20 calls in rapid succession yields only first true', () {
      final throttler = AlertThrottler();
      final results = [for (int i = 0; i < 20; i++) throttler.shouldAlert()];

      // First should be true, rest false
      expect(results[0], isTrue);
      for (int i = 1; i < 20; i++) {
        expect(results[i], isFalse, reason: 'Call $i should be false');
      }
    });

    test('window resets after successful alert', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      var currentTime = now;
      final throttler = AlertThrottler(now: () => currentTime);

      // First alert
      expect(throttler.shouldAlert(), isTrue);

      // Still in window
      currentTime = currentTime.add(const Duration(seconds: 1));
      expect(throttler.shouldAlert(), isFalse);

      // After window expires
      currentTime = currentTime.add(
        const Duration(seconds: 1, milliseconds: 500),
      );
      expect(throttler.shouldAlert(), isTrue);

      // Window resets, so immediate next call should fail
      expect(throttler.shouldAlert(), isFalse);
    });

    test('consecutive alerts across windows respect timing', () {
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      var currentTime = now;
      final throttler = AlertThrottler(now: () => currentTime);

      // First alert at T=0
      expect(throttler.shouldAlert(), isTrue);

      // Second alert at T=2
      currentTime = currentTime.add(const Duration(seconds: 2));
      expect(throttler.shouldAlert(), isTrue);

      // Third alert at T=4
      currentTime = currentTime.add(const Duration(seconds: 2));
      expect(throttler.shouldAlert(), isTrue);

      // All should be true with 2-second gaps
    });
  });
}
