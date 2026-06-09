import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkEntry', () {
    final fixedTime = DateTime(2026, 6, 9, 12, 0, 0);

    test('constructs incomplete by default', () {
      final entry =
          NetworkEntry(method: 'GET', url: 'https://x', timestamp: fixedTime);
      expect(entry.method, 'GET');
      expect(entry.url, 'https://x');
      expect(entry.isComplete, isFalse);
      expect(entry.statusCode, isNull);
    });

    test('copyWith completes the entry', () {
      final pending =
          NetworkEntry(method: 'GET', url: 'https://x', timestamp: fixedTime);
      final done = pending.copyWith(
        statusCode: 200,
        duration: const Duration(milliseconds: 120),
        isComplete: true,
      );
      expect(done.statusCode, 200);
      expect(done.duration, const Duration(milliseconds: 120));
      expect(done.isComplete, isTrue);
      expect(done.url, 'https://x');
    });

    test('equality and hashCode', () {
      final a = NetworkEntry(
        method: 'POST',
        url: 'https://api',
        statusCode: 201,
        timestamp: fixedTime,
        isComplete: true,
      );
      final b = NetworkEntry(
        method: 'POST',
        url: 'https://api',
        statusCode: 201,
        timestamp: fixedTime,
        isComplete: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    group('truncateBody', () {
      test('returns null for null input', () {
        expect(NetworkEntry.truncateBody(null), isNull);
      });

      test('returns body unchanged when within limit', () {
        final body = 'a' * 100;
        expect(NetworkEntry.truncateBody(body), body);
      });

      test('returns body unchanged at exactly the limit', () {
        final body = 'a' * kNetworkBodyMaxLength;
        expect(NetworkEntry.truncateBody(body), body);
      });

      test('truncates body exceeding the limit and appends marker', () {
        final body = 'a' * (kNetworkBodyMaxLength + 50);
        final result = NetworkEntry.truncateBody(body)!;
        expect(result.length, kNetworkBodyMaxLength + kTruncatedMarker.length);
        expect(result.endsWith(kTruncatedMarker), isTrue);
        expect(
          result.substring(0, kNetworkBodyMaxLength),
          'a' * kNetworkBodyMaxLength,
        );
      });
    });
  });
}
