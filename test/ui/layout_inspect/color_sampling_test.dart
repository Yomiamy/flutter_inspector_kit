import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_probe.dart';
import 'package:flutter_inspector_kit/src/ui/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static const Key anchor = ValueKey('anchor');
  static const Rect block = Rect.fromLTWH(100, 100, 100, 100);
  static const Color background = Color(0xFF00AA55);
  static const Color blockColor = Color(0xFFAA00AA);
}

/// App content at the bottom, a [LayoutProbeShield] holding the sampling
/// anchor on top, optionally painting [cover] over the block.
Future<void> _pumpScene(
  WidgetTester tester, {
  Widget app = const ColoredBox(color: _Data.background),
  Color? cover,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(child: app),
          Positioned.fill(
            child: LayoutProbeShield(
              child: Stack(
                children: [
                  const Positioned.fill(child: SizedBox(key: _Data.anchor)),
                  if (cover != null)
                    Positioned.fromRect(
                      rect: _Data.block,
                      child: ColoredBox(color: cover),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _blockOn(Color background, Color block) => Stack(
  children: [
    Positioned.fill(child: ColoredBox(color: background)),
    Positioned.fromRect(
      rect: _Data.block,
      child: ColoredBox(color: block),
    ),
  ],
);

/// Starts a sample, runs the capture frame, then lets the engine finish the
/// pixel read-back. `testWidgets` runs on fake time, so the read-back only
/// completes inside `runAsync`; the `pump` after it delivers the result. The
/// first capture in an isolate, or a loaded machine, can need several rounds.
Future<Color?> _sample(WidgetTester tester, Offset point) async {
  Color? color;
  var done = false;
  Future<void> run() async {
    color = await sampleColorAt(
      tester.renderObject(find.byKey(_Data.anchor)),
      point,
    );
    done = true;
  }

  unawaited(run());
  await tester.pump();
  for (var i = 0; i < 50 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done, isTrue, reason: 'sample did not complete');
  return color;
}

void main() {
  group('sampleColorAt', () {
    testWidgets('reads the app pixel under kit UI painted inside a shield', (
      tester,
    ) async {
      await _pumpScene(
        tester,
        app: _blockOn(_Data.background, _Data.blockColor),
        cover: ThemeColor.color2196F3,
      );

      expect(await _sample(tester, _Data.block.center), _Data.blockColor);
    });

    testWidgets('reports an app color equal to the kit blue as is', (
      tester,
    ) async {
      await _pumpScene(
        tester,
        app: _blockOn(_Data.background, ThemeColor.color2196F3),
      );

      expect(await _sample(tester, _Data.block.center), ThemeColor.color2196F3);
    });

    testWidgets('reads the physical pixel that contains the point at a '
        'fractional devicePixelRatio', (tester) async {
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetDevicePixelRatio);
      // At 2.625, logical x = 40 is physical x = 105 exactly; 39.9 maps to
      // 104.74, inside the left pixel. Rounding would pick the right one.
      await _pumpScene(
        tester,
        app: const Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 40, child: ColoredBox(color: _Data.blockColor)),
            Expanded(child: ColoredBox(color: _Data.background)),
          ],
        ),
      );

      expect(await _sample(tester, const Offset(39.9, 20)), _Data.blockColor);
    });

    testWidgets('returns null over a texture', (tester) async {
      await _pumpScene(
        tester,
        app: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: _Data.background)),
            Positioned.fromRect(
              rect: _Data.block,
              child: const Texture(textureId: 1),
            ),
          ],
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('returns null for a widget drawn over a texture', (
      tester,
    ) async {
      // The hit lands on the translucent box, not the texture below it.
      await _pumpScene(
        tester,
        app: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: _Data.background)),
            Positioned.fromRect(
              rect: _Data.block,
              child: const Texture(textureId: 1),
            ),
            Positioned.fromRect(
              rect: _Data.block.deflate(30),
              child: const ColoredBox(color: Color(0x80AA00AA)),
            ),
          ],
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('does not block points outside a texture', (tester) async {
      // Layers: root TransformLayer (DPR 3) > RepaintBoundary OffsetLayer at
      // (50, 50) > the texture's own OffsetLayer at (50, 50) > TextureLayer
      // (0, 0, 100, 100). The walk must add both offsets and the DPR.
      await _pumpScene(
        tester,
        app: const Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: _Data.background)),
            Positioned(
              left: 50,
              top: 50,
              width: 150,
              height: 150,
              child: RepaintBoundary(
                child: Padding(
                  padding: EdgeInsets.only(left: 50, top: 50),
                  child: Texture(textureId: 1),
                ),
              ),
            ),
          ],
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
      // The texture spans physical 300..600. Dropping the offsets moves it to
      // 0..300 (150..450 if only the outer one is lost), which catches
      // 75 * 3 = 225; applying the DPR twice moves it to 900..1800, which
      // catches 350 * 3 = 1050. Nothing paints over the background there.
      expect(await _sample(tester, const Offset(75, 75)), _Data.background);
      expect(await _sample(tester, const Offset(350, 350)), _Data.background);
    });

    testWidgets('returns null when the pixel is not fully opaque', (
      tester,
    ) async {
      await _pumpScene(tester, app: const ColoredBox(color: Color(0x80AA00AA)));

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('hides every shield for exactly the capture frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: _Data.background)),
              Positioned(
                left: 0,
                top: 0,
                width: 50,
                height: 50,
                child: LayoutProbeShield(
                  child: ColoredBox(color: ThemeColor.color2196F3),
                ),
              ),
              Positioned.fill(
                child: LayoutProbeShield(child: SizedBox(key: _Data.anchor)),
              ),
            ],
          ),
        ),
      );
      final other = tester.renderObject(find.byType(LayoutProbeShield).first);
      expect(other, isNot(paintsNothing));

      unawaited(
        sampleColorAt(
          tester.renderObject(find.byKey(_Data.anchor)),
          const Offset(25, 25),
        ),
      );
      expect(other, paintsNothing);

      await tester.pump();
      expect(other, isNot(paintsNothing));
    });

    testWidgets('returns null when the anchor is outside any shield', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ColoredBox(
          color: _Data.background,
          child: SizedBox.expand(key: _Data.anchor),
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('returns null without throwing when the shield is removed '
        'before the capture frame', (tester) async {
      await _pumpScene(tester);
      Color? color = _Data.blockColor;
      var done = false;
      Future<void> run() async {
        color = await sampleColorAt(
          tester.renderObject(find.byKey(_Data.anchor)),
          _Data.block.center,
        );
        done = true;
      }

      unawaited(run());
      await tester.pumpWidget(const SizedBox.shrink());

      expect(done, isTrue);
      expect(color, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
