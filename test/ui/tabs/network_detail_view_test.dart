import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/dio_interceptor.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_origin.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network/network_detail_view.dart';
import 'package:flutter_inspector_kit/src/ui/theme/theme.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/json_tree_viewer.dart';
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
      expect(
        ThemeColor.statusColor(200, hasError: false),
        ThemeColor.color4CAF50,
      );
      expect(
        ThemeColor.statusColor(301, hasError: false),
        ThemeColor.color2196F3,
      );
      expect(
        ThemeColor.statusColor(404, hasError: false),
        ThemeColor.colorFF9800,
      );
      expect(
        ThemeColor.statusColor(500, hasError: false),
        ThemeColor.colorF44336,
      );
      expect(
        ThemeColor.statusColor(null, hasError: true),
        ThemeColor.colorF44336,
      );
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
      // Held in a local so the WeakReference inside NetworkEntry stays alive:
      // once collected, the button disables for the wrong reason and this
      // stops testing isComplete at all. A bare local is enough because
      // `flutter test` runs the JIT VM, which keeps it live for the frame;
      // AOT's last-use liveness would not, but widget tests never run AOT.
      final dio = Dio();
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/ping',
        requestHeaders: {},
        isComplete: false,
        sourceDio: dio,
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
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
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
      expect(find.text('Resent → 200'), findsOneWidget);
    });

    // Test 4: badResponse (500) resend → error entry recorded + "Resent → 500" snackbar
    testWidgets(
      'resend badResponse (500) records error entry and shows status code',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
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

        // badResponse is treated as successful transmission with status code.
        expect(find.text('Resent → 500'), findsOneWidget);
      },
    );

    // Test 4b: connection failure resend → "Resend failed: connectionError" snackbar
    testWidgets(
      'resend connection failure shows resend failed with error type',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
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

        expect(find.text('Resend failed: connectionError'), findsOneWidget);
      },
    );

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
          of: find.byTooltip(
            'Cannot resend: request body truncated or summarized',
          ),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    // Test 5: double-tap guard during in-flight request
    testWidgets('disabled while request is in-flight', (tester) async {
      final completer = Completer<ResponseBody>();
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
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

  group('NetworkDetailView — JSON body rendering', () {
    NetworkEntry entryWith(String body, {required bool asJson}) => NetworkEntry(
      method: 'POST',
      url: 'https://api.test/users',
      statusCode: 200,
      requestHeaders: {
        'Content-Type': asJson ? 'application/json' : 'text/plain',
      },
      requestBody: body,
      isComplete: true,
      timestamp: t,
    );

    testWidgets('valid JSON body renders a JsonTreeViewer', (tester) async {
      await pumpView(tester, entryWith('{"a":1}', asJson: true));

      expect(find.byType(JsonTreeViewer), findsOneWidget);
    });

    testWidgets('truncated JSON body falls back to plain text', (tester) async {
      await pumpView(tester, entryWith('{"a":', asJson: true));

      expect(tester.takeException(), isNull);
      expect(find.byType(JsonTreeViewer), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is SelectableText && w.data == '{"a":'),
        findsOneWidget,
      );
    });

    testWidgets('non-JSON body stays on the plain-text path', (tester) async {
      await pumpView(tester, entryWith('plain body', asJson: false));

      expect(find.byType(JsonTreeViewer), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'plain body',
        ),
        findsOneWidget,
      );
    });
  });

  group('NetworkDetailView — redaction precedence', () {
    test('an inspector overrides the bool in both directions', () {
      final entry = NetworkEntry(method: 'GET', url: 'https://example.com');

      // A host that opted into redaction is not unmasked by a stale `false`.
      final redactingHost = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      expect(
        NetworkDetailView(
          entry: entry,
          redactSensitiveData: false,
          inspector: redactingHost,
        ).redactSensitiveData,
        isTrue,
      );

      // And a host that opted out is honoured over the secure default.
      final openHost = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        redactSensitiveData: false,
      );
      expect(
        NetworkDetailView(
          entry: entry,
          inspector: openHost,
        ).redactSensitiveData,
        isFalse,
      );

      // With no inspector the parameter still decides, defaulting to secure.
      expect(NetworkDetailView(entry: entry).redactSensitiveData, isTrue);
    });
  });

  group('NetworkDetailView — Response Preview (T14)', () {
    final t = DateTime(2026, 4, 15, 10, 0);

    tearDown(() {
      imageCache.clear();
      imageCache.clearLiveImages();
    });

    testWidgets('6-3 renders ResizeImage preview when responseImageBytes set', (
      tester,
    ) async {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/avatar.png',
        statusCode: 200,
        responseHeaders: {'content-type': 'image/png'},
        responseBody: '[image/png, 70 bytes]',
        responseImageBytes: _Data.png1x1,
        isComplete: true,
        timestamp: t,
      );

      await pumpView(tester, entry);

      expect(find.text('Response Preview'), findsOneWidget);
      expect(find.text('Response Body'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<ResizeImage>()
            .having((r) => r.width, 'width', 1024)
            // A tall image must be bounded too: width alone leaves 1024x30000
            // decoding at ~117 MiB.
            .having((r) => r.height, 'height', 1024)
            .having((r) => r.policy, 'policy', ResizeImagePolicy.fit),
      );
    });

    testWidgets('6-3 decodes a tall image within the 1024 box', (tester) async {
      // 64 x 3000: width alone would not shrink it, the height bound does.
      final decoded = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 64, 3000),
          ui.Paint()..color = const ui.Color(0xFF336699),
        );
        final source = await recorder.endRecording().toImage(64, 3000);
        final png = (await source.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://api.test/tall.png',
          statusCode: 200,
          responseImageBytes: png,
          isComplete: true,
          timestamp: t,
        );
        await pumpView(tester, entry);
        final provider = tester.widget<Image>(find.byType(Image)).image;
        final done = Completer<ui.Image>();
        provider
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener((info, _) => done.complete(info.image)),
            );
        return done.future;
      });

      expect(decoded!.height, lessThanOrEqualTo(1024));
      expect(decoded.width, lessThan(64)); // aspect ratio kept
    });

    testWidgets(
      '6-3 shows fallback text without uncaught error on invalid image bytes',
      (tester) async {
        final corruptPng = Uint8List.fromList([
          ..._Data.png1x1.sublist(0, 8),
          1,
          2,
          3,
          4,
        ]);
        final entry = NetworkEntry(
          method: 'GET',
          url: 'https://api.test/broken.png',
          statusCode: 200,
          responseHeaders: {'content-type': 'image/png'},
          responseBody: '[image/png, 12 bytes]',
          responseImageBytes: corruptPng,
          isComplete: true,
          timestamp: t,
        );

        await pumpView(tester, entry);

        const errorText = 'Preview unavailable: the image could not be decoded';
        for (
          var i = 0;
          i < 40 && find.text(errorText).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }

        expect(tester.takeException(), isNull);
        expect(find.text(errorText), findsOneWidget);
      },
    );

    testWidgets('omits Response Preview when responseImageBytes is null', (
      tester,
    ) async {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/data.json',
        statusCode: 200,
        responseHeaders: {'content-type': 'application/json'},
        responseBody: '{"ok":true}',
        isComplete: true,
        timestamp: t,
      );

      await pumpView(tester, entry);

      expect(find.text('Response Preview'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Response Body'), findsOneWidget);
    });

    testWidgets('6-10 evicts image cache entry when detail view disposes', (
      tester,
    ) async {
      final entry = NetworkEntry(
        method: 'GET',
        url: 'https://api.test/avatar.png',
        statusCode: 200,
        responseHeaders: {'content-type': 'image/png'},
        responseBody: '[image/png, 70 bytes]',
        responseImageBytes: _Data.png1x1,
        isComplete: true,
        timestamp: t,
      );

      await pumpView(tester, entry);

      final image = tester.widget<Image>(find.byType(Image));
      final key = await tester.runAsync(
        () => image.image.obtainKey(ImageConfiguration.empty),
      );
      if (key == null) {
        fail('Expected non-null ResizeImage cache key');
      }

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(imageCache.statusForKey(key).untracked, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(imageCache.statusForKey(key).untracked, isTrue);
    });

    testWidgets(
      '8-3 disables Resend with expected tooltip for httpClient entry without sourceDio',
      (tester) async {
        final entry = NetworkEntry(
          method: 'POST',
          url: 'https://api.test/client-post',
          statusCode: 200,
          origin: NetworkOrigin.httpClient,
          requestBody: '{"a":1}',
          isComplete: true,
          timestamp: t,
        );

        await pumpView(tester, entry);

        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Cannot resend: source Dio not available'),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNull);
      },
    );
  });
}

class _Data {
  // Valid 1x1 PNG (70 bytes; IHDR/IDAT/IEND CRCs verified).
  static final png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );
}
