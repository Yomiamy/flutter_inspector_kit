import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/gap_ruler_geometry.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/gap_ruler_painter.dart';

void main() {
  group('GapRulerPainter', () {
    testWidgets('paints Separated relation without error', (tester) async {
      const a = Rect.fromLTWH(20, 20, 100, 50);
      const b = Rect.fromLTWH(150, 20, 80, 50);
      final model = buildRulerDisplayModel(a, b);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(400, 400),
              painter: GapRulerPainter(model: model),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('paints Contained relation without error', (tester) async {
      const a = Rect.fromLTWH(0, 0, 200, 200);
      const b = Rect.fromLTWH(30, 40, 80, 80);
      final model = buildRulerDisplayModel(a, b);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(400, 400),
              painter: GapRulerPainter(model: model),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('paints Overlapping relation with fill without error', (tester) async {
      const a = Rect.fromLTWH(50, 50, 100, 100);
      const b = Rect.fromLTWH(100, 100, 100, 100);
      final model = buildRulerDisplayModel(a, b);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(400, 400),
              painter: GapRulerPainter(model: model),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('shouldRepaint delegates equality to model', () {
      const a = Rect.fromLTWH(0, 0, 50, 50);
      const b1 = Rect.fromLTWH(80, 0, 50, 50);
      const b2 = Rect.fromLTWH(100, 0, 50, 50);

      final model1 = buildRulerDisplayModel(a, b1);
      final model2 = buildRulerDisplayModel(a, b2);

      final painter1 = GapRulerPainter(model: model1);
      final painter2 = GapRulerPainter(model: model2);
      final painter1Copy = GapRulerPainter(model: model1);

      expect(painter1.shouldRepaint(painter1Copy), isFalse);
      expect(painter1.shouldRepaint(painter2), isTrue);
    });
  });
}
