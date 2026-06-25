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
          inspector.registry.network.entries.first.sourceDio,
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
          inspector.registry.network.entries.first.sourceDio,
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
          inspector.registry.network.entries.first.sourceDio,
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
          inspector.registry.network.entries.first.sourceDio,
          same(dio),
        );
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
  });
}
