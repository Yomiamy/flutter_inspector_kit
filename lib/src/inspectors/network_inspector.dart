import 'package:flutter/foundation.dart';

import '../core/ring_buffer.dart';
import '../models/network_entry.dart';
import '../utils/image_bytes.dart';

/// Callback invoked after a [NetworkEntry] is buffered. [totalCount] is the
/// current number of buffered entries.
typedef NetworkAddListener = void Function(NetworkEntry entry, int totalCount);

// A cut body keeps the size it had; a size the capture layer measured wins.
// A body already ending in the marker is a summary, not the payload.
int? _sizeBeforeCut(String? body, String? truncated, int? known) {
  if (known != null || body == null || body == truncated) return known;
  if (body.endsWith(kTruncatedMarker)) return null;
  return _utf8Length(body);
}

// utf8.encode(body).length without allocating the encoded copy; a lone
// surrogate encodes as U+FFFD (3 bytes), as utf8.encode does.
int _utf8Length(String text) {
  var bytes = 0;
  for (final rune in text.runes) {
    bytes += rune < 0x80
        ? 1
        : rune < 0x800
        ? 2
        : rune < 0x10000
        ? 3
        : 4;
  }
  return bytes;
}

/// Manages a ring buffer of [NetworkEntry] items.
class NetworkInspector {
  /// Creates a network inspector with the given [bufferCapacity].
  /// [onMutate], if given, is forwarded to the underlying [RingBuffer].
  NetworkInspector({int bufferCapacity = 500, VoidCallback? onMutate})
    : _buffer = RingBuffer<NetworkEntry>(bufferCapacity, onMutate: onMutate);

  final RingBuffer<NetworkEntry> _buffer;

  /// Optional listener notified after each [add]. Kept as a plain callback so
  /// this layer never depends on UI or notification code (one-way dependency).
  NetworkAddListener? onAdd;

  /// Returns an unmodifiable list of the buffered network entries, newest first.
  List<NetworkEntry> get entries => _buffer.items;

  /// Adds a [NetworkEntry] to the buffer and returns the stored entry
  /// (which may differ from [entry] when a body was truncated).
  ///
  /// When [replaces] is given, the stored occurrence of that entry is
  /// swapped in place instead of appending — this is how a pending request
  /// entry becomes its completed counterpart without leaving a duplicate.
  /// If [replaces] was already evicted from the buffer, [entry] is appended.
  ///
  /// The request and response bodies will be automatically truncated
  /// if they exceed [kNetworkBodyMaxLength]. A body cut here keeps its real
  /// size in [NetworkEntry.requestBodyLength] or
  /// [NetworkEntry.responseBodyLength], unless the entry already carried one.
  ///
  /// Preview bytes ([NetworkEntry.responseImageBytes]) above [kImageMaxBytes]
  /// are dropped, and once all previews exceed [kImageBudgetBytes] the oldest
  /// entries lose theirs.
  NetworkEntry add(NetworkEntry entry, {NetworkEntry? replaces}) {
    final requestBody = NetworkEntry.truncateBody(entry.requestBody);
    final responseBody = NetworkEntry.truncateBody(entry.responseBody);
    final oversized = (entry.responseImageBytes?.length ?? 0) > kImageMaxBytes;

    if (requestBody != entry.requestBody ||
        responseBody != entry.responseBody ||
        oversized) {
      entry = entry.copyWith(
        requestBody: requestBody,
        requestBodyLength: _sizeBeforeCut(
          entry.requestBody,
          requestBody,
          entry.requestBodyLength,
        ),
        responseBody: responseBody,
        responseBodyLength: _sizeBeforeCut(
          entry.responseBody,
          responseBody,
          entry.responseBodyLength,
        ),
        clearResponseImageBytes: oversized,
      );
    }
    if (replaces == null || !_buffer.replace(replaces, entry)) {
      _buffer.add(entry);
    }
    // Runs after the write above has returned, never inside onMutate
    // (CLAUDE.md invariant #1).
    if (entry.responseImageBytes != null) _evictImageBytes();
    onAdd?.call(entry, _buffer.length);
    return entry;
  }

  /// Drops preview bytes from the oldest entries until all previews fit in
  /// [kImageBudgetBytes]. The stripped copy is `==` to the original, so
  /// [RingBuffer.replace] finds its slot and bookmarks still match.
  void _evictImageBytes() {
    final oldestFirst = _buffer.items.reversed; // items is a snapshot
    var total = 0;
    for (final e in oldestFirst) {
      total += e.responseImageBytes?.length ?? 0;
    }
    for (final e in oldestFirst) {
      if (total <= kImageBudgetBytes) return;
      final bytes = e.responseImageBytes;
      if (bytes == null) continue;
      _buffer.replace(e, e.copyWith(clearResponseImageBytes: true));
      total -= bytes.length;
    }
  }

  /// Clears the buffer.
  void clear() => _buffer.clear();
}
