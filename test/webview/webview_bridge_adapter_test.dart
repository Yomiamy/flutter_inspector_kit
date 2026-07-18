import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/utils/log_formatters.dart';
import 'package:flutter_inspector_kit/src/utils/network_formatters.dart';
import 'package:flutter_inspector_kit/src/webview/webview_bridge_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebViewBridgeAdapter · log 路徑', () {
    test('console.error 成為 error 級 LogEntry 並帶 webview provenance', () {
      final inspector = FlutterInspector();
      final adapter = WebViewBridgeAdapter(inspector);
      adapter.handleMessage(_Data.consoleError);
      final e = inspector.logEntries.single;
      expect(e.level, LogLevel.error);
      expect(e.message, 'boom');
      expect(e.data, {'origin': 'webview', 'pageUrl': 'https://m.example.com'});
    });

    test('五種 console method 對應正確 LogLevel；未知 method 為 info', () {
      final cases = {
        'log': LogLevel.info,
        'info': LogLevel.info,
        'warn': LogLevel.warning,
        'error': LogLevel.error,
        'debug': LogLevel.debug,
        'weird': LogLevel.info,
      };
      for (final entry in cases.entries) {
        final inspector = FlutterInspector();
        WebViewBridgeAdapter(
          inspector,
        ).handleMessage(_Data.consoleMethod(entry.key));
        expect(
          inspector.logEntries.single.level,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('window.onerror 成為 error 級 entry 且帶 JS stack', () {
      final inspector = FlutterInspector();
      WebViewBridgeAdapter(inspector).handleMessage(_Data.windowOnError);
      final e = inspector.logEntries.single;
      expect(e.level, LogLevel.error);
      expect(e.stackTrace, contains('app.js:10'));
    });

    test('page 欄位缺省時 data 不塞 pageUrl', () {
      final inspector = FlutterInspector();
      WebViewBridgeAdapter(inspector).handleMessage(_Data.consoleNoPage);
      expect(inspector.logEntries.single.data, {'origin': 'webview'});
    });

    test('malformed / unknown 訊息靜默丟棄不 throw', () {
      final inspector = FlutterInspector();
      final adapter = WebViewBridgeAdapter(inspector);
      for (final raw in ['not json{', '{"t":"log"', '{"t":"weird"}']) {
        expect(() => adapter.handleMessage(raw), returnsNormally);
      }
      expect(inspector.logEntries, isEmpty);
    });
  });

  group('WebViewBridgeAdapter · network 路徑', () {
    test('WebView fetch 成為非 Dio NetworkEntry：欄位正確對應', () {
      final inspector = FlutterInspector();
      WebViewBridgeAdapter(inspector).handleMessage(_Data.fetch502);
      final e = inspector.networkEntries.single;
      expect(e.method, 'POST');
      expect(e.url, 'https://m.example.com/api/pay');
      expect(e.statusCode, 502);
      expect(e.duration, const Duration(milliseconds: 1234));
      expect(e.requestHeaders, {'Content-Type': 'application/json'});
      expect(e.requestBody, '{"amount":100}');
      expect(e.responseHeaders, {'Content-Type': 'application/json'});
      expect(e.responseBody, '{"ok":false}');
      expect(e.errorType, isNull);
      expect(e.sourceDio, isNull); // Replay 正確地不可用
    });

    test('傳輸失敗：statusCode null 且 error 保留', () {
      final inspector = FlutterInspector();
      WebViewBridgeAdapter(inspector).handleMessage(_Data.fetchTransportError);
      final e = inspector.networkEntries.single;
      expect(e.statusCode, isNull);
      expect(e.error, 'NetworkError: Failed to fetch');
    });

    test('redaction parity：Authorization 遮罩與 native 同一 code path', () {
      final inspector = FlutterInspector();
      WebViewBridgeAdapter(inspector).handleMessage(_Data.fetchWithAuth);
      final e = inspector.networkEntries.single;
      expect(buildPlainText(e, redact: true), contains('••••'));
      expect(buildPlainText(e, redact: false), contains('Bearer secret'));
    });

    test('CRLF 訊息經既有 one-liner formatter 被壓平', () {
      final inspector = FlutterInspector();
      WebViewBridgeAdapter(inspector).handleMessage(_Data.consoleWithCrlf);
      final oneLiner = buildLogOneLiner(inspector.logEntries.single);
      expect(oneLiner, isNot(contains('\n')));
    });

    test('malformed URL 的 net 事件經既有 formatter 不外洩 query', () {
      final inspector = FlutterInspector();
      WebViewBridgeAdapter(inspector).handleMessage(_Data.fetchMalformedUrl);
      final oneLiner = buildNetworkOneLiner(inspector.networkEntries.single);
      expect(oneLiner, isNot(contains('secret=1')));
    });

    test('超出 DateTime 範圍的 ts 靜默丟棄不 throw（敵意輸入）', () {
      final inspector = FlutterInspector();
      final adapter = WebViewBridgeAdapter(inspector);
      expect(() => adapter.handleMessage(_Data.fetchHugeTs), returnsNormally);
      expect(inspector.networkEntries, isEmpty);
    });
  });
}

class _Data {
  static const String consoleError = r'''
  {"t":"log","method":"error","message":"boom","page":"https://m.example.com"}
  ''';

  static const String windowOnError = r'''
  {"t":"log","method":"error","message":"Uncaught TypeError","stack":"at foo (app.js:10)"}
  ''';

  static const String consoleNoPage = r'''
  {"t":"log","method":"info","message":"hi"}
  ''';

  static String consoleMethod(String method) =>
      '{"t":"log","method":"$method","message":"hi"}';

  static const String consoleWithCrlf = r'''
  {"t":"log","method":"info","message":"line1\r\nline2"}
  ''';

  static const String fetch502 = r'''
  {
    "t": "net",
    "method": "POST",
    "url": "https://m.example.com/api/pay",
    "status": 502,
    "durationMs": 1234,
    "reqHeaders": {"Content-Type": "application/json"},
    "reqBody": "{\"amount\":100}",
    "resHeaders": {"Content-Type": "application/json"},
    "resBody": "{\"ok\":false}"
  }
  ''';

  static const String fetchTransportError = r'''
  {
    "t": "net",
    "method": "GET",
    "url": "https://m.example.com/api/pay",
    "error": "NetworkError: Failed to fetch"
  }
  ''';

  static const String fetchWithAuth = r'''
  {
    "t": "net",
    "method": "GET",
    "url": "https://m.example.com/api/secure",
    "status": 200,
    "reqHeaders": {"Authorization": "Bearer secret"}
  }
  ''';

  static const String fetchMalformedUrl = r'''
  {
    "t": "net",
    "method": "GET",
    "url": "https://[malformed?secret=1",
    "status": 200
  }
  ''';

  // ts within int64 range but far outside DateTime's valid ±8.64e15 ms window:
  // DateTime.fromMillisecondsSinceEpoch throws RangeError, which must be caught
  // and dropped rather than escaping handleMessage.
  static const String fetchHugeTs = r'''
  {
    "t": "net",
    "method": "GET",
    "url": "https://m.example.com/api/pay",
    "status": 200,
    "ts": 100000000000000000
  }
  ''';
}
