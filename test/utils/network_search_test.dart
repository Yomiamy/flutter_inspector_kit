import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/utils/network_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime(2026, 6, 10, 12, 0, 0);

  NetworkEntry entry(String method, String url, {int? status, String? error}) =>
      NetworkEntry(
        method: method,
        url: url,
        statusCode: status,
        error: error,
        isComplete: true,
        timestamp: t,
      );

  final entries = [
    entry('GET', 'https://api.test/users', status: 200),
    entry('POST', 'https://api.test/login', status: 401),
    entry('GET', 'https://cdn.test/image.png', status: 500),
    entry('DELETE', 'https://api.test/users/1', error: 'timeout'),
  ];

  group('NetworkFilter', () {
    test('empty filter matches everything', () {
      const f = NetworkFilter();
      expect(f.isEmpty, isTrue);
      expect(applyNetworkFilter(entries, f).length, entries.length);
    });

    test('keyword matches url case-insensitively', () {
      final result = applyNetworkFilter(
        entries,
        const NetworkFilter(keyword: 'USERS'),
      );
      expect(result.length, 2);
    });

    test('keyword matches status code', () {
      final result = applyNetworkFilter(
        entries,
        const NetworkFilter(keyword: '401'),
      );
      expect(result.single.url, 'https://api.test/login');
    });

    test('method filter', () {
      final result = applyNetworkFilter(
        entries,
        const NetworkFilter(methods: {'GET'}),
      );
      expect(result.length, 2);
      expect(result.every((e) => e.method == 'GET'), isTrue);
    });

    test('status group filter — server errors', () {
      final result = applyNetworkFilter(
        entries,
        const NetworkFilter(statusGroups: {NetworkStatusGroup.serverError}),
      );
      expect(result.single.statusCode, 500);
    });

    test('status group filter — failed (no status, has error)', () {
      final result = applyNetworkFilter(
        entries,
        const NetworkFilter(statusGroups: {NetworkStatusGroup.failed}),
      );
      expect(result.single.method, 'DELETE');
    });

    test('combined keyword + method', () {
      final result = applyNetworkFilter(
        entries,
        const NetworkFilter(keyword: 'api.test', methods: {'POST'}),
      );
      expect(result.single.url, 'https://api.test/login');
    });
  });
}
