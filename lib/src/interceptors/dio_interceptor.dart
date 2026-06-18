import 'package:dio/dio.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';

import '../core/flutter_inspector.dart';
import '../models/network_entry.dart';

/// A Dio interceptor that automatically records requests and responses to the
/// [FlutterInspector].
class FlutterInspectorDioInterceptor extends Interceptor {
  /// Creates the interceptor, feeding entries to the provided [_inspector].
  FlutterInspectorDioInterceptor(this._inspector);

  final FlutterInspector _inspector;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_inspector_start_time'] = DateTime.now();
    final entry = NetworkEntry(
      method: options.method,
      url: options.uri.toString(),
      requestHeaders: options.headers,
      requestBody: options.data?.toString(),
    );
    options.extra['_inspector_pending_entry'] = _inspector.logNetwork(entry);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final startTime =
        response.requestOptions.extra['_inspector_start_time'] as DateTime?;
    final duration = startTime != null
        ? DateTime.now().difference(startTime)
        : null;
    final pending =
        response.requestOptions.extra['_inspector_pending_entry']
            as NetworkEntry?;

    final entry = NetworkEntry(
      method: response.requestOptions.method,
      url: response.requestOptions.uri.toString(),
      statusCode: response.statusCode,
      duration: duration,
      requestHeaders: response.requestOptions.headers,
      requestBody: response.requestOptions.data?.toString(),
      responseHeaders: response.headers.map.map(
        (k, v) => MapEntry(k, v.join(',')),
      ),
      responseBody: response.data?.toString(),
      isComplete: true,
      timestamp: startTime,
    );
    _inspector.logNetwork(entry, replaces: pending);
    _inspector.log(
      "entry.url: ${entry.url}\nMethod: ${entry.method}\nStatus: ${entry.statusCode}",
      level: LogLevel.debug,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final startTime =
        err.requestOptions.extra['_inspector_start_time'] as DateTime?;
    final duration = startTime != null
        ? DateTime.now().difference(startTime)
        : null;
    final pending =
        err.requestOptions.extra['_inspector_pending_entry'] as NetworkEntry?;

    final entry = NetworkEntry(
      method: err.requestOptions.method,
      url: err.requestOptions.uri.toString(),
      statusCode: err.response?.statusCode,
      duration: duration,
      requestHeaders: err.requestOptions.headers,
      requestBody: err.requestOptions.data?.toString(),
      responseHeaders: err.response?.headers.map.map(
        (k, v) => MapEntry(k, v.join(',')),
      ),
      responseBody: err.response?.data?.toString(),
      error: err.toString(),
      isComplete: true,
      timestamp: startTime,
    );
    _inspector.logNetwork(entry, replaces: pending);
    _inspector.log(
      "entry.url: ${entry.url}\nMethod: ${entry.method}\nStatus: ${entry.statusCode}",
      level: LogLevel.debug,
    );
    handler.next(err);
  }
}
