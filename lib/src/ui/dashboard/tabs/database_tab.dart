import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../models/database_browser_source.dart';
import '../../../sources/operation_log_source.dart';
import '../../theme/inspector_theme.dart';
import '../../widgets/error_card.dart';
import 'database/table_rows_view.dart';

/// Tab for displaying database tables and operations.
class DatabaseTab extends StatefulWidget {
  const DatabaseTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<DatabaseTab> createState() => _DatabaseTabState();
}

class _DatabaseTabState extends State<DatabaseTab> {
  late DatabaseBrowserSource _selectedSource;
  List<DatabaseTableInfo> _tables = [];
  bool _loading = true;
  bool _isFetching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.inspector.databaseSources.first;
    _loadTables();
  }

  Future<void> _loadTables() async {
    if (!mounted || _isFetching) return;
    _isFetching = true;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final tables = await _selectedSource.listTables();
      if (mounted) {
        setState(() {
          _tables = tables;
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

  void _clearDatabase() {
    widget.inspector.clearDatabase();
    _loadTables();
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.inspector.databaseSources;
    final isOpLog = _selectedSource is OperationLogSource;

    return Column(
      children: [
        Padding(
          padding: InspectorTheme.paddingLgHorizontalSmVertical,
          child: Row(
            children: [
              if (sources.length > 1)
                DropdownButton<DatabaseBrowserSource>(
                  value: _selectedSource,
                  onChanged: (source) {
                    if (source != null) {
                      setState(() {
                        _selectedSource = source;
                      });
                      _loadTables();
                    }
                  },
                  items: sources.map((source) {
                    return DropdownMenuItem<DatabaseBrowserSource>(
                      value: source,
                      child: Text(source.name),
                    );
                  }).toList(),
                )
              else
                Text(_selectedSource.name, style: InspectorTheme.boldStyle),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadTables,
              ),
              if (isOpLog)
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _clearDatabase,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _DatabaseTabBody(
            loading: _loading,
            errorMessage: _errorMessage,
            tables: _tables,
            isOpLog: isOpLog,
            selectedSource: _selectedSource,
            onRetry: _loadTables,
          ),
        ),
      ],
    );
  }
}

class _DatabaseTabBody extends StatelessWidget {
  const _DatabaseTabBody({
    required this.loading,
    required this.errorMessage,
    required this.tables,
    required this.isOpLog,
    required this.selectedSource,
    required this.onRetry,
  });

  final bool loading;
  final String? errorMessage;
  final List<DatabaseTableInfo> tables;
  final bool isOpLog;
  final DatabaseBrowserSource selectedSource;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return ErrorCard(message: errorMessage!, onRetry: onRetry);
    }

    if (tables.isEmpty) {
      final emptyText = isOpLog
          ? 'No database activity'
          : 'No tables in this source';
      return Center(child: Text(emptyText, style: InspectorTheme.mutedStyle));
    }

    return ListView.builder(
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final table = tables[index];
        final rowCountText = table.rowCount != null
            ? '${table.rowCount} rows'
            : 'n/a';

        return ListTile(
          leading: const Icon(Icons.table_chart),
          title: Text(table.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rowCountText, style: InspectorTheme.mutedSmallStyle),
              const SizedBox(width: InspectorTheme.spacingXs),
              const Icon(Icons.chevron_right, color: InspectorTheme.textMuted),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TableRowsView(
                  source: selectedSource,
                  tableName: table.name,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
