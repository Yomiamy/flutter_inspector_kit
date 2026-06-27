import 'package:flutter_inspector_kit/src/utils/redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redactHeaders', () {
    test('masks Authorization regardless of case', () {
      expect(
        redactHeaders({'Authorization': 'Bearer secret'}),
        {'Authorization': '••••'},
      );
      expect(
        redactHeaders({'authorization': 'Bearer secret'}),
        {'authorization': '••••'},
      );
      expect(
        redactHeaders({'AUTHORIZATION': 'Bearer secret'}),
        {'AUTHORIZATION': '••••'},
      );
    });

    test('masks cookie, set-cookie and x-api-key', () {
      expect(
        redactHeaders({
          'Cookie': 'session=abc',
          'Set-Cookie': 'session=abc; HttpOnly',
          'X-Api-Key': 'k-123',
        }),
        {
          'Cookie': '••••',
          'Set-Cookie': '••••',
          'X-Api-Key': '••••',
        },
      );
    });

    test('leaves non-sensitive headers untouched', () {
      expect(
        redactHeaders({
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Request-Id': 'r-1',
        }),
        {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Request-Id': 'r-1',
        },
      );
    });

    test('masks the value even when it is a list (multi-value header)', () {
      expect(
        redactHeaders({
          'Set-Cookie': ['a=1', 'b=2'],
          'Accept': ['application/json', 'text/plain'],
        }),
        {
          'Set-Cookie': '••••',
          'Accept': ['application/json', 'text/plain'],
        },
      );
    });

    test('preserves the original key casing of redacted entries', () {
      final result = redactHeaders({'CooKie': 'session=abc'});
      expect(result.keys, ['CooKie']);
      expect(result['CooKie'], '••••');
    });

    test('does not mutate the input map', () {
      final input = {'Authorization': 'Bearer secret'};
      redactHeaders(input);
      expect(input, {'Authorization': 'Bearer secret'});
    });
  });
}
