import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/utils/network_formatters.dart';
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

    test('escapes single quotes in URL', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: "https://api.test/x?q=it's",
        timestamp: fixedTime,
      );
      final curl = buildCurl(entry);
      // URL must use the same '\'' escape as header/body values.
      expect(curl, endsWith(r"'https://api.test/x?q=it'\''s'"));
    });
  });

  group('buildCurl redaction', () {
    test('masks sensitive request headers by default', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/items',
        requestHeaders: {
          'Authorization': 'Bearer secret-token',
          'Accept': 'application/json',
        },
        timestamp: fixedTime,
      );
      final curl = buildCurl(entry);
      expect(curl.contains('secret-token'), isFalse);
      expect(curl.contains("-H 'Authorization: ••••'"), isTrue);
      expect(curl.contains("-H 'Accept: application/json'"), isTrue);
    });

    test('keeps raw sensitive headers when redact is disabled', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/items',
        requestHeaders: {'Authorization': 'Bearer secret-token'},
        timestamp: fixedTime,
      );
      final curl = buildCurl(entry, redact: false);
      expect(curl.contains("-H 'Authorization: Bearer secret-token'"), isTrue);
    });
  });

  group('buildPlainText redaction', () {
    test('masks sensitive request and response headers by default', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/items',
        requestHeaders: {'Cookie': 'session=abc'},
        responseHeaders: {'Set-Cookie': 'session=abc; HttpOnly'},
        timestamp: fixedTime,
      );
      final text = buildPlainText(entry);
      expect(text.contains('session=abc'), isFalse);
      expect(text.contains('Cookie: ••••'), isTrue);
      expect(text.contains('Set-Cookie: ••••'), isTrue);
    });

    test('keeps raw sensitive headers when redact is disabled', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/items',
        requestHeaders: {'Cookie': 'session=abc'},
        timestamp: fixedTime,
      );
      final text = buildPlainText(entry, redact: false);
      expect(text.contains('Cookie: session=abc'), isTrue);
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

  group('buildReplayRequest', () {
    test('extracts method, url, headers and body from entry', () {
      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test/items',
        requestHeaders: {'Content-Type': 'application/json'},
        requestBody: '{"name":"x"}',
        timestamp: fixedTime,
      );
      final req = buildReplayRequest(entry);
      expect(req.method, 'POST');
      expect(req.url, 'https://api.test/items');
      expect(req.headers, {'Content-Type': 'application/json'});
      expect(req.body, '{"name":"x"}');
    });

    test('headers and body are null when entry has none', () {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/items',
        timestamp: fixedTime,
      );
      final req = buildReplayRequest(entry);
      expect(req.method, 'GET');
      expect(req.url, 'https://api.test/items');
      expect(req.headers, isNull);
      expect(req.body, isNull);
    });

    test('preserves raw body without any escaping', () {
      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test',
        requestBody: "it's a 'test'",
        timestamp: fixedTime,
      );
      final req = buildReplayRequest(entry);
      expect(req.body, "it's a 'test'");
    });
  });
}
