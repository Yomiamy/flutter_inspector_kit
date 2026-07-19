import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Demonstrates WebView bridging: a [WebViewController] wired with
/// [WebViewBridgeAdapter] so `console.*`, `window.onerror`, and `fetch`
/// activity inside the loaded page shows up in the inspector's Console and
/// Network tabs.
///
/// Copy this pattern into your app to bridge a WebView's own JS activity.
class WebViewDemo {
  WebViewDemo(FlutterInspector inspector) {
    final adapter = WebViewBridgeAdapter(inspector);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        kWebViewBridgeChannelName,
        onMessageReceived: (message) => adapter.handleMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) =>
              _controller.runJavaScript(inspectorWebViewBridgeJs),
        ),
      )
      // baseUrl gives the page a real location.href, so bridged events carry
      // a meaningful pageUrl instead of about:blank.
      ..loadHtmlString(_demoHtml, baseUrl: 'https://webview-demo.local/');
  }

  late final WebViewController _controller;

  /// Opens the demo page showing the bridged WebView.
  void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewDemoPage(controller: _controller),
      ),
    );
  }
}

/// Full-page host for the bridged [WebViewController].
class WebViewDemoPage extends StatelessWidget {
  const WebViewDemoPage({super.key, required this.controller});

  final WebViewController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebView Demo')),
      body: WebViewWidget(controller: controller),
    );
  }
}

const String _demoHtml = '''
<!DOCTYPE html>
<html>
  <body style="font-family: sans-serif; padding: 16px;">
    <h3>WebView Bridge Demo</h3>
    <button onclick="console.log('hello from webview')">console.log</button>
    <br /><br />
    <button onclick="console.error('boom from webview')">console.error</button>
    <br /><br />
    <button onclick="fetch('https://httpbin.org/get')">fetch</button>
  </body>
</html>
''';
