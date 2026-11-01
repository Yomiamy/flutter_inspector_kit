import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/gap_ruler_painter.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_inspect_overlay.dart';

void main() {
  group('Gap ruler overlay integration', () {
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
      'locking reference A and tapping target B activates ruler, allows parent navigation on B, '
      'copies measurement to clipboard, and exits cleanly',
      (tester) async {
        final keyA = GlobalKey();
        final keyB = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, top: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 40,
                        child: ColoredBox(
                          key: keyA,
                          color: const Color(0xFF2196F3),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 100,
                        height: 40,
                        child: ColoredBox(
                          key: keyB,
                          color: const Color(0xFFFF9800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final overlay = Overlay.of(
          tester.element(find.byType(Scaffold)),
          rootOverlay: true,
        );
        LayoutInspectOverlay.show(overlay);
        await tester.pump();

        // 1. Initially empty prompt
        expect(find.text('Tap a widget to inspect'), findsOneWidget);

        // 2. Tap Widget A
        final centerA = tester.getCenter(find.byKey(keyA));
        await tester.tapAt(centerA);
        await tester.pump();

        expect(find.textContaining('ColoredBox'), findsOneWidget);
        final rulerBtn = find.byTooltip('Measure distance');
        expect(rulerBtn, findsOneWidget);

        // 3. Tap "Measure distance" to lock A
        await tester.tap(rulerBtn);
        await tester.pump();

        // Prompt guides user to tap second widget
        expect(find.text('Tap another widget to measure gap'), findsOneWidget);
        expect(find.byTooltip('Exit ruler'), findsOneWidget);

        // 4. Tap Widget B
        final centerB = tester.getCenter(find.byKey(keyB));
        await tester.tapAt(centerB);
        await tester.pump();

        // Target B is selected, ruler summary is displayed
        expect(
          find.textContaining('Measuring against: ColoredBox'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Gap: 20dp (60px) (vertical)'),
          findsOneWidget,
        );

        // GapRulerPainter is in tree
        final customPaint = tester.widget<CustomPaint>(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is GapRulerPainter,
          ),
        );
        expect(customPaint.painter, isA<GapRulerPainter>());

        // 5. Navigate Target B up parent chain (to SizedBox)
        final parentBtn = find.byTooltip('Parent');
        expect(parentBtn, findsOneWidget);
        await tester.tap(parentBtn);
        await tester.pump();

        expect(
          find.textContaining('SizedBox (RenderConstrainedBox)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Gap: 20dp (60px) (vertical)'),
          findsOneWidget,
        );

        // Navigate back down to child (Comment 11)
        final childBtn = find.byTooltip('Child');
        expect(childBtn, findsOneWidget);
        await tester.tap(childBtn);
        await tester.pump();
        expect(
          find.textContaining('ColoredBox (_RenderColoredBox)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Gap: 20dp (60px) (vertical)'),
          findsOneWidget,
        );

        // Return to SizedBox for next assertions
        await tester.tap(parentBtn);
        await tester.pump();
        expect(
          find.textContaining('SizedBox (RenderConstrainedBox)'),
          findsOneWidget,
        );

        // 6. Copy layout chain and measurement
        await tester.tap(find.byTooltip('Copy layout chain'));
        await tester.pump();

        expect(clipboardText, isNotNull);
        expect(clipboardText, contains('=== Measurement (Gap Ruler) ==='));
        expect(clipboardText, contains('Reference A: ColoredBox'));
        expect(clipboardText, contains('Target B: SizedBox'));
        expect(
          clipboardText,
          contains('Vertical Gap: 20.0 dp (60.0 px @3.0x)'),
        );

        // 7. Exit ruler mode
        await tester.tap(find.byTooltip('Exit ruler'));
        await tester.pump();

        // Measuring banner and ruler painter are removed, B stays selected
        expect(find.textContaining('Measuring against:'), findsNothing);
        expect(find.byTooltip('Measure distance'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is GapRulerPainter,
          ),
          findsNothing,
        );
        expect(find.textContaining('SizedBox'), findsOneWidget);

        // 8. Close layout inspector
        await tester.tap(find.byTooltip('Close layout inspector'));
        await tester.pump();

        expect(find.byTooltip('Close layout inspector'), findsNothing);
      },
    );

    testWidgets('contained widgets display insets in info card', (
      tester,
    ) async {
      final outerKey = GlobalKey();
      final innerKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Container(
                key: outerKey,
                width: 200,
                height: 200,
                color: Colors.blue,
                alignment: Alignment.center,
                child: SizedBox(
                  key: innerKey,
                  width: 80,
                  height: 60,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );

      final overlay = Overlay.of(
        tester.element(find.byType(Scaffold)),
        rootOverlay: true,
      );
      LayoutInspectOverlay.show(overlay);
      await tester.pump();

      // Tap outer container at top-left corner (avoiding inner widget at center)
      final outerCorner =
          tester.getTopLeft(find.byKey(outerKey)) + const Offset(10, 10);
      await tester.tapAt(outerCorner);
      await tester.pump();

      // Lock outer container as reference A
      await tester.tap(find.byTooltip('Measure distance'));
      await tester.pump();

      // Tap inner widget as target B
      await tester.tapAt(tester.getCenter(find.byKey(innerKey)));
      await tester.pump();

      // Should show insets: T:70dp (210px) B:70dp (210px) L:60dp (180px) R:60dp (180px)
      expect(find.textContaining('Insets:'), findsOneWidget);
      expect(find.textContaining('T:70dp (210px)'), findsOneWidget);
      expect(find.textContaining('B:70dp (210px)'), findsOneWidget);
      expect(find.textContaining('L:60dp (180px)'), findsOneWidget);
      expect(find.textContaining('R:60dp (180px)'), findsOneWidget);
    });

    testWidgets('tapping reference widget A again does not self-measure', (
      tester,
    ) async {
      final btnAKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: btnAKey,
                width: 100,
                height: 100,
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      );

      final overlay = Overlay.of(
        tester.element(find.byType(Scaffold)),
        rootOverlay: true,
      );
      LayoutInspectOverlay.show(overlay);
      await tester.pump();

      // Tap widget A and lock it
      final centerA = tester.getCenter(find.byKey(btnAKey));
      await tester.tapAt(centerA);
      await tester.pump();
      await tester.tap(find.byTooltip('Measure distance'));
      await tester.pump();

      expect(find.text('Tap another widget to measure gap'), findsOneWidget);

      // Tap widget A again
      await tester.tapAt(centerA);
      await tester.pump();

      // Should still prompt to tap another widget, NOT build a self-measuring ruler
      expect(find.text('Tap another widget to measure gap'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is GapRulerPainter,
        ),
        findsNothing,
      );
    });
  });
}
