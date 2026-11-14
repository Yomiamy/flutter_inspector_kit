import 'dart:async';
import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data' show BytesBuilder;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';
import '../models/network_entry.dart';
import '../models/network_origin.dart';
import '../utils/image_bytes.dart';
import '../utils/network_formatters.dart';
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

/// Forgets the install guard and clears any lingering marker entries. Tests
/// restore `HttpOverrides.global` themselves.
@visibleForTesting
void resetHttpClientCaptureForTesting() {
  _installed = null;
  liveDioMarkers.clear();
}

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
  final _Tee _body = _Tee();
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
      if (headers[kDioMarkerHeader] case [final token, ...]) {
        headers.removeAll(kDioMarkerHeader); // Dio's interceptor records it
        final live = liveDioMarkers.remove(token)?.target;
        // A resend may already carry a newer token; leave that one alone.
        if (live != null && live[kDioMarkerHeader] == token) {
          live.remove(kDioMarkerHeader);
        }
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
    return _wrap(value);
  }

  // A marked request is Dio's to record: its response is left untouched.
  HttpClientResponse _wrap(HttpClientResponse response) =>
      _pending == null ? response : _CapturingResponse(response, this);

  /// [whole] is true only when the response body ended normally, so the copy
  /// can be told apart from a cut one.
  void _complete({
    Object? error,
    StackTrace? stackTrace,
    _CapturingResponse? response,
    bool whole = false,
  }) {
    final pending = _pending;
    if (pending == null || _completed) return;
    _completed = true;
    _guard(_inspector, () {
      final body = response == null
          ? null
          : _describe(response._body, whole: whole);
      _inspector.logNetwork(
        pending.copyWith(
          statusCode: response?.statusCode,
          responseHeaders: response == null
              ? null
              : _headerMap(response.headers),
          requestBody: _requestBodyText(),
          responseBody: body?.text,
          responseImageBytes: body?.image,
          duration: DateTime.now().difference(_start),
          error: error?.toString(),
          errorStackTrace: stackTrace?.toString(),
          isComplete: true,
        ),
        replaces: pending,
      );
    });
  }

  // Like Dio's FormData, a multipart body is stored as a summary when
  // redacting: its field values are secrets the bytes would carry verbatim.
  String? _requestBodyText() {
    final type = _inner.headers[HttpHeaders.contentTypeHeader]?.first;
    if (_inspector.redactSensitiveData &&
        _body.total > 0 &&
        type != null &&
        type.toLowerCase().startsWith('multipart/')) {
      return '[${type.split(';').first.trim()}, ${formatBytes(_body.total)}]'
          '$kTruncatedMarker';
    }
    return _describe(_body, whole: true).text;
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
    _guard(_inspector, () => _body.add(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _finalize();
    _inner.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    _finalize();
    // Not transform(): Dio passes a runtime Stream<Uint8List>, and a
    // StreamTransformer<List<int>, List<int>> fails its covariant check.
    return _inner.addStream(
      stream.map((chunk) {
        _guard(_inspector, () => _body.add(chunk));
        return chunk;
      }),
    );
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
    _guard(_inspector, () => _body.add(encoding.encode(text)));
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

/// Subscribes to [_inner] only when the consumer listens and forwards every
/// chunk, pause, resume, cancel and error unchanged (spec 7-3). All other
/// Stream methods are built on [listen].
class _CapturingResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _CapturingResponse(this._inner, this._owner);

  final HttpClientResponse _inner;
  final _CapturingRequest _owner;
  final _Tee _body = _Tee();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<List<int>>(sync: true);
    // Subscribed before returning: a second listen throws StateError right
    // here, as the original does.
    final source = _inner.listen(
      (chunk) {
        // Copy first: the sync controller may run onCancel inside add.
        _guard(_owner._inspector, () => _body.add(chunk));
        controller.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        _owner._complete(response: this, error: error, stackTrace: stackTrace);
        controller.addError(error, stackTrace);
      },
      onDone: () {
        _owner._complete(response: this, whole: true);
        controller.close();
      },
    );
    controller
      ..onPause = source.pause
      ..onResume = source.resume
      // Also fires after done; _complete runs once, so done wins.
      ..onCancel = () {
        _owner._complete(response: this);
        return source.cancel();
      };
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<Socket> detachSocket() {
    _owner._complete(response: this);
    return _inner.detachSocket();
  }

  @override
  int get statusCode => _inner.statusCode;

  @override
  String get reasonPhrase => _inner.reasonPhrase;

  @override
  int get contentLength => _inner.contentLength;

  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  bool get isRedirect => _inner.isRedirect;

  @override
  List<RedirectInfo> get redirects => _inner.redirects;

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => _inner.redirect(method, url, followLoops);

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  X509Certificate? get certificate => _inner.certificate;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  // ponytail: a member the SDK adds later throws NoSuchMethodError when called
  // (only with captureHttpClient on) instead of breaking every build; add an
  // explicit forwarder for it (plan R6, option 2).
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Keeps a bounded prefix of a byte stream and counts the rest (spec Q3).
/// The cap is picked once the signature is visible: [kImageMaxBytes] for
/// images, [_kTextCopyBytes] otherwise.
class _Tee {
  final BytesBuilder _copy = BytesBuilder();
  int total = 0;
  int? _cap;

  void add(List<int> chunk) {
    total += chunk.length;
    // Sniff before copying: one chunk may be the whole body (package:http).
    final need = kImageSniffBytes - _copy.length;
    if (_cap == null && chunk.length >= need) {
      final head = [..._copy.toBytes(), ...chunk.take(need)];
      _cap = imageMimeType(head) != null ? kImageMaxBytes : _kTextCopyBytes;
    }
    final room = (_cap ?? kImageSniffBytes) - _copy.length;
    if (room <= 0) return;
    _copy.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
  }

  Uint8List takeBytes() => _copy.takeBytes();
}

/// At most 4 UTF-8 bytes per code point, so a copy cut at this size decodes
/// to more than kNetworkBodyMaxLength UTF-16 units and NetworkInspector.add
/// appends the marker itself.
const int _kTextCopyBytes = 4 * kNetworkBodyMaxLength;

/// What a [_Tee] saw, as entry body text plus, for a complete image, its bytes.
/// Empties [tee]: call it once per tee.
({String? text, Uint8List? image}) _describe(_Tee tee, {required bool whole}) {
  if (tee.total == 0) return (text: null, image: null);
  final head = tee.takeBytes();
  final complete = whole && head.length == tee.total;
  final mime = imageMimeType(head);
  if (mime != null) {
    // fromList: takeBytes() is a view of the builder's larger buffer.
    return (
      text: imageSummary(mime, tee.total),
      image: complete ? Uint8List.fromList(head) : null,
    );
  }
  return (
    text:
        _decodeUtf8(head, exact: complete) ??
        '[binary ${tee.total} bytes]$kTruncatedMarker',
    image: null,
  );
}

/// A cut prefix may end inside a character: drop up to 3 trailing bytes
/// before calling it binary.
String? _decodeUtf8(Uint8List bytes, {required bool exact}) {
  final maxDrop = exact ? 0 : 3;
  for (var drop = 0; drop <= maxDrop && drop < bytes.length; drop++) {
    try {
      return utf8.decode(Uint8List.sublistView(bytes, 0, bytes.length - drop));
    } on FormatException {
      continue;
    }
  }
  return null;
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
