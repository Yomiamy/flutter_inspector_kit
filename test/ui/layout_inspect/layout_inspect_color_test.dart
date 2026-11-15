import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_inspect_overlay.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/inspector_fab.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static const Rect rectA = Rect.fromLTWH(24, 60, 120, 40);
  static const Rect rectB = Rect.fromLTWH(300, 60, 60, 60);
  static const Color colorA = Color(0xFF336699);
  static const Color colorB = Color(0xFFAA00AA);
  static const String rowA = 'color: #336699';
  static const String rowB = 'color: #AA00AA';
}

Widget _blocks() => Stack(
  children: [
    Positioned.fromRect(
      rect: _Data.rectA,
      child: const ColoredBox(color: _Data.colorA),
    ),
    Positioned.fromRect(
      rect: _Data.rectB,
      child: const ColoredBox(color: _Data.colorB),
    ),
  ],
);

/// Pumps [body] in a Scaffold, optionally under a kit FAB, then opens the
/// inspector above it (the FAB entry goes first, as in a real host).
Future<void> _pumpInspect(
  WidgetTester tester,
  Widget body, {
  bool withFab = false,
}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  final overlay = Overlay.of(
    tester.element(find.byType(Scaffold)),
    rootOverlay: true,
  );
  if (withFab) {
    final fab = OverlayEntry(builder: (_) => InspectorFab(onTap: () {}));
    overlay.insert(fab);
    addTearDown(fab.remove);
  }
  LayoutInspectOverlay.show(overlay);
  await tester.pump();
}

/// Runs the capture frame and lets the engine finish the pixel read-back,
/// which only completes inside `runAsync` under the test's fake time. Stops
/// once a color row shows, else after 0.5s, so "no row" is asserted only
/// after a read-back has had ample time to land.
Future<void> _settleSample(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 50 && _colorRow.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Finder get _colorRow => find.textContaining('color: #');

void main() {
  group('LayoutInspectOverlay color sampling', () {
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

    testWidgets('a tap shows the pixel color, also inside the 2px frame', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());

      await tester.tapAt(_Data.rectB.center);
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
      expect(find.text('size: 60.0 × 60.0'), findsOneWidget);

      // 1px from the left edge: the blue frame is painted right there.
      await tester.tapAt(Offset(_Data.rectA.left + 1, _Data.rectA.center.dy));
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);
      expect(_colorRow, findsOneWidget);
    });

    testWidgets('the color row fits a 320dp screen', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpInspect(tester, _blocks());

      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('parent, ruler and copy keep the color of the point', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);

      await tester.tap(find.byTooltip('Parent'));
      await _settleSample(tester);
      expect(find.textContaining('2 / '), findsOneWidget);
      expect(find.text(_Data.rowA), findsOneWidget);

      await tester.tap(find.byTooltip('Measure distance'));
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);

      await tester.tap(find.byTooltip('Copy layout chain'));
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);
    });

    testWidgets('dragging hides the color; release samples the last aim '
        'point', (tester) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);

      final gesture = await tester.startGesture(_Data.rectA.center);
      await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
      await tester.pump();
      expect(_colorRow, findsNothing);

      await gesture.moveTo(_Data.rectB.center);
      await _settleSample(tester);
      expect(_colorRow, findsNothing);

      await gesture.up();
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('a drag started before the sample finishes drops it', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      // Capture frame only: the read-back for A is still pending.
      await tester.pump();

      final gesture = await tester.startGesture(_Data.rectA.center);
      await gesture.moveTo(_Data.rectB.center);
      await _settleSample(tester);
      expect(_colorRow, findsNothing);

      await gesture.up();
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('two quick taps show only the second color', (tester) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await tester.pump();
      await tester.tapAt(_Data.rectB.center);
      await tester.pump();
      expect(_colorRow, findsNothing);

      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
      expect(_colorRow, findsOneWidget);
    });

    testWidgets('ruler frames are not sampled', (tester) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await tester.pump();
      await tester.tap(find.byTooltip('Measure distance'));
      await tester.pump();

      // The orange 2px stroke of B is centered on its edge.
      await tester.tapAt(Offset(_Data.rectB.left + 0.5, _Data.rectB.center.dy));
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('the kit FAB is not sampled', (tester) async {
      await _pumpInspect(
        tester,
        const Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 200,
              child: ColoredBox(color: _Data.colorB),
            ),
          ],
        ),
        withFab: true,
      );

      await tester.tapAt(tester.getCenter(find.byType(InspectorFab)));
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('a release over the info card samples the app below it', (
      tester,
    ) async {
      await _pumpInspect(
        tester,
        const SizedBox.expand(child: ColoredBox(color: _Data.colorB)),
      );
      final gesture = await tester.startGesture(const Offset(400, 100));
      await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
      await tester.pump();

      await gesture.moveTo(
        tester.getCenter(find.byTooltip('Copy layout chain')),
      );
      await tester.pump();
      await gesture.up();
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('samples the global point when the overlay is offset', (
      tester,
    ) async {
      const targetRect = Rect.fromLTWH(100, 150, 80, 50);
      final overlayKey = GlobalKey<OverlayState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fromRect(
                  rect: targetRect,
                  child: const ColoredBox(color: Color(0xFF00AA55)),
                ),
                Positioned(
                  left: 40,
                  top: 80,
                  width: 500,
                  height: 400,
                  child: Overlay(key: overlayKey),
                ),
              ],
            ),
          ),
        ),
      );
      LayoutInspectOverlay.show(overlayKey.currentState!);
      await tester.pump();

      await tester.tapAt(targetRect.center);
      await _settleSample(tester);
      expect(find.text('color: #00AA55'), findsOneWidget);
    });

    testWidgets('copy writes one color line at the end, also with the ruler', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);
      await tester.tap(find.byTooltip('Copy layout chain'));
      await tester.pump();
      expect(clipboardText, endsWith('\n\n${_Data.rowA}'));
      expect('color: #'.allMatches(clipboardText ?? '').length, 1);

      await tester.tap(find.byTooltip('Measure distance'));
      await tester.pump();
      await tester.tapAt(_Data.rectB.center);
      await _settleSample(tester);
      await tester.tap(find.byTooltip('Copy layout chain'));
      await tester.pump();
      expect(clipboardText, contains('=== Measurement (Gap Ruler) ==='));
      expect(clipboardText, endsWith('\n\n${_Data.rowB}'));
      expect('color: #'.allMatches(clipboardText ?? '').length, 1);
    });

    testWidgets('a failed sample hides the row and leaves the rest intact', (
      tester,
    ) async {
      await _pumpInspect(
        tester,
        const Center(
          child: SizedBox(width: 80, height: 80, child: Texture(textureId: 1)),
        ),
      );

      await tester.tapAt(tester.getCenter(find.byType(Texture)));
      await _settleSample(tester);
      expect(_colorRow, findsNothing);
      expect(find.text('size: 80.0 × 80.0'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Copy layout chain'));
      await tester.pump();
      expect(clipboardText, contains('#0 Texture (TextureBox)'));
      expect(clipboardText, isNot(contains('color:')));
    });

    testWidgets('closing before the sample finishes throws nothing', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await tester.pump();

      await tester.tap(find.byTooltip('Close layout inspector'));
      await _settleSample(tester);
      expect(find.byTooltip('Close layout inspector'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
