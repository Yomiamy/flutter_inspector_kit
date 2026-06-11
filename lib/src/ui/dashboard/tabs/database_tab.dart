import 'package:flutter/material.dart';

import '../../../core/flutter_inspector_impl.dart';
import '../../../models/database_browser_source.dart';
import '../../../sources/operation_log_source.dart';
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                Text(
                  _selectedSource.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
        Expanded(child: _buildBody(isOpLog)),
      ],
    );
  }

  Widget _buildBody(bool isOpLog) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadTables,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_tables.isEmpty) {
      final emptyText = isOpLog
          ? 'No database activity'
          : 'No tables in this source';
      return Center(
        child: Text(emptyText, style: const TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: _tables.length,
      itemBuilder: (context, index) {
        final table = _tables[index];
        final rowCountText = table.rowCount != null
            ? '${table.rowCount} rows'
            : 'n/a';

        return ListTile(
          leading: const Icon(Icons.table_chart),
          title: Text(table.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rowCountText,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TableRowsView(
                  source: _selectedSource,
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
