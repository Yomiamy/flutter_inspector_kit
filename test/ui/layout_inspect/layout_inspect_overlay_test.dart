import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/dashboard_modal.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_inspect_overlay.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/inspector_fab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayoutInspectOverlay & Dashboard integration', () {
    String? clipboardText;

    setUp(() {
      clipboardText = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = call.arguments as Map<Object?, Object?>;
              clipboardText = args['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets(
      'Dashboard Inspect layout button closes dashboard, enters inspect mode, '
      'inspects target, navigates parent chain, copies to clipboard, and closes',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        final targetKey = GlobalKey();
        var appButtonTapped = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, top: 60),
                  child: GestureDetector(
                    onTap: () => appButtonTapped++,
                    child: SizedBox(
                      width: 120,
                      height: 40,
                      child: ColoredBox(
                        key: targetKey,
                        color: const Color(0xFF336699),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final homeContext = tester.element(find.byType(Scaffold));
        DashboardModal.show(homeContext, inspector);
        await tester.pumpAndSettle();

        final inspectBtn = find.byTooltip('Inspect layout');
        expect(inspectBtn, findsOneWidget);

        await tester.tap(inspectBtn);
        await tester.pumpAndSettle();

        // Dashboard closed and empty-state prompt is visible.
        expect(find.byType(DashboardModal), findsNothing);
        expect(find.text('Tap a widget to inspect'), findsOneWidget);

        // Tap the target widget.
        final targetCenter = tester.getCenter(find.byKey(targetKey));
        await tester.tapAt(targetCenter);
        await tester.pump();

        // Intercepted by overlay; underlying GestureDetector did not fire.
        expect(appButtonTapped, 0);
        expect(find.textContaining('ColoredBox'), findsOneWidget);
        expect(find.text('size: 120.0 × 40.0'), findsOneWidget);
        expect(
          find.text('constraints: 120.0 ≤ w ≤ 120.0, 40.0 ≤ h ≤ 40.0'),
          findsOneWidget,
        );
        expect(find.text('offset: (24.0, 60.0)'), findsOneWidget);
        expect(find.textContaining('1 / '), findsOneWidget);

        // At bottom of chain (#0), Child button is disabled.
        final childBtn = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.arrow_downward),
        );
        expect(childBtn.onPressed, isNull);

        // Record card alignment before stepping up parent chain.
        final cardAlignBefore = tester
            .widget<Align>(
              find
                  .ancestor(
                    of: find.byTooltip('Parent'),
                    matching: find.byType(Align),
                  )
                  .first,
            )
            .alignment;

        // Step up to parent (#1 SizedBox / RenderConstrainedBox).
        await tester.tap(find.byTooltip('Parent'));
        await tester.pump();

        expect(find.textContaining('2 / '), findsOneWidget);
        expect(
          find.textContaining('SizedBox (RenderConstrainedBox)'),
          findsOneWidget,
        );
        // Card alignment stays anchored to initial target and does not jump.
        final cardAlignAfter = tester
            .widget<Align>(
              find
                  .ancestor(
                    of: find.byTooltip('Parent'),
                    matching: find.byType(Align),
                  )
                  .first,
            )
            .alignment;
        expect(cardAlignAfter, cardAlignBefore);

        // Step all the way to the top of the chain to verify Parent disables.
        final parentBtnFinder = find.widgetWithIcon(
          IconButton,
          Icons.arrow_upward,
        );
        final childBtnFinder = find.widgetWithIcon(
          IconButton,
          Icons.arrow_downward,
        );
        while (tester.widget<IconButton>(parentBtnFinder).onPressed != null) {
          await tester.tap(parentBtnFinder);
          await tester.pump();
        }
        expect(tester.widget<IconButton>(parentBtnFinder).onPressed, isNull);
        expect(tester.widget<IconButton>(childBtnFinder).onPressed, isNotNull);

        // Copy writes formatted chain to clipboard and shows Copied feedback.
        await tester.tap(find.byTooltip('Copy layout chain'));
        await tester.pump();

        expect(clipboardText, isNotNull);
        expect(clipboardText, contains('Layout inspect — '));
        expect(clipboardText, contains('#0 ColoredBox'));
        expect(find.text('Copied'), findsOneWidget);

        // Copied indicator clears after 2 seconds.
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Copied'), findsNothing);

        // Close removes the overlay so underlying app receives taps again.
        await tester.tap(find.byTooltip('Close layout inspector'));
        await tester.pump();

        expect(find.byTooltip('Close layout inspector'), findsNothing);
        await tester.tapAt(targetCenter);
        await tester.pump();
        expect(appButtonTapped, 1);
      },
    );

    testWidgets(
      'shows obfuscation note when mayBeObfuscated is true, prevents duplicate '
      'entries, and recovers after host Overlay unmount',
      (tester) async {
        final targetKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(key: targetKey, width: 60, height: 60),
              ),
            ),
          ),
        );

        final overlay = Overlay.of(
          tester.element(find.byType(Scaffold)),
          rootOverlay: true,
        );
        LayoutInspectOverlay.show(overlay, mayBeObfuscated: true);
        // Second call while active is a no-op.
        LayoutInspectOverlay.show(overlay, mayBeObfuscated: true);
        await tester.pump();

        expect(find.text('Tap a widget to inspect'), findsOneWidget);

        await tester.tapAt(tester.getCenter(find.byKey(targetKey)));
        await tester.pump();

        expect(find.text('names may be obfuscated'), findsOneWidget);

        // Unmount the entire MaterialApp without pressing Close.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // Re-mount a fresh MaterialApp and verify show() works again.
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.expand())),
        );
        final newOverlay = Overlay.of(
          tester.element(find.byType(Scaffold)),
          rootOverlay: true,
        );
        LayoutInspectOverlay.show(newOverlay, mayBeObfuscated: false);
        await tester.pump();

        expect(find.text('Tap a widget to inspect'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping over InspectorFab hits the underlying app widget instead of the FAB',
      (tester) async {
        final underFabKey = GlobalKey();
        var fabTapCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 20,
                    top: 100,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: ColoredBox(
                        key: underFabKey,
                        color: const Color(0xFFAA00AA),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final overlay = Overlay.of(
          tester.element(find.byType(Scaffold)),
          rootOverlay: true,
        );
        final fabEntry = OverlayEntry(
          builder: (_) => InspectorFab(onTap: () => fabTapCount++),
        );
        overlay.insert(fabEntry);
        LayoutInspectOverlay.show(overlay);
        await tester.pump();

        final fabCenter = tester.getCenter(find.byType(InspectorFab));
        await tester.tapAt(fabCenter);
        await tester.pump();

        expect(fabTapCount, 0);
        expect(find.textContaining('ColoredBox'), findsOneWidget);
        expect(find.text('size: 48.0 × 48.0'), findsOneWidget);

        fabEntry.remove();
      },
    );
  });
}
