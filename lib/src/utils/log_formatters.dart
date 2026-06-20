import '../models/log_entry.dart';

/// Pure formatting helpers for the Console inspector. No Flutter dependencies,
/// so everything here is unit-testable in isolation.

/// Builds a full plain-text export of [entry] covering general info,
/// stack trace, and data sections.
String buildLogPlainText(LogEntry entry) {
  final b = StringBuffer()
    ..writeln('=== General ===')
    ..writeln('Message: ${entry.message}')
    ..writeln('Level: ${entry.level.name}')
    ..writeln('Timestamp: ${entry.timestamp.toIso8601String()}');

  b.writeln('\n=== Stack Trace ===');
  final stackTrace = entry.stackTrace;
  if (stackTrace != null && stackTrace.isNotEmpty) {
    b.writeln(stackTrace);
  } else {
    b.writeln('(none)');
  }

  b.writeln('\n=== Data ===');
  final data = entry.data;
  if (data != null && data.isNotEmpty) {
    data.forEach((k, v) => b.writeln('$k: $v'));
  } else {
    b.writeln('(none)');
  }

  return b.toString().trimRight();
}
