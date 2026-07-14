import 'package:flutter/material.dart';

import '../../core/flutter_inspector.dart';
import '../../models/timestamped_entry.dart';
import '../../utils/diagnostic_report.dart';
import '../../utils/share_text.dart';

/// Bottom sheet that composes a diagnostic report and hands it to the share
/// sheet. Nothing is written to disk.
class ExportReportSheet extends StatefulWidget {
  const ExportReportSheet({required this.inspector, super.key});

  final FlutterInspector inspector;

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
  final Set<TimelineSource> _sections = TimelineSource.values.toSet();

  /// Index into [_ranges]. The radios key off the index rather than the
  /// `Duration?` itself, because `RadioGroup<Duration>` would conflate "All"
  /// (a deliberate null) with "nothing selected" (also null).
  int _rangeIndex = 0;

  bool _errorsOnly = false;
  bool _busy = false;

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

  Future<void> _export() async {
    setState(() => _busy = true);

    final inspector = widget.inspector;
    // The host's source is async; resolving it here keeps the builder pure.
    final info = await inspector.diagnosticInfoSource?.collect();

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

    await shareText(report);

    if (mounted) Navigator.of(context).pop();
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
            RadioGroup<int>(
              groupValue: _rangeIndex,
              onChanged: (index) =>
                  setState(() => _rangeIndex = index ?? _rangeIndex),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _ranges.length; i++)
                    RadioListTile<int>(
                      dense: true,
                      title: Text(_ranges[i].$1),
                      value: i,
                    ),
                ],
              ),
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
  const _SectionLabel(this.text);

  final String text;

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
