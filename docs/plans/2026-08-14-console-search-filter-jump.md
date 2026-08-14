# 實作計畫：Console 搜尋／過濾 + 點擊清過濾捲回主時間軸（§D1 + §P5）

> 規格：`docs/features/2026-08-14-console-search-filter-jump.md`
> Effort: med ｜ 4 個任務 ｜ 預估 diff：新增 2 檔、修改 1 檔、新增/擴充 2 測試檔

## 資料結構（先定這個，其餘都是它的後果）

### `ConsoleFilter` — 鏡射 `NetworkFilter`，但多一層型別分派

既有 `NetworkFilter`（`lib/src/utils/network_utils.dart:65`）是單一型別（`NetworkEntry`）的過濾器。
`ConsoleFilter` 面對的是四源混合流 `List<TimestampedEntry>`，差異全在此。

```dart
@immutable
class ConsoleFilter {
  const ConsoleFilter({
    this.keyword = '',
    this.levels = const <LogLevel>{},
    this.errorsOnly = false,
  });

  final String keyword;
  final Set<LogLevel> levels;
  final bool errorsOnly;

  bool get isEmpty => keyword.trim().isEmpty && levels.isEmpty && !errorsOnly;

  // 外層：條件之間一律 AND（AC-6）
  bool matches(TimestampedEntry entry) =>
      _matchesLevel(entry) && _matchesKeyword(entry);
}

/// 沿用 applyNetworkFilter 的簽章形狀與 isEmpty 短路
List<TimestampedEntry> applyConsoleFilter(
  List<TimestampedEntry> entries,
  ConsoleFilter filter,
) {
  if (filter.isEmpty) return entries;
  return entries.where(filter.matches).toList(growable: false);
}
```

**source 過濾不進 `ConsoleFilter`**：它已由 `inspector.mergedTimeline(sources:)` 在
資料源頭處理（`console_tab.dart:75`），重複實作會產生兩份判定 —— 正是 §P7 的教訓。
AC-6b/6c/6d 的 source 維度靠既有機制，`ConsoleFilter` 只管 keyword + level/errorsOnly。

### 為什麼不動 `TimestampedEntry`

該介面是 `abstract interface class`，註解明寫「存在的唯一理由是讓 mergedTimeline
能用單一型別索取排序鍵」。加 `searchableText` 會讓四個 model 都被迫實作一個
只為 UI 過濾存在的成員 —— 窄契約污染。

改用 `switch (entry)` 型別分派，與 `console_tab.dart:162` 的 `_EntryRowDispatcher`
完全同構（既有程式碼已用這個 idiom 處理四型別差異，照抄即可）。

---

## 任務拆分

四個任務，**T1 → T2 → T3 → T4 嚴格序列**（後三者都依賴 T1 的 `ConsoleFilter`，
且 T2/T3 寫入同一檔 `console_tab.dart`，路徑重疊不可並行）。

### T1：`ConsoleFilter` + `applyConsoleFilter()` 純函式

**複雜度**：標準（設計判斷已在規格定完，此處是照著寫）
**寫入**：`lib/src/utils/console_utils.dart`（新增）

實作要點：

1. `_matchesKeyword` 依型別取可讀欄位（AC-2）：

```dart
bool _matchesKeyword(TimestampedEntry entry) {
  final kw = keyword.trim().toLowerCase();
  if (kw.isEmpty) return true;
  return switch (entry) {
    final LogEntry e =>
      e.message.toLowerCase().contains(kw) ||
      (e.stackTrace?.toLowerCase().contains(kw) ?? false),
    final NetworkEntry e =>
      e.url.toLowerCase().contains(kw) ||
      e.method.toLowerCase().contains(kw) ||
      (e.statusCode?.toString().contains(kw) ?? false),
    final NavigatorEntry e =>
      (e.routeName?.toLowerCase().contains(kw) ?? false) ||
      e.displayName.toLowerCase().contains(kw),
    final DatabaseEntry e =>
      e.tableName.toLowerCase().contains(kw) ||
      e.operation.name.toLowerCase().contains(kw),
    _ => false,
  };
}
```

2. `_matchesLevel` 的兩層結構（AC-4 / AC-5 / AC-6a，**最容易寫錯的一段**）：

```dart
bool _matchesLevel(TimestampedEntry entry) {
  if (errorsOnly) return _matchesErrorsOnly(entry);  // errors-only 取代 level
  if (levels.isEmpty) return true;
  if (entry is! LogEntry) return true;   // ← AC-4/AC-6a：level 不施加於非 log
  return levels.contains(entry.level);
}

// 內層：唯一的 OR（AC-5）。型別互斥，寫成 AND 恆為空
bool _matchesErrorsOnly(TimestampedEntry entry) => switch (entry) {
  final LogEntry e =>
    e.level == LogLevel.warning || e.level == LogLevel.error,
  final NetworkEntry e => e.isFailed,   // 重用 §P7 收斂判定，不重寫（R-5）
  _ => false,                            // nav/db 一律濾掉（AC-5a）
};
```

**驗收**：`test/utils/console_utils_test.dart`（新增，模板為既有
`test/utils/network_utils_test.dart`）。必測 AC-6a/6b/6e 三個組合，
以及 AC-5a 的 nav/db 濾除。

---

### T2：ConsoleTab 接入搜尋欄 + level chips + errors-only chip

**複雜度**：標準
**寫入**：`lib/src/ui/dashboard/tabs/console_tab.dart`

1. `_ConsoleTabState` 新增 `ConsoleFilter _filter = const ConsoleFilter()`
2. `build()` 第 75 行後套用：`entries = applyConsoleFilter(entries, _filter)`
   —— **順序**：`mergedTimeline(sources:)` → `applyConsoleFilter` → bookmark 過濾
3. 搜尋欄：自建私有 `_SearchBar`（**不**跨檔提取 `network_tab.dart` 的同名私有元件，
   見規格「不在範圍內」）。用 `TextField` + `onChanged`，對齊 NetworkTab 的模式
4. level chips：`for (final level in LogLevel.values)` 產生 5 個 `FilterChip`，多選
5. errors-only chip：`⚡ errors-only`，選中時 `levels` 的 UI 呈現為 disabled
   （語意上 errorsOnly 已取代 level，見 T1 的 `_matchesLevel` 短路）
6. 空狀態：過濾後無命中顯示 `No matches`（AC-9），與既有
   `No bookmarked entries` 分支並存

**⚠️ 既有 chip 列已橫向捲動**（`SingleChildScrollView(scrollDirection: Axis.horizontal)`，
L85-86）。新增 5 個 level chip + 1 個 errors-only 會讓該列更長 —— 沿用既有捲動容器即可，
不要改成換行佈局（那會動到既有 source chip 的排版，擴大回歸面）。

**驗收**：AC-1/3/5/9 + AC-10 零回歸（既有 `console_tab_test.dart` 全綠）

---

### T3：點擊清過濾 + 捲回主時間軸

**複雜度**：需設計判斷（狀態與捲動的交互）
**寫入**：`lib/src/ui/dashboard/tabs/console_tab.dart`

1. `_ConsoleTabState` 新增 `final ScrollController _scrollController = ScrollController()`
   —— **必須在 `dispose()` 中 `_scrollController.dispose()`**（style guide §7.4 資源管理）
2. `ListView.builder` 掛上 `controller: _scrollController`
3. `_EntryRowDispatcher` 增加 `onJumpToEntry` 回呼；各 `_*EntryRow` 的 `onTap`：
   - 過濾**有作用**時（`!_filter.isEmpty`）→ 觸發跳轉（AC-7）
   - 過濾**無作用**時 → 維持既有行為開 detail view（AC-8）
4. 跳轉實作：

```dart
Future<void> _jumpToEntry(TimestampedEntry entry) async {
  // 1. 先在「清過濾後的完整清單」中定位目標 index
  final full = widget.inspector.mergedTimeline(sources: _all);
  final index = full.indexOf(entry);
  if (index < 0) return;            // 已被 RingBuffer 淘汰，靜默放棄

  // 2. 清空所有過濾條件並還原 source 為 All
  setState(() {
    _filter = const ConsoleFilter();
    _selected = {..._all};
    _showOnlyBookmarks = false;
  });

  // 3. 等重建完成才捲動 —— 清過濾後清單長度改變，
  //    在同一幀捲動會用到舊的 extent
  await WidgetsBinding.instance.endOfFrame;
  if (!mounted) return;             // style guide §7.5：await 後檢查 mounted
  if (!_scrollController.hasClients) return;
  ...animateTo(...)
}
```

**⚠️ 兩個非顯而易見的坑**（動工前先讀）：

- **`indexOf` 依賴 `==`**。四個 model 是 immutable 且已有 `==`/`hashCode`
  （`NetworkEntry` 刻意把 `WeakReference<Dio>` 排除在外）。若 `indexOf` 回 -1，
  多半是 entry 已被 RingBuffer 淘汰 —— 靜默放棄，不拋錯。
- **捲動位置需估算**：`ListView.builder` 的 item 高度不定（各型別 row 不同），
  無法精確算 offset。用 `index * 估算行高` 近似即可 ——
  **不要**為此引入 `scrollable_positioned_list` 新相依（規格「不在範圍內」的精神）。
  近似落在目標附近即滿足「站回完整時間軸看前後」的目的。

**驗收**：AC-7/AC-8

---

### T4：測試補齊 + 全套回歸

**複雜度**：機械性
**寫入**：`test/utils/console_utils_test.dart`（T1 已建，此處補齊）、
`test/ui/tabs/console_tab_test.dart`（擴充）

1. 補齊 AC-6a~6e 五個組合的單元測試（T1 只需涵蓋 6a/6b/6e，此處補 6c/6d）
2. widget 測試：搜尋 → 點擊 → 驗證過濾已清空（AC-7）
3. 跑全套 `flutter test` 確認零回歸

**⚠️ 既有 timeout 注意**：`magical_tap_test` 有 10 分鐘既有 timeout，
跑全套時預留時間，不要誤判為卡死。

---

## 風險與回滾

| 風險 | 緩解 |
|------|------|
| chip 列過長影響既有 source chip 排版 | 沿用既有橫向捲動容器，不改佈局結構（T2） |
| 捲動位置不精確 | 接受近似（估算行高）；不引入新相依 |
| `indexOf` 回 -1（entry 已淘汰） | 靜默放棄跳轉，不拋錯不提示 |
| 既有 console 測試回歸 | T2/T3 各自跑一次 `console_tab_test.dart`，不等到 T4 |

**回滾點**：四個任務各自獨立 commit。T3 若出問題可單獨 revert，
T1+T2 的過濾功能仍可用（只是少了跳轉）。

## 不做的事（防止範圍蔓延）

- 不提取 `network_tab.dart` 的 `_SearchBar` 為共用元件
- 不動 `TimestampedEntry` / `LogInspector` / `NetworkFilter` / 四個 model
- 不做 `entriesAtLevel()` 的重構（它在 dashboard badge 的 2 處呼叫不受影響）
- 不順手修 `console_tab.dart:19` 的 `withOpacity` deprecation（無關變更，另案處理）
