import 'package:flutter/material.dart';

import '../../../core/flutter_inspector_impl.dart';

/// Tab for displaying database operations.
class DatabaseTab extends StatefulWidget {
  const DatabaseTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<DatabaseTab> createState() => _DatabaseTabState();
}

class _DatabaseTabState extends State<DatabaseTab> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final entries = widget.inspector.databaseEntries;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                widget.inspector.clearDatabase();
                _refresh();
              },
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                title: Text(
                    '${entry.operation.name.toUpperCase()} on ${entry.tableName}'),
                subtitle: Text(
                  'Rows affected: ${entry.affectedRows ?? "-"}\n${entry.data?['query'] ?? ""}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
