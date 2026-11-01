import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_inspect_overlay.dart';
import 'package:flutter_inspector_kit/src/ui/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static const Rect rectA = Rect.fromLTWH(24, 60, 120, 40);
  static const Rect rectB = Rect.fromLTWH(300, 60, 60, 60);
  static const Offset blank = Offset(600, 300);
  static const BoxDecoration frame = BoxDecoration(
    border: Border.fromBorderSide(
      BorderSide(color: ThemeColor.color2196F3, width: ThemeSize.space2),
    ),
  );
}

Future<void> _pumpInspect(WidgetTester tester, {bool? showLoupe}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fromRect(
              rect: _Data.rectA,
              child: const ColoredBox(color: Color(0xFF336699)),
            ),
            Positioned.fromRect(
              rect: _Data.rectB,
              child: const ColoredBox(color: Color(0xFFAA00AA)),
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
  LayoutInspectOverlay.show(overlay, showLoupe: showLoupe);
  await tester.pump();
}

Finder get _loupe => find.byType(RawMagnifier);

Rect _frameRect(WidgetTester tester) => tester.getRect(
  find.byWidgetPredicate(
    (w) => w is DecoratedBox && w.decoration == _Data.frame,
  ),
);

List<String?> _cardTexts(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();

void main() {
  group('LayoutInspectOverlay drag-to-aim', () {
    testWidgets('frame and card follow the RenderBox under the finger', (
      tester,
    ) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(_Data.rectA.center);
      await tester.pump();
      expect(_frameRect(tester), _Data.rectA);
      expect(find.text('size: 120.0 × 40.0'), findsOneWidget);

      await gesture.moveTo(_Data.rectB.center);
      await tester.pump();
      expect(_frameRect(tester), _Data.rectB);
      expect(find.text('size: 60.0 × 60.0'), findsOneWidget);
      expect(find.textContaining('1 / '), findsOneWidget);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('release settles exactly like a tap at the last aim point', (
      tester,
    ) async {
      await _pumpInspect(tester);
      final target = _Data.rectB.center;

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(target);
      await tester.pump();
      // A second finger steps up the chain mid-drag, so the release has
      // something to overwrite.
      await tester.tap(find.byTooltip('Parent'));
      await tester.pump();
      expect(find.textContaining('2 / '), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(find.textContaining('1 / '), findsOneWidget);
      expect(_loupe, findsNothing);
      final dragTexts = _cardTexts(tester);
      final dragFrame = _frameRect(tester);

      // Same pre-release state, then a plain tap at the same point.
      await tester.tap(find.byTooltip('Parent'));
      await tester.pump();
      expect(find.textContaining('2 / '), findsOneWidget);
      await tester.tapAt(target);
      await tester.pump();

      expect(_cardTexts(tester), dragTexts);
      expect(_frameRect(tester), dragFrame);
      expect(dragFrame, _Data.rectB);
    });

    testWidgets('a cancelled drag settles at the last aim point: the SDK '
        'sends onPanEnd, not onPanCancel', (tester) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(_Data.rectB.center);
      await tester.pump();
      await tester.tap(find.byTooltip('Parent'));
      await tester.pump();
      expect(find.textContaining('2 / '), findsOneWidget);

      await gesture.cancel();
      await tester.pump();

      expect(_loupe, findsNothing);
      expect(find.textContaining('1 / '), findsOneWidget);
      expect(_frameRect(tester), _Data.rectB);
    });

    testWidgets('drag starting on the info card does not enter aim mode', (
      tester,
    ) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Tap a widget to inspect')),
      );
      await gesture.moveBy(const Offset(0, -(kTouchSlop * 3)));
      await tester.pump();
      expect(_loupe, findsNothing);

      await gesture.up();
      await tester.pump();
      expect(find.text('Tap a widget to inspect'), findsOneWidget);
    });

    testWidgets('movement within kTouchSlop stays a tap and never shows the '
        'loupe', (tester) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.rectA.center);
      await gesture.moveBy(const Offset(kTouchSlop - 2, 0));
      await tester.pump();
      expect(_loupe, findsNothing);

      await gesture.up();
      await tester.pump();
      expect(_loupe, findsNothing);
      expect(find.text('size: 120.0 × 40.0'), findsOneWidget);
    });

    testWidgets('movement past kTouchSlop enters aim mode with the loupe', (
      tester,
    ) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
      await tester.pump();
      expect(_loupe, findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(_loupe, findsNothing);
    });

    testWidgets('loupe stays on screen, off the finger, and its crosshair '
        'targets the probe point', (tester) async {
      await _pumpInspect(tester);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final points = [
        const Offset(1, 1),
        Offset(screen.width - 1, 1),
        Offset(1, screen.height - 1),
        Offset(screen.width - 1, screen.height - 1),
        screen.center(Offset.zero),
      ];

      final gesture = await tester.startGesture(_Data.blank);
      for (final p in points) {
        await gesture.moveTo(p);
        await tester.pump();

        final rect = tester.getRect(_loupe);
        final magnifier = tester.widget<RawMagnifier>(_loupe);
        expect(rect.contains(p), isFalse, reason: 'covers finger at $p');
        expect(
          (Offset.zero & screen).intersect(rect),
          rect,
          reason: 'off screen at $p',
        );
        expect(
          rect.center + magnifier.focalPointOffset,
          offsetMoreOrLessEquals(p),
          reason: 'crosshair misses $p',
        );
      }

      await gesture.up();
      await tester.pump();
    });

    testWidgets('loupe flips below the finger when the room above is inside '
        'the top safe area', (tester) async {
      tester.view.padding = FakeViewPadding(
        top: 50 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      await _pumpInspect(tester);
      // Room above the screen edge, but not above a 50px status bar.
      const aim = Offset(400, 140);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(aim);
      await tester.pump();

      final rect = tester.getRect(_loupe);
      final magnifier = tester.widget<RawMagnifier>(_loupe);
      expect(rect.top, greaterThan(aim.dy));
      expect(
        rect.center + magnifier.focalPointOffset,
        offsetMoreOrLessEquals(aim),
      );

      await gesture.up();
      await tester.pump();
    });

    testWidgets('showLoupe false (web) aims and settles without RawMagnifier', (
      tester,
    ) async {
      await _pumpInspect(tester, showLoupe: false);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(_Data.rectB.center);
      await tester.pump();
      expect(_loupe, findsNothing);
      expect(_frameRect(tester), _Data.rectB);

      await gesture.up();
      await tester.pump();
      expect(find.text('size: 60.0 × 60.0'), findsOneWidget);
    });

    testWidgets(
      'clears selection frame and returns to prompt when probe hits nothing',
      (tester) async {
        await _pumpInspect(tester);

        // Drag over target A to select it.
        final gesture = await tester.startGesture(_Data.rectA.center);
        await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
        await tester.pump();
        expect(_frameRect(tester), _Data.rectA);
        expect(find.text('size: 120.0 × 40.0'), findsOneWidget);

        // Move outside view bounds where probeLayoutAt returns empty.
        await gesture.moveTo(const Offset(-50, -50));
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (w) => w is DecoratedBox && w.decoration == _Data.frame,
          ),
          findsNothing,
        );
        expect(find.text('Tap a widget to inspect'), findsOneWidget);

        await gesture.up();
        await tester.pump();
        expect(find.text('Tap a widget to inspect'), findsOneWidget);
      },
    );

    testWidgets('normalizes coordinates when overlay has an offset', (
      tester,
    ) async {
      const overlayOffset = Offset(40, 80);
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
                  left: overlayOffset.dx,
                  top: overlayOffset.dy,
                  width: 500,
                  height: 400,
                  child: Overlay(key: overlayKey),
                ),
              ],
            ),
          ),
        ),
      );

      final overlay = overlayKey.currentState!;
      LayoutInspectOverlay.show(overlay, showLoupe: true);
      await tester.pump();

      // Drag over target widget.
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveTo(targetRect.center);
      await tester.pump();

      // The blue frame must align with targetRect on screen.
      expect(_frameRect(tester), targetRect);

      // The loupe crosshair must target the global aim point.
      final rect = tester.getRect(_loupe);
      final magnifier = tester.widget<RawMagnifier>(_loupe);
      expect(
        rect.center + magnifier.focalPointOffset,
        offsetMoreOrLessEquals(targetRect.center),
      );

      await gesture.up();
      await tester.pump();
      expect(_frameRect(tester), targetRect);
    });
  });
}
