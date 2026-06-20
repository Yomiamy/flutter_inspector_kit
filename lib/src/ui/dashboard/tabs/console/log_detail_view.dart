import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/log_entry.dart';
import '../../../../utils/log_formatters.dart';
import '../../../../utils/share_text.dart';
import '../../../widgets/key_value_table.dart';

/// Actions exposed in the detail view's share menu.
enum _ShareAction { text, share }

/// A full-screen, structured view of a single [LogEntry], showing General
/// info, an optional Stack Trace section, and a Data section plus sharing
/// (plain text / system share).
class LogDetailView extends StatelessWidget {
  const LogDetailView({required this.entry, super.key});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final shortTs = _shortTimestamp(entry.timestamp);
    return Scaffold(
      appBar: AppBar(
        title: Text('[${entry.level.name}] $shortTs'),
        actions: [
          PopupMenuButton<_ShareAction>(
            icon: const Icon(Icons.share),
            onSelected: (action) => _onShare(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ShareAction.text,
                child: Text('Copy as text'),
              ),
              PopupMenuItem(
                value: _ShareAction.share,
                child: Text('Share…'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _generalSection(context),
          if (entry.stackTrace != null) _stackTraceSection(context),
          _dataSection(context),
        ],
      ),
    );
  }

  Widget _generalSection(BuildContext context) {
    return _section(
      context,
      'General',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(context, 'Message', entry.message),
          _kv(context, 'Level', entry.level.name),
          _kv(context, 'Timestamp', entry.timestamp.toIso8601String()),
        ],
      ),
    );
  }

  Widget _stackTraceSection(BuildContext context) {
    return _section(
      context,
      'Stack Trace',
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          entry.stackTrace!,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }

  Widget _dataSection(BuildContext context) {
    return _section(
      context,
      'Data',
      KeyValueTable(data: entry.data, emptyLabel: '(no data)'),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$key:',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _shortTimestamp(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    final s = ts.second.toString().padLeft(2, '0');
    return '${ts.year}-${_p(ts.month)}-${_p(ts.day)} $h:$m:$s';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  Future<void> _onShare(BuildContext context, _ShareAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _ShareAction.text:
        await Clipboard.setData(
          ClipboardData(text: buildLogPlainText(entry)),
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Details copied to clipboard')),
        );
      case _ShareAction.share:
        try {
          await shareText(buildLogPlainText(entry));
        } catch (_) {
          // Fallback to clipboard when the platform has no share sheet.
          await Clipboard.setData(
            ClipboardData(text: buildLogPlainText(entry)),
          );
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Share unavailable — copied to clipboard'),
            ),
          );
        }
    }
  }
}
