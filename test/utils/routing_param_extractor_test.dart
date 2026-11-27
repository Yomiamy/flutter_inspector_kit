import 'package:flutter_inspector_kit/src/utils/redaction.dart';
import 'package:flutter_inspector_kit/src/utils/routing_param_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractQueryParams / extractArgParams', () {
    test(
      'returns null when routeName has no query and arguments is null or empty',
      () {
        expect(extractQueryParams(routeName: '/home'), isNull);
        expect(extractQueryParams(routeName: null), isNull);
        expect(extractArgParams(arguments: null), isNull);
        expect(extractArgParams(arguments: <String, dynamic>{}), isNull);
      },
    );

    test('extracts query parameters from routeName', () {
      final params = extractQueryParams(
        routeName: '/search?keyword=flutter&category=tools',
      );
      expect(params, isNotNull);
      expect(params, {'keyword': 'flutter', 'category': 'tools'});
    });

    test('extracts query parameters from Uri arguments', () {
      final uri = Uri.parse(
        'https://example.com/details?id=123&from=notification',
      );
      final params = extractArgParams(arguments: uri);
      expect(params, {'id': '123', 'from': 'notification'});
    });

    test(
      'extracts query parameters from String arguments with query string',
      () {
        final params = extractArgParams(arguments: '/detail?item=book&page=2');
        expect(params, {'item': 'book', 'page': '2'});
      },
    );

    test('extracts scalar primitive types from Map arguments', () {
      final map = {
        'name': 'Alice',
        'age': 30,
        'rating': 4.5,
        'isActive': true,
        'extra': null,
      };
      final params = extractArgParams(arguments: map);
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
      final params = extractArgParams(arguments: map);
      expect(params, {
        'user': '<complex>',
        'items': '<complex>',
        'metadata': '<complex>',
        'tag': 'valid',
      });
    });

    test('keeps routeName query and arguments apart on key collision', () {
      expect(extractQueryParams(routeName: '/order?id=1&source=deeplink'), {
        'id': '1',
        'source': 'deeplink',
      });
      expect(extractArgParams(arguments: {'id': 999, 'status': 'pending'}), {
        'id': '999',
        'status': 'pending',
      });
    });

    test('returns null for arguments that carry no params', () {
      expect(extractArgParams(arguments: Object()), isNull);
    });

    test('truncates strings longer than maxStringLength', () {
      final longString = 'a' * 120;
      final params = extractArgParams(
        arguments: {'message': longString},
        maxStringLength: 50,
      );
      expect(params?['message']?.length, 53); // 50 + '...'
      expect(params?['message'], '${'a' * 50}...');
    });

    test('caps total entries to maxEntries', () {
      final map = {for (var i = 0; i < 30; i++) 'key$i': 'val$i'};
      final params = extractArgParams(arguments: map, maxEntries: 10);
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
        'pinCode': '9876',
        'keyCode': 'secKey1',
        'key': 'my_raw_key',
        'apiKey': 'abc1234',
        'shipping': 'fedex',
        'spinner': 'loading',
        'keyboard': 'mechanical',
      };
      final params = extractArgParams(arguments: map, redact: true);
      expect(params?['username'], 'john_doe');
      expect(params?['password'], kRedactedValue);
      expect(params?['authToken'], kRedactedValue);
      expect(params?['api_key'], kRedactedValue);
      expect(params?['secret'], kRedactedValue);
      expect(params?['access_token'], kRedactedValue);
      expect(params?['userPin'], kRedactedValue);
      expect(params?['pinCode'], kRedactedValue);
      expect(params?['keyCode'], kRedactedValue);
      expect(params?['key'], kRedactedValue);
      expect(params?['apiKey'], kRedactedValue);
      expect(params?['shipping'], 'fedex');
      expect(params?['spinner'], 'loading');
      expect(params?['keyboard'], 'mechanical');
    });

    test('redacts camelCase pinCode parameter specifically', () {
      final params = extractArgParams(
        arguments: {'pinCode': '1234', 'shippingAddress': '123 Main St'},
        redact: true,
      );
      expect(params?['pinCode'], kRedactedValue);
      expect(params?['shippingAddress'], '123 Main St');
    });

    test('redacts uppercase PIN and KEY acronyms and camelCase boundaries', () {
      final map = {
        'userPIN': '1234',
        'userKEY': 'authKey',
        'userPINCode': '5678',
        'userKEYAuth': 'tokenVal',
        'shipping': 'fedex',
        'donkey': 'kong',
      };
      final params = extractArgParams(arguments: map, redact: true);
      expect(params?['userPIN'], kRedactedValue);
      expect(params?['userKEY'], kRedactedValue);
      expect(params?['userPINCode'], kRedactedValue);
      expect(params?['userKEYAuth'], kRedactedValue);
      expect(params?['shipping'], 'fedex');
      expect(params?['donkey'], 'kong');

      expect(isSensitiveRoutingKey('userPIN'), isTrue);
      expect(isSensitiveRoutingKey('userKEY'), isTrue);
      expect(isSensitiveRoutingKey('userPINCode'), isTrue);
      expect(isSensitiveRoutingKey('userKEYAuth'), isTrue);
      expect(isSensitiveRoutingKey('shipping'), isFalse);
      expect(isSensitiveRoutingKey('donkey'), isFalse);
    });

    test('does not redact sensitive keys when redact is false', () {
      final map = {'password': 'plainPassword', 'token': 'plainToken'};
      final params = extractArgParams(arguments: map, redact: false);
      expect(params?['password'], 'plainPassword');
      expect(params?['token'], 'plainToken');
    });

    test('handles malformed Uri query string gracefully', () {
      // Uri with malformed percent-encoding
      final params = extractQueryParams(routeName: '/path?bad=%E0%A4');
      // Should not throw, may be empty or null
      expect(params, isNull);
    });

    test('returned map is unmodifiable', () {
      final params = extractQueryParams(routeName: '/page?id=1');
      expect(params, isNotNull);
      expect(() => params!['id'] = '2', throwsUnsupportedError);
    });
  });

  group('isSensitiveRoutingKey status/metadata whitelist (§P45)', () {
    test('lets through boolean flags and metadata keys', () {
      expect(_Data.releasedKeys.where(isSensitiveRoutingKey), isEmpty);
    });

    test('still redacts credential keys', () {
      expect(
        _Data.credentialKeys.where((k) => !isSensitiveRoutingKey(k)),
        isEmpty,
      );
    });

    test('adds no new redaction', () {
      expect(_Data.plainKeys.where(isSensitiveRoutingKey), isEmpty);
    });

    test('extractArgParams keeps flags and metadata, masks credentials', () {
      final params = extractArgParams(
        arguments: {
          'is_authenticated': false,
          'token_type': 'Bearer',
          'auth_token': 'xyz',
        },
      );
      expect(params, {
        'is_authenticated': 'false',
        'token_type': 'Bearer',
        'auth_token': kRedactedValue,
      });
    });
  });
}

class _Data {
  /// §4.1 A: over-redacted before, let through now.
  static const releasedKeys = [
    'is_authenticated',
    'is_authorized',
    'has_password',
    'has_token',
    'isAuthenticated',
    'hasPassword',
    'canAuth',
    'shouldReauth',
    'hasPin',
    'hasKey',
    'auth_required',
    'auth_enabled',
    'token_expired',
    'token_expires_in',
    'token_expires_at',
    'token_expiry',
    'token_type',
    'auth_mode',
    'auth_method',
    'auth_provider',
    'auth_step',
    'auth_status',
    'tokenType',
    'tokenExpired',
    'tokenExpiresIn',
    'authMode',
    'authStatus',
    'auth-mode',
    'TOKEN_TYPE',
    'is_token_expired',
    'password_required',
    'oauth2Provider',
  ];

  /// §4.1 B: credentials, still redacted.
  static const credentialKeys = [
    'has_secret_token',
    'hasSecretToken',
    'is_password_key',
    'has_api_key',
    'auth_token',
    'authToken',
    'password_reset_token',
    'access_token',
    'refresh_token',
    'auth_code',
    'oauth_state',
    'authorization',
    'apiKey',
    'api_key',
    'X-Api-Key',
    'userPin',
    'userPINCode',
    'userKEYAuth',
    'token_file',
  ];

  /// §4.1 C: never redacted, unchanged.
  static const plainKeys = [
    'isActive',
    'status',
    'keyword',
    'user_pwd',
    'has_db_pwd',
  ];
}
