import 'package:dio/dio.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

/// Demonstrates network capture: a [Dio] instance wired with
/// [FlutterInspectorDioInterceptor] so every request/response shows up in the
/// inspector's Network tab.
///
/// Copy this pattern into your app to capture Dio traffic. The `sourceDio`
/// argument lets the Network detail view replay (resend) a captured request
/// through the original Dio.
class NetworkDemo {
  NetworkDemo(this._inspector) {
    _dio = Dio();
    _dio.interceptors.add(
      FlutterInspectorDioInterceptor(_inspector, sourceDio: _dio),
    );
  }

  final FlutterInspector _inspector;
  late final Dio _dio;

  /// Fires a POST request with a JSON body. httpbin.org echoes the request back
  /// in a structured response, so the Network tab shows a meaningful response
  /// body in addition to the request payload.
  Future<void> makeRequest() async {
    try {
      final option = Options(
        headers: {
          'Authorization': 'Bearer mock-token-123',
          'Set-Cookie': 'mock-cookie-123',
          'X-Api-Key': 'mock-api-key-123',
        },
      );
      await _dio.post(
        'https://httpbin.org/post',
        data: {
          'title': 'flutter_inspector demo',
          'completed': false,
          'userId': 1,
        },
        options: option,
      );
      _inspector.log('Network request successful', level: LogLevel.info);
    } catch (e) {
      _inspector.log('Network request failed: $e', level: LogLevel.error);
    }
  }
}
