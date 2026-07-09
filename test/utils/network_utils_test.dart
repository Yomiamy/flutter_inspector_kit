import 'package:dio/dio.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/utils/network_utils.dart';
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

  group('aggregateNetworkErrors', () {
    NetworkEntry mkEntry({
      int? statusCode,
      String? error,
      DioExceptionType? errorType,
      DateTime? time,
      bool isComplete = true,
    }) {
      return NetworkEntry(
        method: 'GET',
        url: 'http://test',
        statusCode: statusCode,
        error: error,
        errorType: errorType,
        isComplete: isComplete,
        timestamp: time ?? DateTime(2026),
      );
    }

    test('空 entries 回傳空 list', () {
      expect(aggregateNetworkErrors([]), isEmpty);
    });

    test('全部成功請求 → 無 error group', () {
      final entries = List.generate(5, (_) => mkEntry(statusCode: 200));
      expect(aggregateNetworkErrors(entries), isEmpty);
    });

    test('單一 502 error → 1 組, count=1', () {
      final entries = [mkEntry(statusCode: 502, error: 'Bad Gateway')];
      final groups = aggregateNetworkErrors(entries);
      expect(groups, hasLength(1));
      expect(groups.first.statusCode, 502);
      expect(groups.first.count, 1);
    });

    test('相同 502 × 3 → 1 組, count=3', () {
      final entries = List.generate(3, (_) => mkEntry(statusCode: 502));
      final groups = aggregateNetworkErrors(entries);
      expect(groups, hasLength(1));
      expect(groups.first.count, 3);
    });

    test('502 × 2 + 404 × 1 → 2 組，按 count 降序', () {
      final entries = [
        mkEntry(statusCode: 502),
        mkEntry(statusCode: 404),
        mkEntry(statusCode: 502),
      ];
      final groups = aggregateNetworkErrors(entries);
      expect(groups, hasLength(2));
      expect(groups[0].statusCode, 502);
      expect(groups[0].count, 2);
      expect(groups[1].statusCode, 404);
      expect(groups[1].count, 1);
    });

    test('transport error (statusCode=null) 以 errorType 分組', () {
      final entries = [
        mkEntry(error: 'err', errorType: DioExceptionType.connectionTimeout),
        mkEntry(error: 'err', errorType: DioExceptionType.cancel),
        mkEntry(error: 'err', errorType: DioExceptionType.connectionTimeout),
      ];
      final groups = aggregateNetworkErrors(entries);
      expect(groups, hasLength(2));
      expect(groups[0].errorType, DioExceptionType.connectionTimeout);
      expect(groups[0].count, 2);
      expect(groups[1].errorType, DioExceptionType.cancel);
      expect(groups[1].count, 1);
    });

    test('混合 server error + transport error', () {
      final entries = [
        mkEntry(statusCode: 502),
        mkEntry(error: 'err', errorType: DioExceptionType.receiveTimeout),
        mkEntry(statusCode: 502),
        mkEntry(error: 'err', errorType: DioExceptionType.receiveTimeout),
        mkEntry(error: 'err', errorType: DioExceptionType.receiveTimeout),
      ];
      final groups = aggregateNetworkErrors(entries);
      expect(groups, hasLength(2));
      expect(groups[0].errorType, DioExceptionType.receiveTimeout);
      expect(groups[0].count, 3);
      expect(groups[1].statusCode, 502);
      expect(groups[1].count, 2);
    });

    test('成功請求不被計入', () {
      final entries = [
        mkEntry(statusCode: 200),
        mkEntry(statusCode: 502),
        mkEntry(statusCode: 200),
        mkEntry(statusCode: 502),
        mkEntry(statusCode: 200),
      ];
      final groups = aggregateNetworkErrors(entries);
      expect(groups, hasLength(1));
      expect(groups[0].statusCode, 502);
      expect(groups[0].count, 2);
    });

    test('isReplay=true 的錯誤仍被計入 (無特殊欄位，只要有statusCode/error即計入)', () {
      // 假設 isReplay 未來會影響，但目前 entry 模型無特殊欄位，確保一般邏輯支援即可。
      final entries = [mkEntry(statusCode: 502)];
      expect(aggregateNetworkErrors(entries), hasLength(1));
    });

    test('firstSeen/lastSeen 正確', () {
      final t1 = DateTime(2026, 1, 1, 10, 0, 0);
      final t2 = DateTime(2026, 1, 1, 10, 0, 10);
      final t3 = DateTime(2026, 1, 1, 10, 0, 5);
      final entries = [
        mkEntry(statusCode: 502, time: t2),
        mkEntry(statusCode: 502, time: t1),
        mkEntry(statusCode: 502, time: t3),
      ];
      final groups = aggregateNetworkErrors(entries);
      expect(groups.first.firstSeen, t1);
      expect(groups.first.lastSeen, t2);
    });
  });

  group('errorTypeLabel', () {
    test('映射正確', () {
      expect(errorTypeLabel(DioExceptionType.connectionTimeout), 'Connection Timeout');
      expect(errorTypeLabel(DioExceptionType.sendTimeout), 'Send Timeout');
      expect(errorTypeLabel(DioExceptionType.receiveTimeout), 'Receive Timeout');
      expect(errorTypeLabel(DioExceptionType.badCertificate), 'Bad Certificate');
      expect(errorTypeLabel(DioExceptionType.badResponse), 'Bad Response');
      expect(errorTypeLabel(DioExceptionType.cancel), 'Cancelled');
      expect(errorTypeLabel(DioExceptionType.connectionError), 'Connection Error');
      expect(errorTypeLabel(DioExceptionType.unknown), 'Unknown Error');
      // 可以測 _ default 如果有 enum 其他值，但 Dio 基本上就這些。
    });
  });
}
