import '../core/ring_buffer.dart';
import '../models/log_entry.dart';
import '../models/log_level.dart';

/// Stores console log entries in a bounded buffer for the Console tab.
class LogInspector {
  /// Creates a log inspector retaining at most [bufferSize] entries.
  LogInspector({int bufferSize = 500})
    : _buffer = RingBuffer<LogEntry>(bufferSize);

  final RingBuffer<LogEntry> _buffer;

  /// Records a log entry.
  void add(LogEntry entry) => _buffer.add(entry);

  /// All entries, newest first.
  List<LogEntry> get entries => _buffer.items;

  /// Entries at exactly [level], newest first.
  List<LogEntry> entriesAtLevel(LogLevel level) =>
      _buffer.items.where((e) => e.level == level).toList();

  /// Clears all entries.
  void clear() => _buffer.clear();
}
