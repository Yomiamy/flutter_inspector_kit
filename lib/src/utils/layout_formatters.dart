import 'package:flutter/rendering.dart';

import '../ui/layout_inspect/gap_ruler_geometry.dart';
import '../ui/layout_inspect/layout_probe.dart';

String _formatNumber(double value) =>
    value.isInfinite ? '∞' : value.toStringAsFixed(1);

/// Formats [size] as `width × height` with 1 decimal place (or `∞`).
String formatSize(Size size) =>
    '${_formatNumber(size.width)} × ${_formatNumber(size.height)}';

/// Formats [constraints] as `minW ≤ w ≤ maxW, minH ≤ h ≤ maxH`.
String formatConstraints(BoxConstraints constraints) =>
    '${_formatNumber(constraints.minWidth)} ≤ w ≤ '
    '${_formatNumber(constraints.maxWidth)}, '
    '${_formatNumber(constraints.minHeight)} ≤ h ≤ '
    '${_formatNumber(constraints.maxHeight)}';

/// Formats [offset] as `(dx, dy)` with 1 decimal place (or `∞`).
String formatOffset(Offset offset) =>
    '(${_formatNumber(offset.dx)}, ${_formatNumber(offset.dy)})';

/// Formats an entire [chain] of [LayoutLevel] snapshots (target first) as
/// plain text for clipboard copy or share export.
String formatLayoutChain(
  List<LayoutLevel> chain, {
  required bool mayBeObfuscated,
}) {
  final buffer = StringBuffer()
    ..writeln('Layout inspect — ${chain.length} levels (target first)');
  if (mayBeObfuscated) {
    buffer.writeln('Note: names may be obfuscated');
  }
  for (var i = 0; i < chain.length; i++) {
    final level = chain[i];
    final header = level.widgetName != null
        ? '${level.widgetName} (${level.renderName})'
        : level.renderName;
    buffer
      ..writeln('#$i $header')
      ..writeln('   size: ${formatSize(level.size)}')
      ..writeln('   constraints: ${formatConstraints(level.constraints)}')
      ..writeln('   offset: ${formatOffset(level.rect.topLeft)}');
  }
  return buffer.toString().trimRight();
}

/// Formats the measurement between reference [a] and target [b] with their [relation].
String formatMeasurement({
  required LayoutLevel a,
  required LayoutLevel b,
  required GapRelation relation,
}) {
  final buffer = StringBuffer()
    ..writeln('=== Measurement (Gap Ruler) ===')
    ..writeln(
      'Reference A: ${a.widgetName != null ? "${a.widgetName} (${a.renderName})" : a.renderName} '
      '[size: ${formatSize(a.size)}, offset: ${formatOffset(a.rect.topLeft)}]',
    )
    ..writeln(
      'Target B: ${b.widgetName != null ? "${b.widgetName} (${b.renderName})" : b.renderName} '
      '[size: ${formatSize(b.size)}, offset: ${formatOffset(b.rect.topLeft)}]',
    );

  switch (relation) {
    case SeparatedRelation(:final gapX, :final gapY):
      buffer.writeln('Relation: Separated');
      buffer.writeln('Horizontal Gap: ${_formatNumber(gapX)} px');
      buffer.writeln('Vertical Gap: ${_formatNumber(gapY)} px');
    case ContainedRelation(
      :final outerIsA,
      :final top,
      :final bottom,
      :final left,
      :final right,
    ):
      buffer.writeln(
        'Relation: Contained (${outerIsA ? "A contains B" : "B contains A"})',
      );
      buffer.writeln(
        'Insets: Top: ${_formatNumber(top)} px, '
        'Bottom: ${_formatNumber(bottom)} px, '
        'Left: ${_formatNumber(left)} px, '
        'Right: ${_formatNumber(right)} px',
      );
    case OverlappingRelation(:final intersection):
      buffer.writeln(
        'Relation: Overlapping [intersection: ${formatSize(intersection.size)}]',
      );
    case AdjacentRelation(:final axis):
      buffer.writeln(
        'Relation: Adjacent (${axis == Axis.horizontal ? "horizontal" : "vertical"})',
      );
  }

  return buffer.toString().trimRight();
}
