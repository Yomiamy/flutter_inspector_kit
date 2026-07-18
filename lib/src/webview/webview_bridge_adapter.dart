import 'dart:convert';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';
import '../models/network_entry.dart';
import '../models/network_origin.dart';

/// Translates decoded WebView bridge messages into existing [LogEntry] /
/// [NetworkEntry] and hands them to the existing registry. A translator, not
/// a system: it holds no buffer, does no redaction, renders no UI.
///
/// Used the same way as `FlutterInspectorDioInterceptor`: the host creates an
/// adapter holding an [FlutterInspector] reference, and forwards raw message
/// strings from its own `JavaScriptChannel` / `addJavaScriptHandler` to
/// [handleMessage].
class WebViewBridgeAdapter {
  WebViewBridgeAdapter(this._inspector);

  final FlutterInspector _inspector;

  /// Feeds in one raw bridge message (the JSON string handed over by the
  /// host's channel).
  ///
  /// Never throws: malformed input or an unknown message type is silently
  /// dropped — a hostile page must not be able to crash the host's channel
  /// callback with a malformed message.
  void handleMessage(String raw) {
    // One guard covers every handler path: a hostile payload that survives
    // jsonDecode but blows up a downstream helper (e.g. an out-of-range `ts`
    // making DateTime.fromMillisecondsSinceEpoch throw RangeError) must still
    // be dropped silently, never escape to crash the host's channel callback.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      switch (decoded['t']) {
        case 'log':
          _handleLog(decoded);
        case 'net':
          _handleNet(decoded);
      }
    } catch (_) {
      return; // malformed or hostile input — graceful drop
    }
  }

  void _handleLog(Map<String, dynamic> msg) {
    _inspector.log(
      msg['message']?.toString() ?? '',
      level: _levelFor(msg['method']?.toString()),
      stackTrace: msg['stack']?.toString(),
      data: {
        'origin': 'webview',
        if (msg['page'] != null) 'pageUrl': msg['page'],
      },
    );
  }

  void _handleNet(Map<String, dynamic> msg) {
    _inspector.logNetwork(
      NetworkEntry(
        method: msg['method']?.toString() ?? 'GET',
        url: msg['url']?.toString() ?? '',
        statusCode: _asInt(msg['status']),
        duration: _asDuration(msg['durationMs']),
        requestHeaders: _asHeaders(msg['reqHeaders']),
        requestBody: msg['reqBody']?.toString(),
        responseHeaders: _asHeaders(msg['resHeaders']),
        responseBody: msg['resBody']?.toString(),
        error: msg['error']?.toString(),
        // errorType / sourceDio deliberately left null: this isn't a Dio
        // request, so Replay is correctly unavailable (existing null check).
        isComplete: true,
        origin: NetworkOrigin.webview,
        pageUrl: msg['page']?.toString(),
        timestamp: _tsOf(msg['ts']),
      ),
    );
  }

  /// console method -> [LogLevel]. Unknown/missing -> info (safe general level).
  static LogLevel _levelFor(String? method) {
    switch (method) {
      case 'error':
        return LogLevel.error;
      case 'warn':
        return LogLevel.warning;
      case 'debug':
        return LogLevel.debug;
      case 'info':
      case 'log':
      default:
        return LogLevel.info;
    }
  }

  static int? _asInt(Object? v) => v is num ? v.toInt() : null;

  static Duration? _asDuration(Object? v) =>
      v is num ? Duration(milliseconds: v.toInt()) : null;

  static DateTime? _tsOf(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  static Map<String, dynamic>? _asHeaders(Object? v) {
    if (v is! Map) return null;
    return v.map((key, value) => MapEntry(key.toString(), value));
  }
}
