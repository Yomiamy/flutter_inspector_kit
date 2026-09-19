import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// Hard stop for nesting; deeper containers render as a truncation leaf.
const int _kMaxDepth = 32;

/// Containers at depth 0 and 1 start expanded.
const int _kDefaultExpandDepth = 2;

/// Below this many nodes the whole tree fits on screen, so the search field
/// would cost more room than it saves.
const int _kSearchMinNodes = 20;

/// Ceiling on rows laid out at once. Collapsing bounds a deep tree, but not a
/// wide one: a 2000-element array sits entirely at depth 1 and would other-
/// wise be built in full. Nobody reads 2000 rows anyway — past this point the
/// tree is a scrolling wall, so it is cut off and the count reported instead.
const int _kMaxRows = 300;

enum JsonKind { map, list, leaf }

/// A single row in the flattened tree. Immutable — expansion state lives
/// outside, in the widget's set of expanded node ids.
class JsonNode {
  const JsonNode({
    required this.id,
    required this.parentId,
    required this.path,
    required this.label,
    required this.depth,
    required this.kind,
    required this.valueText,
  });

  /// Structural identity: the chain of sibling ordinals, e.g. `0.3.1`.
  /// Derived from traversal order, never from key content, so it cannot
  /// collide no matter what characters a map key contains.
  final String id;

  /// Id of the owning container; '' for children of the root.
  final String parentId;

  /// Human-readable path for display and copy, e.g. `data.users[0].id`.
  /// Two nodes may share a path when a key contains '.'; harmless because
  /// this field never keys state.
  final String path;

  /// Display key: `id` for a map entry, `[0]` for a list element, '' for
  /// the root.
  final String label;

  final int depth;

  final JsonKind kind;

  /// Rendered value: `toString()` for leaves, `{3}` / `[12]` for containers.
  final String valueText;
}

/// Classifies a value into a kind plus its rendered text.
(JsonKind, String) _describe(Object? value) {
  if (value is Map) return (JsonKind.map, '{${value.length}}');
  if (value is List) return (JsonKind.list, '[${value.length}]');
  return (JsonKind.leaf, '$value');
}

/// Re-encodes [value] as indented JSON for the raw view. Values that are not
/// JSON-native (DateTime, custom objects) fall back to `toString()`, matching
/// how the tree renders them as leaves.
///
/// Self-referential data has no raw form to show at all: the encoder throws
/// [JsonCyclicError] rather than consulting `toEncodable`, so the tree — which
/// marks the cycle and keeps going — stays the only way to inspect it.
String _rawJson(Object? value) {
  try {
    return JsonEncoder.withIndent('  ', (o) => o.toString()).convert(value);
  } on JsonCyclicError {
    return '… (circular reference — switch back to the tree to inspect it)';
  }
}

/// One pending traversal entry: either a value to emit, or a marker that
/// pops the ancestor stack when its subtree is done.
class _Frame {
  const _Frame(
    this.value,
    this.id,
    this.parentId,
    this.path,
    this.label,
    this.depth, {
    this.isPop = false,
  });

  final Object? value;
  final String id;
  final String parentId;
  final String path;
  final String label;
  final int depth;
  final bool isPop;
}

/// Flattens [root] into a pre-order list: a parent always precedes all of
/// its descendants. Guards against runaway depth and cyclic references.
@visibleForTesting
List<JsonNode> flattenJson(Object? root) {
  final out = <JsonNode>[];
  final ancestors = <Object>[];
  final stack = <_Frame>[_Frame(root, '0', '', '', '', 0)];

  while (stack.isNotEmpty) {
    final f = stack.removeLast();
    if (f.isPop) {
      ancestors.removeLast();
      continue;
    }

    final value = f.value;
    final cyclic = value != null && ancestors.any((a) => identical(a, value));
    final tooDeep = f.depth >= _kMaxDepth;
    var (kind, text) = _describe(value);

    if (kind != JsonKind.leaf && (cyclic || tooDeep)) {
      kind = JsonKind.leaf;
      text = cyclic ? '… (circular reference)' : '… (max depth reached)';
    }

    final children = kind == JsonKind.map
        ? (value as Map).entries.toList()
        : kind == JsonKind.list
        ? (value as List).indexed
              .map((e) => MapEntry<Object?, Object?>(e.$1, e.$2))
              .toList()
        : const <MapEntry<Object?, Object?>>[];

    out.add(
      JsonNode(
        id: f.id,
        parentId: f.parentId,
        path: f.path,
        label: f.label,
        depth: f.depth,
        kind: kind,
        valueText: text,
      ),
    );

    if (children.isEmpty) continue;

    ancestors.add(value as Object);
    stack.add(_Frame(null, '', '', '', '', 0, isPop: true));
    for (var i = children.length - 1; i >= 0; i--) {
      final label = kind == JsonKind.map
          ? '${children[i].key}'
          : '[${children[i].key}]';
      final path = kind == JsonKind.map
          ? (f.path.isEmpty ? label : '${f.path}.$label')
          : '${f.path}$label';
      stack.add(
        _Frame(children[i].value, '${f.id}.$i', f.id, path, label, f.depth + 1),
      );
    }
  }
  return out;
}

/// Collapsible tree view for already-decoded JSON-like data.
class JsonTreeViewer extends StatefulWidget {
  /// [data] is already-decoded JSON-like data (Map / List / primitive).
  const JsonTreeViewer(this.data, {this.emptyLabel, super.key});

  final Object? data;

  /// Shown when [data] is null or an empty container.
  final String? emptyLabel;

  @override
  State<JsonTreeViewer> createState() => _JsonTreeViewerState();
}

class _JsonTreeViewerState extends State<JsonTreeViewer> {
  final TextEditingController _searchController = TextEditingController();
  late List<JsonNode> _all;
  late Map<String, JsonNode> _byId;
  late Set<String> _expanded;
  String _query = '';
  bool _raw = false;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(JsonTreeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _rebuild();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _rebuild() {
    _all = flattenJson(widget.data);
    _byId = {for (final n in _all) n.id: n};
    _expanded = {
      for (final n in _all)
        if (n.depth < _kDefaultExpandDepth && n.kind != JsonKind.leaf) n.id,
    };
    // New data may drop below the threshold and take the search field with
    // it; a stale query would then filter the tree with no way to clear it.
    if (_all.length < _kSearchMinNodes) {
      _query = '';
      _searchController.clear();
    }
  }

  bool get _isEmpty {
    final data = widget.data;
    return data == null ||
        (data is Map && data.isEmpty) ||
        (data is List && data.isEmpty);
  }

  List<JsonNode> _visibleNodes() {
    final q = _query.toLowerCase();
    Set<String>? keep;
    if (q.isNotEmpty) {
      keep = <String>{};
      for (final n in _all) {
        if (!n.label.toLowerCase().contains(q) &&
            !n.valueText.toLowerCase().contains(q)) {
          continue;
        }
        for (var cur = n; ;) {
          keep.add(cur.id);
          final parent = _byId[cur.parentId];
          if (parent == null) break;
          cur = parent;
        }
      }
    }

    return [
      for (final n in _all)
        if (keep == null || keep.contains(n.id))
          if (_isReachable(n, keep)) n,
    ];
  }

  /// A node shows only when every ancestor up to the root is expanded.
  /// Checking just the parent is not enough: collapsing a grandparent would
  /// otherwise leave an already-expanded child on screen, detached from the
  /// branch that was folded away.
  bool _isReachable(JsonNode node, Set<String>? keep) {
    for (var id = node.parentId; id.isNotEmpty;) {
      if (_expanded.contains(id)) {
        final parent = _byId[id];
        if (parent == null) break;
        id = parent.parentId;
        continue;
      }
      // While searching, the chain down to a hit stays forced open.
      if (keep != null && keep.contains(id)) return true;
      return false;
    }
    return true;
  }

  void _toggle(String id) => setState(() {
    if (!_expanded.remove(id)) _expanded.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final emptyLabel = widget.emptyLabel;
    if (_isEmpty && emptyLabel != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ThemeSize.space4),
        child: Text(
          emptyLabel,
          style: TextStyle(
            color: Theme.of(context).disabledColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final visible = _raw ? const <JsonNode>[] : _visibleNodes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _raw = !_raw),
            icon: Icon(
              _raw ? Icons.account_tree : Icons.notes,
              size: ThemeSize.size16,
            ),
            label: Text(_raw ? 'Show tree' : 'Show raw'),
          ),
        ),
        // Raw mode restores the selectable plain text the tree replaced, so
        // an arbitrary span can still be highlighted and copied by hand.
        if (_raw)
          SelectableText(
            _rawJson(widget.data),
            style: ThemeTextStyle.monospaceStyle,
          ),
        if (!_raw && _all.length >= _kSearchMinNodes) ...[
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: ThemeSize.size16),
              hintText: 'Search',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: ThemeSize.space8),
        ],
        // Both detail views place this inside their own scrolling ListView,
        // which hands children unbounded height. A nested scrollable there
        // would shrink-wrap and build every row anyway, so the rows are laid
        // out directly and the outer list does the scrolling. Row count is
        // bounded by _kMaxRows rather than by lazy building.
        if (!_raw)
          for (final node in visible.take(_kMaxRows))
            JsonNodeRow(
              node,
              isExpanded: _expanded.contains(node.id),
              onToggle: node.kind == JsonKind.leaf
                  ? null
                  : () => _toggle(node.id),
              query: _query,
            ),
        if (!_raw && visible.length > _kMaxRows)
          Padding(
            padding: const EdgeInsets.only(top: ThemeSize.space4),
            child: Text(
              '… ${visible.length - _kMaxRows} more rows hidden — '
              'collapse a branch or search to narrow it down',
              style: TextStyle(
                color: Theme.of(context).disabledColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

/// A single flattened row: indent, expand affordance, `label:` and value.
@visibleForTesting
class JsonNodeRow extends StatelessWidget {
  const JsonNodeRow(
    this.node, {
    required this.isExpanded,
    required this.onToggle,
    required this.query,
    super.key,
  });

  final JsonNode node;
  final bool isExpanded;
  final VoidCallback? onToggle;
  final String query;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = node.path.isEmpty
        ? node.valueText
        : '${node.path}: ${node.valueText}';
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final label = node.label.isEmpty ? '' : '${node.label}: ';
    return InkWell(
      onTap: onToggle,
      onLongPress: () => _copy(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ThemeSize.space2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: node.depth * ThemeSize.space12),
            SizedBox(
              width: ThemeSize.size16,
              child: onToggle == null
                  ? null
                  : Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: ThemeSize.size16,
                    ),
            ),
            Expanded(
              child: HighlightedText('$label${node.valueText}', query: query),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders [text] in monospace, tinting occurrences of [query]. Falls back
/// to a plain [Text] when [query] is empty so `find.text` keeps working.
@visibleForTesting
class HighlightedText extends StatelessWidget {
  const HighlightedText(this.text, {required this.query, super.key});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: ThemeTextStyle.monospaceStyle);
    }

    final hit = TextStyle(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    );
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final at = lower.indexOf(q, i);
      if (at < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (at > i) spans.add(TextSpan(text: text.substring(i, at)));
      spans.add(TextSpan(text: text.substring(at, at + q.length), style: hit));
      i = at + q.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      style: ThemeTextStyle.monospaceStyle,
    );
  }
}
