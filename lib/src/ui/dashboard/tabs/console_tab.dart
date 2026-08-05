import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/database_entry.dart';
import '../../../models/log_entry.dart';
import '../../../models/log_level.dart';
import '../../../models/navigator_entry.dart';
import '../../../models/network_entry.dart';
import '../../../models/timestamped_entry.dart';
import '../../../extensions/log_level_color_extension.dart';
import '../../../observers/inspector_route_names.dart';
import '../../theme/theme.dart';
import 'console/log_detail_view.dart';
import 'network/network_detail_view.dart';

/// Row background applied to error logs and failed network calls so they stand
/// out while scrolling a long merged timeline. Kept faint on purpose: the tint
/// marks the row without competing with the level-coloured text.
final Color _kErrorRowTint = ThemeColor.colorF44336.withOpacity(0.08);

/// Tab for displaying a cross-layer merged timeline (logs, network, navigation,
/// database) with a source filter and per-type row dispatch.
class ConsoleTab extends StatefulWidget {
  const ConsoleTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<ConsoleTab> {
  /// The currently selected timeline sources. Initialised to all four (the
  /// "All" state).
  Set<TimelineSource> _selected = {
    TimelineSource.log,
    TimelineSource.network,
    TimelineSource.nav,
    TimelineSource.db,
  };

  bool _showOnlyBookmarks = false;

  static const Set<TimelineSource> _all = {
    TimelineSource.log,
    TimelineSource.network,
    TimelineSource.nav,
    TimelineSource.db,
  };

  static const Map<TimelineSource, String> _sourceLabels = {
    TimelineSource.log: 'Log',
    TimelineSource.network: 'Network',
    TimelineSource.nav: 'Nav',
    TimelineSource.db: 'DB',
  };

  void _refresh() => setState(() {});

  /// Whether the filter currently equals "All" (every source selected).
  bool get _isAll => _selected.length == _all.length;

  void _selectAll() => setState(() => _selected = {..._all});

  void _selectOnly(TimelineSource source) =>
      setState(() => _selected = {source});

  @override
  Widget build(BuildContext context) {
    var entries = widget.inspector.mergedTimeline(sources: _selected);
    if (_showOnlyBookmarks) {
      entries =
          entries.where((e) => widget.inspector.isBookmarked(e)).toList();
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: ThemeSize.space8),
                    FilterChip(
                      label: const Text('All'),
                      selected: _isAll,
                      onSelected: (_) => _selectAll(),
                    ),
                    for (final source in TimelineSource.values) ...[
                      const SizedBox(width: ThemeSize.space8),
                      FilterChip(
                        label: Text(_sourceLabels[source] ?? ''),
                        selected: !_isAll && _selected.contains(source),
                        onSelected: (_) => _selectOnly(source),
                      ),
                    ],
                    const SizedBox(width: ThemeSize.space8),
                    FilterChip(
                      label: const Text('📌 Bookmarks'),
                      selected: _showOnlyBookmarks,
                      onSelected: (_) => setState(() {
                        _showOnlyBookmarks = !_showOnlyBookmarks;
                      }),
                    ),
                    const SizedBox(width: ThemeSize.space8),
                  ],
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                widget.inspector.clearLogs();
                widget.inspector.clearNetwork();
                widget.inspector.clearNavigator();
                widget.inspector.clearDatabase();
                _refresh();
              },
            ),
          ],
        ),
        Expanded(
          child: _showOnlyBookmarks && entries.isEmpty
              ? const Center(child: Text('No bookmarked entries'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _EntryRowDispatcher(
                    entry: entries[index],
                    inspector: widget.inspector,
                    onToggleBookmark: () => setState(() {
                      widget.inspector.toggleBookmark(entries[index]);
                    }),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Dispatches a [TimestampedEntry] to the matching row visual by runtime type.
class _EntryRowDispatcher extends StatelessWidget {
  const _EntryRowDispatcher({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final TimestampedEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    switch (entry) {
      case final LogEntry e:
        return _LogEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      case final NetworkEntry e:
        return _NetworkEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      case final NavigatorEntry e:
        return _NavigatorEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      case final DatabaseEntry e:
        return _DatabaseEntryRow(
          entry: e,
          inspector: inspector,
          onToggleBookmark: onToggleBookmark,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final LogEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final canTap =
        (entry.stackTrace?.isNotEmpty ?? false) ||
        (entry.data?.isNotEmpty ?? false);
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      tileColor: entry.level == LogLevel.error ? _kErrorRowTint : null,
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(Icons.push_pin,
                size: ThemeSize.size18, color: ThemeColor.colorFF9800),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(color: entry.level.color),
            ),
          ),
        ],
      ),
      subtitle: Text(entry.displayTime),
      trailing: canTap
          ? const Icon(Icons.chevron_right, size: ThemeSize.size18)
          : null,
      onTap: canTap
          ? () => pushInspectorRoute(
                context,
                kInspectorLogDetailRoute,
                (_) => LogDetailView(entry: entry),
              )
          : null,
      onLongPress: onToggleBookmark,
    );
  }
}

class _NetworkEntryRow extends StatelessWidget {
  const _NetworkEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final NetworkEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      tileColor: entry.isFailed ? _kErrorRowTint : null,
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(Icons.push_pin,
                size: ThemeSize.size18, color: ThemeColor.colorFF9800),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(
            child: Text(
              '${entry.method} ${entry.statusCode ?? '-'} ${entry.url}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(entry.displayTime),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.duration != null &&
              entry.duration! >= inspector.slowRequestThreshold)
            Container(
              margin: const EdgeInsets.only(right: ThemeSize.space8),
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeSize.space4,
                vertical: 2.0,
              ),
              decoration: BoxDecoration(
                color: ThemeColor.colorFF9800.withOpacity(0.15),
                borderRadius: BorderRadius.circular(ThemeSize.radius4),
                border: Border.all(color: ThemeColor.colorFF9800),
              ),
              child: const Text(
                '🐢 SLOW',
                style: TextStyle(
                  fontSize: ThemeFontSize.fontSize10,
                  color: ThemeColor.colorFF9800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const Icon(Icons.chevron_right, size: ThemeSize.size18),
        ],
      ),
      onTap: () => pushInspectorRoute(
        context,
        kInspectorNetworkDetailRoute,
        (_) => NetworkDetailView(
          entry: entry,
          redactSensitiveData: inspector.redactSensitiveData,
        ),
      ),
      onLongPress: onToggleBookmark,
    );
  }
}

class _NavigatorEntryRow extends StatelessWidget {
  const _NavigatorEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final NavigatorEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(Icons.push_pin,
                size: ThemeSize.size18, color: ThemeColor.colorFF9800),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(
            child: Text('${entry.action.name} ${entry.displayName}'),
          ),
        ],
      ),
      subtitle: Text(entry.displayTime),
      onLongPress: onToggleBookmark,
    );
  }
}

class _DatabaseEntryRow extends StatelessWidget {
  const _DatabaseEntryRow({
    required this.entry,
    required this.inspector,
    required this.onToggleBookmark,
  });

  final DatabaseEntry entry;
  final FlutterInspector inspector;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final isBookmarked = inspector.isBookmarked(entry);
    return ListTile(
      title: Row(
        children: [
          if (isBookmarked) ...[
            const Icon(Icons.push_pin,
                size: ThemeSize.size18, color: ThemeColor.colorFF9800),
            const SizedBox(width: ThemeSize.space4),
          ],
          Expanded(
            child: Text('${entry.operation.name} ${entry.tableName}'),
          ),
        ],
      ),
      subtitle: Text(entry.displayTime),
      onLongPress: onToggleBookmark,
    );
  }
}
