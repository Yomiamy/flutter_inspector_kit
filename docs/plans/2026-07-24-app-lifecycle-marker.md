# 實作計畫：App 前景/背景切換標記（Lifecycle Marker）

- 日期：2026-07-24
- 對應規格：`docs/features/2026-07-24-app-lifecycle-marker.md`（已定案，本計畫不重新設計）
- 類型：新功能（opt-in flag），low effort
- 實作檔：`lib/src/core/lifecycle_handler.dart`（新增）、`lib/src/core/flutter_inspector.dart`（接線）
- 測試檔：`test/core/lifecycle_handler_test.dart`（新增，TDD red 先行）、`test/core/flutter_inspector_lifecycle_test.dart`（新增，接線層驗收）

---

## 一、核心決策（已由規格鎖定，implementer 不需再做設計判斷）

| 決策點 | 結論 | 依據 |
|--------|------|------|
| 資料模型 | **不新增**。生命週期變化 = 一筆 `LogEntry`（`LogLevel.info`） | 規格「好品味判斷」 |
| message 格式 | `'App lifecycle: ${state.name}'` | 規格 §待決 1，`.name` 直接輸出即滿足驗收條件 2 |
| `data` Map | **不帶**（傳 `null`，即不傳該具名參數） | 規格 (c) YAGNI |
| `hidden` 狀態 | 不特判，五狀態走同一條路徑，零 `if`／零 `switch` | 規格 (a) |
| observer teardown | `detach()` 呼叫 `removeObserver` | 規格 (b) |
| 多實例去重 | **不做**，dartdoc 註明建議單一 app-wide inspector | 規格 (d) |
| 初始狀態 | **不記錄**，只記錄「變化」 | 規格 (e) |
| 新相依 | **無**（`WidgetsBindingObserver` 來自已 import 的 `flutter/widgets.dart`） | 規格 (e) |

### 為何開新檔而非塞進 `flutter_inspector.dart`

`FlutterInspector` 若自己 `implements WidgetsBindingObserver`，就得在公開 API 上曝露 `didChangeAppLifecycleState`、`didChangeMetrics` 等一整組 framework 回呼——污染公開介面，且與既有 `UncaughtErrorHandler` 的「獨立 handler class」慣例衝突。獨立 class 是規格「重用清單」明列的模式，且是**唯一**新檔。

---

## 二、資料結構

新 class `LifecycleHandler` 的完整狀態：

| 欄位 | 型別 | 用途 |
|------|------|------|
| `onLog` | `final LogCallback` | 既有 typedef，從 `uncaught_error_handler.dart` **import 重用**，禁止重複定義 |
| `_attached` | `bool`（初值 `false`） | idempotent 旗標，比照 `UncaughtErrorHandler` |

無其他欄位。**不存**「上一個狀態」——規格未要求去重相鄰重複狀態，framework 本來就只在狀態真的變化時回呼。

---

## 三、核心程式碼結構（implementer 照此實作，不需再做設計決策）

### 3.1 `lib/src/core/lifecycle_handler.dart`（新增）

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/log_level.dart';
import 'uncaught_error_handler.dart' show LogCallback;

/// Records app lifecycle transitions as [LogLevel.info] log entries.
///
/// Registers itself on [WidgetsBinding.instance] as an observer. Flutter keeps
/// observers in a list, so the host app's own observers keep receiving their
/// callbacks unaffected.
class LifecycleHandler with WidgetsBindingObserver {
  /// The function called to log a lifecycle transition.
  final LogCallback onLog;

  bool _attached = false;

  /// Creates a new LifecycleHandler instance.
  LifecycleHandler({required this.onLog});

  /// Registers this handler as a [WidgetsBindingObserver].
  ///
  /// Idempotent: the `_attached` flag ensures a single state change is never
  /// recorded twice by the same instance.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Removes this handler from [WidgetsBinding.instance].
  ///
  /// Safe to call when not attached, and safe to call twice.
  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      onLog('App lifecycle: ${state.name}', level: LogLevel.info);
    } catch (e, s) {
      debugPrintStack(stackTrace: s, label: 'inspector lifecycle log failed: $e');
    }
  }
}
```

實作備註：
- `with WidgetsBindingObserver`（mixin）而非 `implements`——避免被迫實作全部回呼。
- `detach()` 後 `_attached = false`，使 attach → detach → attach 可重新生效（驗收條件 4、5 的自然結果，非額外功能）。
- catch 內措辭沿用既有 `debugPrintStack(... label: '...failed: $e')` 格式。
- 不覆寫其他 `WidgetsBindingObserver` 回呼。

### 3.2 `lib/src/core/flutter_inspector.dart`（修改）

六處異動，全部在既有結構的對應位置：

1. **import**：新增 `import 'lifecycle_handler.dart';`
2. **公開欄位 + dartdoc**（緊接在 `captureUncaughtErrors` 欄位之後，L71 附近）：

```dart
/// Whether to record app lifecycle transitions (`resumed` / `inactive` /
/// `paused` / `detached` / `hidden`) as [LogLevel.info] log entries, so a
/// crash or a stalled request can be read against whether the app was in the
/// foreground at that moment.
///
/// Defaults to `false` so the package registers no observer unless the host
/// opts in.
///
/// Notes:
/// - Enable this on a single, app-wide inspector. Each enabled instance keeps
///   its own observer and its own buffer, so multiple instances each record
///   their own copy (correct per instance, just duplicated across them).
/// - Unlike the error hooks, this observer *is* torn down: [detach] removes it
///   from [WidgetsBinding.instance]. Removing one observer from the binding's
///   list cannot affect the host's own observers.
final bool captureLifecycleEvents;
```

3. **私有欄位**（`_uncaughtErrorHandler` 附近，L87 區塊）：`late final LifecycleHandler _lifecycleHandler;`
4. **建構式**：具名參數清單加 `this.captureLifecycleEvents = false,`（置於 `captureUncaughtErrors` 之後，維持既有順序語意）；body 內緊接 `if (captureUncaughtErrors) setupErrorHandlers();` 之後加：

```dart
_lifecycleHandler = LifecycleHandler(onLog: log);
if (captureLifecycleEvents) _lifecycleHandler.attach();
```

5. **`detach()`**：

```dart
/// Removes the FAB overlay, and the lifecycle observer when
/// [captureLifecycleEvents] is enabled.
void detach() {
  _overlayManager.detach();
  _lifecycleHandler.detach();
}
```

（`_lifecycleHandler.detach()` 在未 attach 時是 no-op，不需外層 `if`——消滅特殊情況。）

6. **`captureUncaughtErrors` dartdoc 修訂**（規格 (b) 要求）：L68-70 原句

   > The hooks are not torn down: once attached they remain for the process lifetime ([detach] only removes the FAB overlay).

   改為：

   > The error hooks are not torn down: once attached they remain for the process lifetime ([detach] does not restore them). The `_old*` handlers are kept solely to chain to, not to restore.

   **只改這句措辭**，不動同段其他內容。

---

## 四、檔案異動清單與寫入 scope

| # | 檔案 | 動作 | 寫入 scope（STAGE 2 並行判斷用） |
|---|------|------|-----------------------------|
| 1 | `test/core/lifecycle_handler_test.dart` | 新增 | 獨佔新檔 |
| 2 | `test/core/flutter_inspector_lifecycle_test.dart` | 新增 | 獨佔新檔 |
| 3 | `lib/src/core/lifecycle_handler.dart` | 新增 | 獨佔新檔 |
| 4 | `lib/src/core/flutter_inspector.dart` | 修改 | 欄位區 L71/L87、建構式 L130-158、`detach()` L191-193、dartdoc L68-70 — **單一檔案，不可與任何其他任務並行寫入** |
| 5 | `README.md` | 修改 | L390-399「Uncaught error capture (opt-in)」段落**之後**插入新小節 |
| 6 | `CHANGELOG.md` | 修改 | 檔頭新增 `## Unreleased` → `### Added` 條目（版號留給 release 流程統一 bump 四處） |
| 7 | `example/lib/main.dart` | 修改 | L18-27 建構式區塊 |

`lib/src/core/uncaught_error_handler.dart` **不修改**（`LogCallback` 直接 import 重用）。

---

## 五、測試計畫（TDD：測試先寫，先看到 red）

### 5.1 `test/core/lifecycle_handler_test.dart`（handler 單元層）

沿用 `uncaught_error_handler_test.dart` 模式：`TestWidgetsFlutterBinding.ensureInitialized()` 起手，直接建 handler 注入 counting `onLog` closure，透過 `WidgetsBinding.instance.handleAppLifecycleStateChanged(state)` 驅動 framework 廣播（真正走 observer list，不是直接呼叫方法——這樣才驗證到 `addObserver` 有生效）。

`tearDown` 內對測試建立的 handler 呼叫 `detach()`，避免 observer 洩漏到下個測試。

| # | 測試名稱 | 驗證 | 對應驗收條件 |
|---|---------|------|------------|
| T1 | `attach: state change produces one info log with the state name` | callCount == 1、level 為 `LogLevel.info`、message 含 `resumed` | 2 |
| T2 | `all five states are recorded` | 依序送 `resumed`/`inactive`/`paused`/`detached`/`hidden`，收到 5 筆，messages 各含對應 `.name` | 3 |
| T3 | `idempotent: attach twice records a state change once` | attach() 兩次後送一次變化，callCount == 1 | 5 |
| T4 | `detach: no further logs after detach` | attach → 送變化 → detach → 再送變化，callCount 維持 1；再呼叫 detach() 不拋錯 | 4 |
| T5 | `not attached: state change produces no log` | 只建構不 attach，送變化，callCount == 0 | 1（handler 層） |
| T6 | `guard: onLog throws does not propagate` | onLog 固定 throw，`handleAppLifecycleStateChanged` 不向上拋；同一次廣播中另一個宿主 observer 仍收到回呼 | 7、6 |

T6 的宿主 observer：測試內定義一個極簡的 `_HostObserver with WidgetsBindingObserver` 記旗標，`addObserver` 進去驗證並存（規格驗收條件 6）。放在測試檔尾，不進 `lib/`。

### 5.2 `test/core/flutter_inspector_lifecycle_test.dart`（接線層）

| # | 測試名稱 | 驗證 | 對應驗收條件 |
|---|---------|------|------------|
| T7 | `default off: no lifecycle log in logEntries` | `FlutterInspector()` 無參數，送狀態變化，`logEntries` 為空 | 1 |
| T8 | `opt-in: lifecycle transition appears in logEntries` | `FlutterInspector(captureLifecycleEvents: true)`，送 `paused`，`logEntries.single.message` 含 `paused`、`level == LogLevel.info`、`data == null` | 2、(c) |
| T9 | `detach stops lifecycle logging` | opt-in 後送一次 → `detach()` → 再送一次，`logEntries.length == 1` | 4 |

T7/T9 的 tearDown 統一呼叫 `inspector.detach()`，確保跨測試不殘留 observer。

驗收條件 8（`flutter test` 全綠、`flutter analyze` 無新增 warning）由第六節驗證步驟覆蓋。

---

## 六、任務拆分

| # | 任務 | 驗收條件 | 複雜度等級 | 相依 |
|---|------|---------|-----------|------|
| **T-1** | 寫 `test/core/lifecycle_handler_test.dart`（T1–T6，含 `_HostObserver`）。此時 `LifecycleHandler` 尚不存在 → 編譯失敗即為預期的 red | 6 個 test case 齊備，測試名稱與 §5.1 一致 | **整合**（需正確使用 `handleAppLifecycleStateChanged` 驅動 binding） | 無。**可與 T-2 並行** |
| **T-2** | 寫 `test/core/flutter_inspector_lifecycle_test.dart`（T7–T9）。`captureLifecycleEvents` 參數尚不存在 → red | 3 個 test case 齊備 | **機械性** | 無。**可與 T-1 並行** |
| **T-3** | 新增 `lib/src/core/lifecycle_handler.dart`，照 §3.1 實作 | `flutter test test/core/lifecycle_handler_test.dart` 全綠 | **機械性**（§3.1 已給完整結構） | 依賴 T-1 |
| **T-4** | 修改 `lib/src/core/flutter_inspector.dart`：新參數、私有欄位、建構式接線、`detach()` 擴充、`captureUncaughtErrors` dartdoc 修訂（§3.2 六處） | `flutter test test/core/` 全綠；既有 `flutter_inspector` 相關測試不回歸 | **設計判斷**（動到公開 API 與 `detach()` 語意，需確認既有測試零回歸、dartdoc 措辭正確） | 依賴 T-2、T-3 |
| **T-5** | 文件三處：`README.md` 新小節、`CHANGELOG.md` `## Unreleased → ### Added` 條目、`example/lib/main.dart` 加 `captureLifecycleEvents: true` 與說明註解 | 三處措辭與既有 opt-in 條目風格一致；example 可編譯 | **機械性** | 依賴 T-4（措辭需與最終 API 一致）。三處檔案彼此獨立，**內部可並行** |

**並行示意**：`(T-1 ∥ T-2)` → `T-3` → `T-4` → `T-5(三檔並行)`

不再拆更細：T-3/T-4 各自是單檔單一連貫改動，拆成「加欄位」「加 detach」只會製造中間態編譯失敗與額外交接成本。

### 文件三處的具體內容

**README.md**（L399 之後、該小節結尾處新增）：

````markdown
### App lifecycle markers (opt-in)

Enable **lifecycle capture** to record every foreground/background transition
as an `info`-level Console log, so a crash or a stalled request can be read
against whether the app was in the foreground at that moment:

```dart
final inspector = FlutterInspector(captureLifecycleEvents: true);
```

It is **disabled by default**, and `detach()` removes the observer again.
Each transition (`resumed` / `inactive` / `paused` / `detached`, plus `hidden`
on Flutter 3.13+) becomes one entry, which the merged Timeline interleaves with
network, navigation and database events automatically.
````

**CHANGELOG.md**（檔頭）：

```markdown
## Unreleased

### Added
* **App lifecycle markers**: `FlutterInspector(captureLifecycleEvents: true)` records every app lifecycle transition (`resumed` / `inactive` / `paused` / `detached`, plus `hidden` on Flutter 3.13+) as an `info` Console log, so crashes and stalled network calls can be read against whether the app was in the foreground. Opt-in and disabled by default; `detach()` removes the observer.
```

（若 release 流程另有版號規則，交由 releaser 調整標題，條目內容不變。）

**example/lib/main.dart**（L26 之後）：

```dart
    // Record app foreground/background transitions as info logs (opt-in).
    // Handy when reading the Console timeline: the nearest lifecycle entry
    // above a crash tells you whether the app was in the foreground.
    captureLifecycleEvents: true,
```

---

## 七、驗證步驟

```bash
# T-3 完成後
flutter test test/core/lifecycle_handler_test.dart

# T-4 完成後
flutter test test/core/

# 全案完成後（magical_tap_test 有 10 分鐘既有 timeout，全套較慢）
flutter test
flutter analyze
```

預期結果：

- `test/core/lifecycle_handler_test.dart`：6 個測試全綠。
- `test/core/flutter_inspector_lifecycle_test.dart`：3 個測試全綠。
- 既有測試零回歸（所有既有測試皆以預設參數建構 inspector，flag off 時執行路徑與現況等價）。
- `flutter analyze`：無新增 warning／info。
- `example/` 可編譯（`flutter analyze` 已涵蓋）。

---

## 八、破壞性分析（規格已論證，此處僅列 implementer 須實際守住的點）

| 風險點 | 守法 |
|--------|------|
| `detach()` 語意擴充 | flag off 時 `_lifecycleHandler.detach()` 因 `_attached == false` 直接 return，執行路徑等價於現況 |
| observer 洩漏到其他測試 | 所有新測試的 `tearDown` 必須 `detach()` |
| 公開 API 破壞 | 新參數為可選且預設 `false`，既有呼叫端一字不改 |
| 宿主 observer | 只用 `addObserver`／`removeObserver(this)`，不觸碰 list 其他成員；T6 測試守住 |
| `LogCallback` 重複定義 | 一律 `import 'uncaught_error_handler.dart' show LogCallback;`，禁止在新檔重新宣告 |
