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

    group('derived getters', () {
      test('size getters count UTF-8 bytes, 0 for null', () {
        final entry = NetworkEntry(
          method: 'POST',
          url: 'https://x',
          requestBody: 'abc',
          responseBody: '日本', // 2 chars, 6 UTF-8 bytes
          timestamp: fixedTime,
        );
        expect(entry.requestSizeBytes, 3);
        expect(entry.responseSizeBytes, 6);

        final empty =
            NetworkEntry(method: 'GET', url: 'https://x', timestamp: fixedTime);
        expect(empty.requestSizeBytes, 0);
        expect(empty.responseSizeBytes, 0);
      });

      test('queryParameters parsed from url', () {
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://api.test/path?page=2&q=hello',
          timestamp: fixedTime,
        );
        expect(entry.queryParameters, {'page': '2', 'q': 'hello'});

        final none = NetworkEntry(
            method: 'GET', url: 'https://api.test/path', timestamp: fixedTime);
        expect(none.queryParameters, isEmpty);
      });

      test('contentType read case-insensitively from headers', () {
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          requestHeaders: {'Content-Type': 'application/json'},
          responseHeaders: {'content-type': 'text/html'},
          timestamp: fixedTime,
        );
        expect(entry.requestContentType, 'application/json');
        expect(entry.responseContentType, 'text/html');
      });

      test('isRequestJson / isResponseJson detection', () {
        final json = NetworkEntry(
          method: 'POST',
          url: 'https://x',
          requestBody: '{"a":1}',
          responseBody: '[1,2,3]',
          timestamp: fixedTime,
        );
        expect(json.isRequestJson, isTrue);
        expect(json.isResponseJson, isTrue);

        final plain = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          responseBody: 'hello world',
          timestamp: fixedTime,
        );
        expect(plain.isResponseJson, isFalse);
      });

      test('isTruncated true when a body carries the marker', () {
        final truncated = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          responseBody: 'data$kTruncatedMarker',
          timestamp: fixedTime,
        );
        expect(truncated.isTruncated, isTrue);

        final normal = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          responseBody: 'data',
          timestamp: fixedTime,
        );
        expect(normal.isTruncated, isFalse);
      });
    });
  });
}
