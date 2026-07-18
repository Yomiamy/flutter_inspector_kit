import 'dart:convert';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';

/// Translates decoded WebView bridge messages into existing [LogEntry] /
/// `NetworkEntry` and hands them to the existing registry. A translator, not
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
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return; // malformed JSON — graceful drop
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['t']) {
      case 'log':
        _handleLog(decoded);
      default:
        return; // 'net' (Chunk 3) and unknown types are ignored here
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
}
