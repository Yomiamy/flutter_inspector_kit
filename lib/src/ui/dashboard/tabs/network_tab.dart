import 'package:flutter/material.dart';

import '../../../core/flutter_inspector_impl.dart';

/// Tab for displaying network requests.
class NetworkTab extends StatefulWidget {
  const NetworkTab({required this.inspector, super.key});

  final FlutterInspector inspector;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final entries = widget.inspector.networkEntries;

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
                widget.inspector.clearNetwork();
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
              return ExpansionTile(
                title: Text('[${entry.method}] ${entry.url}'),
                subtitle: Text(
                  '${entry.statusCode ?? 'Pending'} • ${entry.duration?.inMilliseconds ?? '-'}ms',
                  style: TextStyle(
                    color: entry.error != null ? Colors.red : null,
                  ),
                ),
                children: [
                  if (entry.requestHeaders != null)
                    ListTile(
                        title: const Text('Req Headers'),
                        subtitle: Text(entry.requestHeaders.toString())),
                  if (entry.requestBody != null)
                    ListTile(
                        title: const Text('Req Body'),
                        subtitle: Text(entry.requestBody!)),
                  if (entry.responseHeaders != null)
                    ListTile(
                        title: const Text('Res Headers'),
                        subtitle: Text(entry.responseHeaders.toString())),
                  if (entry.responseBody != null)
                    ListTile(
                        title: const Text('Res Body'),
                        subtitle: Text(entry.responseBody!)),
                  if (entry.error != null)
                    ListTile(
                        title: const Text('Error',
                            style: TextStyle(color: Colors.red)),
                        subtitle: Text(entry.error!)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
