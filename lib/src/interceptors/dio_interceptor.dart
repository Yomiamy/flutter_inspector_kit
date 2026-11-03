import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';
import '../models/network_entry.dart';

/// A Dio interceptor that automatically records requests and responses to the
/// [FlutterInspector].
class FlutterInspectorDioInterceptor extends Interceptor {
  /// Creates the interceptor, feeding entries to the provided [_inspector].
  FlutterInspectorDioInterceptor(this._inspector, {this.sourceDio});

  final FlutterInspector _inspector;

  /// Optional [Dio] instance that originated this request (e.g. for replay).
  final Dio? sourceDio;

  String? _stringifyData(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Uint8List) {
      return '[binary ${data.length} bytes]$kTruncatedMarker';
    }
    if (data is Map || data is List) {
      try {
        return jsonEncode(data);
      } catch (_) {
        return data.toString();
      }
    }
    return data.toString();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      options.extra['_inspector_start_time'] = DateTime.now();
      final entry = NetworkEntry(
        method: options.method,
        url: options.uri.toString(),
        requestHeaders: options.headers,
        requestBody: _stringifyData(options.data),
        sourceDio: sourceDio,
        isReplay: options.extra['_inspector_is_replay'] == true,
      );
      options.extra['_inspector_pending_entry'] = _inspector.logNetwork(entry);
    } on Object catch (e, st) {
      try {
        _inspector.log(
          'DioInterceptor.onRequest internal error: $e',
          level: LogLevel.warning,
          stackTrace: st.toString(),
        );
      } catch (_) {}
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
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
        requestBody: _stringifyData(response.requestOptions.data),
        responseHeaders: response.headers.map.map(
          (k, v) => MapEntry(k, v.join(',')),
        ),
        responseBody: _stringifyData(response.data),
        isComplete: true,
        timestamp: startTime,
        sourceDio: sourceDio,
        isReplay: response.requestOptions.extra['_inspector_is_replay'] == true,
      );
      _inspector.logNetwork(entry, replaces: pending);
    } on Object catch (e, st) {
      try {
        final pending =
            response.requestOptions.extra['_inspector_pending_entry']
                as NetworkEntry?;
        if (pending != null) {
          final startTime =
              response.requestOptions.extra['_inspector_start_time'] as DateTime?;
          final duration = startTime != null
              ? DateTime.now().difference(startTime)
              : null;
          _inspector.logNetwork(
            pending.copyWith(
              statusCode: response.statusCode,
              duration: duration,
              isComplete: true,
            ),
            replaces: pending,
          );
        }
      } catch (_) {}
      try {
        _inspector.log(
          'DioInterceptor.onResponse internal error: $e',
          level: LogLevel.warning,
          stackTrace: st.toString(),
        );
      } catch (_) {}
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
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
        requestBody: _stringifyData(err.requestOptions.data),
        responseHeaders: err.response?.headers.map.map(
          (k, v) => MapEntry(k, v.join(',')),
        ),
        responseBody: _stringifyData(err.response?.data),
        error: err.toString(),
        errorType: err.type,
        errorStackTrace: err.stackTrace.toString(),
        isComplete: true,
        timestamp: startTime,
        sourceDio: sourceDio,
        isReplay: err.requestOptions.extra['_inspector_is_replay'] == true,
      );
      _inspector.logNetwork(entry, replaces: pending);
    } on Object catch (e, st) {
      try {
        final pending =
            err.requestOptions.extra['_inspector_pending_entry'] as NetworkEntry?;
        if (pending != null) {
          final startTime =
              err.requestOptions.extra['_inspector_start_time'] as DateTime?;
          final duration = startTime != null
              ? DateTime.now().difference(startTime)
              : null;
          _inspector.logNetwork(
            pending.copyWith(
              statusCode: err.response?.statusCode,
              duration: duration,
              error: err.toString(),
              errorType: err.type,
              isComplete: true,
            ),
            replaces: pending,
          );
        }
      } catch (_) {}
      try {
        _inspector.log(
          'DioInterceptor.onError internal error: $e',
          level: LogLevel.warning,
          stackTrace: st.toString(),
        );
      } catch (_) {}
    }
    handler.next(err);
  }
}
