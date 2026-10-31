import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/layout_formatters.dart';
import '../../utils/share_text.dart';
import '../theme/theme.dart';
import 'layout_probe.dart';

const double _loupeDiameter = 96;
const double _loupeScale = 2;
// Clearance between the fingertip and the loupe edge, so the finger never
// covers the lens.
const double _loupeGap = 32;
const double _crosshairWidth = 1;

/// Manages the tap-to-inspect layout overlay entry.
abstract final class LayoutInspectOverlay {
  static OverlayEntry? _entry;

  /// Inserts the layout inspection overlay into [overlay].
  ///
  /// Repeated calls while the overlay is already active are ignored.
  /// [showLoupe] defaults to `!kIsWeb`: the drag loupe is skipped on web.
  static void show(
    OverlayState overlay, {
    bool? mayBeObfuscated,
    bool? showLoupe,
  }) {
    if (_entry != null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => LayoutProbeShield(
        child: _LayoutInspectLayer(
          entry: entry,
          mayBeObfuscated: mayBeObfuscated ?? !kDebugMode,
          showLoupe: showLoupe ?? !kIsWeb,
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _LayoutInspectLayer extends StatefulWidget {
  const _LayoutInspectLayer({
    required this.entry,
    required this.mayBeObfuscated,
    required this.showLoupe,
  });

  final OverlayEntry entry;
  final bool mayBeObfuscated;
  final bool showLoupe;

  @override
  State<_LayoutInspectLayer> createState() => _LayoutInspectLayerState();
}

class _LayoutInspectLayerState extends State<_LayoutInspectLayer> {
  List<LayoutLevel> _chain = const [];
  int _index = 0;
  bool _copied = false;
  Timer? _copiedTimer;
  Offset? _aim;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    if (LayoutInspectOverlay._entry == widget.entry) {
      LayoutInspectOverlay._entry = null;
    }
    super.dispose();
  }

  void _onTapUp(TapUpDetails details) => _probeAt(details.globalPosition);

  void _onPanStart(DragStartDetails details) => _aimAt(details.globalPosition);

  void _onPanUpdate(DragUpdateDetails details) =>
      _aimAt(details.globalPosition);

  // Settles through the tap path at the last crosshair point, so a release
  // gives exactly what a tap there would. The SDK also routes a pointer
  // cancel of an accepted drag here, not to onPanCancel.
  void _onPanEnd(DragEndDetails _) {
    final aim = _aim;
    setState(() => _aim = null);
    if (aim != null) _probeAt(aim);
  }

  // shortcut: probes on every pointer move; throttle to once per frame if
  // drag jank shows up on large widget trees.
  void _aimAt(Offset globalPosition) {
    setState(() => _aim = globalPosition);
    _probeAt(globalPosition);
  }

  void _probeAt(Offset globalPosition) {
    final anchor = context.findRenderObject();
    if (anchor == null) return;
    final hit = probeLayoutAt(anchor, globalPosition);
    if (hit.isEmpty) return;
    _copiedTimer?.cancel();
    setState(() {
      _chain = hit;
      _index = 0;
      _copied = false;
    });
  }

  void _onParent() {
    if (_index >= _chain.length - 1) return;
    setState(() => _index++);
  }

  void _onChild() {
    if (_index <= 0) return;
    setState(() => _index--);
  }

  Future<void> _onCopy() async {
    if (_chain.isEmpty) return;
    final text = formatLayoutChain(
      _chain,
      mayBeObfuscated: widget.mayBeObfuscated,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _onShare() async {
    if (_chain.isEmpty) return;
    final text = formatLayoutChain(
      _chain,
      mayBeObfuscated: widget.mayBeObfuscated,
    );
    try {
      await shareText(text);
    } on Object catch (_) {
      await _onCopy();
    }
  }

  void _onClose() {
    if (LayoutInspectOverlay._entry == widget.entry) {
      LayoutInspectOverlay._entry = null;
    }
    widget.entry.remove();
  }

  @override
  Widget build(BuildContext context) {
    final level = _chain.isEmpty ? null : _chain[_index];
    final aim = _aim;
    final screenHeight = MediaQuery.of(context).size.height;
    final alignTop =
        _chain.isNotEmpty && _chain.first.rect.center.dy > screenHeight / 2;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: const SizedBox.expand(),
          ),
        ),
        if (level != null)
          Positioned.fromRect(
            rect: level.rect,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(
                      color: ThemeColor.color2196F3,
                      width: ThemeSize.space2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Align(
          alignment: alignTop ? Alignment.topCenter : Alignment.bottomCenter,
          child: _LayoutInfoCard(
            level: level,
            index: _index,
            total: _chain.length,
            mayBeObfuscated: widget.mayBeObfuscated,
            copied: _copied,
            onParent: _index < _chain.length - 1 ? _onParent : null,
            onChild: _index > 0 ? _onChild : null,
            onCopy: _onCopy,
            onShare: _onShare,
            onClose: _onClose,
          ),
        ),
        // Last child: the loupe magnifies what is painted before it,
        // including the frame.
        if (aim != null && widget.showLoupe) _Loupe(aim: aim),
      ],
    );
  }
}

class _Loupe extends StatelessWidget {
  const _Loupe({required this.aim});

  final Offset aim;

  @override
  Widget build(BuildContext context) {
    const radius = _loupeDiameter / 2;
    final screen = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final above = aim.dy - _loupeGap - radius;
    // shortcut: needs a screen >= 96 wide (clamp throws below that) and
    // >= 256 tall below the safe area; guard both if tiny windows matter.
    final center = Offset(
      aim.dx.clamp(radius, screen.width - radius),
      above - radius >= safeTop ? above : aim.dy + _loupeGap + radius,
    );
    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius,
      width: _loupeDiameter,
      height: _loupeDiameter,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(_loupeDiameter),
          magnificationScale: _loupeScale,
          focalPointOffset: aim - center,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(
                color: ThemeColor.color2196F3,
                width: ThemeSize.space2,
              ),
            ),
          ),
          // Crosshair: drawn over the lens, not magnified.
          child: const Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: _crosshairWidth,
                height: double.infinity,
                child: ColoredBox(color: ThemeColor.color2196F3),
              ),
              SizedBox(
                width: double.infinity,
                height: _crosshairWidth,
                child: ColoredBox(color: ThemeColor.color2196F3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutInfoCard extends StatelessWidget {
  const _LayoutInfoCard({
    required this.level,
    required this.index,
    required this.total,
    required this.mayBeObfuscated,
    required this.copied,
    required this.onParent,
    required this.onChild,
    required this.onCopy,
    required this.onShare,
    required this.onClose,
  });

  final LayoutLevel? level;
  final int index;
  final int total;
  final bool mayBeObfuscated;
  final bool copied;
  final VoidCallback? onParent;
  final VoidCallback? onChild;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final current = level;
    return SafeArea(
      child: Padding(
        padding: ThemePadding.paddingAll12,
        child: Material(
          elevation: ThemeSize.space4,
          borderRadius: BorderRadius.circular(ThemeSize.radius8),
          child: Padding(
            padding: ThemePadding.paddingAll12,
            child: current == null
                ? Row(
                    children: [
                      const Expanded(child: Text('Tap a widget to inspect')),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close layout inspector',
                        onPressed: onClose,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              current.widgetName != null
                                  ? '${current.widgetName} '
                                        '(${current.renderName})'
                                  : current.renderName,
                              style: ThemeTextStyle.boldStyle,
                            ),
                          ),
                          const SizedBox(width: ThemeSize.space8),
                          Text(
                            '${index + 1} / $total',
                            style: ThemeTextStyle.mutedSmallStyle,
                          ),
                        ],
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_upward),
                              tooltip: 'Parent',
                              onPressed: onParent,
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward),
                              tooltip: 'Child',
                              onPressed: onChild,
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy layout chain',
                              onPressed: onCopy,
                            ),
                            IconButton(
                              icon: const Icon(Icons.share),
                              tooltip: 'Share layout chain',
                              onPressed: onShare,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Close layout inspector',
                              onPressed: onClose,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'size: ${formatSize(current.size)}',
                        style: ThemeTextStyle.monospaceStyle,
                      ),
                      Text(
                        'constraints: '
                        '${formatConstraints(current.constraints)}',
                        style: ThemeTextStyle.monospaceStyle,
                      ),
                      Text(
                        'offset: ${formatOffset(current.rect.topLeft)}',
                        style: ThemeTextStyle.monospaceStyle,
                      ),
                      if (mayBeObfuscated)
                        const Padding(
                          padding: EdgeInsets.only(top: ThemeSize.space4),
                          child: Text(
                            'names may be obfuscated',
                            style: ThemeTextStyle.mutedSmallStyle,
                          ),
                        ),
                      if (copied)
                        const Padding(
                          padding: EdgeInsets.only(top: ThemeSize.space4),
                          child: Text(
                            'Copied',
                            style: TextStyle(
                              color: ThemeColor.color4CAF50,
                              fontSize: ThemeFontSize.fontSize12,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
