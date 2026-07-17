import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/diagnostic_info.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/export_report_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel share_plus 13.x talks to, read straight out of
/// `share_plus_platform_interface/lib/method_channel/method_channel_share.dart`
/// (where it is annotated `@visibleForTesting`).
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  late List<String> shared;

  setUp(() => shared = []);

  /// Captures whatever text share_plus is asked to share.
  void mockShareSheet(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      (call) async {
        if (call.method == 'share') {
          shared.add((call.arguments as Map)['text'] as String);
        }
        return 'dev.fluttercommunity.plus/share/success';
      },
    );
  }

  Future<void> pumpSheet(WidgetTester tester, FlutterInspector inspector) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ExportReportSheet.show(context, inspector),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('ExportReportSheet (AC-19, AC-20)', () {
    testWidgets('offers all three filter dimensions', (tester) async {
      await pumpSheet(tester, FlutterInspector());

      // Sources.
      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Navigation'), findsOneWidget);
      expect(find.text('Database'), findsOneWidget);

      // Time range.
      expect(find.text('Last 5m'), findsOneWidget);
      expect(find.text('Last 1h'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);

      // errors-only.
      expect(find.text('Errors & warnings only'), findsOneWidget);
    });

    testWidgets('errors-only is off by default', (tester) async {
      await pumpSheet(tester, FlutterInspector());

      final checkbox = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('Errors & warnings only'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.value, isFalse);
    });

    testWidgets('sharing hands the report to the platform share sheet once',
        (tester) async {
      mockShareSheet(tester);
      final inspector = FlutterInspector()..log('hello from the log');

      await pumpSheet(tester, inspector);
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared, hasLength(1));
      expect(shared.single, contains('# Diagnostic Report'));
      expect(shared.single, contains('hello from the log'));
      // Sheet closed after sharing.
      expect(find.text('Share report'), findsNothing);
    });

    testWidgets('unchecking a source drops it from the shared report',
        (tester) async {
      mockShareSheet(tester);
      final inspector = FlutterInspector()..log('log line');

      await pumpSheet(tester, inspector);
      await tester.tap(find.text('Network'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared.single, isNot(contains('## Network')));
      expect(shared.single, contains('## Timeline'));
    });

    testWidgets('errors-only strips info logs from the shared report',
        (tester) async {
      mockShareSheet(tester);
      final inspector = FlutterInspector()
        ..log('just-fyi')
        ..log('boom', level: LogLevel.error);

      await pumpSheet(tester, inspector);
      await tester.tap(find.text('Errors & warnings only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared.single, contains('boom'));
      expect(shared.single, isNot(contains('just-fyi')));
    });

    testWidgets('defaults to the last-5m window', (tester) async {
      mockShareSheet(tester);
      await pumpSheet(tester, FlutterInspector());
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared.single, contains('| Time range | last 5m |'));
    });

    testWidgets('picking a different time range changes the report window',
        (tester) async {
      mockShareSheet(tester);
      // An old log falls outside the default 5m window but inside "All".
      final inspector = FlutterInspector();
      inspector.registry.log.add(
        LogEntry(
          message: 'ancient-history',
          timestamp: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      );

      await pumpSheet(tester, inspector);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared.single, contains('| Time range | all |'));
      expect(shared.single, contains('ancient-history'));
    });

    testWidgets('the report inherits the host redaction setting', (tester) async {
      mockShareSheet(tester);
      await pumpSheet(tester, FlutterInspector(redactSensitiveData: false));
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared.single, contains('| Redaction | disabled |'));
    });

    testWidgets('an injected DiagnosticInfoSource populates the header',
        (tester) async {
      mockShareSheet(tester);
      await pumpSheet(
        tester,
        FlutterInspector(diagnosticInfoSource: _FakeSource()),
      );
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared.single, contains('| Device | Pixel 8 |'));
    });

    testWidgets(
      'when the share sheet is unavailable, the report falls back to the '
      'clipboard instead of being lost',
      (tester) async {
        // Real trigger: web without navigator.share, or desktop.
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _shareChannel,
          (call) async => throw PlatformException(code: 'unavailable'),
        );
        String? clipboard;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );

        await pumpSheet(tester, FlutterInspector()..log('needle'));
        await tester.tap(find.text('Share report'));
        await tester.pumpAndSettle();

        expect(clipboard, isNotNull);
        expect(clipboard, contains('# Diagnostic Report'));
        expect(clipboard, contains('needle'));
        expect(find.text('Share unavailable — copied to clipboard'),
            findsOneWidget);
      },
    );

    testWidgets('a throwing DiagnosticInfoSource degrades to N/A, not a lost report',
        (tester) async {
      mockShareSheet(tester);

      await pumpSheet(tester, FlutterInspector(diagnosticInfoSource: _BrokenSource()));
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      expect(shared, hasLength(1));
      expect(shared.single, contains('| Device | N/A |'));
    });

    testWidgets('a failed share does not brick the button', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _shareChannel,
        (call) async => throw PlatformException(code: 'unavailable'),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          // Fail ONLY the clipboard — this channel also carries framework
          // calls (SystemChrome), and blanket-throwing breaks the test harness
          // itself rather than the code under test.
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'nope');
          }
          return null;
        },
      );

      await pumpSheet(tester, FlutterInspector());
      await tester.tap(find.text('Share report'));
      await tester.pumpAndSettle();

      // Both ways out failed, so the sheet stays open — but the user must be
      // able to retry: _busy has to have been reset.
      expect(find.text('Export failed — please try again'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull, reason: 'button bricked by _busy');
    });

    testWidgets('sharing is disabled when no source is selected', (tester) async {
      await pumpSheet(tester, FlutterInspector());

      for (final source in ['Logs', 'Network', 'Navigation', 'Database']) {
        await tester.tap(find.text(source));
        await tester.pumpAndSettle();
      }

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('DashboardModal export action (AC-19)', () {
    testWidgets('the AppBar exposes an export action that opens the sheet',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DashboardModal(inspector: FlutterInspector())),
      );

      expect(find.byIcon(Icons.ios_share), findsOneWidget);

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(find.text('Export diagnostic report'), findsOneWidget);
      expect(find.text('Share report'), findsOneWidget);
    });
  });
}

class _FakeSource implements DiagnosticInfoSource {
  @override
  Future<DiagnosticInfo> collect() async =>
      const DiagnosticInfo(deviceModel: 'Pixel 8');
}

/// A host source that throws — third-party code, so this is not hypothetical.
class _BrokenSource implements DiagnosticInfoSource {
  @override
  Future<DiagnosticInfo> collect() async => throw StateError('host blew up');
}
