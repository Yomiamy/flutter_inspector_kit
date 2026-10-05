import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:logging/logging.dart';

/// Forwards one `logging` record to [inspector] as exactly one log entry,
/// prefixed with the logger name (`[Auth] token expired`) so the source
/// module is visible and searchable on the timeline row.
void forwardLogRecord(FlutterInspector inspector, LogRecord record) {
  final name = record.loggerName;
  final message = name.isEmpty ? record.message : '[$name] ${record.message}';
  inspector.log(
    [message, record.error].nonNulls.join('\n'),
    level: _toInspectorLevel(record.level),
    stackTrace: record.stackTrace?.toString(),
  );
}

// Thresholds: Level is an open class (hosts may define their own), so only a
// range check covers every possible value.
LogLevel _toInspectorLevel(Level level) {
  if (level >= Level.SEVERE) return LogLevel.error;
  if (level >= Level.WARNING) return LogLevel.warning;
  if (level >= Level.INFO) return LogLevel.info;
  if (level >= Level.FINE) return LogLevel.debug;
  return LogLevel.verbose;
}
