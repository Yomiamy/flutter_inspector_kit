import '../core/ring_buffer.dart';
import '../models/database_entry.dart';
import '../models/database_operation.dart';

/// Manages a ring buffer of [DatabaseEntry] items.
class DatabaseInspector {
  /// Creates a database inspector with the given [bufferCapacity].
  DatabaseInspector({int bufferCapacity = 500})
    : _buffer = RingBuffer<DatabaseEntry>(bufferCapacity);

  final RingBuffer<DatabaseEntry> _buffer;

  /// Returns an unmodifiable list of the buffered database entries, newest first.
  List<DatabaseEntry> get entries => _buffer.items;

  /// Returns entries filtered by the given [operation].
  List<DatabaseEntry> getEntriesByOperation(DatabaseOperation operation) {
    return _buffer.items.where((e) => e.operation == operation).toList();
  }

  /// Returns entries filtered by the given [tableName].
  List<DatabaseEntry> getEntriesByTable(String tableName) {
    return _buffer.items.where((e) => e.tableName == tableName).toList();
  }

  /// Adds a [DatabaseEntry] to the buffer.
  void add(DatabaseEntry entry) {
    _buffer.add(entry);
  }

  /// Clears the buffer.
  void clear() => _buffer.clear();
}
