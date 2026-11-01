import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Formats a distance [value] as a readable pixel string.
String formatDistance(double value) {
  if (value.isInfinite) return '∞ px';
  if (value % 1 == 0) {
    return '${value.toInt()} px';
  }
  return '${value.toStringAsFixed(1)} px';
}

/// Checks whether [outer] completely encloses [inner] using closed intervals.
///
/// Unlike Flutter's [Rect.contains], which treats the bottom and right edges
/// as open intervals (`dx < right && dy < bottom`), this comparison is
/// inclusive of all four edges.
bool containsRect(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;

/// Computes the 1D gap between two 1D intervals `[aStart, aEnd]` and
/// `[bStart, bEnd]`.
///
/// Returns `0.0` if the intervals overlap or touch. Commutative:
/// `compute1DGap(a1, a2, b1, b2) == compute1DGap(b1, b2, a1, a2)`.
double compute1DGap(
  double aStart,
  double aEnd,
  double bStart,
  double bEnd,
) =>
    math.max(0.0, math.max(aStart, bStart) - math.min(aEnd, bEnd));

/// Represents the exhaustive geometric relationship between two rectangles.
sealed class GapRelation {
  const GapRelation();
}

/// Rectangles are separated in space (pure horizontal, pure vertical, or diagonal).
final class SeparatedRelation extends GapRelation {
  const SeparatedRelation({required this.gapX, required this.gapY});

  /// The horizontal distance between the closest edges (`0.0` if horizontally overlapping).
  final double gapX;

  /// The vertical distance between the closest edges (`0.0` if vertically overlapping).
  final double gapY;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeparatedRelation &&
          other.gapX == gapX &&
          other.gapY == gapY;

  @override
  int get hashCode => Object.hash(gapX, gapY);
}

/// One rectangle is completely enclosed inside the other.
final class ContainedRelation extends GapRelation {
  const ContainedRelation({
    required this.outerIsA,
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  /// `true` if rectangle A is the outer container; `false` if B is outer.
  final bool outerIsA;

  /// Padding from outer top edge to inner top edge.
  final double top;

  /// Padding from inner bottom edge to outer bottom edge.
  final double bottom;

  /// Padding from outer left edge to inner left edge.
  final double left;

  /// Padding from inner right edge to outer right edge.
  final double right;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContainedRelation &&
          other.outerIsA == outerIsA &&
          other.top == top &&
          other.bottom == bottom &&
          other.left == left &&
          other.right == right;

  @override
  int get hashCode => Object.hash(outerIsA, top, bottom, left, right);
}

/// Rectangles intersect partially without one containing the other.
final class OverlappingRelation extends GapRelation {
  const OverlappingRelation({required this.intersection});

  /// The bounding box of the overlapping area.
  final Rect intersection;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlappingRelation && other.intersection == intersection;

  @override
  int get hashCode => intersection.hashCode;
}

/// Rectangles touch along an edge without intersecting.
final class AdjacentRelation extends GapRelation {
  const AdjacentRelation({required this.axis});

  /// The axis perpendicular to the contact edge.
  final Axis axis;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdjacentRelation && other.axis == axis;

  @override
  int get hashCode => axis.hashCode;
}

/// A line segment to be painted on canvas with an associated label.
class RulerSegment {
  const RulerSegment({
    required this.start,
    required this.end,
    required this.label,
    this.isDashed = false,
  });

  final Offset start;
  final Offset end;
  final String label;
  final bool isDashed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulerSegment &&
          other.start == start &&
          other.end == end &&
          other.label == label &&
          other.isDashed == isDashed;

  @override
  int get hashCode => Object.hash(start, end, label, isDashed);
}

/// Pure geometric model describing everything needed to render a gap ruler.
class RulerDisplayModel {
  const RulerDisplayModel({
    required this.rectA,
    required this.rectB,
    required this.relation,
    required this.segments,
  });

  final Rect rectA;
  final Rect rectB;
  final GapRelation relation;
  final List<RulerSegment> segments;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulerDisplayModel &&
          other.rectA == rectA &&
          other.rectB == rectB &&
          other.relation == relation &&
          listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(
        rectA,
        rectB,
        relation,
        Object.hashAll(segments),
      );
}

/// Analyzes the spatial relationship between [a] and [b] and computes
/// all ruler line segments, labels, and geometric relations.
RulerDisplayModel buildRulerDisplayModel(Rect a, Rect b) {
  // 1. Check containment (using closed intervals)
  if (containsRect(a, b)) {
    final top = b.top - a.top;
    final bottom = a.bottom - b.bottom;
    final left = b.left - a.left;
    final right = a.right - b.right;
    final relation = ContainedRelation(
      outerIsA: true,
      top: top,
      bottom: bottom,
      left: left,
      right: right,
    );

    final segments = <RulerSegment>[];
    if (top > 0) {
      segments.add(
        RulerSegment(
          start: Offset(b.center.dx, a.top),
          end: Offset(b.center.dx, b.top),
          label: formatDistance(top),
        ),
      );
    }
    if (bottom > 0) {
      segments.add(
        RulerSegment(
          start: Offset(b.center.dx, b.bottom),
          end: Offset(b.center.dx, a.bottom),
          label: formatDistance(bottom),
        ),
      );
    }
    if (left > 0) {
      segments.add(
        RulerSegment(
          start: Offset(a.left, b.center.dy),
          end: Offset(b.left, b.center.dy),
          label: formatDistance(left),
        ),
      );
    }
    if (right > 0) {
      segments.add(
        RulerSegment(
          start: Offset(b.right, b.center.dy),
          end: Offset(a.right, b.center.dy),
          label: formatDistance(right),
        ),
      );
    }
    return RulerDisplayModel(
      rectA: a,
      rectB: b,
      relation: relation,
      segments: segments,
    );
  }

  if (containsRect(b, a)) {
    final top = a.top - b.top;
    final bottom = b.bottom - a.bottom;
    final left = a.left - b.left;
    final right = b.right - a.right;
    final relation = ContainedRelation(
      outerIsA: false,
      top: top,
      bottom: bottom,
      left: left,
      right: right,
    );

    final segments = <RulerSegment>[];
    if (top > 0) {
      segments.add(
        RulerSegment(
          start: Offset(a.center.dx, b.top),
          end: Offset(a.center.dx, a.top),
          label: formatDistance(top),
        ),
      );
    }
    if (bottom > 0) {
      segments.add(
        RulerSegment(
          start: Offset(a.center.dx, a.bottom),
          end: Offset(a.center.dx, b.bottom),
          label: formatDistance(bottom),
        ),
      );
    }
    if (left > 0) {
      segments.add(
        RulerSegment(
          start: Offset(b.left, a.center.dy),
          end: Offset(a.left, a.center.dy),
          label: formatDistance(left),
        ),
      );
    }
    if (right > 0) {
      segments.add(
        RulerSegment(
          start: Offset(a.right, a.center.dy),
          end: Offset(b.right, a.center.dy),
          label: formatDistance(right),
        ),
      );
    }
    return RulerDisplayModel(
      rectA: a,
      rectB: b,
      relation: relation,
      segments: segments,
    );
  }

  // 2. Check partial intersection (neither contains the other)
  if (a.overlaps(b)) {
    final intersection = Rect.fromLTRB(
      math.max(a.left, b.left),
      math.max(a.top, b.top),
      math.min(a.right, b.right),
      math.min(a.bottom, b.bottom),
    );
    final relation = OverlappingRelation(intersection: intersection);
    final segments = [
      RulerSegment(
        start: intersection.centerLeft,
        end: intersection.centerRight,
        label: formatDistance(intersection.width),
      ),
      RulerSegment(
        start: intersection.topCenter,
        end: intersection.bottomCenter,
        label: formatDistance(intersection.height),
      ),
    ];
    return RulerDisplayModel(
      rectA: a,
      rectB: b,
      relation: relation,
      segments: segments,
    );
  }

  // 3. Compute 1D gaps
  final gapX = compute1DGap(a.left, a.right, b.left, b.right);
  final gapY = compute1DGap(a.top, a.bottom, b.top, b.bottom);

  // 4. Check adjacent (gap == 0 on both axes, touching edge)
  if (gapX == 0.0 && gapY == 0.0) {
    final isHorizontal = a.right == b.left || b.right == a.left;
    final relation = AdjacentRelation(
      axis: isHorizontal ? Axis.horizontal : Axis.vertical,
    );
    return RulerDisplayModel(
      rectA: a,
      rectB: b,
      relation: relation,
      segments: const [],
    );
  }

  // 5. Separated
  final relation = SeparatedRelation(gapX: gapX, gapY: gapY);
  final segments = <RulerSegment>[];

  if (gapX > 0.0 && gapY == 0.0) {
    // Pure horizontal separation (vertical range overlaps)
    final yStart = math.max(a.top, b.top);
    final yEnd = math.min(a.bottom, b.bottom);
    final midY = (yStart + yEnd) / 2;
    final xStart = math.min(a.right, b.right);
    final xEnd = math.max(a.left, b.left);
    segments.add(
      RulerSegment(
        start: Offset(xStart, midY),
        end: Offset(xEnd, midY),
        label: formatDistance(gapX),
      ),
    );
  } else if (gapY > 0.0 && gapX == 0.0) {
    // Pure vertical separation (horizontal range overlaps)
    final xStart = math.max(a.left, b.left);
    final xEnd = math.min(a.right, b.right);
    final midX = (xStart + xEnd) / 2;
    final yStart = math.min(a.bottom, b.bottom);
    final yEnd = math.max(a.top, b.top);
    segments.add(
      RulerSegment(
        start: Offset(midX, yStart),
        end: Offset(midX, yEnd),
        label: formatDistance(gapY),
      ),
    );
  } else {
    // Diagonal separation (both gaps > 0)
    final xStart = math.min(a.right, b.right);
    final xEnd = math.max(a.left, b.left);
    final yStart = math.min(a.bottom, b.bottom);
    final yEnd = math.max(a.top, b.top);

    // Horizontal segment at yStart
    segments.add(
      RulerSegment(
        start: Offset(xStart, yStart),
        end: Offset(xEnd, yStart),
        label: formatDistance(gapX),
      ),
    );

    // Vertical segment at xEnd
    segments.add(
      RulerSegment(
        start: Offset(xEnd, yStart),
        end: Offset(xEnd, yEnd),
        label: formatDistance(gapY),
      ),
    );
  }

  return RulerDisplayModel(
    rectA: a,
    rectB: b,
    relation: relation,
    segments: segments,
  );
}
