# Diagnostic Report Timeline Redesign Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the isolated `## Logs` section in the diagnostic report with a chronological, single-line `## Timeline` section that interleaves events from all four sources (Log, Network, Nav, DB).

**Architecture:** Use the existing `TimestampedEntry` interface to merge the 4 source lists, sort them descendingly by `timestamp`, and map each to a concise single-line representation. Re-route the `errorsOnly` logic to filter the unified stream rather than just logs. Independent detail sections for Network, Nav, and DB remain intact.

**Tech Stack:** Dart, Flutter Inspector Kit

---

## Chunk 1: Formatters

### Task 1: Single-Line Formatters

**Files:**
- Modify: `lib/src/utils/log_formatters.dart`
- Modify: `lib/src/utils/network_formatters.dart`
- Create: `test/utils/diagnostic_report_test.dart`

- [ ] **Step 1: Write failing tests for formatters**

```dart
// test/utils/diagnostic_report_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/utils/log_formatters.dart';
import 'package:flutter_inspector_kit/src/utils/network_formatters.dart';

void main() {
  group('Diagnostic Report Formatters', () {
    test('buildLogOneLiner formats correctly', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'Fetch failed',
        timestamp: DateTime(2026, 7, 16, 10, 30, 6),
      );
      expect(buildLogOneLiner(entry), '[10:30:06] [LOG/error] Fetch failed');
    });

    test('buildLogOneLiner includes truncated stackTrace', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'Crash',
        stackTrace: '#0 func (file:1)\n#1 func (file:2)\n#2 func (file:3)\n#3 func (file:4)',
        timestamp: DateTime(2026, 7, 16, 10, 30, 6),
      );
      final out = buildLogOneLiner(entry);
      expect(out, contains('[LOG/error] Crash\n  │ #0 func'));
      expect(out.split('\n').length, 4); // msg + 3 lines of stack
    });

    test('buildNetworkOneLiner formats success correctly', () {
      final entry = NetworkEntry.test(
        id: '1',
        method: 'GET',
        url: 'https://api.test/data',
        timestamp: DateTime(2026, 7, 16, 10, 30, 5),
        duration: const Duration(milliseconds: 1200),
        statusCode: 200,
      );
      expect(buildNetworkOneLiner(entry), '[10:30:05] [NET] GET /data → 200 (1200ms)');
    });

    test('buildNetworkOneLiner formats error correctly', () {
      final entry = NetworkEntry.test(
        id: '2',
        method: 'POST',
        url: 'https://api.test/api',
        timestamp: DateTime(2026, 7, 16, 10, 30, 5),
        errorType: 'connectionTimeout', // Assuming DioExceptionType enum maps to this
      );
      expect(buildNetworkOneLiner(entry), '[10:30:05] [NET] POST /api ✗ connectionTimeout');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/diagnostic_report_test.dart`
Expected: FAIL with "Undefined name 'buildLogOneLiner'"

- [ ] **Step 3: Write minimal implementation**

Modify `lib/src/utils/log_formatters.dart`:
```dart
String buildLogOneLiner(LogEntry entry) {
  var line = '[${entry.displayTime}] [LOG/${entry.level.name}] ${entry.message}';
  if (entry.stackTrace != null) {
    final traceLines = entry.stackTrace!.split('\n').take(3);
    for (final t in traceLines) {
      if (t.trim().isNotEmpty) {
        line += '\n  │ ${t.trim()}';
      }
    }
  }
  return line;
}
```

Modify `lib/src/utils/network_formatters.dart`:
```dart
String buildNetworkOneLiner(NetworkEntry entry) {
  final path = Uri.tryParse(entry.url)?.path ?? entry.url;
  var line = '[${entry.displayTime}] [NET] ${entry.method} $path ';
  if (entry.statusCode == null && entry.errorType != null) {
    line += '✗ ${entry.errorType!.name}';
  } else {
    line += '→ ${entry.statusCode ?? 'N/A'}';
    if (entry.duration != null) {
      line += ' (${entry.duration!.inMilliseconds}ms)';
    }
  }
  return line;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/diagnostic_report_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/utils/diagnostic_report_test.dart lib/src/utils/log_formatters.dart lib/src/utils/network_formatters.dart
git commit -m "feat(report): add one-liner formatters for log and network entries"
```

## Chunk 2: Timeline Builder

### Task 2: Refactor buildDiagnosticReport

**Files:**
- Modify: `lib/src/utils/diagnostic_report.dart`
- Modify: `test/utils/diagnostic_report_test.dart`

- [ ] **Step 1: Write the failing test**

Modify `test/utils/diagnostic_report_test.dart` to add a test for `buildDiagnosticReport`:
```dart
// test/utils/diagnostic_report_test.dart
import 'package:flutter_inspector_kit/src/inspectors/log_inspector.dart';
import 'package:flutter_inspector_kit/src/models/diagnostic_info.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_inspector_kit/src/utils/diagnostic_report.dart';

// ... inside group ...
test('buildDiagnosticReport includes interleaved Timeline section', () {
  final logs = LogInspector(200);
  logs.log(LogLevel.info, 'App started', timestamp: DateTime(2026, 7, 16, 10, 30, 0));
  
  final navs = [
    NavigatorEntry(
      action: NavigationAction.push,
      routeName: '/home',
      timestamp: DateTime(2026, 7, 16, 10, 30, 1),
    )
  ];
  
  final report = buildDiagnosticReport(
    logInspector: logs,
    networkEntries: [],
    navigatorEntries: navs,
    databaseEntries: [],
    now: DateTime(2026, 7, 16, 10, 30, 10),
  );
  
  expect(report, contains('## Timeline'));
  // Should sort newest first (nav then log)
  final timelineMatch = RegExp(r'## Timeline\n\n- `\[10:30:01\] \[NAV\] push `/home`\n- `\[10:30:00\] \[LOG/info\] App started`').hasMatch(report);
  expect(timelineMatch, isTrue, reason: 'Timeline should interleave events chronologically');
  expect(report, isNot(contains('## Logs')));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/diagnostic_report_test.dart`
Expected: FAIL (missing `## Timeline`, still has `## Logs`)

- [ ] **Step 3: Write minimal implementation**

Modify `lib/src/utils/diagnostic_report.dart`:
1. Remove the `if (sections.contains(TimelineSource.log))` block.
2. Add a new `## Timeline` section builder before `## Network`.
```dart
  // Build the mixed Timeline
  final timelineEntries = <TimestampedEntry>[];
  if (sections.contains(TimelineSource.log)) {
    timelineEntries.addAll(logInspector.entries);
  }
  if (sections.contains(TimelineSource.network)) {
    timelineEntries.addAll(networkEntries);
  }
  if (sections.contains(TimelineSource.nav)) {
    timelineEntries.addAll(navigatorEntries);
  }
  if (sections.contains(TimelineSource.db)) {
    timelineEntries.addAll(databaseEntries);
  }

  // Apply errorsOnly logic to the mixed timeline
  Iterable<TimestampedEntry> stream = timelineEntries;
  if (errorsOnly) {
    stream = stream.where((e) {
      if (e is LogEntry) {
        return e.level == LogLevel.error || e.level == LogLevel.warning;
      }
      if (e is NetworkEntry) {
        return (e.statusCode != null && e.statusCode! >= 400) || e.errorType != null;
      }
      return false; // Nav and DB events are stripped in errors-only mode
    });
  }

  // Sort descending and apply timeRange window
  final visibleTimeline = stream.where(inWindow).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  _writeSection(
    b,
    errorsOnly ? 'Timeline (errors & warnings only)' : 'Timeline',
    visibleTimeline,
    (e) {
      String oneLiner;
      if (e is LogEntry) {
        oneLiner = buildLogOneLiner(e);
      } else if (e is NetworkEntry) {
        oneLiner = buildNetworkOneLiner(e);
      } else if (e is NavigatorEntry) {
        oneLiner = '[${e.displayTime}] [NAV] ${e.action.name} ${_routeLabel(e)}';
      } else if (e is DatabaseEntry) {
        oneLiner = '[${e.displayTime}] [DB] ${e.operation.name} `${e.tableName}`${e.affectedRows == null ? '' : ' (${e.affectedRows} rows)'}';
      } else {
        oneLiner = '[${e.displayTime}] [UNKNOWN]';
      }
      return '- `$oneLiner`';
    },
  );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/diagnostic_report_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/utils/diagnostic_report.dart test/utils/diagnostic_report_test.dart
git commit -m "feat(report): replace Logs section with chronological mixed Timeline"
```
