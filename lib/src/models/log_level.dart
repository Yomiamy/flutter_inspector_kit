/// Severity level for a console log entry.
///
/// Ordered from least to most severe so that filtering by a minimum level
/// can rely on the declaration order via [LogLevel.index].
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
}
