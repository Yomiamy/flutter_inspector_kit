import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

/// The same bridge wired through `flutter_inappwebview`: its [UserScript]
/// injects at document start, so even the page's earliest console/error/fetch
/// activity is captured — the capability `webview_flutter` cannot offer
/// (compare with `webview_demo.dart`, which misses the "early" log below).
///
/// This demo also compile-backs the README's flutter_inappwebview snippet.
class InAppWebViewDemo {
  InAppWebViewDemo(FlutterInspector inspector)
    : _adapter = WebViewBridgeAdapter(inspector);

  final WebViewBridgeAdapter _adapter;

  /// Opens the demo page showing the bridged WebView.
  void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppWebViewDemoPage(adapter: _adapter),
      ),
    );
  }
}

/// Full-page host for the bridged [InAppWebView].
class InAppWebViewDemoPage extends StatelessWidget {
  const InAppWebViewDemoPage({super.key, required this.adapter});

  final WebViewBridgeAdapter adapter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('InAppWebView Demo')),
      body: InAppWebView(
        // AT_DOCUMENT_START runs before the page's own scripts, so the
        // <head> "early" log in _demoHtml is captured — webview_flutter's
        // onPageStarted injection would miss it.
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: inspectorWebViewBridgeJs,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        initialData: InAppWebViewInitialData(
          data: _demoHtml,
          // A real baseUrl gives the page a meaningful location.href, so
          // bridged events carry a useful pageUrl instead of about:blank.
          baseUrl: WebUri('https://inappwebview-demo.local/'),
        ),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: kWebViewBridgeChannelName,
            callback: (args) {
              // The page can call this handler directly — validate before
              // forwarding, mirroring the README snippet.
              final raw = args.isNotEmpty ? args.first : null;
              if (raw is String) adapter.handleMessage(raw);
            },
          );
        },
      ),
    );
  }
}

const String _demoHtml = '''
<!DOCTYPE html>
<html>
  <head>
    <script>
      // Runs while the page is still loading — only a document-start
      // injection can catch this line.
      console.log('early: logged during page load');
    </script>
  </head>
  <body style="font-family: sans-serif; padding: 16px;">
    <h3>InAppWebView Bridge Demo</h3>
    <p>The "early" log above was fired during page load.</p>
    <button onclick="console.log('hello from inappwebview')">console.log</button>
    <br /><br />
    <button onclick="console.error('boom from inappwebview')">console.error</button>
    <br /><br />
    <button onclick="fetch('https://httpbin.org/get')">fetch</button>
  </body>
</html>
''';
