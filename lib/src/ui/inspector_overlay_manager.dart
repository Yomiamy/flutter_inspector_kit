import 'package:flutter/widgets.dart';

import 'widgets/inspector_fab.dart';

/// Manages the overlay lifecycle of the Inspector FAB.
// ponytail: <天花板> 僅支援單一 FAB 實體, <升級路徑> 若需支援多重視窗或多實體，需改為 map 管理 OverlayEntry 並綁定 Route/Window。
class InspectorOverlayManager {
  InspectorOverlayManager({required this.onFabTap});

  final void Function(BuildContext context) onFabTap;
  OverlayEntry? _overlayEntry;

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

  void detach() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
