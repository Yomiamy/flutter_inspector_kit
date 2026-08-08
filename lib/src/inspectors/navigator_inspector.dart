import 'package:flutter/foundation.dart';

import '../core/ring_buffer.dart';
import '../models/navigator_entry.dart';

/// Manages a ring buffer of [NavigatorEntry] items.
class NavigatorInspector {
  /// Creates a navigator inspector with the given [bufferCapacity].
  /// [onMutate], if given, is forwarded to the underlying [RingBuffer].
  NavigatorInspector({int bufferCapacity = 500, VoidCallback? onMutate})
    : _buffer = RingBuffer<NavigatorEntry>(bufferCapacity, onMutate: onMutate);

  final RingBuffer<NavigatorEntry> _buffer;

  /// Returns an unmodifiable list of the buffered navigator entries, newest first.
  List<NavigatorEntry> get entries => _buffer.items;

  /// Adds a [NavigatorEntry] to the buffer.
  void add(NavigatorEntry entry) {
    _buffer.add(entry);
  }

  /// Clears the buffer.
  void clear() => _buffer.clear();
}
