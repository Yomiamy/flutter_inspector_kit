import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/key_value_browser_source.dart';
import '../../theme/theme.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_card.dart';
import 'storage/key_value_edit_dialog.dart';

/// Tab for browsing key-value stores such as SharedPreferences.
///
/// Only mounted when the host app registers at least one
/// [KeyValueBrowserSource]; see `DashboardModal`.
class StorageTab extends StatefulWidget {
  const StorageTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<StorageTab> createState() => _StorageTabState();
}

/// Filters [entries] by [query], matching either key or value.
///
/// Case-insensitive; an empty query returns everything.
List<KeyValueEntry> filterKeyValueEntries(
  List<KeyValueEntry> entries,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return entries
      .where(
        (e) =>
            e.key.toLowerCase().contains(q) ||
            '${e.value}'.toLowerCase().contains(q),
      )
      .toList();
}

class _StorageTabState extends State<StorageTab> {
  late KeyValueBrowserSource _selectedSource;
  List<KeyValueEntry> _entries = [];
  String _query = '';
  bool _loading = true;
  String? _errorMessage;

  /// Identifies the newest load; older responses are discarded on arrival.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.inspector.keyValueSources.first;
    _loadEntries();
  }

  /// Loads the selected source, ignoring any response that has been superseded.
  ///
  /// Blocking concurrent loads instead would drop the newer request: switching
  /// source during a slow load would leave the old source's data on screen
  /// under the new source's name — and this tab can delete what it shows.
  Future<void> _loadEntries() async {
    if (!mounted) return;
    final requestId = ++_requestId;
    final source = _selectedSource;
    setState(() {
      _loading = true;
      _errorMessage = null;
      // Drop the previous source's rows immediately: keeping them visible
      // would let a destructive action be authorised by another source's data.
      _entries = const [];
    });

    try {
      final entries = await source.listAll();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  /// Two-stage edit: type-checked input, then an explicit confirmation.
  ///
  /// Every await is followed by a mounted check — this widget lives in a tab
  /// the user can leave mid-dialog (flutter-styles §7.5).
  Future<void> _editEntry(KeyValueEntry entry) async {
    final newValue = await showKeyValueEditDialog(context, entry: entry);
    if (!mounted || newValue == null) return;

    final confirmed = await showInspectorConfirm(
      context,
      title: 'Update ${entry.key}?',
      message: '${entry.value}  →  $newValue',
    );
    if (!mounted || !confirmed) return;
    await _runWrite(
      () => _selectedSource.setValue(entry.key, newValue),
      auditMessage: '[KV] set "${entry.key}" on ${_selectedSource.name}',
      auditData: {
        'source': _selectedSource.name,
        'key': entry.key,
        'oldValue': entry.value,
        'newValue': newValue,
      },
    );
  }

  Future<void> _deleteEntry(KeyValueEntry entry) async {
    final confirmed = await showInspectorConfirm(
      context,
      title: 'Delete ${entry.key}?',
      message: 'Current value: ${entry.value}',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    await _runWrite(
      () => _selectedSource.remove(entry.key),
      auditMessage: '[KV] removed "${entry.key}" from ${_selectedSource.name}',
      auditData: {
        'source': _selectedSource.name,
        'key': entry.key,
        'oldValue': entry.value,
      },
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showInspectorConfirm(
      context,
      title: 'Clear ${_selectedSource.name}?',
      message:
          'This removes all ${_entries.length} entries. '
          'It cannot be undone.',
      confirmLabel: 'Clear all',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    final clearedCount = _entries.length;
    await _runWrite(
      _selectedSource.clear,
      auditMessage: '[KV] cleared ${_selectedSource.name}',
      auditData: {'source': _selectedSource.name, 'clearedCount': clearedCount},
    );
  }

  /// Builds audit data, masking values when redaction is on.
  ///
  /// Log `data` reaches the clipboard and the share sheet via
  /// `buildLogPlainText`, and a key-value source may well be secure storage —
  /// so values follow the same rule as sensitive network headers. Key, source
  /// and type stay visible: they are what makes the trail useful.
  Map<String, dynamic> _auditData(Map<String, dynamic> values) {
    if (!widget.inspector.redactSensitiveData) return values;
    return {
      for (final entry in values.entries)
        entry.key: _valueKeys.contains(entry.key) ? '***' : entry.value,
    };
  }

  static const _valueKeys = {'oldValue', 'newValue'};

  /// Runs a write, records an audit log, then reloads.
  ///
  /// The log is written only after [write] returns, so a failed write never
  /// leaves a trace claiming it succeeded (AC-28).
  Future<void> _runWrite(
    Future<void> Function() write, {
    required String auditMessage,
    required Map<String, dynamic> auditData,
  }) async {
    try {
      await write();
      // Logged before the mounted check on purpose: the write already
      // happened, so leaving the tab must not erase the trace.
      widget.inspector.log(auditMessage, data: _auditData(auditData));
      if (!mounted) return;
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.inspector.keyValueSources;

    return Column(
      children: [
        Padding(
          padding: ThemePadding.paddingH16V8,
          child: Row(
            children: [
              if (sources.length > 1)
                DropdownButton<KeyValueBrowserSource>(
                  value: _selectedSource,
                  onChanged: (source) {
                    if (source != null) {
                      setState(() {
                        _selectedSource = source;
                      });
                      _loadEntries();
                    }
                  },
                  items: sources.map((source) {
                    return DropdownMenuItem<KeyValueBrowserSource>(
                      value: source,
                      child: Text(source.name),
                    );
                  }).toList(),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _loadEntries,
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Clear all',
                onPressed: (_loading || _entries.isEmpty) ? null : _clearAll,
              ),
            ],
          ),
        ),
        _KvSearchBar(onChanged: (q) => setState(() => _query = q)),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return ErrorCard(message: _errorMessage!, onRetry: _loadEntries);
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('No entries in this source'));
    }
    final visible = filterKeyValueEntries(_entries, _query);
    if (visible.isEmpty) {
      // Distinct from the empty state: the store has keys, the query matched none.
      return const Center(child: Text('No matching entries'));
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) => _EntryRow(
        entry: visible[index],
        onEdit: () => _editEntry(visible[index]),
        onDelete: () => _deleteEntry(visible[index]),
      ),
    );
  }
}

// ponytail: 專案內第三份搜尋欄實作，已知技術債，使用者拍板不抽共用元件（R-2 選 A）
class _KvSearchBar extends StatefulWidget {
  const _KvSearchBar({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_KvSearchBar> createState() => _KvSearchBarState();
}

class _KvSearchBarState extends State<_KvSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ThemePadding.paddingH16V8,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search),
          hintText: 'Search keys and values',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final KeyValueEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(entry.key),
      subtitle: Text('${entry.value}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(entry.type.name, style: Theme.of(context).textTheme.bodySmall),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
