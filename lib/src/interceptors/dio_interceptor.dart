import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';
import '../models/network_entry.dart';
import '../utils/image_bytes.dart';
import '../utils/redaction.dart';
import '../utils/routing_param_extractor.dart';

/// A Dio interceptor that automatically records requests and responses to the
/// [FlutterInspector].
class FlutterInspectorDioInterceptor extends Interceptor {
  /// Creates the interceptor, feeding entries to the provided [_inspector].
  FlutterInspectorDioInterceptor(this._inspector, {this.sourceDio});

  final FlutterInspector _inspector;

  /// Optional [Dio] instance that originated this request (e.g. for replay).
  final Dio? sourceDio;

  // The 5 MB cap and the 50 MB budget live in NetworkInspector.add.
  static Uint8List? _imageBytes(Object? data) =>
      data is Uint8List && imageMimeType(data) != null ? data : null;

  String? _stringifyData(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Uint8List) {
      final mime = imageMimeType(data);
      return mime == null
          ? '[binary ${data.length} bytes]$kTruncatedMarker'
          : imageSummary(mime, data.length);
    }
    if (data is FormData) return _summarizeFormData(data);
    if (data is Map || data is List) {
      try {
        return jsonEncode(data);
      } catch (_) {
        return data.toString();
      }
    }
    // Never listen: host streams are single-subscription, a 2nd listen throws.
    if (data is ResponseBody || data is Stream) {
      return '[stream]$kTruncatedMarker';
    }
    return data.toString();
  }

  String _summarizeFormData(FormData data) {
    final redact = _inspector.redactSensitiveData;
    String masked(String key, String value) =>
        redact && isSensitiveRoutingKey(key) ? kRedactedValue : value;
    // Files first: the 10 KB body cap then trims field values, not files.
    final parts = [
      for (final MapEntry(:key, value: file) in data.files)
        '$key=${masked(key, file.filename ?? '<unnamed>')} (${file.length} B)',
      for (final MapEntry(:key, :value) in data.fields)
        '$key=${masked(key, value)}',
    ];
    // The marker disables Replay: a summary is not a resendable payload.
    return '[FormData: ${parts.isEmpty ? 'empty' : parts.join(', ')}]'
        '$kTruncatedMarker';
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
    // Declared outside try so the recovery path reuses them instead of re-reading.
    NetworkEntry? pending;
    Duration? duration;
    try {
      final startTime =
          response.requestOptions.extra['_inspector_start_time'] as DateTime?;
      duration = startTime != null
          ? DateTime.now().difference(startTime)
          : null;
      pending =
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
        responseImageBytes: _imageBytes(response.data),
        isComplete: true,
        timestamp: startTime,
        sourceDio: sourceDio,
        isReplay: response.requestOptions.extra['_inspector_is_replay'] == true,
      );
      _inspector.logNetwork(entry, replaces: pending);
    } on Object catch (e, st) {
      try {
        if (pending != null) {
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
    // Declared outside try so the recovery path reuses them instead of re-reading.
    NetworkEntry? pending;
    Duration? duration;
    try {
      final startTime =
          err.requestOptions.extra['_inspector_start_time'] as DateTime?;
      duration = startTime != null
          ? DateTime.now().difference(startTime)
          : null;
      pending =
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
        responseImageBytes: _imageBytes(err.response?.data),
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
        if (pending != null) {
          _inspector.logNetwork(
            pending.copyWith(
              statusCode: err.response?.statusCode,
              duration: duration,
              error: err.message ?? err.type.name,
              errorType: err.type,
              errorStackTrace: err.stackTrace.toString(),
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
