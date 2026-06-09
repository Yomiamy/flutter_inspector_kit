import 'dart:collection';

/// A fixed-capacity FIFO buffer.
///
/// Appending is amortized O(1). When [length] reaches [capacity], adding a new
/// item evicts the oldest one. [items] returns a newest-first, unmodifiable
/// snapshot suitable for direct rendering in a list.
class RingBuffer<T> {
  /// Creates a ring buffer holding at most [capacity] items.
  ///
  /// [capacity] must be greater than zero.
  RingBuffer(this.capacity) : assert(capacity > 0, 'capacity must be > 0');

  /// Maximum number of retained items.
  final int capacity;

  // Oldest item at the head, newest at the tail.
  final ListQueue<T> _items = ListQueue<T>();

  /// Appends [item], evicting the oldest item if at capacity.
  void add(T item) {
    if (_items.length >= capacity) {
      _items.removeFirst();
    }
    _items.addLast(item);
  }

  /// A newest-first, unmodifiable snapshot of the buffered items.
  List<T> get items => List<T>.unmodifiable(_items.toList().reversed);

  /// Removes all items.
  void clear() => _items.clear();

  /// The current number of buffered items.
  int get length => _items.length;

  /// Whether the buffer holds no items.
  bool get isEmpty => _items.isEmpty;
}
