/// Throttles alert notifications to at most once every 5 seconds.
///
/// The throttler maintains a single mutable state ([_lastAlertAt]) to track
/// when the last successful alert occurred. [shouldAlert()] checks whether
/// the current time is outside the 5-second window and, if so, updates
/// [_lastAlertAt] and returns true; otherwise returns false. This design
/// ensures judgment and state update are atomic — callers cannot receive
/// true without the state being committed.
class AlertThrottler {
  /// Creates a throttler with a 5-second window.
  ///
  /// [now] supplies the current time; by default it is [DateTime.now].
  /// In tests, pass a custom clock function to control time progression
  /// without flaky sleeps.
  AlertThrottler({
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now());

  /// The fixed throttle window duration.
  static const Duration window = Duration(seconds: 5);

  /// Clock function for testing; by default [DateTime.now].
  final DateTime Function() _now;

  /// The timestamp of the last successful alert, or null if none yet.
  DateTime? _lastAlertAt;

  /// Checks whether an alert should be shown.
  ///
  /// Returns true if no alert has been shown yet, or if at least [window]
  /// has elapsed since [_lastAlertAt]. If true, updates [_lastAlertAt]
  /// to the current time as a side effect.
  ///
  /// Returns false if an alert was shown recently (within [window]).
  bool shouldAlert() {
    final now = _now();
    if (_lastAlertAt == null || now.difference(_lastAlertAt!).compareTo(window) >= 0) {
      _lastAlertAt = now;
      return true;
    }
    return false;
  }
}
