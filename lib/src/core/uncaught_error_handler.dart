import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/log_level.dart';

/// Signature for the function used to log an error.
typedef LogCallback =
    void Function(
      String message, {
      required LogLevel level,
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
  // ponytail: only tracks the last logged details, dedups the common
  // FlutterError.onError + ErrorWidget.builder double-fire for the same
  // error; a bounded history would be needed to dedup non-adjacent repeats.
  FlutterErrorDetails? _lastLoggedDetails;

  /// Creates a new UncaughtErrorHandler instance.
  UncaughtErrorHandler({required this.onLog});

  /// Attaches the three standard Flutter error hooks, chaining/wrapping any
  /// existing host handler so errors are always forwarded downstream.
  ///
  /// Idempotent: the `_attached` flag ensures hooks are attached at most once.
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
    if (identical(details, _lastLoggedDetails)) return;
    _lastLoggedDetails = details;

    final message = details.exceptionAsString();
    final data = <String, dynamic>{
      'source': source,
      'exceptionType': details.exception.runtimeType.toString(),
    };
    final library = details.library;
    if (library != null) data['library'] = library;
    final context = details.context;
    if (context != null) data['context'] = context.toString();

    final overflowInfo = parseRenderFlexOverflow(message) ??
        parseRenderFlexOverflow(details.exception.toString());
    if (overflowInfo != null) {
      data.addAll(overflowInfo);
    }

    onLog(
      message,
      level: LogLevel.error,
      stackTrace: details.stack?.toString(),
      data: data,
    );
  }
}

final _renderFlexOverflowPattern = RegExp(
  r'A RenderFlex overflowed by (\d+(?:\.\d+)?(?:e[+-]?\d+)?) pixels on the (\w+)',
  caseSensitive: false,
);

/// Attempts to parse RenderFlex overflow details from an error [message].
/// Returns a map with `isRenderFlexOverflow`, `overflowPixels`, and
/// `overflowDirection` if matched, or null otherwise.
Map<String, dynamic>? parseRenderFlexOverflow(String message) {
  final match = _renderFlexOverflowPattern.firstMatch(message);
  if (match == null) return null;
  final pixelsStr = match.group(1);
  final direction = match.group(2)?.toLowerCase();
  if (pixelsStr == null || direction == null) return null;
  final pixels = double.tryParse(pixelsStr);
  if (pixels == null) return null;
  return {
    'isRenderFlexOverflow': true,
    'overflowPixels': pixels,
    'overflowDirection': direction,
  };
}
