import 'package:flutter/rendering.dart';

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
