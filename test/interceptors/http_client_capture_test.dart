import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture.dart';
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

class _FakeRequest extends Fake implements HttpClientRequest {}

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
}
