import 'package:flutter/rendering.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_probe.dart';
import 'package:flutter_inspector_kit/src/utils/layout_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('layout_formatters', () {
    test('formatSize formats finite and infinite dimensions', () {
      expect(formatSize(const Size(120, 20.25)), '120.0 × 20.3');
      expect(formatSize(const Size(double.infinity, 48)), '∞ × 48.0');
    });

    test('formatConstraints formats bounded and unbounded constraints', () {
      expect(
        formatConstraints(const BoxConstraints(maxWidth: 360)),
        '0.0 ≤ w ≤ 360.0, 0.0 ≤ h ≤ ∞',
      );
      expect(
        formatConstraints(
          const BoxConstraints.tightFor(width: 100, height: 40),
        ),
        '100.0 ≤ w ≤ 100.0, 40.0 ≤ h ≤ 40.0',
      );
    });

    test('formatOffset formats coordinates to one decimal place', () {
      expect(formatOffset(const Offset(16, 200.5)), '(16.0, 200.5)');
    });

    test(
      'formatLayoutChain formats multi-level chain and obfuscation note',
      () {
        const chain = [
          LayoutLevel(
            widgetName: 'RichText',
            renderName: 'RenderParagraph',
            size: Size(120, 20),
            constraints: BoxConstraints(maxWidth: 360),
            rect: Rect.fromLTWH(16, 200, 120, 20),
          ),
          LayoutLevel(
            widgetName: null,
            renderName: 'RenderPadding',
            size: Size(152, 52),
            constraints: BoxConstraints.tightFor(width: 152, height: 52),
            rect: Rect.fromLTWH(0, 184, 152, 52),
          ),
        ];

        expect(
          formatLayoutChain(chain, mayBeObfuscated: false),
          'Layout inspect — 2 levels (target first)\n'
          '#0 RichText (RenderParagraph)\n'
          '   size: 120.0 × 20.0\n'
          '   constraints: 0.0 ≤ w ≤ 360.0, 0.0 ≤ h ≤ ∞\n'
          '   offset: (16.0, 200.0)\n'
          '#1 RenderPadding\n'
          '   size: 152.0 × 52.0\n'
          '   constraints: 152.0 ≤ w ≤ 152.0, 52.0 ≤ h ≤ 52.0\n'
          '   offset: (0.0, 184.0)',
        );

        expect(
          formatLayoutChain(chain, mayBeObfuscated: true),
          'Layout inspect — 2 levels (target first)\n'
          'Note: names may be obfuscated\n'
          '#0 RichText (RenderParagraph)\n'
          '   size: 120.0 × 20.0\n'
          '   constraints: 0.0 ≤ w ≤ 360.0, 0.0 ≤ h ≤ ∞\n'
          '   offset: (16.0, 200.0)\n'
          '#1 RenderPadding\n'
          '   size: 152.0 × 52.0\n'
          '   constraints: 152.0 ≤ w ≤ 152.0, 52.0 ≤ h ≤ 52.0\n'
          '   offset: (0.0, 184.0)',
        );
      },
    );
  });
}
