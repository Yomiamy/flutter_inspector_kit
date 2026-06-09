import 'package:flutter_inspector/src/models/network_entry.dart';
import 'package:flutter_inspector/src/utils/network_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedTime = DateTime(2026, 6, 10, 12, 0, 0);

  group('formatBytes', () {
    test('bytes below 1 KB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('kilobytes and megabytes', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });
  });

  group('prettyJson', () {
    test('indents valid JSON', () {
      final result = prettyJson('{"a":1,"b":[2,3]}');
      expect(result.contains('\n'), isTrue);
      expect(result.contains('  "a": 1'), isTrue);
    });

    test('returns input unchanged for non-JSON', () {
      expect(prettyJson('not json'), 'not json');
    });

    test('handles null/empty', () {
      expect(prettyJson(null), '');
      expect(prettyJson(''), '');
    });
  });

  group('buildCurl', () {
    test('GET without body', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/items',
        requestHeaders: {'Accept': 'application/json'},
        timestamp: fixedTime,
      );
      final curl = buildCurl(entry);
      expect(curl, startsWith('curl -X GET'));
      expect(curl.contains("-H 'Accept: application/json'"), isTrue);
      expect(curl.contains('--data'), isFalse);
      expect(curl.endsWith("'https://api.test/items'"), isTrue);
    });

    test('POST with body includes --data', () {
      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test/items',
        requestBody: '{"name":"x"}',
        timestamp: fixedTime,
      );
      final curl = buildCurl(entry);
      expect(curl.contains('-X POST'), isTrue);
      expect(curl.contains("--data '{\"name\":\"x\"}'"), isTrue);
    });

    test('escapes single quotes in body', () {
      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test',
        requestBody: "it's",
        timestamp: fixedTime,
      );
      final curl = buildCurl(entry);
      expect(curl.contains(r"'\''"), isTrue);
    });
  });

  group('buildPlainText', () {
    test('includes general, request, response and error sections', () {
      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test/x?id=1',
        statusCode: 500,
        duration: const Duration(milliseconds: 80),
        requestHeaders: {'Content-Type': 'application/json'},
        requestBody: '{"a":1}',
        responseBody: 'oops',
        error: 'Server error',
        isComplete: true,
        timestamp: fixedTime,
      );
      final text = buildPlainText(entry);
      expect(text.contains('=== General ==='), isTrue);
      expect(text.contains('=== Query Parameters ==='), isTrue);
      expect(text.contains('id: 1'), isTrue);
      expect(text.contains('=== Request Body ==='), isTrue);
      expect(text.contains('=== Error ==='), isTrue);
      expect(text.contains('Server error'), isTrue);
    });
  });
}
