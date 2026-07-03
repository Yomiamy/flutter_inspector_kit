import 'package:dio/dio.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/dio_interceptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterInspectorDioInterceptor', () {
    late FlutterInspector inspector;
    late FlutterInspectorDioInterceptor interceptor;

    setUp(() {
      inspector = FlutterInspector();
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

    test('onRequest and onResponse serialize Map/List data as JSON string', () async {
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
      expect(entry.requestBody, '{"userId":1,"id":1,"title":"delectus","completed":false}');

      final response = Response(
        requestOptions: options,
        statusCode: 200,
        data: ['item1', 'item2'],
      );
      interceptor.onResponse(response, ResponseInterceptorHandler());

      expect(inspector.registry.network.entries.length, 1);
      entry = inspector.registry.network.entries.first;
      expect(entry.responseBody, '["item1","item2"]');
    });

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
        final interceptor0 =
            FlutterInspectorDioInterceptor(inspector, sourceDio: dio);
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor0.onRequest(options, RequestInterceptorHandler());

        expect(
          inspector.registry.network.entries.first.sourceDio?.target,
          same(dio),
        );
      });

      test('sourceDio is recorded on onResponse entry', () {
        final dio = Dio();
        final interceptor0 =
            FlutterInspectorDioInterceptor(inspector, sourceDio: dio);
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
        final interceptor0 =
            FlutterInspectorDioInterceptor(inspector, sourceDio: dio);
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
      test('transport layer failure sets errorType and null statusCode', () async {
        final options = RequestOptions(path: 'http://example.com/api');
        interceptor.onRequest(options, RequestInterceptorHandler());

        final errorHandler = ErrorInterceptorHandler();
        final err = DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'x',
        );
        interceptor.onError(err, errorHandler);
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        expect(inspector.registry.network.entries.length, 1);
        final entry = inspector.registry.network.entries.first;
        expect(entry.errorType, DioExceptionType.connectionError);
        expect(entry.statusCode, isNull);
      });

      test('server error path sets errorType, statusCode and responseBody', () async {
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
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        expect(inspector.registry.network.entries.length, 1);
        final entry = inspector.registry.network.entries.first;
        expect(entry.errorType, DioExceptionType.badResponse);
        expect(entry.statusCode, 500);
        expect(entry.responseBody, 'oops');
      });

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
  });
}
