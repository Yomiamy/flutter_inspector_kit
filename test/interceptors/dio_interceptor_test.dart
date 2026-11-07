import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/dio_interceptor.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/utils/redaction.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingData {
  @override
  String toString() => throw StateError('custom toString failed');
}

class _ThrowingRequestHandler extends RequestInterceptorHandler {
  @override
  void next(RequestOptions requestOptions) {
    throw StateError('downstream error');
  }
}

void main() {
  group('FlutterInspectorDioInterceptor', () {
    late FlutterInspector inspector;
    late FlutterInspectorDioInterceptor interceptor;

    setUp(() {
      inspector = FlutterInspector(navigatorKey: GlobalKey<NavigatorState>());
      interceptor = FlutterInspectorDioInterceptor(inspector);
    });

    test('onRequest logs network entry', () async {
      final options = RequestOptions(
        path: 'http://example.com/api',
        method: 'GET',
      );
      final handler = RequestInterceptorHandler();
      interceptor.onRequest(options, handler);

      expect(inspector.registry.network.entries.length, 1);
      final entry = inspector.registry.network.entries.first;
      expect(entry.url, 'http://example.com/api');
      expect(entry.method, 'GET');
      expect(entry.isComplete, false);
    });

    test(
      'onRequest and onResponse serialize Map/List data as JSON string',
      () async {
        final options = RequestOptions(
          path: 'http://example.com/api',
          method: 'POST',
          data: {'userId': 1, 'id': 1, 'title': 'delectus', 'completed': false},
        );
        final handler = RequestInterceptorHandler();
        interceptor.onRequest(options, handler);

        expect(inspector.registry.network.entries.length, 1);
        var entry = inspector.registry.network.entries.first;
        // Should be valid JSON, not Map's toString() representation
        expect(
          entry.requestBody,
          '{"userId":1,"id":1,"title":"delectus","completed":false}',
        );

        final response = Response(
          requestOptions: options,
          statusCode: 200,
          data: ['item1', 'item2'],
        );
        interceptor.onResponse(response, ResponseInterceptorHandler());

        expect(inspector.registry.network.entries.length, 1);
        entry = inspector.registry.network.entries.first;
        expect(entry.responseBody, '["item1","item2"]');
      },
    );

    test('onResponse replaces the pending entry in place', () async {
      final options = RequestOptions(
        path: 'http://example.com/api',
        method: 'GET',
      );
      final handler = RequestInterceptorHandler();
      interceptor.onRequest(options, handler);

      final responseHandler = ResponseInterceptorHandler();
      final response = Response(requestOptions: options, statusCode: 200);
      interceptor.onResponse(response, responseHandler);

      expect(inspector.registry.network.entries.length, 1);
      final entry = inspector.registry.network.entries.first;
      expect(entry.statusCode, 200);
      expect(entry.isComplete, true);
    });

    test('onError replaces the pending entry with the error entry', () async {
      final options = RequestOptions(
        path: 'http://example.com/api',
        method: 'GET',
      );
      final handler = RequestInterceptorHandler();
      interceptor.onRequest(options, handler);

      final errorHandler = ErrorInterceptorHandler();
      final err = DioException(
        requestOptions: options,
        error: 'Connection failed',
      );
      interceptor.onError(err, errorHandler);
      // handler.next(err) completes the handler's future with the error;
      // observe it so it doesn't escape the test zone as unhandled.
      // ignore: invalid_use_of_protected_member
      await errorHandler.future.then((_) {}, onError: (_) {});

      expect(inspector.registry.network.entries.length, 1);
      final entry = inspector.registry.network.entries.first;
      expect(entry.error, isNotNull);
      expect(entry.isComplete, true);
    });

    test('concurrent requests each complete their own entry', () async {
      final optionsA = RequestOptions(
        path: 'http://example.com/a',
        method: 'GET',
      );
      final optionsB = RequestOptions(
        path: 'http://example.com/b',
        method: 'GET',
      );
      interceptor.onRequest(optionsA, RequestInterceptorHandler());
      interceptor.onRequest(optionsB, RequestInterceptorHandler());

      interceptor.onResponse(
        Response(requestOptions: optionsB, statusCode: 200),
        ResponseInterceptorHandler(),
      );

      final entries = inspector.registry.network.entries;
      expect(entries.length, 2);
      final entryB = entries.firstWhere((e) => e.url.endsWith('/b'));
      final entryA = entries.firstWhere((e) => e.url.endsWith('/a'));
      expect(entryB.isComplete, true);
      expect(entryB.statusCode, 200);
      expect(entryA.isComplete, false);
    });

    group('sourceDio', () {
      test('backward compat: single-arg constructor yields null sourceDio', () {
        final interceptor0 = FlutterInspectorDioInterceptor(inspector);
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor0.onRequest(options, RequestInterceptorHandler());

        expect(
          inspector.registry.network.entries.first.sourceDio?.target,
          isNull,
        );
      });

      test('sourceDio is recorded on onRequest entry', () {
        final dio = Dio();
        final interceptor0 = FlutterInspectorDioInterceptor(
          inspector,
          sourceDio: dio,
        );
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor0.onRequest(options, RequestInterceptorHandler());

        expect(
          inspector.registry.network.entries.first.sourceDio?.target,
          same(dio),
        );
      });

      test('sourceDio is recorded on onResponse entry', () {
        final dio = Dio();
        final interceptor0 = FlutterInspectorDioInterceptor(
          inspector,
          sourceDio: dio,
        );
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor0.onRequest(options, RequestInterceptorHandler());
        interceptor0.onResponse(
          Response(requestOptions: options, statusCode: 200),
          ResponseInterceptorHandler(),
        );

        expect(
          inspector.registry.network.entries.first.sourceDio?.target,
          same(dio),
        );
      });

      test('sourceDio is recorded on onError entry', () async {
        final dio = Dio();
        final interceptor0 = FlutterInspectorDioInterceptor(
          inspector,
          sourceDio: dio,
        );
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor0.onRequest(options, RequestInterceptorHandler());

        final errorHandler = ErrorInterceptorHandler();
        interceptor0.onError(
          DioException(requestOptions: options, error: 'fail'),
          errorHandler,
        );
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        expect(
          inspector.registry.network.entries.first.sourceDio?.target,
          same(dio),
        );
      });
    });

    group('no mirror debug log', () {
      test('onResponse does not produce any log entry', () {
        final options = RequestOptions(
          path: 'http://example.com/api',
          method: 'GET',
        );
        interceptor.onRequest(options, RequestInterceptorHandler());
        interceptor.onResponse(
          Response(requestOptions: options, statusCode: 200),
          ResponseInterceptorHandler(),
        );

        expect(inspector.logEntries, isEmpty);
      });

      test('onError does not produce any log entry', () async {
        final options = RequestOptions(
          path: 'http://example.com/api',
          method: 'GET',
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final errorHandler = ErrorInterceptorHandler();
        interceptor.onError(
          DioException(requestOptions: options, error: 'fail'),
          errorHandler,
        );
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        expect(inspector.logEntries, isEmpty);
      });
    });

    group('isReplay flag', () {
      test('onRequest: isReplay true when extra flag set', () {
        final options = RequestOptions(
          path: 'http://example.com/api',
          extra: {'_inspector_is_replay': true},
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        expect(inspector.registry.network.entries.first.isReplay, true);
      });

      test('onRequest: isReplay false when extra flag absent', () {
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor.onRequest(options, RequestInterceptorHandler());

        expect(inspector.registry.network.entries.first.isReplay, false);
      });

      test('onResponse: isReplay true when extra flag set', () {
        final options = RequestOptions(
          path: 'http://example.com/api',
          extra: {'_inspector_is_replay': true},
        );
        interceptor.onRequest(options, RequestInterceptorHandler());
        interceptor.onResponse(
          Response(requestOptions: options, statusCode: 200),
          ResponseInterceptorHandler(),
        );

        expect(inspector.registry.network.entries.first.isReplay, true);
      });

      test('onError: isReplay true when extra flag set', () async {
        final options = RequestOptions(
          path: 'http://example.com/api',
          extra: {'_inspector_is_replay': true},
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final errorHandler = ErrorInterceptorHandler();
        interceptor.onError(
          DioException(requestOptions: options, error: 'fail'),
          errorHandler,
        );
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        expect(inspector.registry.network.entries.first.isReplay, true);
      });

      test('onError: isReplay false when extra flag absent', () async {
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor.onRequest(options, RequestInterceptorHandler());

        final errorHandler = ErrorInterceptorHandler();
        interceptor.onError(
          DioException(requestOptions: options, error: 'fail'),
          errorHandler,
        );
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        expect(inspector.registry.network.entries.first.isReplay, false);
      });
    });

    group('structured error fields', () {
      test(
        'transport layer failure sets errorType and null statusCode',
        () async {
          final options = RequestOptions(path: 'http://example.com/api');
          interceptor.onRequest(options, RequestInterceptorHandler());

          final errorHandler = ErrorInterceptorHandler();
          final err = DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'x',
          );
          interceptor.onError(err, errorHandler);
          // Dio forwards the error through the handler's future.
          // ignore: invalid_use_of_protected_member
          await expectLater(errorHandler.future, throwsA(isA<Object>()));

          expect(inspector.registry.network.entries.length, 1);
          final entry = inspector.registry.network.entries.first;
          expect(entry.errorType, DioExceptionType.connectionError);
          expect(entry.statusCode, isNull);
        },
      );

      test(
        'server error path sets errorType, statusCode and responseBody',
        () async {
          final options = RequestOptions(path: 'http://example.com/api');
          interceptor.onRequest(options, RequestInterceptorHandler());

          final errorHandler = ErrorInterceptorHandler();
          final err = DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              data: 'oops',
            ),
          );
          interceptor.onError(err, errorHandler);
          // Dio forwards the error through the handler's future.
          // ignore: invalid_use_of_protected_member
          await expectLater(errorHandler.future, throwsA(isA<Object>()));

          expect(inspector.registry.network.entries.length, 1);
          final entry = inspector.registry.network.entries.first;
          expect(entry.errorType, DioExceptionType.badResponse);
          expect(entry.statusCode, 500);
          expect(entry.responseBody, 'oops');
        },
      );

      test('stackTrace is recorded and not null or empty', () async {
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor.onRequest(options, RequestInterceptorHandler());

        final errorHandler = ErrorInterceptorHandler();
        final st = StackTrace.current;
        final err = DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          stackTrace: st,
        );
        interceptor.onError(err, errorHandler);
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        expect(inspector.registry.network.entries.length, 1);
        final entry = inspector.registry.network.entries.first;
        expect(entry.errorStackTrace, isNotNull);
        expect(entry.errorStackTrace, isNotEmpty);
        expect(entry.errorStackTrace, contains('dio_interceptor_test.dart'));
      });

      test('success path does not have errorType or errorStackTrace', () async {
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor.onRequest(options, RequestInterceptorHandler());

        final response = Response(requestOptions: options, statusCode: 200);
        interceptor.onResponse(response, ResponseInterceptorHandler());

        expect(inspector.registry.network.entries.length, 1);
        final entry = inspector.registry.network.entries.first;
        expect(entry.errorType, isNull);
        expect(entry.errorStackTrace, isNull);
      });
    });

    group('Uint8List binary payload placeholder', () {
      test(
        'onResponse formats Uint8List as binary placeholder with truncated marker',
        () {
          final options = RequestOptions(
            path: 'http://example.com/file.png',
            method: 'GET',
            responseType: ResponseType.bytes,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final bytes = Uint8List.fromList([137, 80, 78, 71]);
          final response = Response<Uint8List>(
            requestOptions: options,
            statusCode: 200,
            data: bytes,
          );
          interceptor.onResponse(response, ResponseInterceptorHandler());

          final entry = inspector.registry.network.entries.first;
          expect(entry.responseBody, '[binary 4 bytes]$kTruncatedMarker');
          expect(entry.isTruncated, isTrue);
        },
      );

      test(
        'onResponse formats empty Uint8List(0) as binary 0 bytes placeholder',
        () {
          final options = RequestOptions(
            path: 'http://example.com/empty.bin',
            method: 'GET',
            responseType: ResponseType.bytes,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final response = Response<Uint8List>(
            requestOptions: options,
            statusCode: 200,
            data: Uint8List(0),
          );
          interceptor.onResponse(response, ResponseInterceptorHandler());

          final entry = inspector.registry.network.entries.first;
          expect(entry.responseBody, '[binary 0 bytes]$kTruncatedMarker');
          expect(entry.isTruncated, isTrue);
        },
      );

      test(
        'onRequest formats Uint8List as binary placeholder and marks request truncated',
        () {
          final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: bytes,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final entry = inspector.registry.network.entries.first;
          expect(entry.requestBody, '[binary 6 bytes]$kTruncatedMarker');
          expect(entry.isRequestTruncated, isTrue);
          expect(entry.isTruncated, isTrue);
        },
      );

      test(
        'onError formats Uint8List response data as binary placeholder',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/error-bytes',
            method: 'GET',
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final errorHandler = ErrorInterceptorHandler();
          final err = DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<Uint8List>(
              requestOptions: options,
              statusCode: 500,
              data: Uint8List.fromList([0xff, 0x00]),
            ),
          );
          interceptor.onError(err, errorHandler);
          // Dio forwards the error through the handler's future.
          // ignore: invalid_use_of_protected_member
          await expectLater(errorHandler.future, throwsA(isA<Object>()));

          final entry = inspector.registry.network.entries.first;
          expect(entry.responseBody, '[binary 2 bytes]$kTruncatedMarker');
          expect(entry.isTruncated, isTrue);
        },
      );

      test('plain List<int> is still serialized as JSON array, not binary', () {
        final options = RequestOptions(
          path: 'http://example.com/numbers',
          method: 'POST',
          data: <int>[137, 80, 78, 71],
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(entry.requestBody, '[137,80,78,71]');
        expect(entry.isRequestTruncated, isFalse);
      });
    });

    group('Fail-Safe error handling (§P39)', () {
      test(
        'onRequest forwards request and logs warning when inspector throws',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/api',
            method: 'POST',
            data: _ThrowingData(),
          );
          final handler = RequestInterceptorHandler();
          interceptor.onRequest(options, handler);

          // handler.next must have been called
          // ignore: invalid_use_of_protected_member
          expect(handler.future, completes);
          final warningLogs = inspector.registry.log.entries
              .where((l) => l.level == LogLevel.warning)
              .toList();
          expect(warningLogs.length, 1);
          expect(
            warningLogs.first.message,
            contains('DioInterceptor.onRequest internal error:'),
          );
        },
      );

      test(
        'onResponse forwards response and logs warning when inspector throws',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/api',
            method: 'GET',
          );
          final response = Response(
            requestOptions: options,
            statusCode: 200,
            data: _ThrowingData(),
          );
          final handler = ResponseInterceptorHandler();
          interceptor.onResponse(response, handler);

          // ignore: invalid_use_of_protected_member
          expect(handler.future, completes);
          final warningLogs = inspector.registry.log.entries
              .where((l) => l.level == LogLevel.warning)
              .toList();
          expect(warningLogs.length, 1);
          expect(
            warningLogs.first.message,
            contains('DioInterceptor.onResponse internal error:'),
          );
        },
      );

      test(
        'onError forwards error and logs warning when inspector throws',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/api',
            method: 'GET',
          );
          final err = DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              data: _ThrowingData(),
            ),
          );
          final handler = ErrorInterceptorHandler();
          interceptor.onError(err, handler);

          await expectLater(
            // ignore: invalid_use_of_protected_member
            handler.future,
            throwsA(
              isA<dynamic>().having(
                (e) => (e as dynamic).data,
                'data',
                isA<DioException>().having(
                  (e) => e.type,
                  'type',
                  DioExceptionType.badResponse,
                ),
              ),
            ),
          );

          final warningLogs = inspector.registry.log.entries
              .where((l) => l.level == LogLevel.warning)
              .toList();
          expect(warningLogs.length, 1);
          expect(
            warningLogs.first.message,
            contains('DioInterceptor.onError internal error:'),
          );
        },
      );

      test(
        'downstream synchronous exception from handler.next is not swallowed',
        () {
          final options = RequestOptions(
            path: 'http://example.com/api',
            method: 'GET',
          );
          final throwingHandler = _ThrowingRequestHandler();

          expect(
            () => interceptor.onRequest(options, throwingHandler),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                'downstream error',
              ),
            ),
          );

          final warningLogs = inspector.registry.log.entries
              .where((l) => l.level == LogLevel.warning)
              .toList();
          expect(warningLogs, isEmpty);
        },
      );

      test(
        'onResponse completes pending entry when serialization throws',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/api',
            method: 'GET',
          );
          interceptor.onRequest(options, RequestInterceptorHandler());
          expect(inspector.registry.network.entries.single.isComplete, false);

          final response = Response(
            requestOptions: options,
            statusCode: 200,
            data: _ThrowingData(),
          );
          final handler = ResponseInterceptorHandler();
          interceptor.onResponse(response, handler);

          // ignore: invalid_use_of_protected_member
          final state = await handler.future;
          expect(state.data, same(response));
          final entry = inspector.registry.network.entries.single;
          expect(entry.isComplete, true);
          expect(entry.statusCode, 200);
        },
      );

      test(
        'onError completes pending entry when error serialization throws',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/api',
            method: 'GET',
          );
          interceptor.onRequest(options, RequestInterceptorHandler());
          expect(inspector.registry.network.entries.single.isComplete, false);

          final err = DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              data: _ThrowingData(),
            ),
          );
          final handler = ErrorInterceptorHandler();
          interceptor.onError(err, handler);

          await expectLater(
            // ignore: invalid_use_of_protected_member
            handler.future,
            throwsA(
              isA<dynamic>().having(
                (e) => (e as dynamic).data,
                'data',
                isA<DioException>(),
              ),
            ),
          );

          final entry = inspector.registry.network.entries.single;
          expect(entry.isComplete, true);
          expect(entry.isFailed, true);
          expect(entry.statusCode, 500);
        },
      );

      test(
        'onError completes pending entry when err.toString() throws',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/api',
            method: 'GET',
          );
          interceptor.onRequest(options, RequestInterceptorHandler());
          expect(inspector.registry.network.entries.single.isComplete, false);

          // DioException.toString() interpolates the wrapped error, so a
          // throwing toString() on it makes err.toString() throw too.
          final err = DioException(
            requestOptions: options,
            type: DioExceptionType.unknown,
            error: _ThrowingData(),
          );
          final handler = ErrorInterceptorHandler();
          interceptor.onError(err, handler);

          await expectLater(
            // ignore: invalid_use_of_protected_member
            handler.future,
            throwsA(
              isA<dynamic>().having(
                (e) => (e as dynamic).data,
                'data',
                same(err),
              ),
            ),
          );

          final entry = inspector.registry.network.entries.single;
          expect(entry.isComplete, true);
          expect(entry.errorType, DioExceptionType.unknown);
          expect(entry.errorStackTrace, isNotNull);
        },
      );
    });

    group('FormData multipart summary (§P33)', () {
      test(
        'onRequest lists files before fields and never finalizes the FormData',
        () {
          final formData = FormData.fromMap({
            'name': 'Alice',
            'avatar': MultipartFile.fromBytes(
              List<int>.filled(1024, 0),
              filename: 'avatar.png',
            ),
          });
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: formData,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final entry = inspector.registry.network.entries.first;
          expect(
            entry.requestBody,
            '[FormData: avatar=avatar.png (1024 B), name=Alice]$kTruncatedMarker',
          );
          expect(entry.isRequestTruncated, isTrue);
          expect(formData.isFinalized, isFalse);
          expect(formData.files.single.value.isFinalized, isFalse);
        },
      );

      test('empty FormData renders the empty placeholder', () {
        final options = RequestOptions(
          path: 'http://example.com/upload',
          method: 'POST',
          data: FormData(),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(entry.requestBody, '[FormData: empty]$kTruncatedMarker');
        expect(entry.isRequestTruncated, isTrue);
      });

      test('file without a filename renders <unnamed>', () {
        final options = RequestOptions(
          path: 'http://example.com/upload',
          method: 'POST',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes([1, 2, 3]),
          }),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(
          entry.requestBody,
          '[FormData: file=<unnamed> (3 B)]$kTruncatedMarker',
        );
        expect(entry.isRequestTruncated, isTrue);
      });

      test('masks sensitive field values when redactSensitiveData is true', () {
        final options = RequestOptions(
          path: 'http://example.com/login',
          method: 'POST',
          data: FormData.fromMap({'username': 'alice', 'password': 'hunter2'}),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(
          entry.requestBody,
          '[FormData: username=alice, password=$kRedactedValue]$kTruncatedMarker',
        );
        expect(entry.requestBody, isNot(contains('hunter2')));
        expect(entry.isRequestTruncated, isTrue);
      });

      test('masks the filename under a sensitive file key when redacting', () {
        final options = RequestOptions(
          path: 'http://example.com/upload',
          method: 'POST',
          data: FormData.fromMap({
            'token_file': MultipartFile.fromBytes([1, 2], filename: 'me.png'),
            'avatar': MultipartFile.fromBytes([1], filename: 'a.png'),
          }),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final body = inspector.registry.network.entries.first.requestBody;
        expect(body, isNot(contains('me.png')));
        expect(
          body,
          '[FormData: token_file=$kRedactedValue (2 B), avatar=a.png (1 B)]'
          '$kTruncatedMarker',
        );
      });

      test('stops building the summary once past the 10 KB body cap', () {
        // 100 fields x 1 KB: a full summary would be ~100 KB.
        final options = RequestOptions(
          path: 'http://example.com/upload',
          method: 'POST',
          data: FormData.fromMap({
            for (var i = 0; i < 100; i++) 'f$i': 'x' * 1024,
          }),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final body = inspector.registry.network.entries.first.requestBody!;
        expect(body.length, lessThanOrEqualTo(kNetworkBodyMaxLength + 64));
        expect(body, startsWith('[FormData: f0='));
        expect(body, endsWith(kTruncatedMarker));
        expect(body, isNot(contains('f99=')));
      });

      test('keeps raw field values when redactSensitiveData is false', () {
        final rawInspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
          redactSensitiveData: false,
        );
        final options = RequestOptions(
          path: 'http://example.com/login',
          method: 'POST',
          data: FormData.fromMap({'password': 'hunter2'}),
        );
        FlutterInspectorDioInterceptor(
          rawInspector,
        ).onRequest(options, RequestInterceptorHandler());

        final entry = rawInspector.registry.network.entries.first;
        expect(
          entry.requestBody,
          '[FormData: password=hunter2]$kTruncatedMarker',
        );
        expect(entry.isRequestTruncated, isTrue);
      });

      test(
        'onResponse keeps the onRequest summary after Dio drains the FormData',
        () async {
          final formData = FormData.fromMap({
            'password': 'hunter2',
            'avatar': MultipartFile.fromBytes([1, 2], filename: 'a.png'),
          });
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: formData,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());
          final requestSummary =
              inspector.registry.network.entries.single.requestBody;
          // Dio finalizes and streams the FormData while sending it.
          await formData.readAsBytes();

          interceptor.onResponse(
            Response(requestOptions: options, statusCode: 201),
            ResponseInterceptorHandler(),
          );

          final entry = inspector.registry.network.entries.single;
          expect(entry.isComplete, isTrue);
          expect(entry.requestBody, requestSummary);
          // No internal-error warning: the main path ran, not the fallback.
          expect(
            inspector.registry.log.entries.where(
              (l) => l.level == LogLevel.warning,
            ),
            isEmpty,
          );
          expect(
            entry.requestBody,
            '[FormData: avatar=a.png (2 B), password=$kRedactedValue]$kTruncatedMarker',
          );
        },
      );

      test(
        'onError keeps the onRequest summary after Dio drains the FormData',
        () async {
          final formData = FormData.fromMap({
            'password': 'hunter2',
            'avatar': MultipartFile.fromBytes([1, 2], filename: 'a.png'),
          });
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: formData,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());
          final requestSummary =
              inspector.registry.network.entries.single.requestBody;
          await formData.readAsBytes();

          final errorHandler = ErrorInterceptorHandler();
          interceptor.onError(
            DioException(requestOptions: options, error: 'fail'),
            errorHandler,
          );
          // Dio forwards the error through the handler's future.
          // ignore: invalid_use_of_protected_member
          await expectLater(errorHandler.future, throwsA(isA<Object>()));

          final entry = inspector.registry.network.entries.single;
          expect(entry.isComplete, isTrue);
          expect(entry.requestBody, requestSummary);
          // No internal-error warning: the main path ran, not the fallback.
          expect(
            inspector.registry.log.entries.where(
              (l) => l.level == LogLevel.warning,
            ),
            isEmpty,
          );
          expect(
            entry.requestBody,
            '[FormData: avatar=a.png (2 B), password=$kRedactedValue]$kTruncatedMarker',
          );
        },
      );
    });
  });
}
