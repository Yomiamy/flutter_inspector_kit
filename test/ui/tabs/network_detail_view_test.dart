import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/dio_interceptor.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network/network_detail_view.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Stub adapter for Dio — returns whatever the [responder] callback produces.
// ---------------------------------------------------------------------------
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responder);
  final Future<ResponseBody> Function(RequestOptions) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      responder(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  final t = DateTime(2026, 6, 10, 12, 0, 0);

  NetworkEntry sample() => NetworkEntry(
    method: 'POST',
    url: 'https://api.test/users?page=2',
    statusCode: 201,
    duration: const Duration(milliseconds: 120),
    requestHeaders: {'Content-Type': 'application/json'},
    requestBody: '{"name":"x"}',
    responseHeaders: {'content-type': 'application/json'},
    responseBody: '{"id":1}',
    isComplete: true,
    timestamp: t,
  );

  /// Pump helper that enlarges the test surface to avoid overflow.
  Future<void> pumpView(WidgetTester tester, NetworkEntry entry) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: NetworkDetailView(entry: entry)),
    );
  }

  // -------------------------------------------------------------------------
  // Existing tests (must stay green)
  // -------------------------------------------------------------------------

  group('NetworkDetailView', () {
    testWidgets('renders all sections', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: NetworkDetailView(entry: sample())),
      );

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Query Parameters'), findsOneWidget);
      expect(find.text('Request Headers'), findsOneWidget);
      expect(find.text('Request Body'), findsOneWidget);
      expect(find.text('Response Headers'), findsOneWidget);
      expect(find.text('Response Body'), findsOneWidget);
    });

    testWidgets('copy as cURL writes to clipboard', (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(home: NetworkDetailView(entry: sample())),
      );

      await tester.tap(find.byIcon(Icons.share));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy as cURL'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText!.startsWith('curl -X POST'), isTrue);
    });
  });

  group('statusColorFor', () {
    test('semantics by range', () {
      expect(statusColorFor(200, false), Colors.green);
      expect(statusColorFor(301, false), Colors.blue);
      expect(statusColorFor(404, false), Colors.orange);
      expect(statusColorFor(500, false), Colors.red);
      expect(statusColorFor(null, true), Colors.red);
    });
  });

  // -------------------------------------------------------------------------
  // Resend button tests
  // -------------------------------------------------------------------------

  group('Resend action', () {
    // Test 1: no sourceDio → disabled
    testWidgets('disabled when sourceDio is null', (tester) async {
      await pumpView(tester, sample()); // sample() has no sourceDio
      final button = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Resend'),
        matching: find.byType(IconButton),
      ));
      expect(button.onPressed, isNull);
    });

    // Test 2: incomplete entry → disabled
    testWidgets('disabled when entry is not complete', (tester) async {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/ping',
        requestHeaders: {},
        isComplete: false,
        sourceDio: Dio(),
        timestamp: t,
      );
      await pumpView(tester, entry);
      final button = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Resend'),
        matching: find.byType(IconButton),
      ));
      expect(button.onPressed, isNull);
    });

    // Test 3: successful resend → entry recorded + snackbar
    testWidgets('resend success records replay entry and shows snackbar',
        (tester) async {
      final inspector = FlutterInspector();
      final dio = Dio()
        ..httpClientAdapter = _StubAdapter(
          (_) async => ResponseBody.fromString(
            '{}',
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        );
      dio.interceptors
          .add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));

      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test/users',
        requestHeaders: {'Content-Type': 'application/json'},
        requestBody: '{"name":"replay"}',
        statusCode: 200,
        isComplete: true,
        sourceDio: dio,
        timestamp: t,
      );

      await pumpView(tester, entry);
      await tester.tap(find.byTooltip('Resend'));
      await tester.pumpAndSettle();

      // Interceptor should have logged exactly one replay entry. The count
      // guards the no-duplicate-record invariant: if the UI catch ever added
      // a second logNetwork call, this would fail.
      final replays =
          inspector.networkEntries.where((e) => e.isReplay).toList();
      expect(replays.length, 1);
      expect(identical(replays.first.sourceDio, dio), isTrue);

      // Success snackbar shown.
      expect(find.text('Request resent'), findsOneWidget);
    });

    // Test 4: failed resend → error entry recorded + snackbar, no crash
    testWidgets('resend failure records error entry and shows snackbar',
        (tester) async {
      final inspector = FlutterInspector();
      final dio = Dio()
        ..httpClientAdapter = _StubAdapter(
          (_) async => ResponseBody.fromString('err', 500),
        );
      dio.interceptors
          .add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));

      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test/users',
        requestHeaders: {'Content-Type': 'application/json'},
        requestBody: '{"name":"fail"}',
        statusCode: 200,
        isComplete: true,
        sourceDio: dio,
        timestamp: t,
      );

      await pumpView(tester, entry);
      await tester.tap(find.byTooltip('Resend'));
      await tester.pumpAndSettle();

      // Interceptor's onError should have logged exactly one replay entry
      // (no duplicate from the UI catch).
      final replays =
          inspector.networkEntries.where((e) => e.isReplay).toList();
      expect(replays.length, 1);

      // A 500 fails Dio's default validateStatus, so the request goes through
      // onError and the entry carries an error message.
      expect(replays.first.error, isNotNull);

      // Failure snackbar shown.
      expect(find.text('Resend failed'), findsOneWidget);
    });

    // Test 5: double-tap guard during in-flight request
    testWidgets('disabled while request is in-flight', (tester) async {
      final completer = Completer<ResponseBody>();
      final inspector = FlutterInspector();
      final dio = Dio()
        ..httpClientAdapter = _StubAdapter((_) => completer.future);
      dio.interceptors
          .add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));

      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/slow',
        requestHeaders: {},
        isComplete: true,
        sourceDio: dio,
        timestamp: t,
      );

      await pumpView(tester, entry);

      // Tap Resend → request starts but hangs on the completer.
      await tester.tap(find.byTooltip('Resend'));
      await tester.pump(); // process the tap, don't settle

      // While in-flight the button must be disabled.
      final button = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Resend'),
        matching: find.byType(IconButton),
      ));
      expect(button.onPressed, isNull);

      // Release the future so pumpAndSettle can finish cleanly.
      completer.complete(
        ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
      await tester.pumpAndSettle();
    });
  });
}
