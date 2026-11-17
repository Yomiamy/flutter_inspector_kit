import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutLevel &&
          other.widgetName == widgetName &&
          other.renderName == renderName &&
          other.size == size &&
          other.constraints == constraints &&
          other.rect == rect;

  @override
  int get hashCode =>
      Object.hash(widgetName, renderName, size, constraints, rect);
}

bool _probing = false;
bool _hidden = false;
final Set<_RenderLayoutProbeShield> _shields = {};

/// Wraps a subtree so that it is invisible to [probeLayoutAt] hit tests and
/// to [sampleColorAt] captures, while behaving identically to its child
/// otherwise.
class LayoutProbeShield extends SingleChildRenderObjectWidget {
  const LayoutProbeShield({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLayoutProbeShield();
  }
}

class _RenderLayoutProbeShield extends RenderProxyBox {
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shields.add(this);
  }

  @override
  void detach() {
    _shields.remove(this);
    super.detach();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_probing) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_hidden) return;
    super.paint(context, offset);
  }

  // Reads RenderView.layer, which is @protected: legal only inside a
  // RenderObject member.
  ui.Image? _capturePixel(Offset globalPosition) {
    final view = owner?.rootNode;
    if (view is! RenderView) return null;
    final root = view.layer;
    if (root is! TransformLayer) return null;
    final transform = root.transform;
    if (transform == null) return null;
    final p = MatrixUtils.transformPoint(transform, globalPosition);
    if (_coversExternalSurface(root, Matrix4.identity(), p)) return null;
    return root.toImageSync(
      Rect.fromLTWH(p.dx.floorToDouble(), p.dy.floorToDouble(), 1, 1),
    );
  }
}

// Platform views and textures are composited outside the Flutter scene, so a
// capture cannot see what they show on screen.
// shortcut: clips and z-order are ignored, so a platform view clipped away
// at the point, or covered there by opaque UI, still hides the color; refine
// with clip intersection and paint order if that shows up in practice.
bool _coversExternalSurface(Layer layer, Matrix4 transform, Offset point) {
  final rect = switch (layer) {
    PlatformViewLayer(:final rect) || TextureLayer(:final rect) => rect,
    _ => null,
  };
  if (rect != null) {
    return MatrixUtils.transformRect(transform, rect).contains(point);
  }
  if (layer is! ContainerLayer) return false;
  for (var child = layer.firstChild; child != null; child = child.nextSibling) {
    final childTransform = transform.clone();
    layer.applyTransform(child, childTransform);
    if (_coversExternalSurface(child, childTransform, point)) return true;
  }
  return false;
}

// shortcut: kit tooltips are drawn through OverlayPortal, outside any shield,
// so one still showing after a long press (~1.5s) can end up in the sample;
// wrap the tooltip overlay in a shield if that shows up in practice.
void _setHidden(bool value) {
  _hidden = value;
  for (final shield in _shields) {
    shield.markNeedsPaint();
  }
}

/// Reads the on-screen color of the physical pixel under [globalPosition].
///
/// [anchor] must sit inside a [LayoutProbeShield]. Every shield subtree is
/// left unpainted for one frame, so the result never contains kit UI.
/// Completes with `null`, never with an error, when the displayed color
/// cannot be known: a platform view or texture covers the point, the pixel is
/// not fully opaque, or the capture fails.
Future<Color?> sampleColorAt(RenderObject anchor, Offset globalPosition) async {
  RenderObject? node = anchor;
  while (node != null && node is! _RenderLayoutProbeShield) {
    node = node.parent;
  }
  if (node is! _RenderLayoutProbeShield) return null;
  final shield = node;

  final captured = Completer<ui.Image?>();
  SchedulerBinding.instance.addPostFrameCallback((_) {
    try {
      captured.complete(shield._capturePixel(globalPosition));
    } on Object catch (_) {
      // A failed capture only hides the color row (spec AC7).
      captured.complete(null);
    } finally {
      _setHidden(false);
    }
  });
  // Hide only once the callback that unhides is registered.
  _setHidden(true);
  final image = await captured.future;
  if (image == null) return null;
  try {
    final bytes = await image.toByteData();
    // Not fully opaque: what shows through is outside the Flutter scene.
    if (bytes == null || bytes.getUint8(3) != 255) return null;
    return Color.fromARGB(
      255,
      bytes.getUint8(0),
      bytes.getUint8(1),
      bytes.getUint8(2),
    );
  } on Object catch (_) {
    return null;
  } finally {
    image.dispose();
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
