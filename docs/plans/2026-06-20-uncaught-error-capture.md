# 實作計畫：全局未捕捉例外捕捉 + Console 錯誤詳情可展開

- **日期**：2026-06-20
- **功能規格**：`docs/features/2026-06-20-uncaught-error-capture.md`
- **brainstorm 來源**：`docs/brainstorm/2026-07-01-features-brainstorm.md`（#1 + #5 的 LogDetailView 部分）
- **狀態**：STAGE 0b — 待確認
- **已確認的決策（不可推翻）**：
  1. 保留 `runGuarded`（與 `captureUncaughtErrors` 用 flag 去重）。
  2. 不開新 tab；捕捉到的例外 = 一條 `LogLevel.error` log；Console error log 點擊可展開詳情。
  3. 所有掛點 chain/wrap，捕捉後錯誤往下游傳；功能 default off。

---

## 1. 設計總覽

核心策略：**功能天然分兩條互不重疊的寫入路徑，各自獨立可測、可並行**。

- **Core 路徑**（`lib/src/core/`）：三個錯誤掛點 chain/wrap + `runGuarded` 薄包裝 + 去重 flag。捕捉到的例外經由既有 `inspector.log(..., level: LogLevel.error)` 變成一條 `LogEntry`——零新資料模型、零新 tab、零新儲存。
- **UI 路徑**（`lib/src/utils/log_formatters.dart` + `lib/src/ui/dashboard/tabs/console/`）：純 Dart 的 `buildLogPlainText` + 仿 `NetworkDetailView` 的 `LogDetailView`，再把 `ConsoleTab` 的 `ListTile` 接上 `onTap`。

兩條路徑唯一的交會點是「`inspector.log` 的 `level/stackTrace/data` 三欄」——這是**既有契約**，本計畫不改它。因此 Core 與 UI 的寫入檔案集合完全不重疊（見第 2 節），STAGE 2 可由兩個 subagent / 兩個 worktree session 並行推進，最後只在 example/README 收斂。

### 1.1 資料結構決策：零新資料模型

捕捉路徑把 `FlutterErrorDetails` / zone error / platform error **映射成既有 `LogEntry`**：

| 來源 | message | stackTrace | data |
|---|---|---|---|
| `FlutterError.onError`（`FlutterErrorDetails d`） | `d.exceptionAsString()` | `d.stack?.toString()` | `{'exceptionType': d.exception.runtimeType.toString(), 'library': d.library, 'context': d.context?.toStringShort()}`（過濾 null 值） |
| `PlatformDispatcher.onError`（`Object e, StackTrace st`） | `e.toString()` | `st.toString()` | `{'source': 'platformDispatcher', 'exceptionType': e.runtimeType.toString()}` |
| `runGuarded` zone error（`Object e, StackTrace st`） | `e.toString()` | `st.toString()` | `{'source': 'zone', 'exceptionType': e.runtimeType.toString()}` |
| `ErrorWidget.builder`（`FlutterErrorDetails d`） | 同 `FlutterError.onError` 映射 | 同上 | 同上，外加 `'source': 'errorWidget'` |

- `data` 一律過濾 `null` 值（`library`/`context` 可能為 null），避免 `KeyValueTable` 顯示 `null` 字串。
- 不新增 `LogEntry` 欄位、不新增 enum、不碰 `RingBuffer`。

### 1.2 三掛點接線 + 去重（Core 路徑核心）

在 `FlutterInspector` 內新增四個 private 欄位保存原 handler + 一個去重 flag：

```
FlutterExceptionHandler? _oldFlutterErrorHandler;          // void Function(FlutterErrorDetails)
bool Function(Object, StackTrace)? _oldPlatformDispatcherOnError;
ErrorWidget.builder 的原值在接線當下以區域變數 original 捕捉（見下）
bool _uncaughtErrorHandlersAttached = false;              // 去重 flag
```

接線統一收斂在一個 private 方法 `_setupErrorHandlers()`：

```
void _setupErrorHandlers() {
  if (_uncaughtErrorHandlersAttached) return;   // ← flag 去重，保證只接一次
  _uncaughtErrorHandlersAttached = true;

  // 1) FlutterError.onError —— chain
  _oldFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    _logFlutterError(details, source: 'flutterError');
    if (_oldFlutterErrorHandler != null) {
      _oldFlutterErrorHandler!(details);
    } else {
      FlutterError.presentError(details);        // 宿主未設則走預設呈現
    }
  };

  // 2) PlatformDispatcher.instance.onError —— chain
  _oldPlatformDispatcherOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (e, st) {
    _logPlatformError(e, st);
    // 維持宿主原意；宿主未設時 return false（= 未處理，交給預設流程）
    return _oldPlatformDispatcherOnError != null
        ? _oldPlatformDispatcherOnError!(e, st)
        : false;
  };

  // 3) ErrorWidget.builder —— wrap
  final original = ErrorWidget.builder;           // 接線當下捕捉原 builder
  ErrorWidget.builder = (details) {
    try {
      _logFlutterError(details, source: 'errorWidget');
    } catch (e, s) {
      debugPrintStack(stackTrace: s, label: 'inspector errorWidget log failed: $e');
    }                                              // 吞掉自身錯誤，防 reentrancy
    return original(details);                      // 永遠無條件轉交原 builder
  };
}
```

**設計要點（皆為已驗證的硬約束）：**
- **`PlatformDispatcher.onError` 絕不無條件 `return true`**——否則吞掉宿主上報。宿主未設時 `return false`，把「未處理」語意交回預設流程。
- **`ErrorWidget.builder` 包裝層絕不判斷 `kDebugMode`/`kReleaseMode`**——details 原封不動交給 `original(details)`，debug 紅屏 / release 灰屏由原 builder 決定，包裝後呈現與未啟用時完全一致。
- **reentrancy 防護**：`ErrorWidget` 包裝層的 log 段包 try-catch 吞掉自身錯誤（catch 內**不 rethrow**），降級 `debugPrintStack`；`return original(details)` 永遠在 try-catch 外無條件執行。
- **去重 flag**：`captureUncaughtErrors: true`（建構子）與 `runGuarded`（薄包裝）都呼叫同一個 `_setupErrorHandlers()`，flag 保證三掛點只接一次——同一錯誤不會記成兩條 log。

### 1.3 `runGuarded` 薄包裝形狀

```
static void runGuarded(
  void Function() body, {
  required FlutterInspector inspector,
}) {
  runZonedGuarded(
    () {
      inspector._setupErrorHandlers();   // zone 內接好三掛點（flag 去重）
      body();                            // body 內呼叫 runApp(...)
    },
    (e, st) {
      inspector._logZoneError(e, st);    // zone error → error log（往下游：runZonedGuarded 不 rethrow，但已記錄）
    },
  );
}
```

- `_setupErrorHandlers()` 放在 zone 內、`body()` 之前（`ErrorWidget.builder` 在 `runApp` 時被 `WidgetsBinding` 讀取，必須早於 `runApp`）。
- `runGuarded` 不取代宿主 `main()` 其他內容——開發者仍可在 `runGuarded` 外做初始化，`runGuarded` 只負責「在 guarded zone 中接好掛點並執行 body」。

### 1.4 啟用時機

`captureUncaughtErrors: true` 時，**在建構子內**呼叫 `_setupErrorHandlers()`——必須早於 `runApp`（理由同上，`ErrorWidget.builder` 在 `runApp` 時已被讀取）。`false`（預設）時完全不呼叫，三掛點一個位元都不碰（US-6 / Never break userspace）。

### 1.5 UI 路徑：`LogDetailView` 重用 `NetworkDetailView`

- **`buildLogPlainText(LogEntry)`**（純 Dart）：仿 `network_formatters.dart` 的 `buildPlainText`，用 `StringBuffer` 拼三節：`=== General ===`（message/level/timestamp）、`=== Stack Trace ===`（`stackTrace ?? '(none)'`）、`=== Data ===`（逐 key 印或 `(none)`）。可單測，無 Flutter 依賴。
- **`LogDetailView`**：複製 `NetworkDetailView` 結構——`Scaffold`+`AppBar`、`enum _ShareAction { text, share }`（log 無 cURL）、`PopupMenuButton` share menu、`_section()` card 分層、`SelectableText` 顯示 stackTrace、`KeyValueTable(data: entry.data)` 顯示 data。share 走既有 `share_text.dart` + `Clipboard`（複製 `NetworkDetailView._onShare` 的 fallback 慣例）。
- **`ConsoleTab` 接 onTap**：`final canTap = entry.stackTrace != null || entry.data != null;`，`onTap: canTap ? () => Navigator.push(... LogDetailView(entry: entry)) : null;`。`KeyValueTable` 已內建 null guard，`entry.data` 可直接傳。

---

## 2. 檔案異動清單（驗證 Core / UI 路徑不重疊）

> **路徑修正**：規格現況表寫的是 `lib/src/ui/dashboard/tabs/console_tab.dart`（單檔，無 `console/` 子目錄）。本計畫新增 `console/` 子目錄放 `log_detail_view.dart`，鏡像既有 `network/` 子目錄慣例。

| 路徑 | 動作 | 路徑歸屬 | 任務 |
|------|------|---------|------|
| `lib/src/core/flutter_inspector.dart` | 改：新增 `captureUncaughtErrors` 參數 + 四個 handler 欄位 + `_setupErrorHandlers()` + `_logFlutterError`/`_logPlatformError`/`_logZoneError` + `static runGuarded` | **Core** | T1, T2 |
| `test/core/error_capture_test.dart` | **新增**：捕捉路徑單元測試 | **Core** | T1, T2 |
| `lib/src/utils/log_formatters.dart` | **新增**：`buildLogPlainText(LogEntry)` 純 Dart | **UI** | T3 |
| `test/utils/log_formatters_test.dart` | **新增**：三節純文字單測 | **UI** | T3 |
| `lib/src/ui/dashboard/tabs/console/log_detail_view.dart` | **新增**：仿 `NetworkDetailView` 的詳情視圖 | **UI** | T4 |
| `lib/src/ui/dashboard/tabs/console_tab.dart` | 改：`ListTile` 接 `onTap`（canTap 判定 + `Navigator.push`） | **UI** | T5 |
| `test/ui/tabs/log_detail_view_test.dart` | **新增**：詳情視圖 widget 測試（含 null 不崩） | **UI** | T4 |
| `test/ui/tabs/console_tab_test.dart` | 改：新增「點擊可展開 / null 不可點」測試 | **UI** | T5 |
| `example/lib/main.dart` | 改：示範 `runGuarded` 或 `captureUncaughtErrors: true` 捕捉一條 error log | 收斂 | T6 |
| `README.md` / `CHANGELOG.md` | 改：補「Uncaught error capture」段 + 變更記錄 | 收斂 | T6 |

**不重疊驗證**：Core 任務（T1/T2）只寫 `flutter_inspector.dart` + `test/core/error_capture_test.dart`；UI 任務（T3/T4/T5）只寫 `log_formatters.dart`、`console/log_detail_view.dart`、`console_tab.dart` 及對應 test。兩集合交集為空 → **T1+T2 與 T3+T4+T5 可完全並行**。僅 T6（example/README）需在兩路徑都完成後收斂。

**不動的檔案（明列防 scope creep）**：`lib/src/models/log_entry.dart`（不加欄位）、`lib/src/models/log_level.dart`（不加 enum）、`lib/src/inspectors/log_inspector.dart`、`RingBuffer`、`lib/flutter_inspector_kit.dart`（`runGuarded` 是 `FlutterInspector` 的 static，既有 `export 'src/core/flutter_inspector.dart'` 已涵蓋，無需新增 export）。

---

## 3. 任務拆分（TDD：每任務先寫測試）

> 複雜度分級對齊 implementer 的 model 策略：🟢 機械性=快/便宜 model｜🟡 整合=標準 model｜🔴 設計判斷/跨層=最強 model。

### T1 — 三掛點 chain/wrap + 去重 flag + `captureUncaughtErrors` 參數 🔴 設計判斷/跨層

- **路徑歸屬**：**Core**
- **寫入 scope**：`lib/src/core/flutter_inspector.dart`、`test/core/error_capture_test.dart`
- **依賴**：無（可與 UI 路徑並行起步）
- **TDD 順序**（先紅後綠）：
  1. `captureUncaughtErrors: false`（預設）時，建構後 `FlutterError.onError`、`PlatformDispatcher.instance.onError`、`ErrorWidget.builder` **與建構前的值相同**（不接管）。
  2. `captureUncaughtErrors: true` 時，三者皆被替換（!= 建構前的值）。
  3. 觸發新的 `FlutterError.onError(details)` → `inspector.logEntries` 多一條 `level == LogLevel.error`、`message` 含摘要、`stackTrace != null` 的 log。
  4. **chain 驗證**：建構前先設一個會翻轉旗標的 `FlutterError.onError`；啟用後觸發 → 旗標被翻轉（證明原 handler 仍被呼叫，錯誤往下游傳）。
  5. **PlatformDispatcher 回傳語意**：宿主原 handler `return true` → 包裝後也 `return true`；宿主未設（測試中以儲存/還原模擬）→ 包裝後 `return false`。
  6. **去重**：對同一 inspector 連續呼叫兩次 `_setupErrorHandlers()`（經 `@visibleForTesting` 暴露或經 `runGuarded` + `captureUncaughtErrors` 雙觸發），三掛點只被替換一次——觸發一次錯誤只產生一條 log。
- **實作**：第 1.2 / 1.4 節。新增 `captureUncaughtErrors` 參數（預設 `false`）、四個 private 欄位、`_setupErrorHandlers()`、`_logFlutterError(details, {required source})`。`_setupErrorHandlers` 需 `@visibleForTesting` 以便去重測試直接呼叫（或測試經 `runGuarded` 觸發）。
- **測試環境注意**：測試需在 `setUp`/`tearDown` **保存並還原** `FlutterError.onError`、`PlatformDispatcher.instance.onError`、`ErrorWidget.builder` 的全域值，避免污染後續測試（這三者是進程全域狀態）。
- **驗收**：
  - 對應 US-1 驗收 1/2、US-2 驗收 1/2、US-3 驗收 1/2、US-6 驗收 1/2/3。
  - chain 行為（原 handler 仍被呼叫）、default-off 不接管、PlatformDispatcher 回傳語意保持、reentrancy（ErrorWidget log 失敗不影響 `return original`）皆有測試。
  - `flutter analyze` 零新增 issue。

### T2 — `runGuarded` 薄包裝 + zone error 捕捉 🔴 設計判斷/跨層

- **路徑歸屬**：**Core**
- **寫入 scope**：`lib/src/core/flutter_inspector.dart`、`test/core/error_capture_test.dart`
- **依賴**：T1（共用 `_setupErrorHandlers()` 與 `_logZoneError`；同檔）→ **與 T1 序列**
- **TDD 順序**（先紅後綠）：
  1. `runGuarded(() => throw StateError('boom'), inspector: i)` → zone error 被捕捉成一條 `LogLevel.error` log，`message` 含 `'boom'`、`stackTrace != null`、`data['source'] == 'zone'`。
  2. `runGuarded` 內 `inspector._setupErrorHandlers()` 被呼叫（三掛點在 zone 內接好）——可由「zone 內觸發 `FlutterError.onError` 也記成 log」間接驗證。
  3. **去重**：先 `FlutterInspector(captureUncaughtErrors: true)` 再用同 inspector 跑 `runGuarded` → 三掛點仍只接一次（flag 生效）。
- **實作**：第 1.3 節的 `static void runGuarded(...)` + `_logZoneError(e, st)`。
- **驗收**：對應 US-5 驗收 1/2/3。zone error 往下游（`runZonedGuarded` 的 onError 內已記錄，不 rethrow 即為「捕捉後不再向上拋」的正確語意）。`flutter analyze` 零新增 issue。

### T3 — `buildLogPlainText` 純 Dart formatter 🟢 機械性

- **路徑歸屬**：**UI**
- **寫入 scope**：`lib/src/utils/log_formatters.dart`、`test/utils/log_formatters_test.dart`
- **依賴**：無（可與 Core 路徑並行起步）
- **TDD 順序**（先紅後綠）：
  1. 完整 entry（message/level/timestamp/stackTrace/data 都有）→ 輸出含 `=== General ===`、`=== Stack Trace ===`、`=== Data ===` 三節，含 message、level.name、stackTrace、每個 data key:value。
  2. `stackTrace == null` → Stack Trace 節顯示 `(none)`，不出現 `null` 字串。
  3. `data == null` 或空 → Data 節顯示 `(none)`。
  4. 結尾 `trimRight()`（對齊 `buildPlainText` 慣例）。
- **實作**：仿 `network_formatters.dart::buildPlainText`，`String buildLogPlainText(LogEntry entry)`，`import '../models/log_entry.dart'`。無 Flutter 依賴。
- **驗收**：對應 US-4 驗收 3（分享內容正確）。三節純文字皆有測試。`flutter analyze` 零新增 issue。

### T4 — `LogDetailView` 詳情視圖 🟡 整合

- **路徑歸屬**：**UI**
- **寫入 scope**：`lib/src/ui/dashboard/tabs/console/log_detail_view.dart`、`test/ui/tabs/log_detail_view_test.dart`
- **依賴**：T3（用 `buildLogPlainText` 做 share）→ **與 T3 序列**（同屬 UI 路徑，但與 Core 路徑並行）
- **TDD 順序**（先紅後綠）：
  1. 給有 stackTrace + data 的 entry → 渲染出 message、level、timestamp、stackTrace（`SelectableText`）、`KeyValueTable`。
  2. **null 不崩**：`stackTrace == null` 且 `data == null` 的 entry → `LogDetailView` 正常渲染（stackTrace 區段省略或顯示空、data 區段 `KeyValueTable` 顯示 emptyLabel），不丟例外。
  3. share menu（`PopupMenuButton`）存在；點 `Copy as text` → clipboard 寫入 `buildLogPlainText` 結果（用 `TestDefaultBinaryMessengerBinding` 攔 Clipboard）。
- **實作**：第 1.5 節。複製 `NetworkDetailView` 的 `_section`/`_kv`/`_onShare` 結構，刪掉 network 專屬（cURL、body、status color）。`enum _ShareAction { text, share }`。`import '../../../../utils/log_formatters.dart'`、`'../../../../utils/share_text.dart'`、`'../../../widgets/key_value_table.dart'`、`'../../../../models/log_entry.dart'`、`'../../../../models/log_level.dart'`。
- **驗收**：對應 US-4 驗收 1/2/3/4。null stackTrace/data 不崩潰有測試。`flutter analyze` 零新增 issue。

### T5 — `ConsoleTab` ListTile 接 onTap 🟢 機械性

- **路徑歸屬**：**UI**
- **寫入 scope**：`lib/src/ui/dashboard/tabs/console_tab.dart`、`test/ui/tabs/console_tab_test.dart`
- **依賴**：T4（push 目標 `LogDetailView` 需就位）→ **與 T4 序列**
- **TDD 順序**（先紅後綠）：
  1. 既有「displays logs and supports clearing」測試不退化。
  2. 點擊含 stackTrace 的 error log → 開啟 `LogDetailView`（`find.byType(LogDetailView)` 或 AppBar 標題可見）。
  3. 點擊純 info（stackTrace 與 data 皆 null）log → 不導航（`canTap == false`，`onTap == null`）。
- **實作**：第 1.5 節。`ListTile` 加 `onTap: canTap ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LogDetailView(entry: entry))) : null;`。`import 'console/log_detail_view.dart'`。
- **驗收**：對應 US-4 驗收 1/4、US-6 驗收 4（非 error log 呈現不退化）。`flutter analyze` 零新增 issue。

### T6 — example 示範 + 文件 🟢 機械性

- **路徑歸屬**：收斂（需 Core + UI 兩路徑皆完成）
- **寫入 scope**：`example/lib/main.dart`、`README.md`、`CHANGELOG.md`
- **依賴**：T1–T5 全數完成
- **實作**：
  - `example/lib/main.dart`：加一顆按鈕觸發未捕捉例外（如 `Future.error` 或 build 期 throw），並以 `runGuarded` 包 `runApp` 或在 `FlutterInspector(... captureUncaughtErrors: true)` 啟用，示範捕捉到的 error log 出現在 Console 且可展開 stackTrace。
  - `README.md`：補「Uncaught error capture」段——說明可選啟用（建構子 `captureUncaughtErrors` 或 `runGuarded`）、**預設關閉**、以及「捕捉後錯誤仍往下游傳」的保證。
  - `CHANGELOG.md`：記錄新增功能。
- **驗收**：對應規格第 5 節跨領域驗收（example 可編譯、README 補段）。`flutter analyze` 零 issue、`flutter test` 全綠、example 可編譯。

---

## 4. 執行順序與並行判斷

```
Core 路徑（只寫 flutter_inspector.dart + test/core/error_capture_test.dart）
  T1（三掛點 + 去重 + 參數）🔴
    ↓ 同檔，序列
  T2（runGuarded + zone error）🔴

UI 路徑（只寫 log_formatters / console/log_detail_view / console_tab + 對應 test）
  T3（buildLogPlainText）🟢
    ↓ T4 用到 T3 的 formatter
  T4（LogDetailView）🟡
    ↓ T5 push 到 T4
  T5（ConsoleTab onTap）🟢

═══ Core 路徑 (T1→T2) ∥ UI 路徑 (T3→T4→T5) 檔案 scope 完全不重疊 → 🟢 全程可並行 ═══

  兩路徑皆完成後
    ↓
  T6（example + README + CHANGELOG）🟢 收斂
```

**可選執行方式：**

- **subagent-driven（同 session）**：主 session 派兩批——批 A = Core 序列（T1→T2），批 B = UI 序列（T3→T4→T5），兩批並行；完成後主 session 收斂 T6。適合單機、希望集中審查。
- **parallel session（worktree）**：開兩個 git worktree——session 1 跑 Core（T1→T2），session 2 跑 UI（T3→T4→T5）。因兩路徑寫入檔案集合不相交，合流時零衝突（僅 T6 在合流後於主分支收斂）。適合兩人/兩窗並行加速。

> 本功能 5 個實作任務 + 1 收斂任務，Core 兩任務複雜度高（🔴，動進程全域 handler），UI 三任務複雜度中低。**建議 parallel session 切 Core/UI**——並行收益實在（兩條獨立路徑各約一半工作量），且 Core 的全域 handler 測試與 UI 的 widget 測試互不干擾。若偏好集中審查則用 subagent-driven。

---

## 5. 測試計畫

### 新增測試檔與覆蓋點

| 測試檔 | 覆蓋點 | 對應任務 |
|------|------|---------|
| `test/core/error_capture_test.dart` | (a) 捕捉路徑：`FlutterError.onError` / zone error 記成 `LogLevel.error` log（含 stackTrace）；(b) **chain**：既有 `FlutterError.onError` 仍被呼叫（旗標翻轉驗證）；(c) **default-off**：`captureUncaughtErrors: false` 時三掛點不接管（值不變）；(d) **PlatformDispatcher 回傳語意**：宿主 true→true、未設→false；(e) **flag 去重**：雙觸發只接一次、一錯一 log；(f) `runGuarded` zone error 捕捉 | T1, T2 |
| `test/utils/log_formatters_test.dart` | `buildLogPlainText` 三節（General/Stack Trace/Data）；null stackTrace → `(none)`；null/空 data → `(none)`；結尾 trimRight | T3 |
| `test/ui/tabs/log_detail_view_test.dart` | 渲染 message/level/timestamp/stackTrace（SelectableText）/data（KeyValueTable）；**null stackTrace + null data 不崩潰**；share menu 存在、Copy as text 寫 clipboard | T4 |

### 既有測試修改

| 測試檔 | 修改 |
|------|------|
| `test/ui/tabs/console_tab_test.dart` | 保留既有「displays logs and supports clearing」不動；新增「點 error log 開 LogDetailView」「點 null-detail log 不導航」 | T5 |

### 測試環境硬約束

- `FlutterError.onError`、`PlatformDispatcher.instance.onError`、`ErrorWidget.builder` 為**進程全域**狀態。`error_capture_test.dart` 必須在 `setUp` 保存、`tearDown` 還原這三者，避免跨測試污染。
- 本套件採 **mock-free** 風格：捕捉路徑全用真實 `FlutterInspector` + 真實 handler 觸發驗證，不 mock。Clipboard 用 `TestDefaultBinaryMessengerBinding` 攔截（既有 `network_detail_view` 測試的慣例）。
- 每任務結束跑 `flutter analyze` + `flutter test`。

### 不單測（由 example 實機示範）

- 三掛點在真實 `runApp` 生命週期中的接線時機（建構子早於 runApp）、release 灰屏 vs debug 紅屏的實際呈現——由 T6 example app 驗證（widget test 環境無法重現 release 渲染）。

---

## 6. 資料結構 / API 異動清單

### 6.1 建構子新參數（預設 off，不破壞既有呼叫端）

```dart
FlutterInspector({
  // ...既有參數全部不變...
  bool captureUncaughtErrors = false,   // ← 新增，預設 false
});
```

- 既有 `FlutterInspector(...)` 呼叫端零改動即可編譯（US-6 驗收 2）。

### 6.2 新增 static 方法

```dart
static void runGuarded(void Function() body, {required FlutterInspector inspector});
```

- 經既有 `export 'src/core/flutter_inspector.dart'` 自動對外可見，**無需改 `lib/flutter_inspector_kit.dart`**。

### 6.3 新增檔案清單

| 新檔 | 路徑歸屬 | 內容 |
|------|---------|------|
| `lib/src/utils/log_formatters.dart` | UI | `buildLogPlainText(LogEntry)` 純 Dart |
| `lib/src/ui/dashboard/tabs/console/log_detail_view.dart` | UI | `LogDetailView` widget（仿 `NetworkDetailView`） |
| `test/core/error_capture_test.dart` | Core | 捕捉路徑單測 |
| `test/utils/log_formatters_test.dart` | UI | formatter 單測 |
| `test/ui/tabs/log_detail_view_test.dart` | UI | 詳情視圖 widget 測試 |

### 6.4 不變更的契約（Never break userspace）

- `inspector.log(message, {level, stackTrace, data})`：簽名與語意**不變**，捕捉路徑直接複用。
- `LogEntry` / `LogLevel`：**不新增欄位 / 不新增 enum**。
- `ConsoleTab(inspector: ...)` 對外建構不變，僅內部 `ListTile` 加 `onTap`。

---

## 7. 明確「不做」（砍掉研究中的過度設計）

- **不做 `_teardownErrorHandlers()`**：規格未要求 detach 還原（YAGNI）。
- **不做 `truncateStackTrace` / 分享長度限制**：MVP 不需要。
- **不抽 `NetworkDetailView` / `LogDetailView` 共用基類**：scope 外，違反「砍掉一半再砍一半」。可在 PR 留一行未來重構註記，本次不動 `NetworkDetailView`。
- **不做 ConsoleTab 搜尋 / 過濾**：brainstorm #5 的另一半，不在本功能。
- **不開新 tab、不做跨 session 持久化、不做效能監控、不取代宿主任何 handler、不做 #4 Dio 結構化錯誤、不做 #2 時序關聯側欄**（同規格 Out of Scope）。

---

## 8. 風險與破壞性分析

| 風險 | 說明 | 緩解 |
|------|------|------|
| 全域 handler 測試污染 | 三掛點是進程全域狀態，測試替換後若不還原會污染後續測試 | `setUp`/`tearDown` 保存還原；列為 T1 硬約束 |
| `PlatformDispatcher.onError` 誤吞 | 無條件 `return true` 會吞掉宿主上報 | 設計強制宿主未設時 `return false`、有設則回傳原 handler 結果；T1 專測此語意 |
| ErrorWidget reentrancy | log 段自身拋錯可能無限遞迴 | log 段 try-catch 吞掉（不 rethrow）+ `debugPrintStack`，`return original(details)` 永遠在外 |
| 雙啟用重複接線 | `captureUncaughtErrors:true` + `runGuarded` 同用導致一錯兩 log | `_uncaughtErrorHandlersAttached` flag 去重；T1/T2 專測 |
| 接線時機 | `ErrorWidget.builder` 須早於 `runApp` 被讀取 | 建構子內接線 + `runGuarded` zone 內 body 前接線；example 驗證 |
| 回退 | 若捕捉造成不可接受副作用 | 整包行為由 `captureUncaughtErrors`（預設 false）+ `runGuarded` 控制；不啟用即與現況完全一致，revert 對應 commit 零殘留 |

---

## 確認

請確認此實作計畫（6 任務、Core 路徑 T1→T2 ∥ UI 路徑 T3→T4→T5 可並行、T6 收斂、零新資料模型、`captureUncaughtErrors` 預設 false、`runGuarded` 經既有 export 對外可見）。確認後進入 **STAGE 1** 建立 Issue + 分支。
