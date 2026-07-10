import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/log_entry.dart';
import '../../../../utils/log_formatters.dart';
import '../../../../utils/share_text.dart';
import '../../../widgets/detail_section.dart';
import '../../../widgets/key_value_table.dart';
import '../../../theme/theme.dart';

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
              PopupMenuItem(value: _ShareAction.share, child: Text('Share…')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: ThemePadding.paddingAll12,
        children: [
          _generalSection(context),
          if (entry.stackTrace?.isNotEmpty ?? false)
            _stackTraceSection(context),
          _dataSection(context),
        ],
      ),
    );
  }

  Widget _generalSection(BuildContext context) {
    return DetailSection(
      title: 'General',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailKeyValueRow.text('Message', entry.message),
          DetailKeyValueRow.text('Level', entry.level.name),
          DetailKeyValueRow.text(
            'Timestamp',
            entry.timestamp.toIso8601String(),
          ),
        ],
      ),
    );
  }

  Widget _stackTraceSection(BuildContext context) {
    return DetailSection(
      title: 'Stack Trace',
      child: Container(
        width: double.infinity,
        padding: ThemePadding.paddingAll8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(ThemeRadius.radius4),
        ),
        child: SelectableText(
          entry.stackTrace!,
          style: ThemeTextStyle.monospaceStyle,
        ),
      ),
    );
  }

  Widget _dataSection(BuildContext context) {
    return DetailSection(
      title: 'Data',
      child: KeyValueTable(data: entry.data, emptyLabel: '(no data)'),
    );
  }

  String _shortTimestamp(DateTime ts) {
    return '${ts.year}-${_p(ts.month)}-${_p(ts.day)} '
        '${_p(ts.hour)}:${_p(ts.minute)}:${_p(ts.second)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  Future<void> _onShare(BuildContext context, _ShareAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _ShareAction.text:
        await Clipboard.setData(ClipboardData(text: buildLogPlainText(entry)));
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
