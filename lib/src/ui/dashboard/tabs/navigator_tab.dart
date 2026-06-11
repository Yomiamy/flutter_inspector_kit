import 'package:flutter/material.dart';

import '../../../core/flutter_inspector_impl.dart';

/// Tab for displaying navigator history.
class NavigatorTab extends StatefulWidget {
  const NavigatorTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<NavigatorTab> createState() => _NavigatorTabState();
}

class _NavigatorTabState extends State<NavigatorTab> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final entries = widget.inspector.navigatorEntries;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                widget.inspector.clearNavigator();
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
                  '${entry.action.name.toUpperCase()} ${entry.routeName ?? "Unknown Route"}',
                ),
                subtitle: Text(
                  '${entry.timestamp.toIso8601String()}\nArgs: ${entry.arguments ?? "None"}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
