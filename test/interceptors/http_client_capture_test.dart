import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_origin.dart';
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

class _FakeResponse extends Fake implements HttpClientResponse {
  _FakeResponse(this.statusCode);

  @override
  final int statusCode;
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
  void add(List<int> data) => calls.add(['add', data]);

  @override
  void write(Object? object) => calls.add(['write', object]);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      calls.add(['addError', error]);

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

/// Loopback server. Records the headers of every request, holds `/slow` until
/// [release], and answers everything else with `hello`.
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
    try {
      await request.drain<void>();
      if (request.uri.path == '/slow') await _gate.future;
      request.response.write('hello');
      await request.response.close();
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
  });
}
