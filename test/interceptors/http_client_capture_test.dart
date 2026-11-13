import 'dart:io' show HttpClient, HttpOverrides, SecurityContext;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for a host's own `HttpOverrides` (SSL pinning, proxy rules).
class _HostOverrides extends HttpOverrides {
  final contexts = <SecurityContext?>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    contexts.add(context);
    return super.createHttpClient(context);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      'PROXY host:9';
}

class _FakeAdapter extends Fake implements HttpClientAdapter {}

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
}
