import '../inspectors/log_inspector.dart';
import '../inspectors/navigator_stack_resolver.dart';
import '../models/database_entry.dart';
import '../models/diagnostic_info.dart';
import '../models/log_entry.dart';
import '../models/log_level.dart';
import '../models/navigator_entry.dart';
import '../models/network_entry.dart';
import '../models/timestamped_entry.dart';
import '../version.dart';
import 'log_formatters.dart';
import 'network_formatters.dart';

/// Builds a Markdown diagnostic report for a bug report or issue tracker.
///
/// Pure and synchronous: no Flutter widgets, no `BuildContext`, no `dart:io`,
/// and it writes nothing to disk. The caller resolves [info] (async on the host
/// side) and passes the result in.
///
/// Three independent filter dimensions:
/// * [timeRange] — how far back to look. **`null` means all time**, which is
///   why this is a `Duration?` and not an enum: the "all" case would otherwise
///   be a special branch in every switch.
/// * [sections] — which sources to include. Unselected sources are absent
///   entirely, not rendered empty.
/// * [errorsOnly] — restrict the *log* section to error/warning. Off by
///   default: a report whose whole point is "what happened around the error"
///   is worth little once the leading info/debug breadcrumbs are stripped.
///
/// [redact] should be the host's `FlutterInspector.redactSensitiveData`, so the
/// report masks exactly what a single-entry share masks — no more, no less.
String buildDiagnosticReport({
  required LogInspector logInspector,
  required List<NetworkEntry> networkEntries,
  required List<NavigatorEntry> navigatorEntries,
  required List<DatabaseEntry> databaseEntries,
  required DateTime now,
  DiagnosticInfo? info,
  Duration? timeRange,
  Set<TimelineSource> sections = const {
    TimelineSource.log,
    TimelineSource.network,
    TimelineSource.nav,
    TimelineSource.db,
  },
  bool errorsOnly = false,
  bool redact = true,
}) {
  final cutoff = timeRange == null ? null : now.subtract(timeRange);
  bool inWindow(TimestampedEntry e) =>
      cutoff == null || e.timestamp.isAfter(cutoff);

  final b = StringBuffer()
    ..writeln('# Diagnostic Report')
    ..writeln()
    ..writeln('| Field | Value |')
    ..writeln('| --- | --- |')
    ..writeln('| Generated | ${now.toIso8601String()} |')
    ..writeln('| Package | flutter_inspector_kit $packageVersion |')
    ..writeln('| Redaction | ${redact ? 'enabled' : 'disabled'} |')
    ..writeln('| Time range | ${_formatRange(timeRange)} |')
    ..writeln('| App version | ${_orNA(info?.appVersion)} |')
    ..writeln('| Device | ${_orNA(info?.deviceModel)} |')
    ..writeln('| OS | ${_orNA(info?.osVersion)} |');

  if (sections.contains(TimelineSource.log)) {
    // errorsOnly reuses entriesAtLevel(), which returns exactly one level, so
    // the two levels are merged and re-sorted back into newest-first order.
    final logs = errorsOnly
        ? (<LogEntry>[
            ...logInspector.entriesAtLevel(LogLevel.error),
            ...logInspector.entriesAtLevel(LogLevel.warning),
          ]..sort((a, b) => b.timestamp.compareTo(a.timestamp)))
        : logInspector.entries;

    _writeSection(
      b,
      errorsOnly ? 'Logs (errors & warnings only)' : 'Logs',
      logs.where(inWindow),
      (e) => _fenced(buildLogPlainText(e)),
    );
  }

  if (sections.contains(TimelineSource.network)) {
    _writeSection(
      b,
      'Network',
      networkEntries.where(inWindow),
      (e) => _fenced(buildPlainText(e, redact: redact)),
    );
  }

  if (sections.contains(TimelineSource.nav)) {
    b
      ..writeln()
      ..writeln('## Navigation')
      ..writeln()
      ..writeln('### Current route stack');

    // The resolver replays push/pop/replace/remove from the *full* buffer.
    // Feeding it the time-windowed list would pop routes whose push fell
    // outside the window and derive a wrong stack — so this deliberately
    // ignores `inWindow`.
    final stack = NavigatorStackResolver().resolve(navigatorEntries);
    b.writeln();
    if (stack.isEmpty) {
      b.writeln('(none)');
    } else {
      for (var i = 0; i < stack.length; i++) {
        final suffix = i == 0 ? ' ← current' : '';
        b.writeln('${i + 1}. ${_routeLabel(stack[i])}$suffix');
      }
    }

    _writeSection(
      b,
      'Navigation events',
      navigatorEntries.where(inWindow),
      (e) => '- `${e.displayTime}` ${e.action.name} ${_routeLabel(e)}',
      level: '###',
    );
  }

  if (sections.contains(TimelineSource.db)) {
    _writeSection(
      b,
      'Database',
      databaseEntries.where(inWindow),
      (e) =>
          '- `${e.displayTime}` ${e.operation.name} `${e.tableName}`'
          '${e.affectedRows == null ? '' : ' (${e.affectedRows} rows)'}',
    );
  }

  return b.toString();
}

void _writeSection<T extends TimestampedEntry>(
  StringBuffer b,
  String title,
  Iterable<T> entries,
  String Function(T) render, {
  String level = '##',
}) {
  b
    ..writeln()
    ..writeln('$level $title')
    ..writeln();

  final visible = entries.toList();
  if (visible.isEmpty) {
    b.writeln('(none)');
    return;
  }
  for (final e in visible) {
    b.writeln(render(e));
  }
}

String _fenced(String body) => '```\n${body.trimRight()}\n```\n';

String _orNA(String? value) =>
    (value == null || value.isEmpty) ? 'N/A' : value;

String _routeLabel(NavigatorEntry e) {
  final name = e.routeName ?? e.widgetType?.toString() ?? '(unnamed)';
  return '`$name`';
}

String _formatRange(Duration? range) {
  if (range == null) return 'all';
  if (range.inHours >= 1) return 'last ${range.inHours}h';
  return 'last ${range.inMinutes}m';
}
