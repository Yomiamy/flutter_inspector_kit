import 'package:dio/dio.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkEntry', () {
    final fixedTime = DateTime(2026, 6, 9, 12, 0, 0);

    test('constructs incomplete by default', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://x',
        timestamp: fixedTime,
      );
      expect(entry.method, 'GET');
      expect(entry.url, 'https://x');
      expect(entry.isComplete, isFalse);
      expect(entry.statusCode, isNull);
    });

    test('copyWith completes the entry', () {
      final pending = NetworkEntry(
        method: 'GET',
        url: 'https://x',
        timestamp: fixedTime,
      );
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

    group('isReplay', () {
      test('defaults to false', () {
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: fixedTime,
        );
        expect(entry.isReplay, isFalse);
      });

      test('copyWith(isReplay: true) sets isReplay, other fields unchanged', () {
        final original = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          statusCode: 200,
          timestamp: fixedTime,
          isComplete: true,
        );
        final replayed = original.copyWith(isReplay: true);
        expect(replayed.isReplay, isTrue);
        expect(replayed.method, original.method);
        expect(replayed.url, original.url);
        expect(replayed.statusCode, original.statusCode);
        expect(replayed.timestamp, original.timestamp);
        expect(replayed.isComplete, original.isComplete);
      });

      test('entries differing only in isReplay are not equal', () {
        final base = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: fixedTime,
          isComplete: true,
        );
        final replay = base.copyWith(isReplay: true);
        expect(base, isNot(equals(replay)));
        expect(base.hashCode, isNot(replay.hashCode));
      });
    });

    group('sourceDio (transient)', () {
      test('transient sourceDio does not affect equality or hashCode', () {
        final dio = Dio();
        final a = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: fixedTime,
          isComplete: true,
          sourceDio: dio,
        );
        final b = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: fixedTime,
          isComplete: true,
          sourceDio: null,
        );
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('copyWith carries sourceDio while preserving other fields', () {
        final dio = Dio();
        final entry = NetworkEntry(
          method: 'POST',
          url: 'https://api',
          statusCode: 200,
          timestamp: fixedTime,
          isComplete: true,
        );
        final withDio = entry.copyWith(sourceDio: dio);
        expect(withDio.sourceDio, same(dio));
        expect(withDio.method, entry.method);
        expect(withDio.url, entry.url);
        expect(withDio.statusCode, entry.statusCode);
        expect(withDio.timestamp, entry.timestamp);
        expect(withDio.isComplete, entry.isComplete);
      });

      test('copyWith without sourceDio preserves original value', () {
        final dio = Dio();
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: fixedTime,
          sourceDio: dio,
        );
        final copied = entry.copyWith(isReplay: true);
        expect(copied.sourceDio, same(dio));
        expect(copied.isReplay, isTrue);
      });
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

    group('TimestampedEntry contract', () {
      test('NetworkEntry is a TimestampedEntry', () {
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: fixedTime,
        );
        expect(entry, isA<TimestampedEntry>());
      });

      test('displayTime formats as HH:mm:ss.mmm', () {
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: DateTime(2026, 6, 9, 14, 30, 1, 123),
        );
        expect(entry.displayTime, '14:30:01.123');
      });

      test('displayTime zero-pads all components', () {
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: DateTime(2026, 1, 1, 1, 2, 3, 4),
        );
        expect(entry.displayTime, '01:02:03.004');
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

        final empty = NetworkEntry(
          method: 'GET',
          url: 'https://x',
          timestamp: fixedTime,
        );
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
          method: 'GET',
          url: 'https://api.test/path',
          timestamp: fixedTime,
        );
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
