# 實作計畫：ConsoleTab 篩選標籤動態數量徽章（§P41）

- **日期**：2026-11-03
- **規格**：[`docs/features/2026-11-03-console-filter-dynamic-counter-badges.md`](../features/2026-11-03-console-filter-dynamic-counter-badges.md)
- **來源**：`docs/brainstorm/2026-10-31-features-brainstorm.md` §P41
- **Effort**：trivial

---

## 1. 資料結構與設計方向 Trade-off

**零新資料結構、零模型變更、零公開 API 修改、零額外 State 欄位。**

### 核心設計考量（好品味五層分析）

1. **資料結構與記憶體無狀態**：
   - 僅在 `ConsoleTab.build` 函式堆疊中，以無狀態局部變數進行單次 O(N) 遍歷投影。
   - 不在 `_ConsoleTabState` 增加計數狀態變數，消滅快取失效與狀態不同步的潛在 Bug。
2. **消滅重複排序（好品味效能優化）**：
   - 獲取原始緩衝區全量快照：
     `final rawEntries = widget.inspector.mergedTimeline(sources: _all);`
   - **短路複用**：當 `_isAll` 為 true 時，直接複用 `rawEntries`，避免在同一幀呼叫兩次 `mergedTimeline` 與兩次 QuickSort：
     ```dart
     var entries = _isAll
         ? rawEntries
         : widget.inspector.mergedTimeline(sources: _selected);
     ```
3. **特殊情況（邊界條件消除）**：
   - **單次遍歷 (Single-Pass O(N))**：
     避免對每個 FilterChip 分別呼叫 `.where().length`，而是在 `rawEntries` 上跑單一 `for-in` 搭配 Dart 3 pattern matching `switch (entry)`：
     ```dart
     int bookmarkCount = 0;
     int errorCount = 0;
     final sourceCounts = <TimelineSource, int>{
       for (final s in TimelineSource.values) s: 0,
     };
     final levelCounts = <LogLevel, int>{
       for (final l in logLevelLabels.keys) l: 0,
     };

     for (final entry in rawEntries) {
       if (widget.inspector.isBookmarked(entry)) {
         bookmarkCount++;
       }
       switch (entry) {
         case final LogEntry e:
           sourceCounts[TimelineSource.log] = (sourceCounts[TimelineSource.log] ?? 0) + 1;
           if (e.level == LogLevel.warning || e.level == LogLevel.error) {
             errorCount++;
           }
           if (levelCounts.containsKey(e.level)) {
             levelCounts[e.level] = (levelCounts[e.level] ?? 0) + 1;
           }
         case final NetworkEntry e:
           sourceCounts[TimelineSource.network] = (sourceCounts[TimelineSource.network] ?? 0) + 1;
           if (e.isFailed) {
             errorCount++;
           }
         case NavigatorEntry():
           sourceCounts[TimelineSource.nav] = (sourceCounts[TimelineSource.nav] ?? 0) + 1;
         case DatabaseEntry():
           sourceCounts[TimelineSource.db] = (sourceCounts[TimelineSource.db] ?? 0) + 1;
       }
     }
     ```
   - **空資料邊界**：若 `rawEntries` 為空，所有計數自然初始化為 0，直接印出 `All (0)`、`DB (0)` 等，零特殊 `if-else`。
   - **Errors only 語意保證**：與 `ConsoleFilter._matchesErrorsOnly` 嚴格對齊，計入 `LogLevel.warning`、`LogLevel.error` 以及 `NetworkEntry.isFailed`。
4. **破壞性分析與測試防護 (Never break userspace)**：
   - **既有測試破壞點**：既有 Widget 測試中包含對 FilterChip label 的完全文字精確比對（如 `find.widgetWithText(FilterChip, 'Network')`、`find.text('All')`、`find.text('📌 Bookmarks')`、`tapChip(tester, 'Warning')`）。當文字加上 `(count)` 後，這些精確比對會失效。
   - **比對誤傷陷阱防護**：
     - 注意：`'⚡ Errors only'` 字串內部包含 `'Error'`。若使用 `find.textContaining('Error')` 會誤傷 `⚡ Errors only` Chip。因此檢查不存在的獨立 `Error` Chip 時，必須使用正則前綴 `RegExp(r'^Error \(')` 或精確 predicate `startsWith('Error (')`。
   - **適配對策**：
     - 在 `test/ui/tabs/console_tab_test.dart` 中，升級 `tapChip` 為包含比對。
     - 升級 `console_tab_test.dart` 中第 632-655 行的 4 個斷言（Warning、Info、Errors only 與 Error 不存在斷言）。
     - 在 `test/ui/dashboard/tabs/console_tab_bookmark_test.dart` 中，將 `find.text('All')` 與 `find.text('📌 Bookmarks')` 改為 `find.textContaining('All')` 與 `find.textContaining('📌 Bookmarks')`。
   - 對外部使用者而言，公開 API 完全零破壞。
5. **實用性驗證**：
   - 緩衝區上限固定為 500 條（RingBuffer），500 次記憶體物件的單次欄位讀取耗時小於 0.05ms，消除二次排序後對渲染完全零負擔。

---

## 2. 異動檔案清單

| 檔案 | 變更類型 | 說明 |
|:---|:---:|:---|
| `lib/src/ui/dashboard/tabs/console_tab.dart` | 修改 | 在 `build()` 內進行徽章計數投影與排序複用，更新所有 FilterChip label |
| `test/ui/dashboard/tabs/console_tab_badge_test.dart` | 新增 | 針對動態數量徽章的專用 Widget 測試 |
| `test/ui/tabs/console_tab_test.dart` | 修改 | 適配既有 FilterChip 點擊輔助函式與斷言，支援動態數量 label |
| `test/ui/dashboard/tabs/console_tab_bookmark_test.dart` | 修改 | 將精確 `find.text` 升級為 `find.textContaining` |

---

## 3. 實作任務拆分

### Task 1: [快/便宜] 撰寫專用失敗測試（TDD Red）
- **目標檔案**：`test/ui/dashboard/tabs/console_tab_badge_test.dart`
- **內容**：
  1. 建立測試環境（`FlutterInspector` 注入各種事件）。
  2. 驗證空狀態下所有 FilterChip label 包含 `(0)`。
  3. 注入 1 筆 Log (warning)、1 筆 Log (info)、1 筆失敗 Network、1 筆 Nav、1 筆 DB，並將其中 1 筆加入書籤。
  4. 驗證各 Chip 文字：
     - `All (5)`
     - `Log (2)`
     - `Network (1)`
     - `Nav (1)`
     - `DB (1)`
     - `📌 Bookmarks (1)`
     - `⚡ Errors only (2)`（1 筆 warning log + 1 筆 failed network）
     - `Info (1)`
     - `Warning (1)`
     - `Verbose (0)`
     - `Debug (0)`
  5. 驗證清除所有資料後，所有 Chip 標籤更新歸零。

### Task 2: [快/便宜] 實作 ConsoleTab 徽章計數與效能優化（TDD Green）
- **目標檔案**：`lib/src/ui/dashboard/tabs/console_tab.dart`
- **內容**：
  1. 在 `build(BuildContext context)` 開頭獲取 `final rawEntries = widget.inspector.mergedTimeline(sources: _all);`。
  2. 進行單次 O(N) 計數投影。
  3. 優化 `entries` 獲取：當 `_isAll` 為 true 時直接複用 `rawEntries`，消除重複排序。
  4. 將 FilterChip label 改為：
     - `Text('All (${rawEntries.length})')`
     - `Text('${_sourceLabels[source] ?? ''} (${sourceCounts[source] ?? 0})')`
     - `Text('📌 Bookmarks ($bookmarkCount)')`
     - `Text('⚡ Errors only ($errorCount)')`
     - `Text('${entry.value} (${levelCounts[entry.key] ?? 0})')`
  5. 驗證 `console_tab_badge_test.dart` 轉為綠燈。

### Task 3: [快/便宜] 適配既有測試（Regression Protection）
- **目標檔案**：
  - `test/ui/tabs/console_tab_test.dart`
  - `test/ui/dashboard/tabs/console_tab_bookmark_test.dart`
- **內容**：
  1. 在 `console_tab_test.dart` 中升級 `tapChip`：
     ```dart
     Future<void> tapChip(WidgetTester tester, String label) async {
       final finder = find.descendant(
         of: find.byType(FilterChip),
         matching: find.textContaining(label),
       );
       await tester.scrollUntilVisible(
         finder,
         200,
         scrollable: find.byType(Scrollable).first,
       );
       await tester.pumpAndSettle();
       await tester.tap(finder);
       await tester.pumpAndSettle();
     }
     ```
  2. 在 `console_tab_test.dart` L228 將 `find.widgetWithText(FilterChip, 'Network')` 改為：
     `find.descendant(of: find.byType(FilterChip), matching: find.textContaining('Network'))`。
  3. 在 `console_tab_test.dart` L644-652 升級該測試案例中的 4 個斷言：
     - `expect(find.descendant(of: find.byType(FilterChip), matching: find.textContaining('Warning')), findsOneWidget);`
     - `expect(find.descendant(of: find.byType(FilterChip), matching: find.textContaining('Info')), findsOneWidget);`
     - `expect(find.descendant(of: find.byType(FilterChip), matching: find.textContaining('Errors only')), findsOneWidget);`
     - 檢查不存在獨立 Error Chip（排除 `Errors only` 誤傷）：
       ```dart
       expect(
         find.descendant(
           of: find.byType(FilterChip),
           matching: find.textContaining(RegExp(r'^Error \(')),
         ),
         findsNothing,
       );
       ```
  4. 在 `console_tab_bookmark_test.dart` 中將 `find.text('📌 Bookmarks')` 與 `find.text('All')` 改為 `find.textContaining('📌 Bookmarks')` 與 `find.textContaining('All')`。
  5. 執行全量測試驗證零回歸。

---

## 4. 驗收指令

```bash
flutter test test/ui/dashboard/tabs/console_tab_badge_test.dart
flutter test test/ui/tabs/console_tab_test.dart test/ui/dashboard/tabs/console_tab_bookmark_test.dart
flutter test
flutter analyze lib/ test/
```
