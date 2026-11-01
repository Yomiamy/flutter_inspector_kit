import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'gap_ruler_geometry.dart';

/// Paints the gap ruler between reference A and target B on Canvas.
class GapRulerPainter extends CustomPainter {
  const GapRulerPainter({required this.model});

  final RulerDisplayModel model;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paint A outline (blue)
    final paintA = Paint()
      ..color = ThemeColor.color2196F3
      ..style = PaintingStyle.stroke
      ..strokeWidth = ThemeSize.space2;
    canvas.drawRect(model.rectA, paintA);

    // 2. Paint B outline (orange)
    final paintB = Paint()
      ..color = ThemeColor.colorFF9800
      ..style = PaintingStyle.stroke
      ..strokeWidth = ThemeSize.space2;
    canvas.drawRect(model.rectB, paintB);

    // 3. If overlapping, paint intersection fill
    if (model.relation case OverlappingRelation(:final intersection)) {
      final fillPaint = Paint()
        ..color = const Color(0x33FF9800)
        ..style = PaintingStyle.fill;
      canvas.drawRect(intersection, fillPaint);
    }

    // 4. Paint segments
    final linePaint = Paint()
      ..color = ThemeColor.colorF44336
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final segment in model.segments) {
      if (segment.isDashed) {
        _drawDashedLine(canvas, segment.start, segment.end, linePaint);
      } else {
        canvas.drawLine(segment.start, segment.end, linePaint);
        _drawEndTicks(canvas, segment.start, segment.end, linePaint);
        if (segment.label.isNotEmpty) {
          _drawBadge(canvas, segment);
        }
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final distance = (end - start).distance;
    if (distance <= 0) return;
    final direction = (end - start) / distance;
    const dashLength = 4.0;
    const dashGap = 4.0;
    var current = 0.0;
    while (current < distance) {
      final p1 = start + direction * current;
      final step = math.min(dashLength, distance - current);
      final p2 = p1 + direction * step;
      canvas.drawLine(p1, p2, paint);
      current += dashLength + dashGap;
    }
  }

  void _drawEndTicks(Canvas canvas, Offset start, Offset end, Paint paint) {
    final diff = end - start;
    if (diff.distance <= 0) return;
    final normal = Offset(-diff.dy, diff.dx) / diff.distance;
    const tickHalf = 3.5;
    canvas.drawLine(
      start - normal * tickHalf,
      start + normal * tickHalf,
      paint,
    );
    canvas.drawLine(end - normal * tickHalf, end + normal * tickHalf, paint);
  }

  void _drawBadge(Canvas canvas, RulerSegment segment) {
    final textSpan = TextSpan(
      text: segment.label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: ThemeFontSize.fontSize10,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final center = (segment.start + segment.end) / 2;
    const padH = 4.0;
    const padV = 2.0;
    final badgeWidth = textPainter.width + padH * 2;
    final badgeHeight = textPainter.height + padV * 2;

    final badgeRect = Rect.fromCenter(
      center: center,
      width: badgeWidth,
      height: badgeHeight,
    );

    final bgPaint = Paint()
      ..color = const Color(0xE6212121)
      ..style = PaintingStyle.fill;
    final rrect = RRect.fromRectAndRadius(
      badgeRect,
      const Radius.circular(3.0),
    );
    canvas.drawRRect(rrect, bgPaint);

    final textOffset = Offset(badgeRect.left + padH, badgeRect.top + padV);
    textPainter.paint(canvas, textOffset);
    textPainter.dispose();
  }

  @override
  bool shouldRepaint(covariant GapRulerPainter oldDelegate) {
    return oldDelegate.model != model;
  }
}
