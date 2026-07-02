import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/database_entry.dart';
import '../../../models/log_entry.dart';
import '../../../models/log_level.dart';
import '../../../models/navigator_entry.dart';
import '../../../models/network_entry.dart';
import '../../../models/timestamped_entry.dart';
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

  void _refresh() => setState(() {});

  /// Whether the filter currently equals "All" (every source selected).
  bool get _isAll => _selected.length == _all.length;

  void _selectAll() => setState(() => _selected = {..._all});

  void _selectOnly(TimelineSource source) =>
      setState(() => _selected = {source});

  Color _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.verbose:
      case LogLevel.debug:
        return Colors.blueGrey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

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
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('All'),
                      selected: _isAll,
                      onSelected: (_) => _selectAll(),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Log'),
                      selected: !_isAll && _selected.contains(TimelineSource.log),
                      onSelected: (_) => _selectOnly(TimelineSource.log),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Network'),
                      selected: !_isAll &&
                          _selected.contains(TimelineSource.network),
                      onSelected: (_) => _selectOnly(TimelineSource.network),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Nav'),
                      selected: !_isAll && _selected.contains(TimelineSource.nav),
                      onSelected: (_) => _selectOnly(TimelineSource.nav),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('DB'),
                      selected: !_isAll && _selected.contains(TimelineSource.db),
                      onSelected: (_) => _selectOnly(TimelineSource.db),
                    ),
                    const SizedBox(width: 8),
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
            itemBuilder: (context, index) => _buildRow(entries[index]),
          ),
        ),
      ],
    );
  }

  /// Dispatches a [TimestampedEntry] to the matching row visual by runtime type.
  Widget _buildRow(TimestampedEntry entry) {
    switch (entry) {
      case final LogEntry e:
        return _logRow(e);
      case final NetworkEntry e:
        return _networkRow(e);
      case final NavigatorEntry e:
        return _navigatorRow(e);
      case final DatabaseEntry e:
        return _databaseRow(e);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _logRow(LogEntry e) {
    final canTap =
        (e.stackTrace?.isNotEmpty ?? false) || (e.data?.isNotEmpty ?? false);
    return ListTile(
      title: Text(
        e.message,
        style: TextStyle(color: _getColorForLevel(e.level)),
      ),
      subtitle: Text(e.displayTime),
      trailing: canTap ? const Icon(Icons.chevron_right, size: 18) : null,
      onTap: canTap
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LogDetailView(entry: e),
                ),
              )
          : null,
    );
  }

  Widget _networkRow(NetworkEntry e) {
    return ListTile(
      title: Text('${e.method} ${e.statusCode ?? '-'} ${e.url}'),
      subtitle: Text(e.displayTime),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NetworkDetailView(
            entry: e,
            redactSensitiveData: widget.inspector.redactSensitiveData,
          ),
        ),
      ),
    );
  }

  Widget _navigatorRow(NavigatorEntry e) {
    return ListTile(
      title: Text('${e.action.name} ${e.displayName}'),
      subtitle: Text(e.displayTime),
    );
  }

  Widget _databaseRow(DatabaseEntry e) {
    return ListTile(
      title: Text('${e.operation.name} ${e.tableName}'),
      subtitle: Text(e.displayTime),
    );
  }
}
