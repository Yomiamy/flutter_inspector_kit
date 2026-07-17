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

  // The mixed Timeline: entries from every selected source interleaved by time,
  // newest first — the cross-layer causality the four detail sections below
  // can't show. It reuses the shared TimestampedEntry.timestamp sort key and
  // introduces no new model; it is a formatting projection of existing entries.
  final timeline = <TimestampedEntry>[
    if (sections.contains(TimelineSource.log)) ...logInspector.entries,
    if (sections.contains(TimelineSource.network)) ...networkEntries,
    if (sections.contains(TimelineSource.nav)) ...navigatorEntries,
    if (sections.contains(TimelineSource.db)) ...databaseEntries,
  ];

  var stream = timeline.where(inWindow);
  if (errorsOnly) {
    // errorsOnly now filters the whole stream, not just logs: keep error/warning
    // logs and failed network calls; nav/db carry no error signal, so drop them.
    stream = stream.where(_isError);
  }

  final visibleTimeline = stream.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  _writeSection(
    b,
    errorsOnly ? 'Timeline (errors & warnings only)' : 'Timeline',
    visibleTimeline,
    _timelineLine,
  );

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

/// Whether [e] carries an error signal, for the errors-only timeline filter.
/// Only logs and network calls can; nav/db events are never "errors".
bool _isError(TimestampedEntry e) {
  if (e is LogEntry) {
    return e.level == LogLevel.error || e.level == LogLevel.warning;
  }
  if (e is NetworkEntry) {
    return (e.statusCode ?? 0) >= 400 || e.errorType != null;
  }
  return false;
}

/// Renders one timeline entry as a single-line Markdown list item. Nav/DB use
/// inline formatting matching their detail sections; log/network delegate to
/// their dedicated one-liner formatters.
String _timelineLine(TimestampedEntry e) {
  if (e is LogEntry) return '- ${buildLogOneLiner(e)}';
  if (e is NetworkEntry) return '- ${buildNetworkOneLiner(e)}';
  if (e is NavigatorEntry) {
    return '- [${e.displayTime}] [NAV] ${e.action.name} ${_routeLabel(e)}';
  }
  if (e is DatabaseEntry) {
    final rows = e.affectedRows == null ? '' : ' (${e.affectedRows} rows)';
    return '- [${e.displayTime}] [DB] ${e.operation.name} `${e.tableName}`$rows';
  }
  return '- [${e.displayTime}] [UNKNOWN]';
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
