import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A snapshot of one [RenderBox] level captured at tap time.
///
/// The UI reads only these immutable snapshots and never holds a reference to
/// the underlying [RenderObject].
@immutable
class LayoutLevel {
  const LayoutLevel({
    required this.widgetName,
    required this.renderName,
    required this.size,
    required this.constraints,
    required this.rect,
  });

  /// The runtime type name of the owning [Widget], or `null` if no matching
  /// [RenderObjectElement] was found in the element tree.
  final String? widgetName;

  /// The runtime type name of the [RenderBox].
  final String renderName;

  /// The laid-out size of the [RenderBox].
  final Size size;

  /// The [BoxConstraints] received by the [RenderBox] during layout.
  final BoxConstraints constraints;

  /// The bounding rectangle in global screen coordinates.
  final Rect rect;
}

bool _probing = false;

/// Wraps a subtree so that it is invisible to [probeLayoutAt] hit tests while
/// behaving identically to its child during normal pointer events.
class LayoutProbeShield extends SingleChildRenderObjectWidget {
  const LayoutProbeShield({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLayoutProbeShield();
  }
}

class _RenderLayoutProbeShield extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_probing) return false;
    return super.hitTest(result, position: position);
  }
}

/// Hit-tests the [RenderView] enclosing [anchor] at [globalPosition] and
/// returns the [RenderBox] ancestor chain starting from the deepest hit target
/// up to (but excluding) the [RenderView].
///
/// Any subtree wrapped in [LayoutProbeShield] is ignored during the hit test.
List<LayoutLevel> probeLayoutAt(RenderObject anchor, Offset globalPosition) {
  RenderView? view;
  Object? node = anchor;
  while (node != null) {
    if (node is RenderView) {
      view = node;
      break;
    }
    node = node is RenderObject ? node.parent : null;
  }
  if (view == null) return const [];

  final result = BoxHitTestResult();
  _probing = true;
  try {
    view.hitTest(result, position: globalPosition);
  } finally {
    _probing = false;
  }

  RenderBox? target;
  for (final entry in result.path) {
    final candidate = entry.target;
    if (candidate is RenderBox && candidate.hasSize) {
      target = candidate;
      break;
    }
  }
  if (target == null) return const [];

  final boxes = <RenderBox>[];
  Object? current = target;
  while (current != null && current is! RenderView) {
    if (current is RenderBox && current.hasSize) {
      boxes.add(current);
    }
    current = current is RenderObject ? current.parent : null;
  }
  if (boxes.isEmpty) return const [];

  final boxSet = boxes.toSet();
  final widgetNames = <RenderObject, String>{};
  void visit(Element element) {
    if (element is RenderObjectElement) {
      final ro = element.renderObject;
      if (boxSet.contains(ro)) {
        widgetNames[ro] = element.widget.runtimeType.toString();
      }
    }
    element.visitChildElements(visit);
  }

  final rootElement = WidgetsBinding.instance.rootElement;
  if (rootElement != null) {
    visit(rootElement);
  }

  return [
    for (final box in boxes)
      LayoutLevel(
        widgetName: widgetNames[box],
        renderName: box.runtimeType.toString(),
        size: box.size,
        constraints: box.constraints,
        rect: MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        ),
      ),
  ];
}
