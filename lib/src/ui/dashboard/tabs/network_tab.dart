import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/network_entry.dart';
import '../../../utils/network_formatters.dart';
import '../../../utils/network_utils.dart';
import 'network/network_detail_view.dart';

/// Tab for displaying network requests with keyword search and filtering.
class NetworkTab extends StatefulWidget {
  const NetworkTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _methods = <String>{};
  final Set<NetworkStatusGroup> _statusGroups = <NetworkStatusGroup>{};
  String _keyword = '';

  NetworkFilter get _filter => NetworkFilter(
    keyword: _keyword,
    methods: _methods,
    statusGroups: _statusGroups,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final networkEntries = widget.inspector.networkEntries;
    final entries = applyNetworkFilter(networkEntries, _filter);

    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          keyword: _keyword,
          total: networkEntries.length,
          shown: entries.length,
          onKeywordChanged: (value) => setState(() => _keyword = value),
          onRefresh: _refresh,
          onClearAll: () {
            widget.inspector.clearNetwork();
            _refresh();
          },
        ),
        _FilterChips(
          selectedMethods: _methods,
          selectedStatusGroups: _statusGroups,
          onMethodSelected: (method, selected) =>
              _toggle(_methods, method, selected),
          onStatusGroupSelected: (group, selected) =>
              _toggle(_statusGroups, group, selected),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    networkEntries.isEmpty
                        ? 'No network requests'
                        : 'No matches',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _EntryTile(
                    entry: entries[index],
                    redactSensitiveData: widget.inspector.redactSensitiveData,
                  ),
                ),
        ),
      ],
    );
  }

  void _toggle<T>(Set<T> set, T value, bool selected) => setState(() {
    if (selected) {
      set.add(value);
    } else {
      set.remove(value);
    }
  });



  void _refresh() => setState(() {});
}

/// Search field with refresh and clear-all actions for the Network tab.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String keyword;
  final int total;
  final int shown;
  final ValueChanged<String> onKeywordChanged;
  final VoidCallback onRefresh;
  final VoidCallback onClearAll;

  const _SearchBar({
    required this.controller,
    required this.keyword,
    required this.total,
    required this.shown,
    required this.onKeywordChanged,
    required this.onRefresh,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search url / method / status',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          controller.clear();
                          onKeywordChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: onKeywordChanged,
            ),
          ),
          IconButton(
            tooltip: 'Refresh ($shown/$total)',
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete),
            onPressed: onClearAll,
          ),
        ],
      ),
    );
  }
}

/// Horizontal chips filtering by HTTP method and status group.
class _FilterChips extends StatelessWidget {
  final Set<String> selectedMethods;
  final Set<NetworkStatusGroup> selectedStatusGroups;
  final void Function(String method, bool selected) onMethodSelected;
  final void Function(NetworkStatusGroup group, bool selected)
  onStatusGroupSelected;

  const _FilterChips({
    required this.selectedMethods,
    required this.selectedStatusGroups,
    required this.onMethodSelected,
    required this.onStatusGroupSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final method in httpMethods)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(method),
                selected: selectedMethods.contains(method),
                onSelected: (selected) => onMethodSelected(method, selected),
              ),
            ),
          const SizedBox(width: 8),
          for (final group in statusLabels.keys)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(statusLabels[group]!),
                selected: selectedStatusGroups.contains(group),
                onSelected: (selected) =>
                    onStatusGroupSelected(group, selected),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single network request row that opens [NetworkDetailView] on tap.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.redactSensitiveData});

  final NetworkEntry entry;
  final bool redactSensitiveData;

  @override
  Widget build(BuildContext context) {
    final statusColor = statusColorFor(entry.statusCode, entry.error != null);
    final statusText = entry.isComplete
        ? '${entry.statusCode ?? entry.error ?? '-'}'
        : 'Pending';
    final totalSize = entry.requestSizeBytes + entry.responseSizeBytes;

    return ListTile(
      dense: true,
      leading: _MethodBadge(method: entry.method, color: statusColor),
      title: Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$statusText · ${entry.duration?.inMilliseconds ?? '-'} ms · '
        '${formatBytes(totalSize)} · ${timeOf(entry.timestamp)}',
        style: TextStyle(color: entry.error != null ? statusColor : null),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NetworkDetailView(
            entry: entry,
            redactSensitiveData: redactSensitiveData,
          ),
        ),
      ),
    );
  }
}

/// A small colored pill showing the HTTP method.
class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method, required this.color});

  final String method;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        method.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
