import 'package:flutter/material.dart';

import '../../../core/flutter_inspector.dart';
import '../../../inspectors/navigator_stack_resolver.dart';
import '../../../models/navigator_entry.dart';

/// Which sub-view of the Navigator tab is currently displayed.
enum StackViewMode { activeStack, eventHistory }

/// Tab for displaying navigator history.
class NavigatorTab extends StatefulWidget {
  const NavigatorTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<NavigatorTab> createState() => _NavigatorTabState();
}

class _NavigatorTabState extends State<NavigatorTab> {
  StackViewMode _mode = StackViewMode.eventHistory;

  void _refresh() => setState(() {});

  Widget _buildActiveStack(BuildContext context, List<NavigatorEntry> entries) {
    final stack = NavigatorStackResolver().resolve(entries);
    if (stack.isEmpty) {
      return const Center(child: Text('Empty stack history'));
    }
    return ListView.builder(
      itemCount: stack.length,
      itemBuilder: (context, index) {
        final entry = stack[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: index == 0
                ? const Icon(Icons.visibility, color: Colors.blue)
                : null,
            title: Text(entry.displayName),
            subtitle: Text(entry.routeName ?? '(no route name)'),
            trailing: index == 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(50),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(fontSize: 10, color: Colors.blue),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('當前堆疊'),
              selected: _mode == StackViewMode.activeStack,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _mode = StackViewMode.activeStack);
                }
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('事件歷史'),
              selected: _mode == StackViewMode.eventHistory,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _mode = StackViewMode.eventHistory);
                }
              },
            ),
          ],
        ),
        Expanded(
          child: _mode == StackViewMode.eventHistory
              ? ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      title: Text(
                        '${entry.action.name.toUpperCase()} ${entry.displayName}',
                      ),
                      subtitle: Text(
                        '${entry.timestamp.toIso8601String()}\nArgs: ${entry.arguments ?? "None"}',
                      ),
                    );
                  },
                )
              : _buildActiveStack(context, entries),
        ),
      ],
    );
  }
}
