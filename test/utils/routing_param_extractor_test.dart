import 'package:flutter_inspector_kit/src/utils/redaction.dart';
import 'package:flutter_inspector_kit/src/utils/routing_param_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractRoutingParams', () {
    test('returns null when routeName has no query and arguments is null or empty', () {
      expect(extractRoutingParams(routeName: '/home', arguments: null), isNull);
      expect(extractRoutingParams(routeName: null, arguments: null), isNull);
      expect(extractRoutingParams(routeName: '/order', arguments: <String, dynamic>{}), isNull);
    });

    test('extracts query parameters from routeName', () {
      final params = extractRoutingParams(
        routeName: '/search?keyword=flutter&category=tools',
      );
      expect(params, isNotNull);
      expect(params, {
        'keyword': 'flutter',
        'category': 'tools',
      });
    });

    test('extracts query parameters from Uri arguments', () {
      final uri = Uri.parse('https://example.com/details?id=123&from=notification');
      final params = extractRoutingParams(arguments: uri);
      expect(params, {
        'id': '123',
        'from': 'notification',
      });
    });

    test('extracts query parameters from String arguments with query string', () {
      final params = extractRoutingParams(arguments: '/detail?item=book&page=2');
      expect(params, {
        'item': 'book',
        'page': '2',
      });
    });

    test('extracts scalar primitive types from Map arguments', () {
      final map = {
        'name': 'Alice',
        'age': 30,
        'rating': 4.5,
        'isActive': true,
        'extra': null,
      };
      final params = extractRoutingParams(arguments: map);
      expect(params, {
        'name': 'Alice',
        'age': '30',
        'rating': '4.5',
        'isActive': 'true',
        'extra': 'null',
      });
    });

    test('substitutes complex objects in Map with <complex>', () {
      final map = {
        'user': Object(),
        'items': [1, 2, 3],
        'metadata': {'nested': true},
        'tag': 'valid',
      };
      final params = extractRoutingParams(arguments: map);
      expect(params, {
        'user': '<complex>',
        'items': '<complex>',
        'metadata': '<complex>',
        'tag': 'valid',
      });
    });

    test('merges routeName query parameters and Map arguments', () {
      final params = extractRoutingParams(
        routeName: '/order?source=deeplink',
        arguments: {'orderId': 999, 'status': 'pending'},
      );
      expect(params, {
        'source': 'deeplink',
        'orderId': '999',
        'status': 'pending',
      });
    });

    test('truncates strings longer than maxStringLength', () {
      final longString = 'a' * 120;
      final params = extractRoutingParams(
        arguments: {'message': longString},
        maxStringLength: 50,
      );
      expect(params?['message']?.length, 53); // 50 + '...'
      expect(params?['message'], '${'a' * 50}...');
    });

    test('caps total entries to maxEntries', () {
      final map = {
        for (var i = 0; i < 30; i++) 'key$i': 'val$i',
      };
      final params = extractRoutingParams(arguments: map, maxEntries: 10);
      expect(params?.length, 10);
    });

    test('redacts sensitive keys when redact is true', () {
      final map = {
        'username': 'john_doe',
        'password': 'secretPassword123',
        'authToken': 'xyz987654321',
        'api_key': 'super_secret_key',
        'secret': 'mySecret',
        'access_token': 'bearer_token',
        'userPin': '1234',
      };
      final params = extractRoutingParams(arguments: map, redact: true);
      expect(params?['username'], 'john_doe');
      expect(params?['password'], kRedactedValue);
      expect(params?['authToken'], kRedactedValue);
      expect(params?['api_key'], kRedactedValue);
      expect(params?['secret'], kRedactedValue);
      expect(params?['access_token'], kRedactedValue);
      expect(params?['userPin'], kRedactedValue);
    });

    test('does not redact sensitive keys when redact is false', () {
      final map = {
        'password': 'plainPassword',
        'token': 'plainToken',
      };
      final params = extractRoutingParams(arguments: map, redact: false);
      expect(params?['password'], 'plainPassword');
      expect(params?['token'], 'plainToken');
    });

    test('handles malformed Uri query string gracefully', () {
      // Uri with malformed percent-encoding
      final params = extractRoutingParams(routeName: '/path?bad=%E0%A4');
      // Should not throw, may be empty or null
      expect(params == null || params.isEmpty, isTrue);
    });

    test('returned map is unmodifiable', () {
      final params = extractRoutingParams(
        routeName: '/page?id=1',
      );
      expect(params, isNotNull);
      expect(() => params!['id'] = '2', throwsUnsupportedError);
    });
  });
}
