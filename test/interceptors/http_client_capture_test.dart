import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/dio_interceptor.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_origin.dart';
import 'package:flutter_inspector_kit/src/utils/agent_prompt.dart';
import 'package:flutter_inspector_kit/src/utils/diagnostic_report.dart';
import 'package:flutter_inspector_kit/src/utils/network_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for a host's own `HttpOverrides` (SSL pinning, proxy rules);
/// hands out [client] when given one.
class _HostOverrides extends HttpOverrides {
  _HostOverrides([this.client]);

  final HttpClient? client;
  final contexts = <SecurityContext?>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    contexts.add(context);
    return client ?? super.createHttpClient(context);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      'PROXY host:9';
}

class _FakeAdapter extends Fake implements HttpClientAdapter {}

class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('ok', 200);

  @override
  void close({bool force = false}) {}
}

class _FakeCertificate extends Fake implements X509Certificate {}

class _FakeSocket extends Fake implements Socket {}

/// A response driven by hand. [events] records what reaches the source: the
/// proxy may listen, pause, resume and cancel it only when the consumer does.
class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse([this.statusCode = 200]);

  final events = <String>[];
  final socket = _FakeSocket();
  final redirectArgs = <Object?>[];
  late final next = _FakeResponse(302);
  late final controller = StreamController<List<int>>(
    onListen: () => events.add('listen'),
    onPause: () => events.add('pause'),
    onResume: () => events.add('resume'),
    onCancel: () => events.add('cancel'),
  );

  @override
  final int statusCode;
  @override
  final reasonPhrase = 'Teapot';
  @override
  final contentLength = 42;
  @override
  final compressionState = HttpClientResponseCompressionState.decompressed;
  @override
  final persistentConnection = false;
  @override
  final isRedirect = true;
  @override
  final redirects = <RedirectInfo>[];
  @override
  final headers = _FakeHeaders();
  @override
  final cookies = <Cookie>[];
  @override
  final X509Certificate certificate = _FakeCertificate();
  @override
  final HttpConnectionInfo connectionInfo = _FakeConnectionInfo();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<Socket> detachSocket() async => socket;

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) async {
    redirectArgs
      ..add(method)
      ..add(url)
      ..add(followLoops);
    return next;
  }
}

/// A header bag with just what the proxy reads and strips.
class _FakeHeaders extends Fake implements HttpHeaders {
  final map = <String, List<String>>{};

  @override
  List<String>? operator [](String name) => map[name.toLowerCase()];

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      map[name.toLowerCase()] = ['$value'];

  @override
  void removeAll(String name) => map.remove(name.toLowerCase());

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      map.forEach(action);
}

class _FakeConnectionInfo extends Fake implements HttpConnectionInfo {}

/// Records what it is handed, in order. [closing] and [doneFuture] let a test
/// make `close()` and `done` answer with different responses.
class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest({this.closing, this.doneFuture});

  final Future<HttpClientResponse>? closing;
  final Future<HttpClientResponse>? doneFuture;
  final calls = <List<Object?>>[];

  @override
  final headers = _FakeHeaders();
  @override
  final method = 'GET';
  @override
  final uri = Uri.parse('http://a.test/p');
  @override
  final cookies = <Cookie>[];
  @override
  final HttpConnectionInfo connectionInfo = _FakeConnectionInfo();
  @override
  final Encoding encoding = utf8;

  @override
  void add(List<int> data) => calls.add(['add', data]);

  @override
  void write(Object? object) => calls.add(['write', object]);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      calls.add(['addError', error]);

  @override
  Future addStream(Stream<List<int>> stream) =>
      stream.forEach((chunk) => calls.add(['addStream', chunk]));

  @override
  Future flush() async => calls.add(['flush']);

  @override
  Future<HttpClientResponse> close() {
    calls.add(['close']);
    return closing ?? Future.value(_FakeResponse(200));
  }

  @override
  Future<HttpClientResponse> get done =>
      doneFuture ?? Future.value(_FakeResponse(200));
}

/// Its headers cannot be read: capture bookkeeping fails, the request must not.
class _BrokenHeadersRequest extends _FakeRequest {
  @override
  HttpHeaders get headers => throw StateError('headers unavailable');
}

/// Its encoding cannot be read, which only the body copy needs.
class _BrokenEncodingRequest extends _FakeRequest {
  @override
  Encoding get encoding => throw StateError('encoding unavailable');
}

class _Data {
  // Valid 1x1 PNG (70 bytes; IHDR/IDAT/IEND CRCs verified).
  static final png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );
}

/// Loopback server. Records the headers of every request and answers by path:
/// `/slow` waits for [release]; `/echo` returns the request body; `/png`,
/// `/big` (6 MB PNG), `/binary`, `/long` and `/utf8` serve fixed bodies;
/// anything else says `hello`.
class _TestServer {
  _TestServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_TestServer> start() async =>
      _TestServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final received = <HttpHeaders>[];
  final _gate = Completer<void>();

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  Future<void> close() {
    release();
    return _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    received.add(request.headers);
    final response = request.response;
    try {
      final body = await request.expand((chunk) => chunk).toList();
      switch (request.uri.path) {
        case '/slow':
          await _gate.future;
          response.write('hello');
        case '/echo':
          response.add(body);
        case '/png':
          response.add(_Data.png1x1);
        case '/big':
          response
            ..add(_Data.png1x1.sublist(0, 8)) // the PNG signature
            ..add(Uint8List(6 * 1024 * 1024));
        case '/binary':
          response.add([0xFF, 0xFE, 0x00, 0x80]);
        case '/long':
          response.write('a' * 60 * 1024);
        case '/utf8':
          response.write('é' * 30000);
        case '/401':
          if (request.headers.value('authorization') != 'Bearer refreshed') {
            response.statusCode = HttpStatus.unauthorized;
          } else {
            response.write('ok');
          }
        default:
          response.write('hello');
      }
      await response.close();
    } on Object {
      // The client may abort mid-request; nobody is left to answer.
    }
  }
}

/// Records every call it receives and answers each with [opener]'s request.
class _FakeClient implements HttpClient {
  _FakeClient(this.opener);

  final Future<HttpClientRequest> Function() opener;
  final calls = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return opener();
  }
}

/// A loopback port nothing listens on: connecting to it is refused at once.
Future<int> _closedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  // `test()` only: `testWidgets` would make the binding install flutter_test's
  // own HttpOverrides on top of these (plan section 1, point 9).
  HttpOverrides? saved;
  late FlutterInspector inspector;

  setUp(() {
    saved = HttpOverrides.current;
    inspector = FlutterInspector(navigatorKey: GlobalKey<NavigatorState>());
  });
  tearDown(() {
    HttpOverrides.global = saved;
    resetHttpClientCaptureForTesting();
  });

  group('installHttpClientCapture', () {
    test('hands the caller\'s SecurityContext to the host as is (3-1)', () {
      final host = _HostOverrides();
      HttpOverrides.global = host;
      installHttpClientCapture(inspector);

      final context = SecurityContext(withTrustedRoots: false);
      HttpClient(context: context).close(force: true);

      expect(host.contexts, hasLength(1));
      expect(host.contexts.single, same(context));
    });

    test('forwards the host\'s proxy rules (3-2)', () {
      HttpOverrides.global = _HostOverrides();
      installHttpClientCapture(inspector);

      expect(
        HttpClient.findProxyFromEnvironment(Uri.parse('http://a.test')),
        'PROXY host:9',
      );
    });

    test('chains over the host once per isolate (4-3, Q6)', () {
      final host = _HostOverrides();
      HttpOverrides.global = host;

      installHttpClientCapture(inspector);
      final layer = HttpOverrides.current;
      expect(layer, isNotNull);
      expect(layer, isNot(same(host)));

      installHttpClientCapture(inspector);
      expect(HttpOverrides.current, same(layer));
    });

    test('a host override set later wins and nothing breaks (3-4)', () {
      installHttpClientCapture(inspector);
      final later = _HostOverrides();
      HttpOverrides.global = later;

      HttpClient().close(force: true);

      expect(later.contexts, hasLength(1));
      expect(shouldTagDioRequest(Dio()), isFalse);
    });

    test('installs over the global slot, not a zone override (D3)', () {
      var zoneCalls = 0;
      HttpOverrides.runZoned(
        () => installHttpClientCapture(inspector),
        createHttpClient: (context) {
          zoneCalls++;
          throw StateError('zone factory reached outside its zone');
        },
      );
      HttpClient().close(force: true); // outside the zone
      expect(zoneCalls, 0);
    });
  });

  group('shouldTagDioRequest', () {
    test('is false before install', () {
      expect(shouldTagDioRequest(Dio()), isFalse);
    });

    test('is true for an IOHttpClientAdapter Dio after install', () {
      installHttpClientCapture(inspector);
      expect(shouldTagDioRequest(Dio()), isTrue);
    });

    test('is false for null and for a non-IO adapter', () {
      installHttpClientCapture(inspector);
      expect(shouldTagDioRequest(null), isFalse);
      expect(
        shouldTagDioRequest(Dio()..httpClientAdapter = _FakeAdapter()),
        isFalse,
      );
    });
  });

  group('capturing client over a host client (3-1, 7-1, 3-3)', () {
    late _FakeClient fake;
    late HttpClient client;

    setUp(() {
      fake = _FakeClient(() => Future.value(_FakeRequest()));
      HttpOverrides.global = _HostOverrides(fake);
      installHttpClientCapture(inspector);
      client = HttpClient();
      // Every test below is about the proxy; without one `client` is `fake`.
      expect(client, isNot(same(fake)), reason: 'HttpClient() must be wrapped');
    });

    final uri = Uri.parse('http://a.test/p?q=1');
    const hostArgs = ['a.test', 80, '/p'];
    final opens =
        <
          (String, Future<HttpClientRequest> Function(HttpClient), List<Object>)
        >[
          (
            'open',
            (c) => c.open('GET', 'a.test', 80, '/p'),
            ['GET', ...hostArgs],
          ),
          ('openUrl', (c) => c.openUrl('GET', uri), ['GET', uri]),
          ('get', (c) => c.get('a.test', 80, '/p'), hostArgs),
          ('getUrl', (c) => c.getUrl(uri), [uri]),
          ('post', (c) => c.post('a.test', 80, '/p'), hostArgs),
          ('postUrl', (c) => c.postUrl(uri), [uri]),
          ('put', (c) => c.put('a.test', 80, '/p'), hostArgs),
          ('putUrl', (c) => c.putUrl(uri), [uri]),
          ('delete', (c) => c.delete('a.test', 80, '/p'), hostArgs),
          ('deleteUrl', (c) => c.deleteUrl(uri), [uri]),
          ('patch', (c) => c.patch('a.test', 80, '/p'), hostArgs),
          ('patchUrl', (c) => c.patchUrl(uri), [uri]),
          ('head', (c) => c.head('a.test', 80, '/p'), hostArgs),
          ('headUrl', (c) => c.headUrl(uri), [uri]),
        ];
    for (final (name, call, args) in opens) {
      test('$name forwards to the same-named member (7-1)', () async {
        await call(client);

        expect(fake.calls.single.memberName, Symbol(name));
        expect(fake.calls.single.positionalArguments, args);
      });
    }

    test('hands setter-only callbacks to the host client as is (3-3)', () {
      Future<bool> authenticate(Uri url, String scheme, String? realm) async =>
          true;
      Future<ConnectionTask<Socket>> connectionFactory(
        Uri url,
        String? proxyHost,
        int? proxyPort,
      ) => throw UnimplementedError();
      String findProxy(Uri url) => 'DIRECT';
      Future<bool> authenticateProxy(
        String host,
        int port,
        String scheme,
        String? realm,
      ) async => true;
      bool badCertificate(X509Certificate cert, String host, int port) => true;
      void keyLog(String line) {}

      client
        ..authenticate = authenticate
        ..connectionFactory = connectionFactory
        ..findProxy = findProxy
        ..authenticateProxy = authenticateProxy
        ..badCertificateCallback = badCertificate
        ..keyLog = keyLog;

      final given = <String, Object>{
        'authenticate=': authenticate,
        'connectionFactory=': connectionFactory,
        'findProxy=': findProxy,
        'authenticateProxy=': authenticateProxy,
        'badCertificateCallback=': badCertificate,
        'keyLog=': keyLog,
      };
      expect(fake.calls.map((c) => c.memberName), [
        for (final name in given.keys) Symbol(name),
      ]);
      for (final (i, callback) in given.values.indexed) {
        expect(fake.calls[i].positionalArguments.single, same(callback));
      }
    });

    test('forwards credentials and close(force:) arguments as is (3-3)', () {
      final credentials = HttpClientBasicCredentials('user', 'pw');

      client
        ..addCredentials(uri, 'realm', credentials)
        ..addProxyCredentials('proxy.test', 8080, 'realm', credentials)
        ..close(force: true);

      expect(fake.calls.map((c) => c.memberName), [
        #addCredentials,
        #addProxyCredentials,
        #close,
      ]);
      expect(fake.calls[0].positionalArguments, [
        uri,
        'realm',
        same(credentials),
      ]);
      expect(fake.calls[1].positionalArguments, [
        'proxy.test',
        8080,
        'realm',
        same(credentials),
      ]);
      expect(fake.calls[2].namedArguments, {#force: true});
    });
  });

  group('capturing client over a real client (3-3, 1-4)', () {
    late HttpClient real;
    late HttpClient client;

    setUp(() {
      real = HttpClient(); // built before the overrides: the SDK's own client
      HttpOverrides.global = _HostOverrides(real);
      installHttpClientCapture(inspector);
      client = HttpClient();
    });
    tearDown(() => real.close(force: true));

    test('getters and setters reach the inner client (3-3)', () {
      client
        ..idleTimeout = const Duration(seconds: 3)
        ..connectionTimeout = const Duration(seconds: 4)
        ..maxConnectionsPerHost = 7
        ..autoUncompress = false
        ..userAgent = 'via-proxy';
      expect(real.idleTimeout, const Duration(seconds: 3));
      expect(real.connectionTimeout, const Duration(seconds: 4));
      expect(real.maxConnectionsPerHost, 7);
      expect(real.autoUncompress, isFalse);
      expect(real.userAgent, 'via-proxy');

      real
        ..idleTimeout = const Duration(seconds: 5)
        ..connectionTimeout = null
        ..maxConnectionsPerHost = 9
        ..autoUncompress = true
        ..userAgent = null;
      expect(client.idleTimeout, const Duration(seconds: 5));
      expect(client.connectionTimeout, isNull);
      expect(client.maxConnectionsPerHost, 9);
      expect(client.autoUncompress, isTrue);
      expect(client.userAgent, isNull);
    });

    test('records a refused connection, rethrows the original (1-4)', () async {
      final url = Uri.parse('http://127.0.0.1:${await _closedPort()}/x');
      Object? error;
      StackTrace? stack;

      try {
        await client.getUrl(url);
      } on Object catch (e, st) {
        error = e;
        stack = st;
      }

      expect(error, isA<SocketException>());
      final entry = inspector.networkEntries.single;
      expect(entry.method, 'GET');
      expect(entry.url, '$url');
      expect(entry.origin, NetworkOrigin.httpClient);
      expect(entry.isComplete, isTrue);
      expect(entry.error, error.toString());
      expect(entry.errorStackTrace, stack.toString()); // rethrow keeps it
      expect(entry.errorType, isNull);
      expect(entry.sourceDio, isNull);
    });

    test(
      'host/port/path requests record a scheme-relative url (7-1)',
      () async {
        final port = await _closedPort();

        await expectLater(
          client.get('127.0.0.1', port, '/y'),
          throwsA(isA<SocketException>()),
        );

        expect(inspector.networkEntries.single.url, '//127.0.0.1:$port/y');
      },
    );
  });

  /// Opens a proxy request that wraps [inner], through the installed layer.
  Future<HttpClientRequest> openOver(HttpClientRequest inner) {
    HttpOverrides.global = _HostOverrides(
      _FakeClient(() => Future.value(inner)),
    );
    installHttpClientCapture(inspector);
    return HttpClient().getUrl(Uri.parse('http://a.test/p'));
  }

  /// The response a proxy request hands out when its inner one answers [fake].
  Future<HttpClientResponse> respondWith(_FakeResponse fake) async {
    final req = await openOver(_FakeRequest(closing: Future.value(fake)));
    return req.close();
  }

  group('capturing request over a fake request (7-2, 7-4, 7-6, R6)', () {
    test('writes go straight through, in order and unchanged (7-2)', () async {
      final fake = _FakeRequest();
      final req = await openOver(fake);
      final first = <int>[1, 2];
      final second = <int>[3];
      final failure = StateError('boom');

      req
        ..add(first)
        ..add(second)
        ..addError(failure)
        ..write('é')
        ..writeAll(['a', 'b'], ',')
        ..writeln('c')
        ..writeCharCode(0x41);
      await req.flush();

      expect(fake.calls, [
        ['add', same(first)],
        ['add', same(second)],
        ['addError', same(failure)],
        ['write', 'é'],
        ['write', 'a,b'],
        ['write', 'c\n'],
        ['write', 'A'],
        ['flush'],
      ]);
    });

    test('addStream hands each chunk on as the same object (R2-1)', () async {
      final fake = _FakeRequest();
      final req = await openOver(fake);
      final chunk = Uint8List.fromList([1, 2, 3]);

      await req.addStream(Stream<Uint8List>.fromIterable([chunk]));

      expect(fake.calls, [
        ['addStream', same(chunk)],
      ]);
    });

    test('a failing body copy is a warning log; the write still goes out '
        '(7-6)', () async {
      final fake = _BrokenEncodingRequest();
      final req = await openOver(fake);

      req.write('x');

      expect(fake.calls, [
        ['write', 'x'],
      ]);
      final warnings = inspector.logEntries.where(
        (e) => e.level == LogLevel.warning,
      );
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('encoding unavailable'));
    });

    test('close() and done give one response although the inner ones differ '
        '(7-4, R2-2)', () async {
      final fake = _FakeRequest(
        closing: Future.value(_FakeResponse(201)),
        doneFuture: Future.value(_FakeResponse(202)),
      );
      final req = await openOver(fake);

      final response = await req.close();

      expect(response.statusCode, 201);
      expect(await req.done, same(response));
    });

    test('close() still reaches the inner request when done was read first '
        '(R2-2)', () async {
      final fake = _FakeRequest();
      final req = await openOver(fake);

      final early = req.done;
      final response = await req.close();

      expect(fake.calls, [
        ['close'],
      ]);
      expect(await early, same(response));
    });

    test('a failing close preserves the original stack trace', () async {
      final error = StateError('down');
      final stack = StackTrace.current;
      final closing = Completer<HttpClientResponse>();
      final req = await openOver(_FakeRequest(closing: closing.future));
      final result = req.close();
      closing.completeError(error, stack);
      StackTrace? got;
      try {
        await result;
      } on Object catch (_, st) {
        got = st;
      }
      expect('$got', '$stack');
    });

    test('read-only members come from the inner request unchanged', () async {
      final fake = _FakeRequest();
      final req = await openOver(fake);

      expect(req.headers, same(fake.headers));
      expect(req.cookies, same(fake.cookies));
      expect(req.connectionInfo, same(fake.connectionInfo));
      expect(req.method, fake.method);
      expect(req.uri, fake.uri);
    });

    test('a capture failure is a warning log; the request still goes out '
        '(7-6)', () async {
      final fake = _BrokenHeadersRequest();
      final req = await openOver(fake);

      await req.close();

      expect(fake.calls, [
        ['close'],
      ]);
      expect(inspector.networkEntries, isEmpty);
      final warnings = inspector.logEntries.where(
        (e) => e.level == LogLevel.warning,
      );
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('headers unavailable'));
    });
  });

  group('capturing request over a real server (1-2, 7-4, 7-5, 1-4, R6)', () {
    late _TestServer server;
    late HttpClient client;

    setUp(() async {
      server = await _TestServer.start();
      installHttpClientCapture(inspector);
      client = HttpClient();
    });
    tearDown(() async {
      client.close(force: true);
      await server.close();
    });

    test('is pending only from the moment it is closed (1-2)', () async {
      final req = await client.getUrl(server.url('/text'));
      expect(inspector.networkEntries, isEmpty);

      final closing = req.close();

      final pending = inspector.networkEntries.single;
      expect(pending.isComplete, isFalse);
      expect(pending.origin, NetworkOrigin.httpClient);
      expect(pending.method, 'GET');
      expect(pending.url, '${server.url('/text')}');
      expect(pending.requestHeaders, contains('host'));
      await (await closing).drain<void>();
    });

    test('takes the Dio marker off before the first write and records nothing '
        '(7-5, 2-2)', () async {
      final req = await client.postUrl(server.url('/text'));
      req.headers.set(kDioMarkerHeader, 'x');

      await req.addStream(Stream.value([1, 2, 3]));
      await (await req.close()).drain<void>();

      expect(server.received.single[kDioMarkerHeader], isNull);
      expect(inspector.networkEntries, isEmpty);
    });

    test('a bodyless marked request removes the Dio marker before close sends '
        'headers (7-5, 2-2)', () async {
      final req = await client.getUrl(server.url('/text'));
      req.headers.set(kDioMarkerHeader, 'x');
      await (await req.close()).drain<void>();
      expect(server.received.single[kDioMarkerHeader], isNull);
      expect(inspector.networkEntries, isEmpty);
    });

    test(
      'close() and done return the same response, recorded once (7-4)',
      () async {
        final req = await client.getUrl(server.url('/text'));

        final response = await req.close();

        expect(await req.done, same(response));
        expect(inspector.networkEntries, hasLength(1));
        await response.drain<void>();
      },
    );

    test('a caller that drops close() and awaits done sees one failure '
        '(R2-2)', () async {
      final req = await client.getUrl(server.url('/slow'));

      req.close(); // return value ignored on purpose
      req.abort();

      await expectLater(req.done, throwsA(anything));
    });

    test(
      'abort after a write completes the entry with an error (1-4)',
      () async {
        final req = await client.postUrl(server.url('/text'));

        req
          ..write('x')
          ..abort();

        final entry = inspector.networkEntries.single;
        expect(entry.isComplete, isTrue);
        expect(entry.error, isNotNull);
      },
    );

    test(
      'abort before the response marks the entry complete immediately (1-4)',
      () async {
        final req = await client.getUrl(server.url('/slow'));
        final closing = req.close();
        req.abort(StateError('cancelled'));
        expect(inspector.networkEntries.single.isComplete, isTrue);
        await expectLater(closing, throwsA(anything));
      },
    );

    test('abort before the response fails done with the original exception '
        'and completes once (1-4, R2-3)', () async {
      final req = await client.getUrl(server.url('/slow'));
      final reason = StateError('cancelled');

      final closing = req.close();
      req.abort(reason);

      await expectLater(closing, throwsA(same(reason)));
      // A second completion would add a second entry: replaces: no longer matches.
      final entry = inspector.networkEntries.single;
      expect(entry.isComplete, isTrue);
      expect(entry.error, reason.toString());
    });

    test('abort after the response arrived is a no-op: still pending, body '
        'still readable (1-4, R2-3)', () async {
      final req = await client.getUrl(server.url('/text'));
      final response = await req.close();

      req.abort();

      final entry = inspector.networkEntries.single;
      expect(entry.isComplete, isFalse);
      expect(entry.error, isNull);
      expect(await utf8.decodeStream(response), 'hello');
    });

    test('settable members round-trip through the inner request (R6)', () async {
      final req = await client.postUrl(server.url('/text'));

      req
        ..persistentConnection = false
        ..followRedirects = false
        ..maxRedirects = 7
        ..contentLength = 5
        ..bufferOutput = false;

      expect(req.persistentConnection, isFalse);
      expect(req.followRedirects, isFalse);
      expect(req.maxRedirects, 7);
      expect(req.contentLength, 5);
      expect(req.bufferOutput, isFalse);
      // dart:io derives the encoding from the Content-Type charset and rejects
      // the setter, so the forwarded getter and setter are what we can pin.
      expect(req.encoding, latin1);
      req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
      expect(req.encoding, utf8);
      expect(() => req.encoding = utf8, throwsStateError);
      req.abort();
    });

    test(
      'the entry is completed in place once the body is read (1-2)',
      () async {
        final req = await client.getUrl(server.url('/text'));
        final response = await req.close();
        expect(inspector.networkEntries.single.isComplete, isFalse);

        expect(await utf8.decodeStream(response), 'hello');

        final entry = inspector.networkEntries.single;
        expect(entry.isComplete, isTrue);
        expect(entry.statusCode, 200);
        expect(entry.error, isNull);
      },
    );

    test('abort after the response arrived: the body completes the entry '
        '(R2-3)', () async {
      final req = await client.getUrl(server.url('/text'));
      final response = await req.close();

      req.abort();
      await response.drain<void>();

      final entry = inspector.networkEntries.single;
      expect(entry.isComplete, isTrue);
      expect(entry.statusCode, 200);
      expect(entry.error, isNull);
    });
  });

  group('capturing response over a fake response (7-3, 3-3, 1-5, 1-4, R6)', () {
    test('listens only when the consumer does, forwards chunks as they are '
        '(7-3)', () async {
      final fake = _FakeResponse();
      final response = await respondWith(fake);
      expect(response, isNot(same(fake)));
      expect(fake.events, isEmpty); // the inspector never listens on its own

      final received = <List<int>>[];
      final done = Completer<void>();
      response.listen(received.add, onDone: done.complete);
      expect(fake.events, ['listen']);

      final first = <int>[1];
      final second = <int>[2, 3];
      fake.controller
        ..add(first)
        ..add(second)
        ..close();
      await done.future;

      expect(received, [same(first), same(second)]);
    });

    test('pause, resume and cancel reach the source (7-3)', () async {
      final fake = _FakeResponse();
      final subscription = (await respondWith(fake)).listen((_) {});

      subscription
        ..pause()
        ..resume();
      await subscription.cancel();

      expect(fake.events, ['listen', 'pause', 'resume', 'cancel']);
    });

    test('errors reach the consumer with their stack trace (7-3)', () async {
      final fake = _FakeResponse();
      final response = await respondWith(fake);
      final error = StateError('reset');
      final stack = StackTrace.current;
      Object? gotError;
      StackTrace? gotStack;
      response.listen(
        (_) {},
        onError: (Object e, StackTrace s) {
          gotError = e;
          gotStack = s;
        },
      );

      fake.controller.addError(error, stack);
      await pumpEventQueue();

      expect(gotError, same(error));
      expect(gotStack, same(stack));
    });

    test(
      'a second listen throws StateError, like the original (7-3)',
      () async {
        final response = await respondWith(_FakeResponse());

        response.listen((_) {});

        expect(() => response.listen((_) {}), throwsStateError);
      },
    );

    test('every other member is the inner response\'s own (3-3)', () async {
      final fake = _FakeResponse(207);
      final response = await respondWith(fake);

      expect(response.headers, same(fake.headers));
      expect(response.certificate, same(fake.certificate));
      expect(response.connectionInfo, same(fake.connectionInfo));
      expect(response.redirects, same(fake.redirects));
      expect(response.cookies, same(fake.cookies));
      expect(response.statusCode, 207);
      expect(response.reasonPhrase, fake.reasonPhrase);
      expect(response.contentLength, fake.contentLength);
      expect(response.compressionState, fake.compressionState);
      expect(response.persistentConnection, fake.persistentConnection);
      expect(response.isRedirect, fake.isRedirect);
    });

    test('redirect() forwards its arguments and returns the new response as '
        'is', () async {
      final fake = _FakeResponse();
      final response = await respondWith(fake);
      final target = Uri.parse('http://a.test/next');

      final next = await response.redirect('GET', target, true);

      expect(fake.redirectArgs, ['GET', target, true]);
      expect(next, same(fake.next));
    });

    test('cancelling the subscription completes the entry, no error '
        '(1-5)', () async {
      final response = await respondWith(_FakeResponse());
      final subscription = response.listen((_) {});
      expect(inspector.networkEntries.single.isComplete, isFalse);

      await subscription.cancel();

      final entry = inspector.networkEntries.single;
      expect(entry.isComplete, isTrue);
      expect(entry.error, isNull);
      expect(entry.statusCode, 200);
    });

    test('detachSocket completes the entry and returns the inner socket '
        '(1-5)', () async {
      final fake = _FakeResponse();
      final response = await respondWith(fake);

      expect(await response.detachSocket(), same(fake.socket));

      final entry = inspector.networkEntries.single;
      expect(entry.isComplete, isTrue);
      expect(entry.error, isNull);
    });

    test('a stream error completes the entry with it (1-4)', () async {
      final fake = _FakeResponse(206);
      final response = await respondWith(fake);
      final failure = StateError('reset');
      response.listen((_) {}, onError: (Object _) {});

      fake.controller.addError(failure);
      await pumpEventQueue();

      final entry = inspector.networkEntries.single;
      expect(entry.isComplete, isTrue);
      expect(entry.error, failure.toString());
      expect(entry.statusCode, 206);
    });

    test('done completes the entry once; the cancel after it adds nothing '
        '(1-2)', () async {
      final fake = _FakeResponse();
      final response = await respondWith(fake);
      final drained = response.drain<void>();

      fake.controller
        ..add([1])
        ..close();
      await drained;
      await pumpEventQueue(); // the sync controller's onCancel runs after done

      expect(fake.events, contains('cancel'));
      // A second completion would add a second entry: replaces: no longer matches.
      final entry = inspector.networkEntries.single;
      expect(entry.isComplete, isTrue);
      expect(entry.error, isNull);
    });

    test('a text prefix cut inside a character is still text (1-3)', () async {
      final fake = _FakeResponse();
      final response = await respondWith(fake);
      final drained = response.drain<void>();

      // The first chunk reaches the copy cap in the middle of an 'é' (C3 A9).
      fake.controller
        ..add([...List.filled(40959, 0x61), 0xC3])
        ..add([0xA9])
        ..close();
      await drained;

      final body = inspector.networkEntries.single.responseBody;
      expect(body, startsWith('aaaa'));
      expect(body, endsWith(kTruncatedMarker));
    });

    test('a cancelled prefix of a few non-text bytes is binary, not an empty '
        'body (1-3)', () async {
      final fake = _FakeResponse();
      final response = await respondWith(fake);
      final subscription = response.listen((_) {});

      fake.controller.add([0xFF, 0xFE]);
      await pumpEventQueue();
      await subscription.cancel();

      expect(
        inspector.networkEntries.single.responseBody,
        '[binary 2 bytes]$kTruncatedMarker',
      );
    });

    test(
      'a mid-size image arriving in chunks keeps its preview bytes (6-1)',
      () async {
        final fake = _FakeResponse();
        final response = await respondWith(fake);
        final drained = response.drain<void>();
        final image = Uint8List(100 * 1024)
          ..setAll(0, _Data.png1x1.sublist(0, 8));
        for (var i = 0; i < image.length; i += 1024) {
          fake.controller.add(image.sublist(i, i + 1024));
        }
        fake.controller.close();
        await drained;
        expect(inspector.networkEntries.single.responseImageBytes, image);
      },
    );

    test(
      'a complete image keeps its own bytes, not the copy buffer (6-1)',
      () async {
        final fake = _FakeResponse();
        final response = await respondWith(fake);
        final drained = response.drain<void>();
        // One chunk: BytesBuilder grows its buffer to a power of two.
        final image = Uint8List(3 * 1024 * 1024 + 1)
          ..setAll(0, _Data.png1x1.sublist(0, 8));
        fake.controller
          ..add(image)
          ..close();
        await drained;

        final kept = inspector.networkEntries.single.responseImageBytes!;
        expect(kept, image);
        expect(kept.buffer.lengthInBytes, kept.length);
      },
    );

    test(
      'multibyte UTF-8 arriving in chunks is truncated with the marker (1-3)',
      () async {
        final fake = _FakeResponse();
        final response = await respondWith(fake);
        final drained = response.drain<void>();
        final bytes = utf8.encode('\u00e9' * 30000);
        for (var i = 0; i < bytes.length; i += 1000) {
          fake.controller.add(bytes.sublist(i, i + 1000));
        }
        fake.controller.close();
        await drained;
        final body = inspector.networkEntries.single.responseBody;
        expect(body, startsWith('\u00e9'));
        expect(body, endsWith(kTruncatedMarker));
      },
    );

    test('a response to a marked request is passed through untouched '
        '(7-5)', () async {
      final fake = _FakeResponse();
      final inner = _FakeRequest(closing: Future.value(fake));
      inner.headers.set(kDioMarkerHeader, 'x');
      final req = await openOver(inner);

      expect(await req.close(), same(fake));
      expect(inspector.networkEntries, isEmpty);
    });
  });

  group('capturing bodies over a real server (1-1, 1-3, 6-1, 6-4, R2-1)', () {
    late _TestServer server;
    late HttpClient client;

    setUp(() async {
      server = await _TestServer.start();
      installHttpClientCapture(inspector);
      client = HttpClient();
    });
    tearDown(() async {
      client.close(force: true);
      await server.close();
    });

    /// Reads the whole body of a GET to [path]; returns once the entry is done.
    Future<NetworkEntry> get(String path) async {
      final req = await client.getUrl(server.url(path));
      await (await req.close()).drain<void>();
      return inspector.networkEntries.single;
    }

    test('a GET and a POST are each recorded once with what is known '
        '(1-1)', () async {
      final getRequest = await client.getUrl(server.url('/text'));
      expect(await utf8.decodeStream(await getRequest.close()), 'hello');
      final post = await client.postUrl(server.url('/echo'));
      post
        ..add(utf8.encode('{"a":'))
        ..write('1}');
      expect(await utf8.decodeStream(await post.close()), '{"a":1}');

      expect(inspector.networkEntries, hasLength(2));
      final byMethod = {for (final e in inspector.networkEntries) e.method: e};
      final getEntry = byMethod['GET']!;
      final postEntry = byMethod['POST']!;
      expect(getEntry.url, '${server.url('/text')}');
      expect(getEntry.requestBody, isNull);
      expect(getEntry.responseBody, 'hello');
      expect(postEntry.url, '${server.url('/echo')}');
      expect(postEntry.requestBody, '{"a":1}');
      expect(postEntry.responseBody, '{"a":1}');
      for (final entry in [getEntry, postEntry]) {
        expect(entry.origin, NetworkOrigin.httpClient);
        expect(entry.isComplete, isTrue);
        expect(entry.statusCode, 200);
        expect(entry.duration, isNotNull);
        expect(entry.requestHeaders, contains('host'));
        // A header dart:io's HttpServer adds to every response.
        expect(
          entry.responseHeaders,
          containsPair('x-content-type-options', 'nosniff'),
        );
        expect(entry.error, isNull);
      }
    });

    for (final (path, prefix) in [('/long', 'aaaa'), ('/utf8', 'éééé')]) {
      test(
        '$path is text: cut by the inspector, never [binary] (1-3)',
        () async {
          final entry = await get(path);

          final body = entry.responseBody!;
          expect(body, startsWith(prefix));
          expect(body.length, kNetworkBodyMaxLength + kTruncatedMarker.length);
        },
      );
    }

    test(
      'bytes that are neither text nor an image are counted (1-3)',
      () async {
        final entry = await get('/binary');

        expect(entry.responseBody, '[binary 4 bytes]$kTruncatedMarker');
        expect(entry.responseImageBytes, isNull);
      },
    );

    test('a complete PNG is summarized and its bytes are kept (6-1)', () async {
      final entry = await get('/png');

      expect(entry.responseBody, '[image/png, 70 B]$kTruncatedMarker');
      expect(entry.responseImageBytes, _Data.png1x1);
    });

    test('an image above 5 MB keeps its size, not its bytes (6-4)', () async {
      final entry = await get('/big');

      expect(entry.responseBody, '[image/png, 6.0 MB]$kTruncatedMarker');
      expect(entry.responseImageBytes, isNull);
    });

    test('addStream takes the Stream<Uint8List> Dio sends (R2-1)', () async {
      final req = await client.postUrl(server.url('/echo'));

      await req.addStream(
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList(utf8.encode('{"a":1}')),
        ]),
      );

      expect(await utf8.decodeStream(await req.close()), '{"a":1}');
      expect(inspector.networkEntries.single.requestBody, '{"a":1}');
    });

    // package:http sends the whole body as one chunk; only a bounded prefix
    // may be copied, so the non-text tail past it is never seen (Q3).
    test('a body sent as one large chunk is cut to its text prefix '
        '(Q3)', () async {
      final req = await client.postUrl(server.url('/echo'));
      req.add([...List.filled(5 * kNetworkBodyMaxLength, 0x61), 0xFF]);
      await (await req.close()).drain<void>();

      final body = inspector.networkEntries.single.requestBody!;
      expect(body, startsWith('aaaa'));
      expect(body.length, kNetworkBodyMaxLength + kTruncatedMarker.length);
    });
  });

  group('live Dio marker handshake (T12b)', () {
    late _TestServer server;

    setUp(() async {
      server = await _TestServer.start();
      installHttpClientCapture(inspector);
    });
    tearDown(() async => server.close());

    test(
      'earlier response interceptor does not see the marker (R14c)',
      () async {
        final seenHeaders = <Map<String, dynamic>>[];
        final dio = Dio();
        dio.interceptors
          ..add(
            InterceptorsWrapper(
              onResponse: (response, handler) {
                seenHeaders.add(Map.of(response.requestOptions.headers));
                handler.next(response);
              },
            ),
          )
          ..add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));

        await dio.get<String>(server.url('/text').toString());

        expect(seenHeaders.single, isNot(contains(kDioMarkerHeader)));
        expect(inspector.logEntries, isEmpty);
        expect(liveDioMarkers, isEmpty);
      },
    );

    test('401 token refresh resent through another Dio records httpClient and '
        'never leaks the marker', () async {
      final dioA = Dio();
      final dioB = Dio();
      dioA.interceptors
        ..add(
          InterceptorsWrapper(
            onError: (err, handler) async {
              err.requestOptions.headers['authorization'] = 'Bearer refreshed';
              handler.resolve(await dioB.fetch<dynamic>(err.requestOptions));
            },
          ),
        )
        ..add(FlutterInspectorDioInterceptor(inspector, sourceDio: dioA));

      final response = await dioA.get<String>(server.url('/401').toString());

      expect(response.data, 'ok');
      expect(server.received, hasLength(2));
      for (final headers in server.received) {
        expect(headers[kDioMarkerHeader], isNull);
      }
      expect(
        inspector.networkEntries.where(
          (e) => e.origin == NetworkOrigin.httpClient && e.statusCode == 200,
        ),
        hasLength(1),
      );
      expect(liveDioMarkers, isEmpty);
    });

    test(
      'pre-connect failure resent through another Dio skips recording: known '
      'residual (plan §9.2)',
      () async {
        final port = await _closedPort();
        final dioA = Dio();
        final dioB = Dio();
        var retried = false;
        dioA.interceptors
          ..add(
            InterceptorsWrapper(
              onError: (err, handler) async {
                if (!retried) {
                  retried = true;
                  err.requestOptions.path = server.url('/text').toString();
                  handler.resolve(
                    await dioB.fetch<dynamic>(err.requestOptions),
                  );
                  return;
                }
                handler.next(err);
              },
            ),
          )
          ..add(FlutterInspectorDioInterceptor(inspector, sourceDio: dioA));

        final response = await dioA.get<String>('http://127.0.0.1:$port/text');

        expect(response.data, 'hello');
        expect(server.received.single[kDioMarkerHeader], isNull);
        expect(
          inspector.networkEntries.where(
            (e) => e.origin == NetworkOrigin.httpClient && e.statusCode == 200,
          ),
          isEmpty,
        );
        expect(liveDioMarkers, isEmpty);
      },
    );

    test('leaves no orphans in liveDioMarkers across sequential request '
        'scenarios', () async {
      final dio = Dio();
      dio.interceptors.add(
        FlutterInspectorDioInterceptor(inspector, sourceDio: dio),
      );

      // 1. GET
      await dio.get<String>(server.url('/text').toString());
      expect(liveDioMarkers, isEmpty, reason: 'after GET');

      // 2. POST
      await dio.post<String>(server.url('/echo').toString(), data: {'a': 1});
      expect(liveDioMarkers, isEmpty, reason: 'after POST');

      // 3. 401 resent via Dio B
      final dioRefresh = Dio();
      final dioB = Dio();
      dioRefresh.interceptors
        ..add(
          InterceptorsWrapper(
            onError: (err, handler) async {
              err.requestOptions.headers['authorization'] = 'Bearer refreshed';
              handler.resolve(await dioB.fetch<dynamic>(err.requestOptions));
            },
          ),
        )
        ..add(FlutterInspectorDioInterceptor(inspector, sourceDio: dioRefresh));
      await dioRefresh.get<String>(server.url('/401').toString());
      expect(liveDioMarkers, isEmpty, reason: 'after 401 -> Dio B');

      // 4. Pre-connect failure resent via the same Dio (dio.fetch)
      final closed = await _closedPort();
      var retriedSame = false;
      final dioSameRetry = Dio();
      dioSameRetry.interceptors
        ..add(
          InterceptorsWrapper(
            onError: (err, handler) async {
              if (!retriedSame) {
                retriedSame = true;
                err.requestOptions.path = server.url('/text').toString();
                handler.resolve(
                  await dioSameRetry.fetch<dynamic>(err.requestOptions),
                );
                return;
              }
              handler.next(err);
            },
          ),
        )
        ..add(
          FlutterInspectorDioInterceptor(inspector, sourceDio: dioSameRetry),
        );
      final sameRetryRes = await dioSameRetry.get<String>(
        'http://127.0.0.1:$closed/text',
      );
      expect(sameRetryRes.data, 'hello');
      expect(liveDioMarkers, isEmpty, reason: 'after pre-connect -> same');

      // 5. Pre-connect failure resent via Dio B: known residual (plan §9.2)
      var retriedOther = false;
      final dioOtherRetry = Dio();
      dioOtherRetry.interceptors
        ..add(
          InterceptorsWrapper(
            onError: (err, handler) async {
              if (!retriedOther) {
                retriedOther = true;
                err.requestOptions.path = server.url('/text').toString();
                handler.resolve(await dioB.fetch<dynamic>(err.requestOptions));
                return;
              }
              handler.next(err);
            },
          ),
        )
        ..add(
          FlutterInspectorDioInterceptor(inspector, sourceDio: dioOtherRetry),
        );
      await dioOtherRetry.get<String>('http://127.0.0.1:$closed/text');
      expect(liveDioMarkers, isEmpty, reason: 'after pre-connect -> Dio B');
    });

    test(
      'keeps a newer token on live headers when an older request finalizes',
      () async {
        final live = <String, dynamic>{};
        final token1 = registerDioMarker(live);
        final token2 = registerDioMarker(live);
        live[kDioMarkerHeader] = token2;
        expect(token1, isNot(token2));

        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final req = await client.getUrl(server.url('/text'));
        req.headers.set(kDioMarkerHeader, token1);
        await (await req.close()).drain<void>();

        expect(live[kDioMarkerHeader], token2);
        expect(liveDioMarkers.containsKey(token1), isFalse);
        expect(liveDioMarkers[token2]?.target, same(live));
      },
    );

    test('logs a warning when a cloned Dio with non-IO adapter retains the '
        'marker (R14a)', () async {
      final dio = Dio();
      dio.interceptors.add(
        FlutterInspectorDioInterceptor(inspector, sourceDio: dio),
      );
      final cloned = dio.clone(httpClientAdapter: _OkAdapter());

      final response = await cloned.get<String>('http://example.com/a');

      expect(response.statusCode, 200);
      expect(liveDioMarkers, isEmpty);
      expect(
        inspector.logEntries.where(
          (e) =>
              e.level == LogLevel.warning &&
              e.message.contains('may have reached the server'),
        ),
        hasLength(1),
      );
    });
  });

  group('end-to-end with FlutterInspector(captureHttpClient: true) (T13)', () {
    late _TestServer server;
    late FlutterInspector liveInspector;

    setUp(() async {
      server = await _TestServer.start();
      liveInspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        captureHttpClient: true,
      );
    });
    tearDown(() async => server.close());

    test('Dio GET and JSON POST are recorded once as dio with no leaked marker '
        '(2-1, 2-2)', () async {
      final dio = Dio();
      dio.interceptors.add(
        FlutterInspectorDioInterceptor(liveInspector, sourceDio: dio),
      );

      final getRes = await dio.get<String>(server.url('/text').toString());
      final postRes = await dio.post<String>(
        server.url('/echo').toString(),
        data: {'hello': 'world'},
      );

      expect(getRes.data, 'hello');
      expect(postRes.data, '{"hello":"world"}');
      expect(liveInspector.networkEntries, hasLength(2));
      for (final entry in liveInspector.networkEntries) {
        expect(entry.origin, NetworkOrigin.dio);
        expect(entry.isComplete, isTrue);
      }
      expect(server.received, hasLength(2));
      for (final headers in server.received) {
        expect(headers[kDioMarkerHeader], isNull);
      }
      expect(liveDioMarkers, isEmpty);
    });

    test('Dio without the interceptor is captured once as httpClient '
        '(2-6)', () async {
      final dio = Dio();

      final response = await dio.get<String>(server.url('/text').toString());

      expect(response.data, 'hello');
      final entry = liveInspector.networkEntries.single;
      expect(entry.origin, NetworkOrigin.httpClient);
      expect(entry.method, 'GET');
      expect(entry.statusCode, 200);
      expect(entry.responseBody, 'hello');
      expect(entry.isComplete, isTrue);
    });

    test('tagged Dio failing before connecting records both dio and httpClient '
        '— accepted per spec §8 C2', () async {
      final port = await _closedPort();
      final dio = Dio();
      dio.interceptors.add(
        FlutterInspectorDioInterceptor(liveInspector, sourceDio: dio),
      );

      await expectLater(
        dio.get<String>('http://127.0.0.1:$port/text'),
        throwsA(isA<DioException>()),
      );

      expect(liveInspector.networkEntries, hasLength(2));
      final byOrigin = {
        for (final entry in liveInspector.networkEntries) entry.origin: entry,
      };
      final dioEntry = byOrigin[NetworkOrigin.dio];
      final clientEntry = byOrigin[NetworkOrigin.httpClient];
      expect(dioEntry, isNotNull);
      expect(dioEntry?.errorType, DioExceptionType.connectionError);
      expect(dioEntry?.isComplete, isTrue);
      expect(clientEntry, isNotNull);
      expect(clientEntry?.error, isNotNull);
      expect(clientEntry?.isComplete, isTrue);
      expect(liveDioMarkers, isEmpty);
    });

    test('pending and completed entries keep the route active at request start '
        '(8-4)', () async {
      Route<void> routeFor(String name) => PageRouteBuilder<void>(
        settings: RouteSettings(name: name),
        pageBuilder: (_, _, _) => const SizedBox(),
      );
      final routeA = routeFor('/a');
      final routeB = routeFor('/b');
      liveInspector.navigatorObserver.didPush(routeA, null);

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final req = await client.getUrl(server.url('/slow'));
      final closing = req.close();

      final pending = liveInspector.networkEntries.single;
      expect(pending.isComplete, isFalse);
      expect(pending.activeRoute, '/a');

      liveInspector.navigatorObserver.didPush(routeB, routeA);
      server.release();
      final response = await closing;
      await response.drain<void>();

      final completed = liveInspector.networkEntries.single;
      expect(completed.isComplete, isTrue);
      expect(completed.activeRoute, '/a');
    });

    test(
      'PNG response exports carry only the summary, never raw bytes (6-9)',
      () async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final req = await client.getUrl(server.url('/png'));
        final response = await req.close();
        await response.drain<void>();

        final entry = liveInspector.networkEntries.single;
        expect(entry.responseImageBytes, _Data.png1x1);

        final curl = buildCurl(entry);
        expect(curl, isNot(contains('iVBOR')));
        expect(curl, isNot(contains('[137, 80')));

        final responseExports = {
          'plainText': buildPlainText(entry),
          'agentPrompt': buildAgentPrompt(entry, timeline: [entry]),
          'diagnosticReport': buildDiagnosticReport(
            logInspector: liveInspector.logInspector,
            networkEntries: liveInspector.networkEntries,
            navigatorEntries: liveInspector.navigatorEntries,
            databaseEntries: liveInspector.databaseEntries,
            now: DateTime.now(),
          ),
        };
        responseExports.forEach((name, output) {
          expect(output, contains('[image/png,'), reason: name);
          expect(output, isNot(contains('iVBOR')), reason: name);
          expect(output, isNot(contains('[137, 80')), reason: name);
        });
      },
    );
  });
}
