# Diagnostic Report Timeline Redesign

## 1. Context & Problem
In `v1.5.0`, the diagnostic report exports `LogEntry`, `NetworkEntry`, `NavigatorEntry`, and `DatabaseEntry` into four isolated sections. When troubleshooting, the causal relationship across layers (e.g., a button tap leading to an API call, which fails and produces an error log) is lost because events are grouped by type rather than interleaved by time.

The `## Logs` section in particular takes up excessive vertical space (formatting every log with `General`, `StackTrace`, and `Data` blocks) even when 90% of the entries have no stack trace or data.

## 2. Goal
Replace the isolated `## Logs` section with a single `## Timeline` section that chronologically interleaves events from all four layers, matching the visual mental model of `ConsoleTab`'s `mergedTimeline()`. 

## 3. Design: The Timeline Mixed Stream (方案 A)

### 3.1 Data Flow
Instead of just rendering `logInspector.entries`, the report builder will merge all selected buffers based on the `sections` filter, sort them descendingly by `timestamp` (newest first), and apply the `timeRange` cutoff.

No new data models will be introduced. It reuses the existing `TimestampedEntry` interface.

### 3.2 Single-Line Format
Each entry renders as a dense, single-line head to maximize information density. The only multi-line case is a log entry carrying a stack trace: its head stays one line and up to 3 indented continuation lines follow (message newlines themselves are flattened).

Timestamps reuse the existing `displayTime` extension (`HH:mm:ss.mmm`, millisecond precision), matching the Nav/DB detail sections.

| Type | Format | Example |
|------|--------|---------|
| **LogEntry** | `[HH:mm:ss.mmm] [LOG/{level}] {message}` | `[10:30:06.000] [LOG/error] Fetch failed` |
| **LogEntry** (with StackTrace) | *Message head* + up to 3 continuation lines, each indented 2 spaces and prefixed `│` | `│ #0 UserRepo.fetch (repo.dart:42)` |
| **NetworkEntry** | `[HH:mm:ss.mmm] [NET] {method} {path} → {status} ({duration}ms)` | `[10:30:05.000] [NET] GET /api/data → 502 (1200ms)` |
| **NetworkEntry** (Error, no status) | `[HH:mm:ss.mmm] [NET] {method} {path} ✗ {errorType}` | `[10:30:05.000] [NET] POST /api ✗ connectionTimeout` |
| **NavigatorEntry** | `[HH:mm:ss.mmm] [NAV] {action} {routeName}` | `[10:30:01.000] [NAV] push /home` |
| **DatabaseEntry** | `[HH:mm:ss.mmm] [DB] {operation} {tableName} ({rows} rows)` | `[10:30:06.000] [DB] query users (3 rows)` |

### 3.3 Semantic Updates
1. **Section Renaming**: The report's `## Logs` header becomes `## Timeline`.
2. **`errorsOnly` Flag**: The `errorsOnly` filter on `ExportReportSheet` previously only affected logs. Now, it will filter the Timeline stream to show **only** error/warning logs AND error network entries (`statusCode >= 400` or `errorType != null`). 
3. **Detail Sections Unchanged**: The independent `## Network`, `## Navigation`, and `## Database` sections remain at the bottom of the report to preserve full request/response payloads.

## 4. Implementation Details
* **`lib/src/utils/log_formatters.dart`**: Add `buildLogOneLiner`.
* **`lib/src/utils/network_formatters.dart`**: Add `buildNetworkOneLiner`.
* **`lib/src/utils/diagnostic_report.dart`**: Refactor `_writeSection(..., 'Logs', ...)` into a new mixed timeline rendering logic.
* **Tests**: Update `test/utils/diagnostic_report_test.dart` to assert the new single-line formats and chronological sorting.
