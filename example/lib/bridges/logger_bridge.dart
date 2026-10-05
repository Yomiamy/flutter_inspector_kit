import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:logger/logger.dart';

/// Forwards one `logger` event to [inspector] as exactly one log entry.
///
/// Reads the structured [OutputEvent.origin] rather than the printer's
/// `lines`, so no ANSI colours or box borders reach the Console and the
/// stack trace lands in its own tappable field.
void forwardLoggerEvent(FlutterInspector inspector, OutputEvent event) {
  final origin = event.origin;
  final raw = origin.message;
  final message = '${raw is Function ? raw() : raw}';
  inspector.log(
    [message, origin.error].nonNulls.join('\n'),
    level: _toInspectorLevel(origin.level),
    stackTrace: origin.stackTrace?.toString(),
  );
}

// Thresholds, not a switch: deprecated levels (verbose, wtf) fall into the
// right band without being named, which would trip deprecated_member_use.
LogLevel _toInspectorLevel(Level level) {
  if (level >= Level.error) return LogLevel.error;
  if (level >= Level.warning) return LogLevel.warning;
  if (level >= Level.info) return LogLevel.info;
  if (level >= Level.debug) return LogLevel.debug;
  return LogLevel.verbose;
}
