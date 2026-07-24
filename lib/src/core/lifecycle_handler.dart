import 'package:flutter/widgets.dart';

import '../models/log_level.dart';
import 'uncaught_error_handler.dart' show LogCallback;

/// Records app lifecycle transitions as [LogLevel.info] log entries.
///
/// Registers itself on [WidgetsBinding.instance] as an observer. Flutter keeps
/// observers in a list, so the host app's own observers keep receiving their
/// callbacks unaffected.
class LifecycleHandler with WidgetsBindingObserver {
  /// The function called to log a lifecycle transition.
  final LogCallback onLog;

  bool _attached = false;

  /// Creates a new LifecycleHandler instance.
  LifecycleHandler({required this.onLog});

  /// Registers this handler as a [WidgetsBindingObserver].
  ///
  /// Idempotent: the `_attached` flag ensures a single state change is never
  /// recorded twice by the same instance.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Removes this handler from [WidgetsBinding.instance].
  ///
  /// Safe to call when not attached, and safe to call twice.
  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      onLog('App lifecycle: ${state.name}', level: LogLevel.info);
    } catch (e, s) {
      debugPrintStack(
        stackTrace: s,
        label: 'inspector lifecycle log failed: $e',
      );
    }
  }
}
