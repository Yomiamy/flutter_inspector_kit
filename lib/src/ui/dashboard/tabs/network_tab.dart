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
    final all = widget.inspector.networkEntries;
    final entries = applyNetworkFilter(all, _filter);

    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          keyword: _keyword,
          total: all.length,
          shown: entries.length,
          onKeywordChanged: (value) => setState(() => _keyword = value),
          onRefresh: _refresh,
          onClearAll: () {
            widget.inspector.clearNetwork();
            _refresh();
          },
        ),
        _buildFilterChips(),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    all.isEmpty ? 'No network requests' : 'No matches',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _buildEntryTile(entries[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
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
                selected: _methods.contains(method),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _methods.add(method);
                  } else {
                    _methods.remove(method);
                  }
                }),
              ),
            ),
          const SizedBox(width: 8),
          for (final group in statusLabels.keys)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(statusLabels[group]!),
                selected: _statusGroups.contains(group),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _statusGroups.add(group);
                  } else {
                    _statusGroups.remove(group);
                  }
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(NetworkEntry entry) {
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
        '${formatBytes(totalSize)} · ${_timeOf(entry.timestamp)}',
        style: TextStyle(color: entry.error != null ? statusColor : null),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NetworkDetailView(
            entry: entry,
            redactSensitiveData: widget.inspector.redactSensitiveData,
          ),
        ),
      ),
    );
  }

  String _timeOf(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  void _refresh() => setState(() {});
}

/// Search field with refresh and clear-all actions for the Network tab.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.keyword,
    required this.total,
    required this.shown,
    required this.onKeywordChanged,
    required this.onRefresh,
    required this.onClearAll,
  });

  final TextEditingController controller;
  final String keyword;
  final int total;
  final int shown;
  final ValueChanged<String> onKeywordChanged;
  final VoidCallback onRefresh;
  final VoidCallback onClearAll;

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
