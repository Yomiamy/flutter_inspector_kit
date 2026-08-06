import 'package:flutter/foundation.dart';

import '../inspectors/database_inspector.dart';
import '../inspectors/log_inspector.dart';
import '../inspectors/navigator_inspector.dart';
import '../inspectors/network_inspector.dart';
import '../models/timestamped_entry.dart';

/// Internal registry holding instances of the four fixed inspectors.
class InspectorRegistry {
  /// Creates a registry with inspectors initialized to the given [bufferSize].
  ///
  /// Each inspector's [onMutate] is wired to [_bump], so [revision] increments
  /// on every mutation of any of the four buffers.
  InspectorRegistry({int bufferSize = 500}) {
    log = LogInspector(bufferSize: bufferSize, onMutate: _bump);
    network = NetworkInspector(bufferCapacity: bufferSize, onMutate: _bump);
    navigator = NavigatorInspector(bufferCapacity: bufferSize, onMutate: _bump);
    database = DatabaseInspector(bufferCapacity: bufferSize, onMutate: _bump);
  }

  /// Inspector for console logs.
  late final LogInspector log;

  /// Inspector for network requests.
  late final NetworkInspector network;

  /// Inspector for navigation events.
  late final NavigatorInspector navigator;

  /// Inspector for database operations.
  late final DatabaseInspector database;

  // Not disposed: this registry (and the inspector that owns it) is a
  // long-lived, app-scoped object with no dispose lifecycle. Leak protection
  // is the subscriber's responsibility (see _DashboardTabBar.dispose).
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Bumped on every mutation of any of the four buffers (add, successful
  /// replace, or clear). Read-only to callers; not part of the package's
  /// public API surface.
  ValueListenable<int> get revision => _revision;

  void _bump() => _revision.value++;

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
