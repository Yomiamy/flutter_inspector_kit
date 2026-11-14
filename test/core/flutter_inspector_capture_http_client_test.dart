import 'dart:io' show HttpOverrides;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture.dart';
import 'package:flutter_test/flutter_test.dart';

FlutterInspector _inspector({required bool captureHttpClient}) =>
    FlutterInspector(
      navigatorKey: GlobalKey<NavigatorState>(),
      captureHttpClient: captureHttpClient,
    );

void main() {
  // `test()` only: `testWidgets` would make the binding install flutter_test's
  // own HttpOverrides on top of these (plan section 1, point 9).
  HttpOverrides? saved;
  setUp(() => saved = HttpOverrides.current);
  tearDown(() {
    HttpOverrides.global = saved;
    resetHttpClientCaptureForTesting();
  });

  group('FlutterInspector.captureHttpClient', () {
    test('leaves HttpOverrides untouched by default and when false (4-1)', () {
      final before = HttpOverrides.current;

      FlutterInspector(navigatorKey: GlobalKey<NavigatorState>());
      expect(identical(HttpOverrides.current, before), isTrue);

      _inspector(captureHttpClient: false);
      expect(identical(HttpOverrides.current, before), isTrue);
      expect(shouldTagDioRequest(Dio()), isFalse);
    });

    test('true chains a layer onto the global slot', () {
      final before = HttpOverrides.current;

      _inspector(captureHttpClient: true);

      expect(HttpOverrides.current, isNotNull);
      expect(identical(HttpOverrides.current, before), isFalse);
      expect(shouldTagDioRequest(Dio()), isTrue);
    });

    test('detach() does not touch HttpOverrides (4-2)', () {
      final inspector = _inspector(captureHttpClient: true);
      final installed = HttpOverrides.current;

      inspector.detach();

      expect(identical(HttpOverrides.current, installed), isTrue);
    });

    test('only the first enabled inspector installs the layer (Q6)', () {
      _inspector(captureHttpClient: true);
      final layer = HttpOverrides.current;

      _inspector(captureHttpClient: true);

      expect(identical(HttpOverrides.current, layer), isTrue);
    });
  });
}
