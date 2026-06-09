import 'package:flutter/widgets.dart';

/// A widget that detects a specific number of rapid consecutive taps.
class FlutterInspectorMagicalTap extends StatefulWidget {
  const FlutterInspectorMagicalTap({
    required this.child,
    required this.onTap,
    this.tapCount = 5,
    this.timeout = const Duration(milliseconds: 500),
    super.key,
  });

  /// The widget below this widget in the tree.
  final Widget child;

  /// Called when the magical tap sequence is completed.
  final VoidCallback onTap;

  /// The number of taps required to trigger the callback.
  final int tapCount;

  /// The maximum duration allowed between consecutive taps.
  final Duration timeout;

  @override
  State<FlutterInspectorMagicalTap> createState() =>
      _FlutterInspectorMagicalTapState();
}

class _FlutterInspectorMagicalTapState
    extends State<FlutterInspectorMagicalTap> {
  int _taps = 0;
  DateTime? _lastTap;

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTap == null || now.difference(_lastTap!) > widget.timeout) {
      _taps = 1;
    } else {
      _taps++;
    }
    _lastTap = now;

    if (_taps >= widget.tapCount) {
      _taps = 0;
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _handleTap,
      child: widget.child,
    );
  }
}
