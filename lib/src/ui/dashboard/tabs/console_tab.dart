import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/database_entry.dart';
import '../../../models/log_entry.dart';
import '../../../models/navigator_entry.dart';
import '../../../models/network_entry.dart';
import '../../../models/timestamped_entry.dart';
import '../../../extensions/log_level_color_extension.dart';
import '../../theme/inspector_theme.dart';
import 'console/log_detail_view.dart';
import 'network/network_detail_view.dart';

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
    final entries = widget.inspector.mergedTimeline(sources: _selected);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: ThemeSpacing.spacing8),
                    FilterChip(
                      label: const Text('All'),
                      selected: _isAll,
                      onSelected: (_) => _selectAll(),
                    ),
                    for (final source in TimelineSource.values) ...[
                      const SizedBox(width: ThemeSpacing.spacing8),
                      FilterChip(
                        label: Text(_sourceLabels[source] ?? ''),
                        selected: !_isAll && _selected.contains(source),
                        onSelected: (_) => _selectOnly(source),
                      ),
                    ],
                    const SizedBox(width: ThemeSpacing.spacing8),
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
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) => _EntryRowDispatcher(
              entry: entries[index],
              redactSensitiveData: widget.inspector.redactSensitiveData,
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
    required this.redactSensitiveData,
  });

  final TimestampedEntry entry;
  final bool redactSensitiveData;

  @override
  Widget build(BuildContext context) {
    switch (entry) {
      case final LogEntry e:
        return _LogEntryRow(entry: e);
      case final NetworkEntry e:
        return _NetworkEntryRow(
          entry: e,
          redactSensitiveData: redactSensitiveData,
        );
      case final NavigatorEntry e:
        return _NavigatorEntryRow(entry: e);
      case final DatabaseEntry e:
        return _DatabaseEntryRow(entry: e);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final canTap =
        (entry.stackTrace?.isNotEmpty ?? false) ||
        (entry.data?.isNotEmpty ?? false);
    return ListTile(
      title: Text(entry.message, style: TextStyle(color: entry.level.color)),
      subtitle: Text(entry.displayTime),
      trailing: canTap ? const Icon(Icons.chevron_right, size: 18) : null,
      onTap: canTap
          ? () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LogDetailView(entry: entry)),
            )
          : null,
    );
  }
}

class _NetworkEntryRow extends StatelessWidget {
  const _NetworkEntryRow({
    required this.entry,
    required this.redactSensitiveData,
  });

  final NetworkEntry entry;
  final bool redactSensitiveData;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${entry.method} ${entry.statusCode ?? '-'} ${entry.url}'),
      subtitle: Text(entry.displayTime),
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

class _NavigatorEntryRow extends StatelessWidget {
  const _NavigatorEntryRow({required this.entry});

  final NavigatorEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${entry.action.name} ${entry.displayName}'),
      subtitle: Text(entry.displayTime),
    );
  }
}

class _DatabaseEntryRow extends StatelessWidget {
  const _DatabaseEntryRow({required this.entry});

  final DatabaseEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${entry.operation.name} ${entry.tableName}'),
      subtitle: Text(entry.displayTime),
    );
  }
}
