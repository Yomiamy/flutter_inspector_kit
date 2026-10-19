import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_probe.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingHitTestWidget extends SingleChildRenderObjectWidget {
  const _ThrowingHitTestWidget({required this.shouldThrow, super.child});

  final bool shouldThrow;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderThrowingHitTest(shouldThrow: shouldThrow);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderThrowingHitTest renderObject,
  ) {
    renderObject.shouldThrow = shouldThrow;
  }
}

class _RenderThrowingHitTest extends RenderProxyBox {
  _RenderThrowingHitTest({required this.shouldThrow});

  bool shouldThrow;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (shouldThrow) {
      throw StateError('Simulated hitTest failure');
    }
    return super.hitTest(result, position: position);
  }
}

void main() {
  group('probeLayoutAt & LayoutProbeShield', () {
    testWidgets(
      'captures target size, tight constraints, widget names, and excludes RenderView',
      (tester) async {
        final anchorKey = GlobalKey();
        final targetKey = GlobalKey();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              key: anchorKey,
              child: SizedBox(
                width: 100,
                height: 40,
                child: ColoredBox(
                  key: targetKey,
                  color: const Color(0xFFFF0000),
                ),
              ),
            ),
          ),
        );

        final anchor = anchorKey.currentContext!.findRenderObject()!;
        final targetCenter = tester.getCenter(find.byKey(targetKey));

        final chain = probeLayoutAt(anchor, targetCenter);

        expect(chain, isNotEmpty);
        expect(chain.first.widgetName, 'ColoredBox');
        expect(chain.first.size, const Size(100, 40));
        expect(
          chain.first.constraints,
          const BoxConstraints.tightFor(width: 100, height: 40),
        );
        expect(chain.first.rect.size, const Size(100, 40));
        expect(chain.first.rect.center, targetCenter);

        // Next ancestor in the chain is the SizedBox's RenderConstrainedBox.
        expect(chain[1].widgetName, 'SizedBox');
        expect(chain[1].renderName, 'RenderConstrainedBox');

        // RenderView itself must not be included in the chain.
        expect(chain.any((l) => l.renderName == 'RenderView'), isFalse);
      },
    );

    testWidgets(
      'LayoutProbeShield is transparent during probeLayoutAt but receives normal taps',
      (tester) async {
        final anchorKey = GlobalKey();
        final targetKey = GlobalKey();
        var shieldTapped = false;

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              key: anchorKey,
              children: [
                Center(
                  child: SizedBox(
                    width: 80,
                    height: 30,
                    child: ColoredBox(
                      key: targetKey,
                      color: const Color(0xFF00FF00),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: LayoutProbeShield(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => shieldTapped = true,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        final anchor = anchorKey.currentContext!.findRenderObject()!;
        final center = tester.getCenter(find.byKey(targetKey));

        // Probing ignores the opaque GestureDetector inside LayoutProbeShield.
        final chain = probeLayoutAt(anchor, center);
        expect(chain, isNotEmpty);
        expect(chain.first.widgetName, 'ColoredBox');
        expect(chain.first.size, const Size(80, 30));

        // Normal gesture hit-testing still hits the shielded GestureDetector.
        await tester.tapAt(center);
        expect(shieldTapped, isTrue);
      },
    );

    testWidgets(
      'returns empty list when anchor is detached or position misses all RenderBoxes',
      (tester) async {
        final detached = RenderConstrainedBox(
          additionalConstraints: const BoxConstraints.tightFor(
            width: 10,
            height: 10,
          ),
        );
        expect(probeLayoutAt(detached, Offset.zero), isEmpty);

        final anchorKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              key: anchorKey,
              alignment: Alignment.topLeft,
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        );

        final anchor = anchorKey.currentContext!.findRenderObject()!;
        // Outside the 800x600 test view bounds, RenderView.hitTest hits nothing.
        expect(probeLayoutAt(anchor, const Offset(-50, -50)), isEmpty);
      },
    );

    testWidgets('resets probing state even if hitTest throws', (tester) async {
      final anchorKey = GlobalKey();
      var shieldTapped = false;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            key: anchorKey,
            children: [
              const Positioned.fill(
                child: _ThrowingHitTestWidget(
                  shouldThrow: true,
                  child: SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: LayoutProbeShield(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => shieldTapped = true,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      final anchor = anchorKey.currentContext!.findRenderObject()!;
      expect(
        () => probeLayoutAt(anchor, const Offset(100, 100)),
        throwsStateError,
      );

      // Even after a thrown exception during probeLayoutAt, _probing was
      // reset in finally so LayoutProbeShield still handles normal taps.
      await tester.tapAt(const Offset(100, 100));
      expect(shieldTapped, isTrue);
    });
  });
}
