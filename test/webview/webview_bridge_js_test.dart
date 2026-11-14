import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/webview/webview_bridge_js.dart';

void main() {
  test('JS payload 與 host 引用同一個 channel 名', () {
    expect(inspectorWebViewBridgeJs, contains(kWebViewBridgeChannelName));
  });
  test('JS payload 涵蓋 console/error/fetch/xhr 四類 hook 與雙傳輸', () {
    for (final needle in [
      'console',
      'onerror',
      'unhandledrejection',
      'fetch',
      'XMLHttpRequest',
      'flutter_inappwebview',
      'postMessage',
    ]) {
      expect(inspectorWebViewBridgeJs, contains(needle), reason: needle);
    }
  });
  test('JS 端截斷上限為具名常數且存在截斷標記', () {
    expect(inspectorWebViewBridgeJs, contains('MAX_CHARS'));
    expect(inspectorWebViewBridgeJs, contains('truncated'));
  });
  test('JS 截斷標記與 Dart kTruncatedMarker 一致', () {
    // 不一致時 JS 已截的 body 會被當成完整 payload 量大小。
    expect(inspectorWebViewBridgeJs, contains("'$kTruncatedMarker'"));
  });
}
