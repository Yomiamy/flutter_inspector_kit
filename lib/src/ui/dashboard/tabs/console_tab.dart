import 'package:flutter/material.dart';

import '../../../core/flutter_inspector_impl.dart';
import '../../../models/log_level.dart';

/// Tab for displaying console logs.
class ConsoleTab extends StatefulWidget {
  const ConsoleTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<ConsoleTab> {
  void _refresh() => setState(() {});

  Color _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.verbose:
      case LogLevel.debug:
        return Colors.grey;
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
    final entries = widget.inspector.logEntries;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                widget.inspector.clearLogs();
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
                  entry.message,
                  style: TextStyle(color: _getColorForLevel(entry.level)),
                ),
                subtitle: Text(entry.timestamp.toIso8601String()),
              );
            },
          ),
        ),
      ],
    );
  }
}
