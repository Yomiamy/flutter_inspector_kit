/// Where a [NetworkEntry] was captured from.
///
/// Explicit provenance beats inferring from `sourceDio == null`: the Dio
/// reference is a [WeakReference] that can be collected, which would make a
/// native request indistinguishable from a WebView one.
enum NetworkOrigin {
  /// Captured by `FlutterInspectorDioInterceptor` from a host Dio instance.
  dio,

  /// Captured by `WebViewBridgeAdapter` from a WebView's `fetch`/`XHR`.
  webview,

  /// Captured by the `captureHttpClient` layer from `dart:io` `HttpClient`
  /// traffic (`Image.network`, `package:http`, SDKs, Dio without the
  /// inspector interceptor).
  httpClient,
}
