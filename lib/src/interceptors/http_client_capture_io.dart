import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';
import '../models/network_entry.dart';
import '../models/network_origin.dart';

/// The overrides this isolate installed; also the once-per-isolate guard.
_InspectorHttpOverrides? _installed;

/// Chains an inspector layer onto the global `HttpOverrides` slot, once per
/// isolate.
///
/// Never restored or set to `null`: the slot is shared, so a later host
/// override simply replaces this layer and the host keeps working.
void installHttpClientCapture(FlutterInspector inspector) {
  if (_installed != null) {
    if (kDebugMode) {
      debugPrint(
        'flutter_inspector_kit: captureHttpClient is already active in this '
        'isolate; this inspector will not capture HttpClient traffic.',
      );
    }
    return;
  }
  // `current` is `zone value ?? global`; read the global slot itself so a
  // zone override is never promoted to apply outside its zone.
  final previous = Zone.root.run(() => HttpOverrides.current);
  final overrides = _InspectorHttpOverrides(previous, inspector);
  _installed = overrides;
  HttpOverrides.global = overrides;
}

/// Whether a request from [dio] will pass the layer that strips the marker:
/// this isolate's layer is the current one and [dio] uses
/// `IOHttpClientAdapter`. It proves this for [dio] only, not for whichever
/// Dio actually sends the request.
bool shouldTagDioRequest(Dio? dio) =>
    _installed != null &&
    identical(HttpOverrides.current, _installed) &&
    dio?.httpClientAdapter is IOHttpClientAdapter;

/// Forgets the install guard. Tests restore `HttpOverrides.global` themselves.
@visibleForTesting
void resetHttpClientCaptureForTesting() => _installed = null;

class _InspectorHttpOverrides extends HttpOverrides {
  _InspectorHttpOverrides(this._previous, this._inspector);

  final HttpOverrides? _previous;
  final FlutterInspector _inspector;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _CapturingHttpClient(
    _previous?.createHttpClient(context) ?? super.createHttpClient(context),
    _inspector,
  );

  // SDK reads this through HttpOverrides.current, so the host's proxy
  // settings would be lost without forwarding it.
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      _previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);
}

/// Forwards every member to the same-named member of [_inner]; only the
/// requests it opens are wrapped (spec 7-1).
class _CapturingHttpClient implements HttpClient {
  _CapturingHttpClient(this._inner, this._inspector);

  final HttpClient _inner;
  final FlutterInspector _inspector;

  /// Passes [opening] through, and records a failure to open (DNS, refused
  /// connection, TLS handshake): no request exists yet to track it later.
  Future<HttpClientRequest> _capture(
    Future<HttpClientRequest> opening,
    String method,
    String url,
  ) async {
    final start = DateTime.now(); // runs before the first await
    final HttpClientRequest request;
    try {
      request = await opening;
    } on Object catch (error, stackTrace) {
      _guard(
        _inspector,
        () => _inspector.logNetwork(
          NetworkEntry(
            method: method,
            url: url,
            origin: NetworkOrigin.httpClient,
            timestamp: start,
            duration: DateTime.now().difference(start),
            error: error.toString(),
            errorStackTrace: stackTrace.toString(),
            isComplete: true,
          ),
        ),
      );
      rethrow;
    }
    return request;
  }

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _capture(_inner.openUrl(method, url), method, '$url');

  // Without a request there is no scheme to read; a scheme-relative URL is
  // honest, a guessed one is not.
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _capture(
    _inner.open(method, host, port, path),
    method,
    '//$host:$port$path',
  );

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _capture(_inner.getUrl(url), 'GET', '$url');

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _capture(_inner.postUrl(url), 'POST', '$url');

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      _capture(_inner.putUrl(url), 'PUT', '$url');

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _capture(_inner.deleteUrl(url), 'DELETE', '$url');

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _capture(_inner.patchUrl(url), 'PATCH', '$url');

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _capture(_inner.headUrl(url), 'HEAD', '$url');

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _capture(_inner.get(host, port, path), 'GET', '//$host:$port$path');

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _capture(_inner.post(host, port, path), 'POST', '//$host:$port$path');

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _capture(_inner.put(host, port, path), 'PUT', '//$host:$port$path');

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _capture(_inner.delete(host, port, path), 'DELETE', '//$host:$port$path');

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _capture(_inner.patch(host, port, path), 'PATCH', '//$host:$port$path');

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _capture(_inner.head(host, port, path), 'HEAD', '//$host:$port$path');

  // ponytail: a member the SDK adds later throws NoSuchMethodError when called
  // (only with captureHttpClient on) instead of breaking every build; add an
  // explicit forwarder for it (plan R6, option 2).
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs capture bookkeeping; its own failures become a warning log and never
/// reach the host's request or response (spec 7-6).
void _guard(FlutterInspector inspector, void Function() body) {
  try {
    body();
  } on Object catch (e, st) {
    try {
      inspector.log(
        'HttpClient capture internal error: $e',
        level: LogLevel.warning,
        stackTrace: st.toString(),
      );
    } on Object catch (_) {}
  }
}
