import '../inspectors/log_inspector.dart';
import '../inspectors/navigator_stack_resolver.dart';
import '../models/database_entry.dart';
import '../models/diagnostic_info.dart';
import '../models/log_entry.dart';
import '../models/log_level.dart';
import '../models/navigator_entry.dart';
import '../models/network_entry.dart';
import 'dart:convert';

import '../models/timestamped_entry.dart';
import '../version.dart';
import 'log_formatters.dart';
import 'network_formatters.dart';
import 'redaction.dart';

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
      cutoff == null || !e.timestamp.isBefore(cutoff);

  final b = StringBuffer()
    ..writeln('# Diagnostic Report')
    ..writeln()
    ..writeln('| Field | Value |')
    ..writeln('| --- | --- |')
    ..writeln(
      '| Generated | ${now.toIso8601String()} (${_formatOffset(now)}) |',
    )
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
    _writeSection(b, 'Database', databaseEntries.where(inWindow), (e) {
      var row =
          '- `${e.displayTime}` ${e.operation.name} `${e.tableName}`'
          '${e.affectedRows == null ? '' : ' (${e.affectedRows} rows)'}';
      final data = e.data;
      if (data != null) {
        final payload = redact ? redactHeaders(data) : data;
        row +=
            '\n${_fenced(const JsonEncoder.withIndent('  ').convert(payload))}';
      }
      return row;
    });
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

/// Wraps [body] in a fence long enough to survive its own content.
///
/// A log message or response body can itself contain a ``` fence (LLM output,
/// CMS content, a pasted snippet). With a fixed 3-backtick fence that closes
/// the block early and leaks the payload into the rendered Markdown — and an
/// odd number of fences swallows every heading that follows. CommonMark says
/// the fence must be longer than any backtick run inside it, so measure first.
String _fenced(String body) {
  final text = body.trimRight();
  final longest = RegExp('`+')
      .allMatches(text)
      .fold<int>(
        0,
        (max, m) => (m[0]?.length ?? 0) > max ? (m[0]?.length ?? 0) : max,
      );
  final fence = '`' * (longest < 3 ? 3 : longest + 1);
  return '$fence\n$text\n$fence\n';
}

String _orNA(String? value) => (value == null || value.isEmpty) ? 'N/A' : value;

String _routeLabel(NavigatorEntry e) {
  final name = e.routeName ?? e.widgetType?.toString() ?? '(unnamed)';
  return '`$name`';
}

String _formatRange(Duration? range) {
  if (range == null) return 'all';
  if (range.inHours >= 1) return 'last ${range.inHours}h';
  return 'last ${range.inMinutes}m';
}

/// The device timezone as `UTC±HH:MM`, anchoring every local timestamp in the
/// report so a recipient in another zone can line events up. Dart omits the
/// offset from a local `toIso8601String()`, and the per-event `displayTime`
/// carries no zone either, so without this the whole report is unanchored.
String _formatOffset(DateTime time) {
  final offset = time.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hh = offset.inHours.abs().toString().padLeft(2, '0');
  final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hh:$mm';
}
