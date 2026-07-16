import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/network_entry.dart';
import '../../../utils/network_formatters.dart';
import '../../../utils/network_utils.dart';
import '../../theme/theme.dart';
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
  NetworkErrorGroup? _selectedErrorGroup;
  bool _errorSummaryExpanded = true;

  NetworkFilter get _filter => NetworkFilter(
    keyword: _searchController.text,
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
    // filteredEntries: keyword/method/status filter only — feeds the error
    // summary banner so every group card stays visible after one is selected.
    final filteredEntries = applyNetworkFilter(networkEntries, _filter);
    // entries: narrowed further by the selected error group — feeds the list.
    final group = _selectedErrorGroup;
    final entries = group == null
        ? filteredEntries
        : filteredEntries
              .where(
                (e) =>
                    e.error != null || (e.statusCode ?? 0) >= 400,
              )
              .where(
                (e) => group.statusCode != null
                    ? e.statusCode == group.statusCode
                    : e.errorType == group.errorType,
              )
              .toList(growable: false);

    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          total: networkEntries.length,
          shown: entries.length,
          onKeywordChanged: (_) => setState(() {}),
          onRefresh: _refresh,
          onClearAll: () {
            widget.inspector.clearNetwork();
            _selectedErrorGroup = null;
            _refresh();
          },
        ),
        _ErrorSummaryBanner(
          entries: filteredEntries,
          selectedGroup: _selectedErrorGroup,
          expanded: _errorSummaryExpanded,
          onGroupTap: (group) => setState(() {
            _selectedErrorGroup = _selectedErrorGroup == group ? null : group;
          }),
          onExpandToggle: () => setState(() {
            _errorSummaryExpanded = !_errorSummaryExpanded;
          }),
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
  final int total;
  final int shown;
  final ValueChanged<String> onKeywordChanged;
  final VoidCallback onRefresh;
  final VoidCallback onClearAll;

  const _SearchBar({
    required this.controller,
    required this.total,
    required this.shown,
    required this.onKeywordChanged,
    required this.onRefresh,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeSpacing.spacing8,
        ThemeSpacing.spacing8,
        ThemeSpacing.spacing4,
        ThemeSpacing.spacing4,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search url / method / status',
                prefixIcon: const Icon(Icons.search, size: ThemeSize.size20),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: ThemeSize.size18),
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
      height: ThemeSize.size44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: ThemePadding.paddingH8,
        children: [
          for (final method in httpMethods)
            Padding(
              padding: const EdgeInsets.only(right: ThemeSpacing.spacing8),
              child: FilterChip(
                label: Text(method),
                selected: selectedMethods.contains(method),
                onSelected: (selected) => onMethodSelected(method, selected),
              ),
            ),
          const SizedBox(width: ThemeSpacing.spacing8),
          for (final group in statusLabels.keys)
            Padding(
              padding: const EdgeInsets.only(right: ThemeSpacing.spacing8),
              child: FilterChip(
                label: Text(statusLabels[group] ?? ''),
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
    final statusColor = ThemeColor.statusColor(
      entry.statusCode,
      hasError: entry.error != null,
    );
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
      trailing: const Icon(Icons.chevron_right, size: ThemeSize.size18),
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
      width: ThemeSize.size56,
      padding: const EdgeInsets.symmetric(vertical: ThemeSpacing.spacing4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(ThemeRadius.radius4),
        border: Border.all(color: color),
      ),
      child: Text(
        method.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: ThemeFontSize.fontSize11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Banner displaying aggregated network errors.
class _ErrorSummaryBanner extends StatelessWidget {
  const _ErrorSummaryBanner({
    required this.entries,
    required this.selectedGroup,
    required this.expanded,
    required this.onGroupTap,
    required this.onExpandToggle,
  });

  final List<NetworkEntry> entries;
  final NetworkErrorGroup? selectedGroup;
  final bool expanded;
  final ValueChanged<NetworkErrorGroup> onGroupTap;
  final VoidCallback onExpandToggle;

  @override
  Widget build(BuildContext context) {
    final groups = aggregateNetworkErrors(entries);
    if (groups.isEmpty) return const SizedBox.shrink();

    if (!expanded) {
      return InkWell(
        onTap: onExpandToggle,
        child: Padding(
          padding: ThemePadding.paddingAll8,
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: ThemeSize.size16,
                color: ThemeColor.colorFF9800,
              ),
              const SizedBox(width: ThemeSpacing.spacing8),
              Text(
                '⚠ ${groups.fold(0, (sum, g) => sum + g.count)} errors '
                '(${groups.length} types)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              const Icon(Icons.expand_more, size: ThemeSize.size16),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeSpacing.spacing12,
            ThemeSpacing.spacing8,
            ThemeSpacing.spacing12,
            0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Error Summary',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              InkWell(
                onTap: onExpandToggle,
                child: const Icon(Icons.expand_less, size: ThemeSize.size16),
              ),
            ],
          ),
        ),
        SizedBox(
          height: ThemeSize.size72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: ThemePadding.paddingH8,
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return _ErrorGroupCard(
                group: group,
                selected: group == selectedGroup,
                onTap: () => onGroupTap(group),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorGroupCard extends StatelessWidget {
  const _ErrorGroupCard({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  // Special case: inner bar radius is the card radius (radiusMd=8) minus the
  // 1px border, so the color bar's rounded corner sits flush inside the frame.
  static const double _colorBarBorderRadius = ThemeRadius.radius8 - 1;

  final NetworkErrorGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = ThemeColor.statusColor(group.statusCode, hasError: true);

    return Padding(
      padding: const EdgeInsets.only(right: ThemeSpacing.spacing8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeRadius.radius8),
        child: Container(
          width: ThemeSize.size140,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? color : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(ThemeRadius.radius8),
            color: selected ? color.withValues(alpha: 0.1) : null,
          ),
          child: Row(
            children: [
              Container(
                width: ThemeSpacing.spacing4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(_colorBarBorderRadius),
                    bottomLeft: Radius.circular(_colorBarBorderRadius),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: ThemePadding.paddingAll8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '×${group.count}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: ThemeSpacing.spacing4),
                      Text(
                        '${timeOf(group.firstSeen)} - ${timeOf(group.lastSeen)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: ThemeFontSize.fontSize10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
