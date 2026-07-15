import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/flutter_inspector.dart';
import '../../models/diagnostic_info.dart';
import '../../models/timestamped_entry.dart';
import '../../utils/diagnostic_report.dart';
import '../../utils/share_text.dart';

/// Bottom sheet that composes a diagnostic report and hands it to the share
/// sheet. Nothing is written to disk.
class ExportReportSheet extends StatefulWidget {
  final FlutterInspector inspector;

  const ExportReportSheet({required this.inspector, super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context, FlutterInspector inspector) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExportReportSheet(inspector: inspector),
    );
  }

  @override
  State<ExportReportSheet> createState() => _ExportReportSheetState();
}

class _ExportReportSheetState extends State<ExportReportSheet> {
  /// `null` means all time — the same convention the report builder uses.
  static const _ranges = <(String, Duration?)>[
    ('Last 5m', Duration(minutes: 5)),
    ('Last 1h', Duration(hours: 1)),
    ('All', null),
  ];

  static const _sourceLabels = <TimelineSource, String>{
    TimelineSource.log: 'Logs',
    TimelineSource.network: 'Network',
    TimelineSource.nav: 'Navigation',
    TimelineSource.db: 'Database',
  };

  final Set<TimelineSource> _sections = TimelineSource.values.toSet();
  /// Index into [_ranges]. The radios key off the index rather than the
  /// `Duration?` itself, because `RadioGroup<Duration>` would conflate "All"
  /// (a deliberate null) with "nothing selected" (also null).
  int _rangeIndex = 0;
  bool _errorsOnly = false;
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final inspector = widget.inspector;

    try {
      // The host's source is async, and third-party — it may well throw.
      // Resolving it here also keeps the report builder pure and synchronous.
      DiagnosticInfo? info;
      try {
        info = await inspector.diagnosticInfoSource?.collect();
      } catch (_) {
        // A broken host source degrades the header to N/A; it must never cost
        // the user the report they just waited for.
        info = null;
      }
      if (!mounted) return;

      final report = buildDiagnosticReport(
        logInspector: inspector.logInspector,
        networkEntries: inspector.networkEntries,
        navigatorEntries: inspector.navigatorEntries,
        databaseEntries: inspector.databaseEntries,
        now: DateTime.now(),
        info: info,
        timeRange: _ranges[_rangeIndex].$2,
        sections: _sections,
        errorsOnly: _errorsOnly,
        redact: inspector.redactSensitiveData,
      );

      try {
        await shareText(report);
      } catch (_) {
        if (!mounted) return;
        // Fallback to clipboard when the platform has no share sheet.
        try {
          await Clipboard.setData(ClipboardData(text: report));
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Share unavailable — copied to clipboard'),
            ),
          );
        } catch (_) {
          if (!mounted) return;
          // Both paths out failed. Keep the sheet open so the user can retry
          // rather than silently swallowing the report they just waited for.
          messenger.showSnackBar(
            const SnackBar(content: Text('Export failed — please try again')),
          );
          return;
        }
      }

      if (!mounted) return;
      navigator.pop();
    } finally {
      // Without this the button stays disabled forever on any failure.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Export diagnostic report',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            const _SectionLabel('Include'),
            for (final source in TimelineSource.values)
              CheckboxListTile(
                dense: true,
                title: Text(_sourceLabels[source]!),
                value: _sections.contains(source),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _sections.add(source);
                  } else {
                    _sections.remove(source);
                  }
                }),
              ),

            const _SectionLabel('Time range'),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _ranges.length; i++)
                  RadioListTile<int>(
                    dense: true,
                    title: Text(_ranges[i].$1),
                    value: i,
                    groupValue: _rangeIndex,
                    onChanged: (index) =>
                        setState(() => _rangeIndex = index ?? _rangeIndex),
                  ),
              ],
            ),

            CheckboxListTile(
              dense: true,
              title: const Text('Errors & warnings only'),
              subtitle: const Text('Applies to the log section'),
              value: _errorsOnly,
              onChanged: (checked) =>
                  setState(() => _errorsOnly = checked ?? false),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share report'),
                  // Guards against double-taps while the share sheet opens.
                  onPressed: _busy || _sections.isEmpty ? null : _export,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {

  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
