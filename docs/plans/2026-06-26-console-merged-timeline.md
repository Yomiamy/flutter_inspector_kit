# 實作計畫：Console 升級為跨層混合時序軸

- **日期**：2026-06-26
- **對應規格**：`docs/features/2026-06-26-console-merged-timeline.md`
- **狀態**：STAGE 0b — 實作計畫（設計決策已定稿，本文件僅描述 How）
- **語言**：本文件繁體中文；程式碼、識別字、指令保留原文

---

## 0. 設計快照（落地依據，不再議）

| 項目 | 決策 |
|---|---|
| 排序契約 | 新增 `abstract interface class TimestampedEntry`（只 `timestamp` getter），四個 model `implements` 它 |
| 顯示格式 | `displayTime` 以 **extension** 提供，格式 `HH:mm:ss.mmm`（如 `14:30:01.123`） |
| merge 歸屬 | `InspectorRegistry.mergedTimeline({Set<TimelineSource> sources})`，回傳 `List<TimestampedEntry>`，依 `timestamp` **降冪**（newest-first，對齊 `RingBuffer.items`） |
| 過濾時機 | 在「收集階段」用 `if` 依 `sources` 過濾，**不**在排序階段過濾 |
| 對外 API | `FlutterInspector` 開薄 getter/方法轉發給 `registry.mergedTimeline`；`console_tab` 不直接碰 `registry` |
| filter UI | 頂部 chip `[All][Log][Network][Nav][DB]`，預設 All；State 持有 `Set<TimelineSource>` 或等價 |
| 列分派 | `console_tab` row builder 用 `switch` / `is` 判型分派四種視覺 |
| 點擊跳轉 | network→`NetworkDetailView`（**須比照 network_tab 傳 `redactSensitiveData: widget.inspector.redactSensitiveData`**，見 §1.6）、log→`LogDetailView`（無需 redaction 參數）；nav/db 不可點（不顯 chevron、不補 detail view） |
| 移除鏡射 | `dio_interceptor` 兩處 `_inspector.log(debug)`、`navigator_observer` 一處 `_inspector.log(warning)` 全刪，並同步 doc |

---

## 1. 資料結構設計

### 1.1 `TimestampedEntry`（新檔 `lib/src/models/timestamped_entry.dart`）

```dart
/// 統一的排序契約：所有可進時序軸的 entry 都暴露一個 [timestamp]。
///
/// 用 abstract interface class（只能 implements、不能 extends），把它鎖死為窄契約：
/// 它存在的唯一理由是讓 [mergedTimeline] 能用單一型別索取排序鍵，
/// extension（[displayTime]）才得以掛在這個契約上。
abstract interface class TimestampedEntry {
  /// 事件發生時間，作為時序軸排序鍵。
  DateTime get timestamp;
}

/// [TimestampedEntry] 的衍生顯示。
///
/// [displayTime] 是 derived（不是 raw data），四種 model 格式統一、不依賴具體型別，
/// 因此用 extension 提供一份共用實作，避免四個 model 各抄一份（DRY）。
/// 格式為 `HH:mm:ss.mmm`（如 `14:30:01.123`），刻意不沿用 toIso8601String（帶日期+微秒太冗長）。
extension TimestampedEntryDisplay on TimestampedEntry {
  String get displayTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}
```

判準（已定稿，僅記錄落地理由）：
- `timestamp` 是 raw data → 必須進介面當契約。extension 無法穿進具體型別取 field，唯一能統一索取的方式是介面。
- `displayTime` 是 derived、格式統一 → 進 extension。若進介面會逼四個 model 各抄一份相同代碼（DRY 違規）。
- 用 `abstract interface class` 鎖死它只當窄契約（只 implements 不 extends）。

### 1.2 `TimelineSource`（同檔 `lib/src/models/timestamped_entry.dart`，與契約並置）

```dart
/// 時序軸的來源類別，用於 [mergedTimeline] 過濾與 console_tab filter chip。
enum TimelineSource { log, network, nav, db }
```

> 歸屬決策：放在 `timestamped_entry.dart` 同檔（兩者都是時序軸的基礎型別、無循環依賴疑慮），避免新增碎檔。`InspectorRegistry` 與 `console_tab` 各自 import 此檔。

### 1.3 四個 model 加 `implements TimestampedEntry`

四個 model 本來就有 `final DateTime timestamp`，加 `implements TimestampedEntry` 後在 `timestamp` 欄位上加 `@override`，**零行為改動**（欄位定義、建構子、`copyWith`、`==`、`hashCode` 全不動）：

- `lib/src/models/log_entry.dart`：`class LogEntry implements TimestampedEntry`
- `lib/src/models/network_entry.dart`：`class NetworkEntry implements TimestampedEntry`
- `lib/src/models/navigator_entry.dart`：`class NavigatorEntry implements TimestampedEntry`
- `lib/src/models/database_entry.dart`：`class DatabaseEntry implements TimestampedEntry`

每檔需 `import 'timestamped_entry.dart';`，並在 `final DateTime timestamp;` 上方加 `@override`。

### 1.4 `InspectorRegistry.mergedTimeline`

```dart
/// 在渲染讀取當下，把四個 buffer 依 [sources] 過濾、合併、依 timestamp 降冪排序。
///
/// 過濾發生在收集階段（用 if 決定要不要讀某個 buffer），不在排序階段。
/// 降冪（newest-first）對齊 RingBuffer.items 慣例。
/// 預設 sources 為全選（All）。
List<TimestampedEntry> mergedTimeline({
  Set<TimelineSource> sources = const {
    TimelineSource.log,
    TimelineSource.network,
    TimelineSource.nav,
    TimelineSource.db,
  },
}) {
  final merged = <TimestampedEntry>[];
  if (sources.contains(TimelineSource.log)) merged.addAll(log.entries);
  if (sources.contains(TimelineSource.network)) merged.addAll(network.entries);
  if (sources.contains(TimelineSource.nav)) merged.addAll(navigator.entries);
  if (sources.contains(TimelineSource.db)) merged.addAll(database.entries);
  merged.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // 降冪
  return merged;
}
```

資料流：四個 buffer（各自 newest-first 的 snapshot）→ 依 sources 收集 → 合併成單一 list → 整體 `sort` 降冪。不複製資料、不引入第二份真相（list 內裝的是原始 entry 指標）。

### 1.5 `FlutterInspector` 薄轉發

```dart
/// 跨層混合時序軸：依 [sources] 讀四個 buffer，合併後依 timestamp 降冪排序。
/// 預設回傳全部來源（All）。
List<TimestampedEntry> mergedTimeline({Set<TimelineSource> sources = const {
  TimelineSource.log, TimelineSource.network, TimelineSource.nav, TimelineSource.db,
}}) => _registry.mergedTimeline(sources: sources);
```

維持對外 API 乾淨：`registry` 是 `@visibleForTesting` 才暴露的，`console_tab` 透過此薄方法取得時序軸，不直接伸手進 registry。`logEntries` / `clearLogs` 等既有 API 全部保留（向後相容）。

> **插入位置（已對齊當前 main）**：薄轉發 `mergedTimeline` 插在 `flutter_inspector.dart` 的 `logEntries` getter（行 138）附近、與 `networkEntries` / `navigatorEntries` / `databaseEntries` 等 buffer 存取 getter 並置。`_registry` 在 redaction（PR #39）後已改為 `late final InspectorRegistry _registry;`（行 125，建構子 body 內賦值）——**不影響薄轉發**：轉發是讀取端，執行時 `_registry` 早已賦值完成，語意無差異。

### 1.6 redaction × timeline 接線契約（redaction merge 後新增的必要接線）

本計畫定稿於 redaction（PR #39）之前。redaction merge 後，`NetworkDetailView` 多了 `redactSensitiveData` 建構參數（`network_detail_view.dart:16-27`，預設 `true`，doc 明載「Mirrors `FlutterInspector.redactSensitiveData`」），而 `network_tab.dart:189-192` 的跳轉**已傳**此值：

```dart
builder: (_) => NetworkDetailView(
  entry: entry,
  redactSensitiveData: widget.inspector.redactSensitiveData,
),
```

**契約**：T9 改寫 console_tab 時，network 列跳轉 **必須比照傳同一個值**。
- 若不傳：因預設 `true` 不會洩密，但會造成 host 設 `redactSensitiveData: false` 時「Network tab 不遮、Console timeline 遮」的行為分歧——違反「引用同一原 entry、行為應一致」的設計精神（Never break userspace 等級的一致性問題）。
- log 列跳 `LogDetailView` **不需** redaction 參數（redaction 未碰 `log_detail_view.dart`，該 view 無此參數）。

---

## 2. 逐檔異動清單

| 檔案 | 動作 | 類型 |
|---|---|---|
| `lib/src/models/timestamped_entry.dart` | 新增（契約 + extension + enum） | 設計判斷 |
| `lib/src/models/log_entry.dart` | `implements` + `@override` | 機械性 |
| `lib/src/models/network_entry.dart` | `implements` + `@override` | 機械性 |
| `lib/src/models/navigator_entry.dart` | `implements` + `@override` | 機械性 |
| `lib/src/models/database_entry.dart` | `implements` + `@override` | 機械性 |
| `lib/src/core/inspector_registry.dart` | 新增 `mergedTimeline` | 整合 |
| `lib/src/core/flutter_inspector.dart` | 新增薄 `mergedTimeline` 轉發 | 機械性 |
| `lib/src/ui/dashboard/tabs/console_tab.dart` | 改寫（filter chip + 判型分派 + 跳轉） | 設計判斷 |
| `lib/src/interceptors/dio_interceptor.dart` | 刪 `onResponse`/`onError` 兩處鏡射 log | 機械性 |
| `lib/src/observers/navigator_observer.dart` | 刪 `_record` 鏡射 log + 改 class/method doc | 機械性 |

共享檔 owner 標註：
- `lib/src/core/flutter_inspector.dart` 由 **T6（registry 轉發任務）唯一 owner**。其他任務不得改它。
- `lib/src/models/timestamped_entry.dart` 由 **T1 唯一 owner**，建立後其餘任務只 import 不改。

---

## 3. 任務拆分（TDD-first，依相依順序）

> 每個任務標註：觸及檔案、複雜度、可否並行。複雜度三級：機械性 / 整合 / 設計判斷。

### T1 — 建立 `TimestampedEntry` 契約 + extension + enum
- **觸及**：`lib/src/models/timestamped_entry.dart`（新）、`test/models/timestamped_entry_test.dart`（新）
- **複雜度**：設計判斷
- **並行**：無相依（最先做），但下游 T2–T6 全部依賴它 → **必須最先完成**
- **TDD**：
  - 先寫 `test/models/timestamped_entry_test.dart`：用一個 test-local 的 `_Fixture implements TimestampedEntry`（只給 `timestamp`），驗證 `displayTime`：
    - `DateTime(2026, 6, 26, 14, 30, 1, 123).displayTime == '14:30:01.123'`
    - 個位數補零：`DateTime(2026, 1, 1, 9, 5, 3, 7).displayTime == '09:05:03.007'`
    - 毫秒三位補零：millisecond `0` → `.000`
  - 後寫實作（§1.1 + §1.2）通過。
- **驗收**：`flutter test test/models/timestamped_entry_test.dart` 綠。

### T2 — `LogEntry implements TimestampedEntry`
- **觸及**：`lib/src/models/log_entry.dart`、`test/models/log_entry_test.dart`（追加）
- **複雜度**：機械性
- **並行**：依賴 T1；與 T3/T4/T5 **路徑不重疊，可並行**
- **TDD**：
  - 追加 test：`LogEntry(...) is TimestampedEntry` 為 true；`entry.displayTime` 等於對應格式（沿用既有 `fixedTime` 風格）。
  - 改 `log_entry.dart`：`import 'timestamped_entry.dart';`、`class LogEntry implements TimestampedEntry`、`timestamp` 上加 `@override`。
- **驗收**：`flutter test test/models/log_entry_test.dart` 綠。

### T3 — `NetworkEntry implements TimestampedEntry`
- **觸及**：`lib/src/models/network_entry.dart`、`test/models/network_entry_test.dart`（追加）
- **複雜度**：機械性
- **並行**：依賴 T1；與 T2/T4/T5 並行
- **TDD**：追加 `is TimestampedEntry` + `displayTime` 斷言；改 model 加 `implements` + `@override`。
- **驗收**：`flutter test test/models/network_entry_test.dart` 綠。

### T4 — `NavigatorEntry implements TimestampedEntry`
- **觸及**：`lib/src/models/navigator_entry.dart`、`test/models/navigator_entry_test.dart`（新增或追加；目前 `test/models/` 無 navigator_entry_test → **新建**）
- **複雜度**：機械性
- **並行**：依賴 T1；與 T2/T3/T5 並行
- **TDD**：新建 `test/models/navigator_entry_test.dart`，最小斷言 `is TimestampedEntry` + `displayTime`；改 model 加 `implements` + `@override`。
- **驗收**：`flutter test test/models/navigator_entry_test.dart` 綠。

### T5 — `DatabaseEntry implements TimestampedEntry`
- **觸及**：`lib/src/models/database_entry.dart`、`test/models/database_entry_test.dart`（新建；目前 `test/models/` 無此檔）
- **複雜度**：機械性
- **並行**：依賴 T1；與 T2/T3/T4 並行
- **TDD**：新建測試，最小斷言 `is TimestampedEntry` + `displayTime`；改 model 加 `implements` + `@override`。
- **驗收**：`flutter test test/models/database_entry_test.dart` 綠。

### T6 — `mergedTimeline`（registry + inspector 薄轉發）
- **觸及**：`lib/src/core/inspector_registry.dart`、`lib/src/core/flutter_inspector.dart`、`test/core/inspector_registry_merged_timeline_test.dart`（新建）
- **複雜度**：整合
- **並行**：依賴 **T2–T5 全部完成**（merge 需四個 model 已是 `TimestampedEntry`）。**唯一 owner of `flutter_inspector.dart`**，與後續 console 改寫序列化（T9 依賴 T6）
- **TDD**（先寫 test）：
  - 用固定 timestamp 各塞 log/network/nav/db 一筆（時間錯開），斷言：
    - 預設（不傳 sources）回傳 4 筆，且依 timestamp **降冪**（`result[0].timestamp` 最新）。
    - 傳 `{TimelineSource.network}` 只回 network 那筆。
    - 傳 `{TimelineSource.log, TimelineSource.nav}` 回兩筆，仍降冪。
    - 空 buffer → 回空 list。
  - 經由 `FlutterInspector.mergedTimeline(...)` 與 `registry.mergedTimeline(...)` 都驗一次，確認薄轉發等價。
  - 後寫實作（§1.4 + §1.5）。
- **驗收**：新測試綠 + `flutter test test/core/` 全綠（確認沒破壞既有 core 測試）。

### T7 — 移除 dio_interceptor 鏡射 log
- **觸及**：`lib/src/interceptors/dio_interceptor.dart`、`test/interceptors/dio_interceptor_test.dart`（追加守門測試）
- **複雜度**：機械性
- **並行**：**完全獨立**（不依賴 T1–T6，路徑不與任何任務重疊）→ 可在第一批就並行
- **TDD**：
  - 追加守門 test：`onResponse` 後 `inspector.logEntries`（即 `registry.log.entries`）為 **empty**（網路完成不再產生 debug 鏡射）；`onError` 後同樣 empty。
  - 改 `dio_interceptor.dart`：刪 `onResponse` 的 `_inspector.log(...)`（行 76–79）與 `onError` 的 `_inspector.log(...)`（行 111–114）；移除不再需要的 `import '.../log_level.dart';`。
- **驗收**：`flutter test test/interceptors/dio_interceptor_test.dart` 綠（既有測試不依賴鏡射，全數仍通過）。

### T8 — 移除 navigator_observer 鏡射 log + 同步 doc
- **觸及**：`lib/src/observers/navigator_observer.dart`、`test/observers/navigator_observer_test.dart`（**改既有測試**，見 §5）
- **複雜度**：機械性
- **並行**：**完全獨立**（不依賴 T1–T6）→ 可在第一批就並行；與 T7 路徑不重疊，兩者可同批
- **TDD**：
  - 改既有測試（見 §5）：刪 `mirrors a navigation event to the console log at warning level`，改寫 `does not log for the inspector dashboard route` 為「`_record` 不再寫任何 log」的守門測試（push 一般 route 後 `inspector.logEntries` 為 empty）。
  - 改 `navigator_observer.dart`：刪 `_record` 內 `_inspector.log(..., level: LogLevel.warning)`（行 64–67）；class doc（行 8–12）移除「mirroring the interceptor / written to the console log at warning level」描述、`_record` doc（行 51–52）移除「mirrors it to the console log」描述；移除不再需要的 `import '.../log_level.dart';`。
- **驗收**：`flutter test test/observers/navigator_observer_test.dart` 綠。

### T9 — 改寫 `console_tab`（filter chip + 判型分派 + 跳轉）
- **觸及**：`lib/src/ui/dashboard/tabs/console_tab.dart`、`test/ui/tabs/console_tab_test.dart`（**大幅改寫**，見 §5）
- **複雜度**：設計判斷
- **並行**：依賴 **T6（mergedTimeline）+ T1（TimestampedEntry/displayTime）+ T2–T5（判型用的 `is LogEntry` 等）全部就位** → **最後做、序列**
- **TDD**（先寫 widget test，見 §5 清單）：
  - State 持有 `Set<TimelineSource> _selected`，初值四種全選（All）。
  - filter chip row：`[All][Log][Network][Nav][DB]`，All 切回全選；單一來源切成只含該源。
  - row builder：`final entries = widget.inspector.mergedTimeline(sources: _selected);` 後對每筆 `switch`/`is` 分派：
    - `LogEntry` → level 色 + message，subtitle 顯 `displayTime`，可點（沿用既有 canTap：有 stackTrace/data 才可點）→ `LogDetailView`。
    - `NetworkEntry` → `method + statusCode + url`，subtitle `displayTime`，可點 → `NetworkDetailView(entry: e, redactSensitiveData: widget.inspector.redactSensitiveData)`。**必須傳 `redactSensitiveData`**，與 `network_tab.dart:189-192` 的跳轉一致——否則 host 設 `redactSensitiveData: false` 時，同一筆 entry 從 Network tab 點進去不遮、從 Console timeline 點進去卻遮，行為不一致（見 §1.6）。console_tab 需 `import '../network/network_detail_view.dart';`。
    - `NavigatorEntry` → `action + routeName`（沿用 `displayName`），subtitle `displayTime`，**不可點**（trailing 無 chevron）。
    - `DatabaseEntry` → `operation + tableName`，subtitle `displayTime`，**不可點**。
  - 保留 refresh / clear 按鈕；clear 行為維持呼叫 `clearLogs()`（規格 US-5：clear 仍清 log buffer；其他 buffer 各自 tab 清，本功能不擴張 clear 語意）。
- **驗收**：`flutter test test/ui/tabs/console_tab_test.dart` 綠 + 跑整套 `flutter test`（排除已知 10 分鐘 timeout 的 magical_tap_test）。

---

## 4. 並行批次規劃

| 批次 | 任務 | 並行性 | 相依說明 |
|---|---|---|---|
| **Batch 0** | T1、T7、T8 | 三者並行 | T1 是契約根；T7/T8 是移除鏡射，路徑與 T1 及彼此皆不重疊，無需等 T1 |
| **Batch 1** | T2、T3、T4、T5 | 四者並行 | 全部依賴 T1 完成；四個 model 路徑互不重疊 |
| **Batch 2** | T6 | 單一序列 | 依賴 T2–T5 全部完成（merge 需四 model 已是 `TimestampedEntry`）；唯一 owner of `flutter_inspector.dart` |
| **Batch 3** | T9 | 單一序列 | 依賴 T6 + T1–T5 全部就位 |

> 序列鏈關鍵路徑：`T1 → (T2..T5) → T6 → T9`。T7/T8 可塞進關鍵路徑的任何空檔（Batch 0 即可完成）。
> 預估並行收益：Batch 1 四 model 並行（vs 序列）約省 3/4 時間；T7/T8 與 T1 同批不佔關鍵路徑。

---

## 5. 需調整的既有測試清單

> 「移除鏡射」與「console 由 logEntries 改 mergedTimeline」會使部分既有測試的前提失效。逐項列出改什麼、為何改。

### 5.1 `test/observers/navigator_observer_test.dart`（T8 owner）

| 既有測試 | 動作 | 原因 |
|---|---|---|
| `mirrors a navigation event to the console log at warning level`（行 127–139） | **刪除** | 斷言 `inspector.logEntries.length == 1` 且 `log.level == warning` — 鏡射移除後此行為消失，斷言永遠失敗 |
| `does not log for the inspector dashboard route`（行 141–149） | **改寫為守門測試** | 原意是「dashboard route 不鏡射」；鏡射移除後改為驗「任何 route 都不再寫 log」：push 一般 route 後 `expect(inspector.logEntries, isEmpty)`，鎖死「不再有鏡射」 |
| 其餘 navigator buffer 測試（行 18–125） | **不動** | 它們驗的是 `navigatorInspector.entries`，與鏡射無關 |

### 5.2 `test/interceptors/dio_interceptor_test.dart`（T7 owner）

| 既有測試 | 動作 | 原因 |
|---|---|---|
| 全部既有測試（行 16–254） | **不動，全數通過** | 它們只斷言 `registry.network.entries`，**從不**斷言 debug 鏡射 log 存在 → 移除鏡射不影響它們 |
| （新增）`onResponse / onError 不再寫 debug 鏡射 log` | **追加守門測試** | 鎖死「移除鏡射」這個行為改變，防止未來回歸 |

### 5.3 `test/ui/tabs/console_tab_test.dart`（T9 owner，大幅改寫）

現有 5 個測試全部以「`inspector.log(...)` → Console 直接顯示 log」為前提，改寫後 Console 改讀 `mergedTimeline`。逐項：

| 既有測試 | 動作 | 改寫重點 |
|---|---|---|
| `displays logs and supports clearing`（行 10–29） | **保留+微調** | log-only 仍會顯示（mergedTimeline 含 log）；clear 仍清 log。斷言可沿用，但需確認在 All filter 下兩筆 log 仍出現 |
| `tapping error log with stackTrace opens LogDetailView`（行 31–53） | **保留** | log 列仍可點進 `LogDetailView`，判型分派後行為不變 |
| `tapping error log with data opens LogDetailView`（行 55–77） | **保留** | 同上 |
| `shows a chevron only on expandable rows`（行 79–105） | **保留+擴充** | log 列 canTap 規則不變；可擴充驗 nav/db 列不顯 chevron |
| `tapping pure info log without stackTrace or data does not navigate`（行 107–128） | **保留** | 不可點 log 列行為不變 |
| （新增）`filter chip 切 Network 只顯 network 列` | **新增** | 驗 US-3：塞 log + network，切 Network filter 後只剩 network 列 |
| （新增）`All filter 下四種來源混合並依時間排序` | **新增** | 驗 US-1：塞四種來源、時間錯開，斷言混合呈現且 newest-first |
| （新增）`network 列可點進 NetworkDetailView` | **新增** | 驗 US-2 跳轉 |
| （新增）`network 列跳轉正確轉傳 redactSensitiveData` | **新增** | 驗 §1.6 契約：建構 `FlutterInspector(redactSensitiveData: false)`，點 network 列後斷言進入的 `NetworkDetailView.redactSensitiveData == false`（防止 timeline 與 Network tab 行為分歧） |
| （新增）`nav / db 列不可點（無 chevron）` | **新增** | 驗設計決策（nav/db 暫不可點） |
| （新增）`每列顯示 displayTime（HH:mm:ss.mmm）` | **新增** | 驗格式落地 |

> 注意：改寫 console_tab_test 時需 import `network_entry.dart` / `navigator_action.dart` / `database_operation.dart` 等，以便構造混合來源資料（透過 `inspector.logNetwork(...)`、`inspector.navigatorObserver.didPush(...)`、`inspector.database(...)` 餵入各 buffer）。

### 5.4 其他既有測試 — 確認不受影響

- `test/core/flutter_inspector_test.dart`：只斷言各 inspector buffer 計數，**不依賴鏡射**，不動。
- `test/core/error_capture_test.dart`：用 `logEntries.where(level == error)`，error log 來源不變，不動。
- Network / Navigator / Database 各 tab 測試：本功能不動這三個 tab，不受影響。

---

## 6. 風險與品味守則

- **Never break userspace**：`logEntries` / `clearLogs` / `networkEntries` 等公開 API 全保留語意；唯一行為改變是「Console 預設不再混入偽 level 鏡射 log」，且該資訊改由時序軸以正確語意呈現（資訊不減反增）。
- **不引入第二份真相**：`mergedTimeline` 回傳的是原始 entry 指標的合併 list，無複製、無快照；network entry pending→completed 後下次渲染自動反映最新（因為讀的是同一 buffer）。
- **消滅特殊情況**：過濾在收集階段用 `if` 決定要不要讀某 buffer，排序階段一視同仁降冪 — 不在排序裡再塞 source 判斷。
- **窄契約**：`TimestampedEntry` 只有 `timestamp`，`abstract interface class` 鎖死不被誤用為基底類別。

---

## 7. 執行方式選擇（供 orchestrator 選用）

### 方式 A：subagent-driven（推薦）
- **Batch 0**：開 3 個 subagent 並行跑 T1 / T7 / T8（路徑零重疊）。
- **Batch 1**：T1 完成後，開 4 個 subagent 並行跑 T2 / T3 / T4 / T5。
- **Batch 2 / 3**：T6、T9 各由單一 agent 序列完成（T6 是 `flutter_inspector.dart` 唯一 owner，T9 依賴全部）。
- 優點：最大化並行（關鍵路徑只有 T1→model→T6→T9）；缺點：需 orchestrator 控管 batch barrier。

### 方式 B：parallel session（人工分工）
- Session 1（契約線）：T1 →（協調 T2–T5）→ T6 → T9，握住 `flutter_inspector.dart` owner 權。
- Session 2（清理線）：T7 + T8 並行做完（與 Session 1 路徑零重疊），先行合入。
- 優點：人為邊界清晰、衝突面小；缺點：T2–T5 的四路並行收益不如方式 A 充分。

兩方式皆遵守同一相依鏈與 owner 規範，差別僅在並行調度顆粒度。
