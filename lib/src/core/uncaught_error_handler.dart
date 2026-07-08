import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/log_level.dart';

/// Signature for the function used to log an error.
typedef LogCallback = void Function(
  String message, {
  LogLevel level,
  String? stackTrace,
  Map<String, dynamic>? data,
});

/// Handles attaching error hooks and forwarding to a log function.
class UncaughtErrorHandler {

  /// The function called to log an error.
  final LogCallback onLog;

  FlutterExceptionHandler? _oldFlutterErrorHandler;
  bool Function(Object, StackTrace)? _oldPlatformDispatcherOnError;
  bool _attached = false;

  /// Creates a new UncaughtErrorHandler instance.
  UncaughtErrorHandler({required this.onLog});
  /// Attaches the three standard Flutter error hooks, chaining/wrapping any
  /// existing host handler so errors are always forwarded downstream.
  ///
  /// Idempotent: the dedup flag ensures hooks are attached at most once.
  void attach() {
    if (_attached) return;
    _attached = true;

    // 1) FlutterError.onError — chain.
    _oldFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      try {
        _logFlutterError(details, source: 'flutterError');
      } catch (e, s) {
        debugPrintStack(stackTrace: s, label: 'inspector log failed: $e');
      }
      if (_oldFlutterErrorHandler != null) {
        _oldFlutterErrorHandler!(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    // 2) PlatformDispatcher.instance.onError — chain.
    _oldPlatformDispatcherOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, st) {
      try {
        onLog(
          e.toString(),
          level: LogLevel.error,
          stackTrace: st.toString(),
          data: {
            'source': 'platformDispatcher',
            'exceptionType': e.runtimeType.toString(),
          },
        );
      } catch (err, s) {
        debugPrintStack(stackTrace: s, label: 'inspector log failed: $err');
      }
      final old = _oldPlatformDispatcherOnError;
      return old != null ? old(e, st) : false;
    };

    // 3) ErrorWidget.builder — wrap.
    final original = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      try {
        _logFlutterError(details, source: 'errorWidget');
      } catch (e, s) {
        debugPrintStack(
          stackTrace: s,
          label: 'inspector errorWidget log failed: $e',
        );
      }
      return original(details);
    };
  }

  void _logFlutterError(FlutterErrorDetails details, {required String source}) {
    final data = <String, dynamic>{
      'source': source,
      'exceptionType': details.exception.runtimeType.toString(),
    };
    final library = details.library;
    if (library != null) data['library'] = library;
    final context = details.context;
    if (context != null) data['context'] = context.toString();

    onLog(
      details.exceptionAsString(),
      level: LogLevel.error,
      stackTrace: details.stack?.toString(),
      data: data,
    );
  }
}
