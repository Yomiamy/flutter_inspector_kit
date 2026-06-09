import 'package:dio/dio.dart';
import 'package:flutter_inspector/src/core/flutter_inspector_impl.dart';
import 'package:flutter_inspector/src/integrations/dio_interceptor.dart';
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
      final options =
          RequestOptions(path: 'http://example.com/api', method: 'GET');
      final handler = RequestInterceptorHandler();
      interceptor.onRequest(options, handler);

      expect(inspector.registry.network.entries.length, 1);
      final entry = inspector.registry.network.entries.first;
      expect(entry.url, 'http://example.com/api');
      expect(entry.method, 'GET');
      expect(entry.isComplete, false);
    });

    test('onResponse completes network entry', () async {
      final options =
          RequestOptions(path: 'http://example.com/api', method: 'GET');
      final handler = RequestInterceptorHandler();
      interceptor.onRequest(options, handler);

      final responseHandler = ResponseInterceptorHandler();
      final response = Response(requestOptions: options, statusCode: 200);
      interceptor.onResponse(response, responseHandler);

      expect(inspector.registry.network.entries.length, 2);
      final entry = inspector.registry.network.entries.first;
      expect(entry.statusCode, 200);
      expect(entry.isComplete, true);
    });

    test('onError completes network entry with error', () async {
      final options =
          RequestOptions(path: 'http://example.com/api', method: 'GET');
      final handler = RequestInterceptorHandler();
      interceptor.onRequest(options, handler);

      final errorHandler = ErrorInterceptorHandler();
      final err =
          DioException(requestOptions: options, error: 'Connection failed');
      interceptor.onError(err, errorHandler);

      expect(inspector.registry.network.entries.length, 2);
      final entry = inspector.registry.network.entries.first;
      expect(entry.error, isNotNull);
      expect(entry.isComplete, true);
    });
  });
}
