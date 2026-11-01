import 'dart:ui';

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
      final customPaint = tester.widget<CustomPaint>(
        find.byType(CustomPaint).last,
      );
      expect((customPaint.painter as GapRulerPainter).model, model);
      expect(model.segments, isNotEmpty);
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
      final customPaint = tester.widget<CustomPaint>(
        find.byType(CustomPaint).last,
      );
      expect((customPaint.painter as GapRulerPainter).model, model);
      expect(model.segments, isNotEmpty);
    });

    testWidgets('paints Overlapping relation with fill without error', (
      tester,
    ) async {
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
      final customPaint = tester.widget<CustomPaint>(
        find.byType(CustomPaint).last,
      );
      expect((customPaint.painter as GapRulerPainter).model, model);
      expect(model.segments, isNotEmpty);
    });

    test(
      'shouldRepaint delegates value equality to model across distinct instances',
      () {
        const a = Rect.fromLTWH(0, 0, 50, 50);
        const b1 = Rect.fromLTWH(80, 0, 50, 50);
        const b2 = Rect.fromLTWH(100, 0, 50, 50);

        final model1 = buildRulerDisplayModel(a, b1);
        final model1Clone = buildRulerDisplayModel(a, b1);
        final model2 = buildRulerDisplayModel(a, b2);

        // Verify they are distinct objects in memory but value-equal
        expect(identical(model1, model1Clone), isFalse);
        expect(model1 == model1Clone, isTrue);

        final painter1 = GapRulerPainter(model: model1);
        final painter1Clone = GapRulerPainter(model: model1Clone);
        final painter2 = GapRulerPainter(model: model2);

        expect(painter1.shouldRepaint(painter1Clone), isFalse);
        expect(painter1.shouldRepaint(painter2), isTrue);
      },
    );

    test(
      'direct paint invocation executes drawing instructions without error',
      () {
        const a = Rect.fromLTWH(20, 20, 100, 50);
        const b = Rect.fromLTWH(150, 20, 80, 50);
        final model = buildRulerDisplayModel(a, b);

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        final painter = GapRulerPainter(model: model);

        painter.paint(canvas, const Size(400, 400));
        final picture = recorder.endRecording();
        expect(picture.approximateBytesUsed, greaterThan(0));
      },
    );
  });
}
