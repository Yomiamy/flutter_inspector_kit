import 'package:flutter/material.dart';

/// A draggable Floating Action Button that triggers the inspector dashboard.
class InspectorFab extends StatefulWidget {
  const InspectorFab({required this.onTap, this.visible = true, super.key});

  /// Called when the FAB is tapped.
  final VoidCallback onTap;

  /// Controls the visibility of the FAB.
  final bool visible;

  @override
  State<InspectorFab> createState() => _InspectorFabState();
}

class _InspectorFabState extends State<InspectorFab> {
  Offset position = const Offset(20, 100);

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final size = MediaQuery.of(context).size;
          setState(() {
            final newX = (position.dx + details.delta.dx).clamp(
              0.0,
              size.width - 48.0,
            );
            final newY = (position.dy + details.delta.dy).clamp(
              0.0,
              size.height - 48.0,
            );
            position = Offset(newX, newY);
          });
        },
        child: FloatingActionButton(
          onPressed: widget.onTap,
          mini: true,
          child: const Icon(Icons.bug_report),
        ),
      ),
    );
  }
}
