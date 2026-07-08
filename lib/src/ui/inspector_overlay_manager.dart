import 'package:flutter/widgets.dart';

import 'widgets/inspector_fab.dart';

/// Manages the FAB overlay for the Flutter Inspector.
class InspectorOverlayManager {
  /// Creates an [InspectorOverlayManager].
  InspectorOverlayManager({required this.onFabTap});

  /// Called when the FAB is tapped, providing the FAB's build context.
  final void Function(BuildContext context) onFabTap;

  OverlayEntry? _overlayEntry;

  /// Mounts the FAB overlay onto the screen.
  void attach({required BuildContext context, bool visible = true}) {
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => InspectorFab(
        onTap: () => onFabTap(context),
        visible: visible,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  /// Removes the FAB overlay.
  void detach() {
    if (_overlayEntry?.mounted ?? false) {
      _overlayEntry!.remove();
    }
    _overlayEntry = null;
  }
}
