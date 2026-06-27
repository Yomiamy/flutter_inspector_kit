import '../inspectors/database_inspector.dart';
import '../inspectors/log_inspector.dart';
import '../inspectors/navigator_inspector.dart';
import '../inspectors/network_inspector.dart';
import '../models/timestamped_entry.dart';

/// Internal registry holding instances of the four fixed inspectors.
class InspectorRegistry {
  /// Creates a registry with inspectors initialized to the given [bufferSize].
  InspectorRegistry({int bufferSize = 500})
    : log = LogInspector(bufferSize: bufferSize),
      network = NetworkInspector(bufferCapacity: bufferSize),
      navigator = NavigatorInspector(bufferCapacity: bufferSize),
      database = DatabaseInspector(bufferCapacity: bufferSize);

  /// Inspector for console logs.
  final LogInspector log;

  /// Inspector for network requests.
  final NetworkInspector network;

  /// Inspector for navigation events.
  final NavigatorInspector navigator;

  /// Inspector for database operations.
  final DatabaseInspector database;

  /// Merges the four buffers into a single timeline, filtered by [sources] and
  /// sorted by [TimestampedEntry.timestamp] descending (newest first).
  ///
  /// Filtering happens at the collection stage (an `if` decides whether a buffer
  /// is read at all), not during sorting. Descending order matches the
  /// newest-first convention of [RingBuffer.items]. Defaults to all sources.
  ///
  /// Returns the original entry pointers (no copy, no second source of truth):
  /// a network entry that later transitions pending -> completed is reflected on
  /// the next read, because the same buffer is read each time.
  List<TimestampedEntry> mergedTimeline({
    Set<TimelineSource> sources = const {
      TimelineSource.log,
      TimelineSource.network,
      TimelineSource.nav,
      TimelineSource.db,
    },
  }) {
    final merged = <TimestampedEntry>[];
    if (sources.contains(TimelineSource.log)) merged.addAll(log.entries);
    if (sources.contains(TimelineSource.network)) {
      merged.addAll(network.entries);
    }
    if (sources.contains(TimelineSource.nav)) merged.addAll(navigator.entries);
    if (sources.contains(TimelineSource.db)) merged.addAll(database.entries);
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // descending
    return merged;
  }
}
