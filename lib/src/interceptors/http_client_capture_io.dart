import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';
import '../models/network_entry.dart';
import '../models/network_origin.dart';
import 'http_client_capture_common.dart';

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
    return _CapturingRequest(request, _inspector, start);
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

/// Write-through request proxy. Decides "already recorded by Dio or not" once,
/// right before the first body write or close: that is when dart:io sends the
/// headers, and after Dio has set them (spec 7-5).
class _CapturingRequest implements HttpClientRequest {
  _CapturingRequest(this._inner, this._inspector, this._start);

  final HttpClientRequest _inner;
  final FlutterInspector _inspector;
  final DateTime _start;
  bool _finalized = false;
  bool _completed = false;
  bool _responded = false;
  NetworkEntry? _pending;
  Future<HttpClientResponse>? _tracked;

  void _finalize() {
    if (_finalized) return;
    _finalized = true;
    _guard(_inspector, () {
      final headers = _inner.headers;
      if (headers[kDioMarkerHeader] != null) {
        headers.removeAll(kDioMarkerHeader); // Dio's interceptor records it
        return;
      }
      _pending = _inspector.logNetwork(
        NetworkEntry(
          method: _inner.method,
          url: _inner.uri.toString(),
          requestHeaders: _headerMap(headers),
          origin: NetworkOrigin.httpClient,
          timestamp: _start,
        ),
      );
    });
  }

  /// Awaits the response once for both [close] and [done] (spec 7-4).
  /// Failures complete the entry and are rethrown unchanged.
  Future<HttpClientResponse> _track(Future<HttpClientResponse> response) async {
    final HttpClientResponse value;
    try {
      value = await response;
    } on Object catch (error, stackTrace) {
      _complete(error: error, stackTrace: stackTrace);
      rethrow;
    }
    _responded = true;
    return value;
  }

  void _complete({Object? error, StackTrace? stackTrace}) {
    final pending = _pending;
    if (pending == null || _completed) return;
    _completed = true;
    _guard(_inspector, () {
      _inspector.logNetwork(
        pending.copyWith(
          duration: DateTime.now().difference(_start),
          error: error?.toString(),
          errorStackTrace: stackTrace?.toString(),
          isComplete: true,
        ),
        replaces: pending,
      );
    });
  }

  // One memo for both: dart:io's close() returns done, so a caller may ignore
  // one and await the other.
  @override
  Future<HttpClientResponse> get done => _tracked ??= _track(_inner.done);

  @override
  Future<HttpClientResponse> close() {
    _finalize();
    final closing = _inner.close(); // always forwarded: this sends the request
    return _tracked ??= _track(closing);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _inner.abort(exception, stackTrace);
    // After the response is out, dart:io's abort is a no-op and the body
    // completes the entry.
    if (!_responded) {
      _complete(error: exception ?? 'aborted', stackTrace: stackTrace);
    }
  }

  @override
  void add(List<int> data) {
    _finalize();
    _inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _finalize();
    _inner.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    _finalize();
    return _inner.addStream(stream);
  }

  @override
  Future flush() {
    _finalize();
    return _inner.flush();
  }

  // dart:io's own writeAll/writeln/writeCharCode are built on write, so one
  // write of the same text sends the same bytes; toString and the iterable
  // run exactly once.
  @override
  void write(Object? object) {
    final text = '$object';
    _finalize();
    _inner.write(text);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  bool get followRedirects => _inner.followRedirects;

  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;

  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  int get contentLength => _inner.contentLength;

  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  bool get bufferOutput => _inner.bufferOutput;

  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  // ponytail: a member the SDK adds later throws NoSuchMethodError when called
  // (only with captureHttpClient on) instead of breaking every build; add an
  // explicit forwarder for it (plan R6, option 2).
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _headerMap(HttpHeaders headers) {
  final map = <String, dynamic>{};
  headers.forEach((name, values) => map[name] = values.join(','));
  return map;
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
