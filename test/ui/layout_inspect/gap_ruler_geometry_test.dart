import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/gap_ruler_geometry.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_probe.dart';
import 'package:flutter_inspector_kit/src/utils/layout_formatters.dart';

void main() {
  group('containsRect', () {
    test('returns true for exact same rect (inclusive closed interval)', () {
      const rect = Rect.fromLTWH(10, 10, 100, 100);
      expect(containsRect(rect, rect), isTrue);
    });

    test(
      'returns true when inner touches right and bottom borders (padding 0)',
      () {
        const outer = Rect.fromLTWH(0, 0, 100, 100);
        const inner = Rect.fromLTWH(20, 20, 80, 80); // right: 100, bottom: 100
        expect(containsRect(outer, inner), isTrue);
      },
    );

    test('returns true when inner is strictly inside', () {
      const outer = Rect.fromLTWH(0, 0, 100, 100);
      const inner = Rect.fromLTWH(10, 10, 50, 50);
      expect(containsRect(outer, inner), isTrue);
    });

    test('returns false when inner extends beyond any edge', () {
      const outer = Rect.fromLTWH(0, 0, 100, 100);
      expect(containsRect(outer, const Rect.fromLTWH(-1, 10, 50, 50)), isFalse);
      expect(containsRect(outer, const Rect.fromLTWH(10, -1, 50, 50)), isFalse);
      expect(containsRect(outer, const Rect.fromLTWH(10, 10, 95, 50)), isFalse);
      expect(containsRect(outer, const Rect.fromLTWH(10, 10, 50, 95)), isFalse);
    });
  });

  group('compute1DGap', () {
    test('calculates gap between disjoint intervals symmetrically', () {
      expect(compute1DGap(0, 50, 70, 100), 20.0);
      expect(compute1DGap(70, 100, 0, 50), 20.0);
    });

    test('returns 0 for overlapping intervals', () {
      expect(compute1DGap(0, 50, 30, 80), 0.0);
      expect(compute1DGap(30, 80, 0, 50), 0.0);
    });

    test('returns 0 for touching intervals', () {
      expect(compute1DGap(0, 50, 50, 100), 0.0);
      expect(compute1DGap(50, 100, 0, 50), 0.0);
    });

    test('returns 0 for contained intervals', () {
      expect(compute1DGap(0, 100, 20, 50), 0.0);
      expect(compute1DGap(20, 50, 0, 100), 0.0);
    });
  });

  group('buildRulerDisplayModel', () {
    test('Contained: A contains B', () {
      const a = Rect.fromLTWH(0, 0, 100, 100);
      const b = Rect.fromLTWH(10, 15, 60, 40); // right: 70, bottom: 55
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<ContainedRelation>());
      final rel = model.relation as ContainedRelation;
      expect(rel.outerIsA, isTrue);
      expect(rel.top, 15.0);
      expect(rel.bottom, 45.0);
      expect(rel.left, 10.0);
      expect(rel.right, 30.0);

      // 4 inset segments
      expect(model.segments.length, 4);
      expect(model.segments.any((s) => s.label == '15dp'), isTrue);
      expect(model.segments.any((s) => s.label == '45dp'), isTrue);
      expect(model.segments.any((s) => s.label == '10dp'), isTrue);
      expect(model.segments.any((s) => s.label == '30dp'), isTrue);
    });

    test('Contained: B contains A (symmetric insets)', () {
      const a = Rect.fromLTWH(10, 15, 60, 40);
      const b = Rect.fromLTWH(0, 0, 100, 100);
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<ContainedRelation>());
      final rel = model.relation as ContainedRelation;
      expect(rel.outerIsA, isFalse);
      expect(rel.top, 15.0);
      expect(rel.bottom, 45.0);
      expect(rel.left, 10.0);
      expect(rel.right, 30.0);
    });

    test('Separated: Pure horizontal separation with vertical overlap', () {
      const a = Rect.fromLTWH(0, 10, 50, 80);
      const b = Rect.fromLTWH(80, 20, 60, 50); // gapX = 30, gapY = 0
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<SeparatedRelation>());
      final rel = model.relation as SeparatedRelation;
      expect(rel.gapX, 30.0);
      expect(rel.gapY, 0.0);

      expect(model.segments.length, 1);
      final segment = model.segments.first;
      expect(segment.label, '30dp');
      expect(segment.start.dx, 50.0);
      expect(segment.end.dx, 80.0);
      expect(segment.start.dy, segment.end.dy); // horizontal line
    });

    test('Separated: Pure vertical separation with horizontal overlap', () {
      const a = Rect.fromLTWH(10, 0, 80, 40);
      const b = Rect.fromLTWH(20, 65, 50, 60); // gapX = 0, gapY = 25
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<SeparatedRelation>());
      final rel = model.relation as SeparatedRelation;
      expect(rel.gapX, 0.0);
      expect(rel.gapY, 25.0);

      expect(model.segments.length, 1);
      final segment = model.segments.first;
      expect(segment.label, '25dp');
      expect(segment.start.dy, 40.0);
      expect(segment.end.dy, 65.0);
      expect(segment.start.dx, segment.end.dx); // vertical line
    });

    test('Separated: Diagonal separation Top-Left and Bottom-Right', () {
      const a = Rect.fromLTWH(0, 0, 50, 50);
      const b = Rect.fromLTWH(70, 90, 40, 40); // gapX = 20, gapY = 40
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<SeparatedRelation>());
      final rel = model.relation as SeparatedRelation;
      expect(rel.gapX, 20.0);
      expect(rel.gapY, 40.0);

      expect(model.segments.length, 2);
      final segH = model.segments.firstWhere((s) => s.label == '20dp');
      final segV = model.segments.firstWhere((s) => s.label == '40dp');

      expect(segH.start, const Offset(50, 50));
      expect(segH.end, const Offset(70, 50));

      expect(segV.start, const Offset(70, 50));
      expect(segV.end, const Offset(70, 90));
    });

    test('Separated: Diagonal separation Top-Right and Bottom-Left', () {
      const a = Rect.fromLTWH(70, 10, 40, 40); // right: 110, bottom: 50
      const b = Rect.fromLTWH(10, 80, 40, 40); // right: 50, bottom: 120
      // gapX = 70 - 50 = 20
      // gapY = 80 - 50 = 30
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<SeparatedRelation>());
      final rel = model.relation as SeparatedRelation;
      expect(rel.gapX, 20.0);
      expect(rel.gapY, 30.0);

      expect(model.segments.length, 2);
      final segH = model.segments.firstWhere((s) => s.label == '20dp');
      final segV = model.segments.firstWhere((s) => s.label == '30dp');

      expect(segH.start, const Offset(50, 50));
      expect(segH.end, const Offset(70, 50));

      expect(segV.start, const Offset(70, 50));
      expect(segV.end, const Offset(70, 80));
    });

    test('Overlapping: partial intersection without containment', () {
      const a = Rect.fromLTWH(0, 0, 60, 60);
      const b = Rect.fromLTWH(
        30,
        30,
        60,
        60,
      ); // intersection: (30, 30, 60, 60), size 30x30
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<OverlappingRelation>());
      final rel = model.relation as OverlappingRelation;
      expect(rel.intersection, const Rect.fromLTWH(30, 30, 30, 30));
      expect(model.segments.length, 2);
      expect(model.segments[0].start, const Offset(30, 45));
      expect(model.segments[0].end, const Offset(60, 45));
      expect(model.segments[0].label, '30dp');
      expect(model.segments[1].start, const Offset(45, 30));
      expect(model.segments[1].end, const Offset(45, 60));
      expect(model.segments[1].label, '30dp');
    });

    test('Adjacent: touching along vertical border', () {
      const a = Rect.fromLTWH(0, 0, 50, 50);
      const b = Rect.fromLTWH(50, 0, 50, 50);
      final model = buildRulerDisplayModel(a, b);

      expect(model.relation, isA<AdjacentRelation>());
      final rel = model.relation as AdjacentRelation;
      expect(rel.axis, Axis.horizontal);
    });
  });

  group('formatDualDistance', () {
    test(
      'formats whole numbers and decimals correctly across different DPR',
      () {
        expect(formatDualDistance(20, 1.0), '20dp (20px)');
        expect(formatDualDistance(20, 2.0), '20dp (40px)');
        expect(formatDualDistance(20, 3.0), '20dp (60px)');
        expect(formatDualDistance(15.5, 2.0), '15.5dp (31px)');
        expect(formatDualDistance(10, 2.625), '10dp (26.3px)');
        expect(formatDualDistance(0, 3.0), '0dp (0px)');
        expect(formatDualDistance(double.infinity, 3.0), '∞ dp');
      },
    );
  });

  group('formatMeasurement', () {
    const a = LayoutLevel(
      widgetName: 'ReferenceWidget',
      renderName: 'RenderParagraph',
      size: Size(100, 40),
      constraints: BoxConstraints.tightFor(width: 100, height: 40),
      rect: Rect.fromLTWH(10, 10, 100, 40),
    );

    const b = LayoutLevel(
      widgetName: 'TargetWidget',
      renderName: 'RenderBox',
      size: Size(80, 30),
      constraints: BoxConstraints.tightFor(width: 80, height: 30),
      rect: Rect.fromLTWH(130, 10, 80, 30),
    );

    test('formats Separated measurement correctly', () {
      final text = formatMeasurement(
        a: a,
        b: b,
        relation: const SeparatedRelation(gapX: 20, gapY: 0),
        devicePixelRatio: 2.0,
      );

      expect(text, contains('=== Measurement (Gap Ruler) ==='));
      expect(text, contains('Reference A: ReferenceWidget (RenderParagraph)'));
      expect(text, contains('Target B: TargetWidget (RenderBox)'));
      expect(text, contains('Relation: Separated'));
      expect(text, contains('Horizontal Gap: 20.0 dp (40.0 px @2.0x)'));
      expect(text, contains('Vertical Gap: 0.0 dp (0.0 px @2.0x)'));
    });

    test('formats Contained measurement correctly', () {
      final text = formatMeasurement(
        a: a,
        b: b,
        relation: const ContainedRelation(
          outerIsA: true,
          top: 10,
          bottom: 20,
          left: 15,
          right: 25,
        ),
        devicePixelRatio: 3.0,
      );

      expect(text, contains('Relation: Contained (A contains B)'));
      expect(
        text,
        contains(
          'Insets: Top: 10.0 dp (30.0 px @3.0x), '
          'Bottom: 20.0 dp (60.0 px @3.0x), '
          'Left: 15.0 dp (45.0 px @3.0x), '
          'Right: 25.0 dp (75.0 px @3.0x)',
        ),
      );
    });

    test('formats Overlapping measurement correctly with dual units', () {
      final text = formatMeasurement(
        a: a,
        b: b,
        relation: const OverlappingRelation(
          intersection: Rect.fromLTWH(0, 0, 30, 40),
        ),
        devicePixelRatio: 2.0,
      );

      expect(
        text,
        contains(
          'Relation: Overlapping [intersection: 30.0 dp (60.0 px @2.0x) × 40.0 dp (80.0 px @2.0x)]',
        ),
      );
    });

    test('preserves exact fractional DPR without premature rounding', () {
      final text = formatMeasurement(
        a: a,
        b: b,
        relation: const SeparatedRelation(gapX: 20, gapY: 0),
        devicePixelRatio: 2.625,
      );

      expect(text, contains('Horizontal Gap: 20.0 dp (52.5 px @2.625x)'));
    });
  });
}
