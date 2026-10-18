import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/layout_formatters.dart';
import '../../utils/share_text.dart';
import '../theme/theme.dart';
import 'layout_probe.dart';

/// Manages the tap-to-inspect layout overlay entry.
abstract final class LayoutInspectOverlay {
  static OverlayEntry? _entry;

  /// Inserts the layout inspection overlay into [overlay].
  ///
  /// Repeated calls while the overlay is already active are ignored.
  static void show(OverlayState overlay, {bool? mayBeObfuscated}) {
    if (_entry != null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => LayoutProbeShield(
        child: _LayoutInspectLayer(
          entry: entry,
          mayBeObfuscated: mayBeObfuscated ?? !kDebugMode,
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
  });

  final OverlayEntry entry;
  final bool mayBeObfuscated;

  @override
  State<_LayoutInspectLayer> createState() => _LayoutInspectLayerState();
}

class _LayoutInspectLayerState extends State<_LayoutInspectLayer> {
  List<LayoutLevel> _chain = const [];
  int _index = 0;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    if (LayoutInspectOverlay._entry == widget.entry) {
      LayoutInspectOverlay._entry = null;
    }
    super.dispose();
  }

  void _onTapUp(TapUpDetails details) {
    final anchor = context.findRenderObject();
    if (anchor == null) return;
    final hit = probeLayoutAt(anchor, details.globalPosition);
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
    final screenHeight = MediaQuery.of(context).size.height;
    final alignTop =
        _chain.isNotEmpty && _chain.first.rect.center.dy > screenHeight / 2;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
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
      ],
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
