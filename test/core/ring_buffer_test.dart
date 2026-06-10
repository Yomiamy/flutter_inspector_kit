import 'package:flutter_inspector/src/core/ring_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RingBuffer', () {
    test('asserts positive capacity', () {
      expect(() => RingBuffer<int>(0), throwsAssertionError);
    });

    test('adds items up to capacity', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      expect(buffer.length, 3);
      expect(buffer.items, [3, 2, 1]); // newest first
    });

    test('FIFO eviction when exceeding capacity', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4); // evicts 1
      buffer.add(5); // evicts 2
      expect(buffer.length, 3);
      expect(buffer.items, [5, 4, 3]); // newest first, oldest evicted
    });

    test('items returns newest-first order', () {
      final buffer = RingBuffer<String>(5);
      buffer.add('a');
      buffer.add('b');
      buffer.add('c');
      expect(buffer.items, ['c', 'b', 'a']);
    });

    test('items snapshot is unmodifiable', () {
      final buffer = RingBuffer<int>(2)..add(1);
      expect(() => buffer.items.add(2), throwsUnsupportedError);
    });

    test('clear empties the buffer', () {
      final buffer = RingBuffer<int>(3)
        ..add(1)
        ..add(2);
      buffer.clear();
      expect(buffer.length, 0);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.items, isEmpty);
    });

    test('handles capacity of one', () {
      final buffer = RingBuffer<int>(1);
      buffer.add(1);
      buffer.add(2);
      expect(buffer.items, [2]);
      expect(buffer.length, 1);
    });

    test('replace swaps an item in place, preserving order', () {
      final buffer = RingBuffer<int>(3)
        ..add(1)
        ..add(2)
        ..add(3);
      expect(buffer.replace(2, 20), isTrue);
      expect(buffer.items, [3, 20, 1]);
      expect(buffer.length, 3);
    });

    test('replace returns false when item is absent', () {
      final buffer = RingBuffer<int>(3)
        ..add(1)
        ..add(2);
      expect(buffer.replace(9, 90), isFalse);
      expect(buffer.items, [2, 1]);
    });

    test('replace invalidates the items snapshot cache', () {
      final buffer = RingBuffer<int>(3)..add(1);
      expect(buffer.items, [1]); // populate cache
      buffer.replace(1, 10);
      expect(buffer.items, [10]);
    });
  });
}
