import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/key_value_browser_source.dart';
import '../../theme/theme.dart';
import '../../widgets/error_card.dart';

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
  bool _isFetching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.inspector.keyValueSources.first;
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    if (!mounted || _isFetching) return;
    _isFetching = true;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final entries = await _selectedSource.listAll();
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    } finally {
      _isFetching = false;
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
      itemBuilder: (context, index) => _EntryRow(entry: visible[index]),
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
  const _EntryRow({required this.entry});

  final KeyValueEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(entry.key),
      subtitle: Text('${entry.value}'),
      trailing: Text(
        entry.type.name,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
