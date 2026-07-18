import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
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
}
