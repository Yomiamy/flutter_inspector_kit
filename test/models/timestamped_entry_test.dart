import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-local fixture: implements the narrow contract by exposing only
/// [timestamp], so [displayTime] is exercised purely through the extension.
class _Fixture implements TimestampedEntry {
  _Fixture(this.timestamp);

  @override
  final DateTime timestamp;
}

void main() {
  group('TimestampedEntryDisplay.displayTime', () {
    test('formats as HH:mm:ss.mmm', () {
      final entry = _Fixture(DateTime(2026, 6, 26, 14, 30, 1, 123));
      expect(entry.displayTime, '14:30:01.123');
    });

    test('zero-pads single-digit hour/minute/second and millisecond', () {
      final entry = _Fixture(DateTime(2026, 1, 1, 9, 5, 3, 7));
      expect(entry.displayTime, '09:05:03.007');
    });

    test('renders millisecond 0 as .000', () {
      final entry = _Fixture(DateTime(2026, 1, 1, 0, 0, 0, 0));
      expect(entry.displayTime, '00:00:00.000');
    });
  });
}
