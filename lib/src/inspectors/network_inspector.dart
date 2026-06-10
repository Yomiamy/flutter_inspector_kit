import '../core/ring_buffer.dart';
import '../models/network_entry.dart';

/// Callback invoked after a [NetworkEntry] is buffered. [totalCount] is the
/// current number of buffered entries.
typedef NetworkAddListener = void Function(NetworkEntry entry, int totalCount);

/// Manages a ring buffer of [NetworkEntry] items.
class NetworkInspector {
  /// Creates a network inspector with the given [bufferCapacity].
  NetworkInspector({int bufferCapacity = 500})
      : _buffer = RingBuffer<NetworkEntry>(bufferCapacity);

  final RingBuffer<NetworkEntry> _buffer;

  /// Optional listener notified after each [add]. Kept as a plain callback so
  /// this layer never depends on UI or notification code (one-way dependency).
  NetworkAddListener? onAdd;

  /// Returns an unmodifiable list of the buffered network entries, newest first.
  List<NetworkEntry> get entries => _buffer.items;

  /// Adds a [NetworkEntry] to the buffer.
  ///
  /// The request and response bodies will be automatically truncated
  /// if they exceed [kNetworkBodyMaxLength].
  void add(NetworkEntry entry) {
    final requestBody = NetworkEntry.truncateBody(entry.requestBody);
    final responseBody = NetworkEntry.truncateBody(entry.responseBody);

    if (requestBody != entry.requestBody ||
        responseBody != entry.responseBody) {
      entry = entry.copyWith(
        requestBody: requestBody,
        responseBody: responseBody,
      );
    }
    _buffer.add(entry);
    onAdd?.call(entry, _buffer.length);
  }

  /// Clears the buffer.
  void clear() => _buffer.clear();
}
