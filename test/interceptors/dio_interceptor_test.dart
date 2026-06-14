import 'package:dio/dio.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector_impl.dart';
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
  });
}
