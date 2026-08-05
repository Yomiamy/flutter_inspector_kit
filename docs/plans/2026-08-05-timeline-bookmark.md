# Timeline Bookmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 `flutter_inspector` 的 Console Tab 新增 Timeline 書籤 (Long-press Bookmark) 功能，支援長按標記/取消標記條目、Bookmarks 專屬過濾晶片，並在匯出 Diagnostic Report 時自動加入 `📌` 視覺前綴標籤。

**Architecture:** 採用零侵入性架構，在核心 `FlutterInspector` 維護不可變 Entry 的參照集合 (`Set<TimestampedEntry> _bookmarkedEntries`)，實現 $O(1)$ 的低開銷標記與過濾，避免修改既有 Model 介面。UI 層 `ConsoleTab` 利用 ListTile `onLongPress` 手勢進行狀態切換，並將書籤集合傳遞給 `buildDiagnosticReport` 進行 Markdown Timeline 渲染。

**Tech Stack:** Dart 3.x / Flutter Framework / `flutter_test`

## Global Constraints
- 不改動 `TimestampedEntry`, `LogEntry`, `NetworkEntry`, `NavigatorEntry`, `DatabaseEntry` 之不可變 Model 結構與建構子，維護不可變 (Immutable) 特性。
- `buildDiagnosticReport` 之 `bookmarkedEntries` 參數預設值必須為 `const {}`，維護 100% 向下相容 (Never break userspace)。
- 手勢採用 ListTile `onLongPress`，不得干擾單擊 (`onTap`) 開啟 Detail View。
- 記憶體生命週期：清空 Console 日誌行動 (`clearLogs`, `clearNetwork`, `clearNavigator`, `clearDatabase`) 必須同步清理 `_bookmarkedEntries`。

---

## 1. 實現機制詳細說明 (How)

### 1.1 資料結構追蹤邏輯 (Data Structure Tracking)
- 於 `FlutterInspector` 中維護記憶體內建集合：
  `final Set<TimestampedEntry> _bookmarkedEntries = <TimestampedEntry>{};`
- 提供對外 API：
  - `Set<TimestampedEntry> get bookmarkedEntries => Set.unmodifiable(_bookmarkedEntries);`
  - `bool isBookmarked(TimestampedEntry entry) => _bookmarkedEntries.contains(entry);`
  - `void toggleBookmark(TimestampedEntry entry)`：若存在則移除，否則加入。
  - `void clearBookmarks()`：清空集合。
- 於 `clearLogs()`, `clearNetwork()`, `clearNavigator()`, `clearDatabase()` 以及 ConsoleTab 刪除按鈕觸發時同步呼叫 `clearBookmarks()`。

### 1.2 UI 層 Long-press 接線 (UI Layer Long-press Wiring)
- 於 `ConsoleTab` 及 `_EntryRowDispatcher` 中將 `FlutterInspector` 傳遞予各列 Widget (`_LogEntryRow`, `_NetworkEntryRow`, `_NavigatorEntryRow`, `_DatabaseEntryRow`)。
- 在各列 Widget 的 `ListTile` 設定 `onLongPress: () => inspector.toggleBookmark(entry)`。
- 若 `inspector.isBookmarked(entry)` 為 `true`，在該列圖示或標題區域渲染 📌 圖示 (`Icon(Icons.push_pin, size: ThemeSize.size18, color: ThemeColor.colorFF9800)`)。
- `ConsoleTab` 新增 `Bookmarks` FilterChip，點擊切換 `_showOnlyBookmarks` 狀態；啟用時對 `mergedTimeline` 結果進行 `.where((e) => inspector.isBookmarked(e))` 過濾。
- 若過濾後無任何書籤條目，ListView 區塊顯示 `Center(child: Text('No bookmarked entries'))` 空狀態。

### 1.3 Diagnostic Report 擴充 (Diagnostic Report Extension)
- `buildDiagnosticReport` 擴充可選參數 `Set<TimestampedEntry> bookmarkedEntries = const {}`。
- 修改內部 `_timelineLine(TimestampedEntry e, {bool isBookmarked = false})` 渲染邏輯：
  若 `isBookmarked` 為 `true`，於該行清單項前添加 `📌 ` 前綴（例如：`- 📌 [14:30:01.123] [LOG] User tapped login button`）。

---

## 2. 檔案異動清單 (File Change Summary)

| 檔案路徑 | 異動類型 | 說明 |
|---|---|---|
| `lib/src/core/flutter_inspector.dart` | Modify | 新增 `_bookmarkedEntries` 集合、`toggleBookmark`、`isBookmarked`、`clearBookmarks` 介面與生命週期清理 |
| `lib/src/utils/diagnostic_report.dart` | Modify | `buildDiagnosticReport` 擴充 `bookmarkedEntries` 參數與 `_timelineLine` 的 `📌 ` 前綴邏輯 |
| `lib/src/ui/dashboard/tabs/console_tab.dart` | Modify | 擴充 `Bookmarks` FilterChip、`ListTile.onLongPress` 手勢傳遞、`📌` 圖示與無書籤時的空狀態 UI |
| `test/core/flutter_inspector_bookmark_test.dart` | Create | 測試 `FlutterInspector` 的書籤 State 切換與清空邏輯 |
| `test/utils/diagnostic_report_bookmark_test.dart` | Create | 測試 `buildDiagnosticReport` Markdown Timeline 帶有 `📌 ` 前綴之單元測試 |
| `test/ui/dashboard/tabs/console_tab_bookmark_test.dart` | Create | 測試 UI 長按標記、 FilterChip 篩選與空狀態之 Widget 測試 |

---

## 3. 獨立驗證任務拆解 (Task Decomposition)

### Task 1: Core State - FlutterInspector 書籤狀態管理與邏輯

**Files:**
- Create: `test/core/flutter_inspector_bookmark_test.dart`
- Modify: `lib/src/core/flutter_inspector.dart`

**Interfaces:**
- Consumes: `TimestampedEntry` from `lib/src/models/timestamped_entry.dart`
- Produces: `FlutterInspector.bookmarkedEntries`, `FlutterInspector.isBookmarked(entry)`, `FlutterInspector.toggleBookmark(entry)`, `FlutterInspector.clearBookmarks()`

- [ ] **Step 1: Write the failing unit test**

```dart
// test/core/flutter_inspector_bookmark_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector/src/core/flutter_inspector.dart';
import 'package:flutter_inspector/src/models/log_entry.dart';
import 'package:flutter_inspector/src/models/log_level.dart';

void main() {
  group('FlutterInspector Bookmarks', () {
    test('should toggle bookmark state correctly', () {
      final inspector = FlutterInspector();
      final entry = LogEntry(message: 'Test log', level: LogLevel.info);

      expect(inspector.isBookmarked(entry), false);
      expect(inspector.bookmarkedEntries, isEmpty);

      inspector.toggleBookmark(entry);
      expect(inspector.isBookmarked(entry), true);
      expect(inspector.bookmarkedEntries.contains(entry), true);

      inspector.toggleBookmark(entry);
      expect(inspector.isBookmarked(entry), false);
      expect(inspector.bookmarkedEntries, isEmpty);
    });

    test('clearBookmarks and clearLogs should reset bookmarks', () {
      final inspector = FlutterInspector();
      final entry = LogEntry(message: 'Test log', level: LogLevel.info);
      inspector.toggleBookmark(entry);
      expect(inspector.isBookmarked(entry), true);

      inspector.clearBookmarks();
      expect(inspector.bookmarkedEntries, isEmpty);

      inspector.toggleBookmark(entry);
      inspector.clearLogs();
      expect(inspector.bookmarkedEntries, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/flutter_inspector_bookmark_test.dart`
Expected: FAIL with compilation error (getter 'bookmarkedEntries' / method 'toggleBookmark' not defined for 'FlutterInspector')

- [ ] **Step 3: Implement minimal code in FlutterInspector**

Modify `lib/src/core/flutter_inspector.dart`:
```dart
// 在 _customDatabaseSources 下方新增：
final Set<TimestampedEntry> _bookmarkedEntries = <TimestampedEntry>{};

/// Unmodifiable view of currently bookmarked entries.
Set<TimestampedEntry> get bookmarkedEntries => Set.unmodifiable(_bookmarkedEntries);

/// Checks if an entry is bookmarked.
bool isBookmarked(TimestampedEntry entry) => _bookmarkedEntries.contains(entry);

/// Toggles bookmark state for an entry.
void toggleBookmark(TimestampedEntry entry) {
  if (_bookmarkedEntries.contains(entry)) {
    _bookmarkedEntries.remove(entry);
  } else {
    _bookmarkedEntries.add(entry);
  }
}

/// Clears all bookmarks.
void clearBookmarks() => _bookmarkedEntries.clear();
```

並更新 `clearLogs`, `clearNetwork`, `clearNavigator`, `clearDatabase` 同步呼叫 `clearBookmarks()`:
```dart
void clearLogs() {
  _registry.log.clear();
  clearBookmarks();
}

void clearNetwork() {
  _registry.network.clear();
  clearBookmarks();
}

void clearNavigator() {
  _registry.navigator.clear();
  clearBookmarks();
}

void clearDatabase() {
  _registry.database.clear();
  clearBookmarks();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/flutter_inspector_bookmark_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/core/flutter_inspector.dart test/core/flutter_inspector_bookmark_test.dart
git commit -m "feat(core): add bookmark state management to FlutterInspector"
```

---

### Task 2: Utility Extension - Diagnostic Report 📌 書籤前綴

**Files:**
- Create: `test/utils/diagnostic_report_bookmark_test.dart`
- Modify: `lib/src/utils/diagnostic_report.dart`

**Interfaces:**
- Consumes: `FlutterInspector.bookmarkedEntries`
- Produces: `buildDiagnosticReport(..., bookmarkedEntries: ...)` with `📌 ` prefixed timeline lines

- [ ] **Step 1: Write the failing unit test**

```dart
// test/utils/diagnostic_report_bookmark_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector/src/utils/diagnostic_report.dart';
import 'package:flutter_inspector/src/inspectors/log_inspector.dart';
import 'package:flutter_inspector/src/models/log_entry.dart';
import 'package:flutter_inspector/src/models/log_level.dart';

void main() {
  group('buildDiagnosticReport with Bookmarks', () {
    test('renders 📌 prefix for bookmarked entries in timeline', () {
      final logInspector = LogInspector(bufferSize: 100);
      final log1 = LogEntry(message: 'Regular log', level: LogLevel.info);
      final log2 = LogEntry(message: 'Important log', level: LogLevel.warning);
      logInspector.add(log1);
      logInspector.add(log2);

      final now = DateTime.now();
      final report = buildDiagnosticReport(
        logInspector: logInspector,
        networkEntries: [],
        navigatorEntries: [],
        databaseEntries: [],
        now: now,
        bookmarkedEntries: {log2},
      );

      expect(report.contains('- 📌 ['), true);
      expect(report.contains('Important log'), true);
      expect(report.contains('- ['), true);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/diagnostic_report_bookmark_test.dart`
Expected: FAIL with compilation error or assertion failure because `bookmarkedEntries` parameter or `📌 ` prefix is missing.

- [ ] **Step 3: Implement minimal code in diagnostic_report.dart**

In `lib/src/utils/diagnostic_report.dart`:
1. 擴充 `buildDiagnosticReport` 參數列表：
```dart
String buildDiagnosticReport({
  required LogInspector logInspector,
  required List<NetworkEntry> networkEntries,
  required List<NavigatorEntry> navigatorEntries,
  required List<DatabaseEntry> databaseEntries,
  required DateTime now,
  Set<TimestampedEntry> bookmarkedEntries = const {},
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
```

2. 在 `_writeSection` 呼叫 `_timelineLine` 時傳送 `isBookmarked` 判斷：
```dart
  _writeSection(
    b,
    errorsOnly ? 'Timeline (errors & warnings only)' : 'Timeline',
    visibleTimeline,
    (e) => _timelineLine(e, isBookmarked: bookmarkedEntries.contains(e)),
  );
```

3. 更新 `_timelineLine` 簽名與渲染前綴：
```dart
String _timelineLine(TimestampedEntry e, {bool isBookmarked = false}) {
  final prefix = isBookmarked ? '📌 ' : '';
  if (e is LogEntry) return '- ${prefix}${buildLogOneLiner(e)}';
  if (e is NetworkEntry) return '- ${prefix}${buildNetworkOneLiner(e)}';
  if (e is NavigatorEntry) {
    return '- [${e.displayTime}] [NAV] ${prefix}${e.action.name} ${_routeLabel(e)}';
  }
  if (e is DatabaseEntry) {
    final rows = e.affectedRows == null ? '' : ' (${e.affectedRows} rows)';
    return '- [${e.displayTime}] [DB] ${prefix}${e.operation.name} `${e.tableName}`$rows';
  }
  return '- [${e.displayTime}] [UNKNOWN]';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/diagnostic_report_bookmark_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/utils/diagnostic_report.dart test/utils/diagnostic_report_bookmark_test.dart
git commit -m "feat(report): add 📌 prefix for bookmarked entries in diagnostic report timeline"
```

---

### Task 3: UI Integration - ConsoleTab Long-press 標記與 📌 圖示渲染與 Filter

**Files:**
- Create: `test/ui/dashboard/tabs/console_tab_bookmark_test.dart`
- Modify: `lib/src/ui/dashboard/tabs/console_tab.dart`

**Interfaces:**
- Consumes: `FlutterInspector.toggleBookmark`, `FlutterInspector.isBookmarked`
- Produces: `_EntryRowDispatcher` 與各列 Widget 的 `onLongPress` 手勢傳遞、`📌` 圖示 UI 呈現、`📌 Bookmarks` FilterChip 與無書籤時的空狀態 Widget

- [ ] **Step 1: Write failing widget test**

```dart
// test/ui/dashboard/tabs/console_tab_bookmark_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector/src/core/flutter_inspector.dart';
import 'package:flutter_inspector/src/ui/dashboard/tabs/console_tab.dart';

void main() {
  testWidgets('Long press on timeline entry toggles bookmark icon and filters list', (tester) async {
    final inspector = FlutterInspector();
    inspector.log('Test message 1');
    inspector.log('Test message 2');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConsoleTab(inspector: inspector),
      ),
    ));

    expect(find.byIcon(Icons.push_pin), findsNothing);

    // Long press to toggle bookmark
    await tester.longPress(find.text('Test message 1'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(inspector.bookmarkedEntries.length, 1);

    // Tap Bookmarks FilterChip
    await tester.tap(find.text('📌 Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Test message 1'), findsOneWidget);
    expect(find.text('Test message 2'), findsNothing);

    // Toggle bookmark off
    await tester.longPress(find.text('Test message 1'));
    await tester.pumpAndSettle();

    expect(find.text('No bookmarked entries'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/dashboard/tabs/console_tab_bookmark_test.dart`
Expected: FAIL with `findsOneWidget` failed for `push_pin` icon or `📌 Bookmarks` text.

- [ ] **Step 3: Implement minimal code in console_tab.dart**

In `lib/src/ui/dashboard/tabs/console_tab.dart`:
1. `_ConsoleTabState` 新增 `bool _showOnlyBookmarks = false;`
2. 頂部 FilterChips 區塊加入 `📌 Bookmarks` FilterChip:
```dart
const SizedBox(width: ThemeSize.space8),
FilterChip(
  label: const Text('📌 Bookmarks'),
  selected: _showOnlyBookmarks,
  onSelected: (_) => setState(() {
    _showOnlyBookmarks = !_showOnlyBookmarks;
  }),
),
```
3. 對 `mergedTimeline` 進行過濾與空狀態顯示：
```dart
var entries = widget.inspector.mergedTimeline(sources: _selected);
if (_showOnlyBookmarks) {
  entries = entries.where((e) => widget.inspector.isBookmarked(e)).toList();
}
```
4. 在 `_EntryRowDispatcher` 傳入 `inspector` 並處理各 Row Widget 的 `onLongPress` 與 `isBookmarked` 📌 圖示指示器。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/dashboard/tabs/console_tab_bookmark_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/ui/dashboard/tabs/console_tab.dart test/ui/dashboard/tabs/console_tab_bookmark_test.dart
git commit -m "feat(ui): implement long-press bookmarking, push_pin indicator, and Bookmarks FilterChip in ConsoleTab"
```

---

## 4. 全套單元與 UI 測試驗證 (Verification Plan)

所有任務完成後，執行全套測試驗證：

- [ ] **執行單元與 Widget 測試套件**
Run: `flutter test`
Expected: All tests PASS with 0 failures.
