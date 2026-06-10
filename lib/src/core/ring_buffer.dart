/// A fixed-capacity FIFO buffer.
///
/// When [length] reaches [capacity], adding a new item evicts the oldest one.
/// [items] returns a newest-first, unmodifiable snapshot suitable for direct
/// rendering in a list.
///
/// Backed by a plain [List]: eviction shifts elements (a contiguous memmove,
/// no allocation), and [replace] is a single index assignment.
class RingBuffer<T> {
  /// Creates a ring buffer holding at most [capacity] items.
  ///
  /// [capacity] must be greater than zero.
  RingBuffer(this.capacity) : assert(capacity > 0, 'capacity must be > 0');

  /// Maximum number of retained items.
  final int capacity;

  // Oldest item first, newest last.
  final List<T> _items = <T>[];
  List<T>? _cachedItems;

  /// Appends [item], evicting the oldest item if at capacity.
  void add(T item) {
    if (_items.length >= capacity) {
      _items.removeAt(0);
    }
    _items.add(item);
    _cachedItems = null;
  }

  /// Replaces the first occurrence of [oldItem] (by `==`) with [newItem],
  /// keeping its position. Returns `false` when [oldItem] is no longer
  /// buffered (e.g. already evicted).
  bool replace(T oldItem, T newItem) {
    final index = _items.indexOf(oldItem);
    if (index < 0) return false;
    _items[index] = newItem;
    _cachedItems = null;
    return true;
  }

  /// A newest-first, unmodifiable snapshot of the buffered items.
  List<T> get items {
    _cachedItems ??= List<T>.unmodifiable(_items.toList().reversed);
    return _cachedItems!;
  }

  /// Removes all items.
  void clear() {
    _items.clear();
    _cachedItems = null;
  }

  /// The current number of buffered items.
  int get length => _items.length;

  /// Whether the buffer holds no items.
  bool get isEmpty => _items.isEmpty;
}
