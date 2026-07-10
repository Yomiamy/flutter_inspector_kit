import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/dio_interceptor.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network/network_detail_view.dart';
import 'package:flutter_inspector_kit/src/ui/theme/theme.dart';
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
  ) => responder(options);

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

    await tester.pumpWidget(MaterialApp(home: NetworkDetailView(entry: entry)));
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

    testWidgets(
      'opt-out: redactSensitiveData false leaves Authorization unmasked in cURL',
      (tester) async {
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

        final entry = NetworkEntry(
          method: 'POST',
          url: 'https://api.test/users?page=2',
          statusCode: 201,
          duration: const Duration(milliseconds: 120),
          requestHeaders: {
            'Authorization': 'Bearer secret-token-123',
            'Content-Type': 'application/json',
          },
          requestBody: '{"name":"x"}',
          responseHeaders: {'content-type': 'application/json'},
          responseBody: '{"id":1}',
          isComplete: true,
          timestamp: t,
        );

        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: NetworkDetailView(entry: entry, redactSensitiveData: false),
          ),
        );

        await tester.tap(find.byIcon(Icons.share));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy as cURL'));
        await tester.pumpAndSettle();

        expect(clipboardText, isNotNull);
        expect(clipboardText, contains('secret-token-123'));
        expect(clipboardText, isNot(contains('••••')));
      },
    );

    testWidgets(
      'default: redactSensitiveData omitted masks Authorization in cURL',
      (tester) async {
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

        final entry = NetworkEntry(
          method: 'POST',
          url: 'https://api.test/users?page=2',
          statusCode: 201,
          duration: const Duration(milliseconds: 120),
          requestHeaders: {
            'Authorization': 'Bearer secret-token-123',
            'Content-Type': 'application/json',
          },
          requestBody: '{"name":"x"}',
          responseHeaders: {'content-type': 'application/json'},
          responseBody: '{"id":1}',
          isComplete: true,
          timestamp: t,
        );

        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(home: NetworkDetailView(entry: entry)),
        );

        await tester.tap(find.byIcon(Icons.share));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy as cURL'));
        await tester.pumpAndSettle();

        expect(clipboardText, isNotNull);
        expect(clipboardText, contains('••••'));
        expect(clipboardText, isNot(contains('secret-token-123')));
      },
    );

    testWidgets(
      'default: redactSensitiveData omitted masks Authorization and Cookie '
      'in text',
      (tester) async {
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

        final entry = NetworkEntry(
          method: 'POST',
          url: 'https://api.test/users?page=2',
          statusCode: 201,
          duration: const Duration(milliseconds: 120),
          requestHeaders: {
            'Authorization': 'Bearer secret-token-123',
            'Cookie': 'session=abc-secret',
            'Content-Type': 'application/json',
          },
          requestBody: '{"name":"x"}',
          responseHeaders: {'content-type': 'application/json'},
          responseBody: '{"id":1}',
          isComplete: true,
          timestamp: t,
        );

        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(home: NetworkDetailView(entry: entry)),
        );

        await tester.tap(find.byIcon(Icons.share));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy as text'));
        await tester.pumpAndSettle();

        expect(clipboardText, isNotNull);
        expect(clipboardText, contains('••••'));
        expect(clipboardText, isNot(contains('secret-token-123')));
        expect(clipboardText, isNot(contains('session=abc-secret')));
      },
    );
  });

  group('statusColorFor', () {
    test('semantics by range', () {
      expect(ThemeColor.statusColor(200, hasError: false),
          ThemeColor.color4CAF50);
      expect(ThemeColor.statusColor(301, hasError: false),
          ThemeColor.color2196F3);
      expect(ThemeColor.statusColor(404, hasError: false),
          ThemeColor.colorFF9800);
      expect(ThemeColor.statusColor(500, hasError: false),
          ThemeColor.colorF44336);
      expect(ThemeColor.statusColor(null, hasError: true),
          ThemeColor.colorF44336);
    });
  });

  // -------------------------------------------------------------------------
  // Resend button tests
  // -------------------------------------------------------------------------

  group('Resend action', () {
    // Test 1: no sourceDio → disabled
    testWidgets('disabled when sourceDio is null', (tester) async {
      await pumpView(tester, sample()); // sample() has no sourceDio
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Cannot resend: source Dio not available'),
          matching: find.byType(IconButton),
        ),
      );
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
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Resend'),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    // Test 3: successful resend → entry recorded + snackbar
    testWidgets('resend success records replay entry and shows snackbar', (
      tester,
    ) async {
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
      dio.interceptors.add(
        FlutterInspectorDioInterceptor(inspector, sourceDio: dio),
      );

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
      final replays = inspector.networkEntries
          .where((e) => e.isReplay)
          .toList();
      expect(replays.length, 1);
      expect(identical(replays.first.sourceDio?.target, dio), isTrue);

      // Success snackbar shown.
      expect(find.text('Request resent'), findsOneWidget);
    });

    // Test 4: badResponse (500) resend → error entry recorded + "Request resent" snackbar
    testWidgets(
      'resend badResponse (500) records error entry and shows request resent',
      (tester) async {
        final inspector = FlutterInspector();
        final dio = Dio()
          ..httpClientAdapter = _StubAdapter(
            (_) async => ResponseBody.fromString('err', 500),
          );
        dio.interceptors.add(
          FlutterInspectorDioInterceptor(inspector, sourceDio: dio),
        );

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

        final replays = inspector.networkEntries
            .where((e) => e.isReplay)
            .toList();
        expect(replays.length, 1);
        expect(replays.first.error, isNotNull);

        // badResponse is treated as successful transmission.
        expect(find.text('Request resent'), findsOneWidget);
      },
    );

    // Test 4b: connection failure resend → "Resend failed" snackbar
    testWidgets('resend connection failure shows resend failed', (
      tester,
    ) async {
      final inspector = FlutterInspector();
      final dio = Dio()
        ..httpClientAdapter = _StubAdapter(
          (_) async => throw DioException(
            requestOptions: RequestOptions(path: 'https://api.test/users'),
            type: DioExceptionType.connectionError,
            error: 'Connection failed',
          ),
        );
      dio.interceptors.add(
        FlutterInspectorDioInterceptor(inspector, sourceDio: dio),
      );

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

      expect(find.text('Resend failed'), findsOneWidget);
    });

    // Test 4c: truncated request body → disabled
    testWidgets('disabled when request body is truncated', (tester) async {
      final dio = Dio();
      final entry = NetworkEntry(
        method: 'POST',
        url: 'https://api.test/users',
        requestBody: 'a' * 10 * 1024 + kTruncatedMarker,
        statusCode: 200,
        isComplete: true,
        sourceDio: dio,
        timestamp: t,
      );

      await pumpView(tester, entry);
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Cannot resend: request body truncated'),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    // Test 5: double-tap guard during in-flight request
    testWidgets('disabled while request is in-flight', (tester) async {
      final completer = Completer<ResponseBody>();
      final inspector = FlutterInspector();
      final dio = Dio()
        ..httpClientAdapter = _StubAdapter((_) => completer.future);
      dio.interceptors.add(
        FlutterInspectorDioInterceptor(inspector, sourceDio: dio),
      );

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
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Resend'),
          matching: find.byType(IconButton),
        ),
      );
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

  group('Exception Details section', () {
    testWidgets('transport layer failure renders kind and error type', (
      tester,
    ) async {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test',
        statusCode: null,
        errorType: DioExceptionType.connectionError,
        error: 'Connection failed',
        isComplete: true,
        timestamp: t,
      );

      await pumpView(tester, entry);

      expect(find.text('Exception Details'), findsOneWidget);
      expect(
        find.text('傳輸層失敗 (transport failure — request did not reach server)'),
        findsOneWidget,
      );
      expect(find.text('connectionError'), findsOneWidget);
      expect(find.text('Connection failed'), findsOneWidget);

      // Verify Status displays '-'
      expect(
        find.descendant(
          of: find.byType(Row),
          matching: find.byWidgetPredicate(
            (widget) => widget is SelectableText && widget.data == '-',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'server error failure renders kind and is displayed with response sections',
      (tester) async {
        final entry = NetworkEntry(
          method: 'POST',
          url: 'https://api.test',
          statusCode: 500,
          errorType: DioExceptionType.badResponse,
          error: 'Internal Server Error',
          responseHeaders: {'content-type': 'application/json'},
          responseBody: 'oops',
          isComplete: true,
          timestamp: t,
        );

        await pumpView(tester, entry);

        expect(find.text('Exception Details'), findsOneWidget);
        expect(
          find.text('Server 錯誤回應 (server responded with error)'),
          findsOneWidget,
        );
        expect(find.text('badResponse'), findsOneWidget);
        expect(find.text('Internal Server Error'), findsOneWidget);

        // Verify response headers and body are also rendered
        expect(find.text('Response Headers'), findsOneWidget);
        expect(find.text('Response Body'), findsOneWidget);
      },
    );

    testWidgets('renders selectable and copyable stack trace', (tester) async {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test',
        errorStackTrace: '#0 foo\n#1 bar',
        isComplete: true,
        timestamp: t,
      );

      await pumpView(tester, entry);

      expect(find.text('Exception Details'), findsOneWidget);
      final selectableTextFinder = find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '#0 foo\n#1 bar',
      );
      expect(selectableTextFinder, findsOneWidget);

      final selectableText = tester.widget<SelectableText>(
        selectableTextFinder,
      );
      expect(selectableText.style?.fontFamily, 'monospace');
    });

    testWidgets('does not render Exception Details for success request', (
      tester,
    ) async {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test',
        statusCode: 200,
        isComplete: true,
        timestamp: t,
      );

      await pumpView(tester, entry);

      expect(find.text('Exception Details'), findsNothing);
    });
  });
}
