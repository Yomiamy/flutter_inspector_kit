# 功能規格：App 前景/背景切換標記（Lifecycle Marker）

- 日期：2026-07-24
- 類型：新功能（opt-in flag）
- 對應 brainstorm：`docs/brainstorm/2026-07-24-features-brainstorm.md` §P13（Tier 1）
- Effort：low ｜排查價值：⭐⭐⭐⭐

## Why（一句話）

崩潰或異常網路行為發生時，「當下 app 是在前景還是背景」這個 context 現在完全沒被記錄——把生命週期切換記成一筆 log，Timeline 上崩潰前最近一筆 lifecycle log 就是答案。

## 背景與痛點

iOS/Android 對背景 app 有資源限制（網路被暫停、被系統 kill 前的緊急回收）。一筆看起來詭異的 timeout、一次沒有明顯成因的崩潰，如果知道它發生在 app 剛被切到背景的瞬間，排查方向立刻收斂。Sentry 等工具的 breadcrumb 預設就包含這個維度，本 package 目前缺席。

`lib/` 與 `test/` 完全沒有 `WidgetsBindingObserver` / `didChangeAppLifecycleState` / `AppLifecycleState` 的任何使用——這是全新地基，不是既有行為的修改。

## 好品味判斷：不新增資料模型

生命週期切換**本身就是一條 log**。比照 §1 未捕捉例外的既有做法，轉成一筆 `LogEntry`（`LogLevel.info`，訊息如 `App lifecycle: resumed`）灌進既有 log buffer。

由此免費得到：
- Console 分頁直接看得到
- `mergedTimeline()` 自動把它與 network / nav / db 事件按時間軸交錯排序
- 診斷報告、匯出、篩選全部無需改動

**不需要**任何側欄、新分頁、新 model、新 buffer。零 UI 工作。

## 使用者故事

作為使用 flutter_inspector_kit 的**開發者 / QA**：

1. 我在 `FlutterInspector(captureLifecycleEvents: true)` 開啟後，把 app 切到背景再切回前景，打開 Console 能看到對應的 lifecycle log 條目。
2. 我在 Timeline（`mergedTimeline()`）上看到一筆 error 或失敗的 network entry 時，往上找最近一筆 lifecycle log，就能判斷「當時 app 在前景還是背景」。
3. 我**沒有**開啟這個 flag 時（預設），package 完全不掛 observer、Console 不出現任何 lifecycle log——與升級前行為完全一致。

## 驗收條件

reviewer 可逐條驗證：

1. **預設 off**：`FlutterInspector()` 不帶參數建構後，觸發任意 `AppLifecycleState` 變化，`logEntries` 中不出現 lifecycle log。
2. **opt-in 生效**：`FlutterInspector(captureLifecycleEvents: true)` 後，每次生命週期狀態變化各產生**一筆** `LogLevel.info` 的 `LogEntry`，message 可辨識狀態名稱（如 `App lifecycle: paused`）。
3. **狀態覆蓋**：`resumed` / `inactive` / `paused` / `detached` / `hidden` 五個狀態各自都能產生對應 log（見「範圍邊界 (a)」）。
4. **可乾淨移除**：呼叫 `detach()` 後，再觸發生命週期變化**不再**產生新的 lifecycle log（見「範圍邊界 (b)」）。
5. **idempotent**：重複掛載不造成同一次狀態變化記錄兩筆。
6. **不影響宿主**：package 使用 `WidgetsBinding.instance.addObserver`，宿主 app 自己註冊的 observer 照常收到回呼（Flutter 的 observer 是 list，天生並存）。
7. **容錯**：log 呼叫若拋例外，不得讓 `didChangeAppLifecycleState` 向上拋錯影響宿主——比照 `UncaughtErrorHandler` 內部 try-catch 的既有做法。
8. `flutter test` 全綠、`flutter analyze` 無新增 warning。

## 範圍邊界（Out of scope）與設計判斷

### (a) `AppLifecycleState.hidden` — **納入**

本專案 Flutter 3.35，`hidden` 是 enum 的合法成員。**不特別處理它就是最好的處理**：直接把 enum 值轉成字串記錄，五個狀態走同一條路徑，沒有 `if`、沒有白名單、沒有 switch。

刻意排除 `hidden` 反而需要寫一個特殊情況分支，而且會在 desktop / web 上遺失真實訊號（`hidden` 在那些平台是有意義的獨立狀態）。Linus 原則：消滅邊界情況優於新增條件檢查。

副作用可接受：iOS 上 `hidden` 與 `inactive` 常成對出現，會多一筆 log。這是誠實反映 framework 實際發出的狀態，不是雜訊——而且未來 Flutter 新增狀態時，此設計自動支援，零改動。

### (b) observer 生命週期 — **`detach()` 負責 `removeObserver`**

**不沿用** `captureUncaughtErrors` 的「不 teardown」慣例。理由是實質差異，不是慣例偏好：

- `FlutterError.onError` 是**單一 slot**。它之所以不 teardown，是因為 attach 後宿主可能又覆寫過，貿然還原 `_old*` 會把宿主後裝的 handler 也一起幹掉——那才是真正的 break userspace。
- `WidgetsBindingObserver` 是**一個 list**。`removeObserver(this)` 只移除自己這一個實例，對宿主與其他 observer 零影響。可以乾淨移除，就應該乾淨移除——這是 Flutter style guide §7.4「資源管理」的直接要求。

因此 `detach()` 的職責從「只移除 FAB overlay」擴充為「移除 FAB overlay + 移除 lifecycle observer」。這**不是**破壞性變更：既有呼叫者對 `detach()` 的期待是「停止 inspector 的畫面介入」，多清一個自己註冊的 observer 完全落在這個語意內；且未開啟 flag 時 detach 行為逐字不變。

`captureUncaughtErrors` 的 dartdoc 中「hooks are not torn down（detach 只移除 FAB overlay）」這句敘述在本功能落地後會失準，需同步修訂為「error hooks 不 teardown」以免誤導——這是文件精確性問題，不是行為變更。

### (c) log 的 `data` Map — **不帶額外欄位，純 message**

`UncaughtErrorHandler` 帶 `data: {'source': ...}` 是因為它有**三個來源**（`flutterError` / `platformDispatcher` / `errorWidget`）需要區分，那是真實的資訊需求。

lifecycle 只有一個來源，狀態名稱已經在 message 裡。加 `{'source': 'lifecycle'}` 是為不存在的消費者準備的欄位——沒有任何 UI 或篩選器讀它。YAGNI：不加。真的需要程式化篩選時，message 前綴 `App lifecycle:` 已足夠。

### (d) 多實例情境 — **不做去重，文件說明**

同一 app 建多個 `captureLifecycleEvents: true` 的 inspector，會有多個 observer 各記各的 buffer——每個 inspector 的 Console 各看到一筆，行為正確且無交互污染（不像 error hooks 會層層疊加）。

比照 `captureUncaughtErrors` 的既有做法，在 dartdoc 註明「建議只在單一 app-wide inspector 開啟」，不引入全域 registry 或跨實例去重機制。

### (e) 其他明確不做

- **不記錄狀態停留時長**：`paused` 停了多久，讀 Timeline 上兩筆 log 的時間差即可，不預先計算。
- **不新增 UI**：不做側欄、不做 Timeline 上的視覺標記、不做背景時段的區塊著色。
- **不記錄 app 啟動當下的初始狀態**：只記錄「變化」。啟動即前景是常態，一筆固定的開場 log 沒有排查價值。
- **不觸碰 `AppLifecycleListener`**（Flutter 3.13+ 的更細粒度 API，含 `onRestart`/`onExitRequested` 等）：五個狀態已滿足痛點，更細的粒度是 YAGNI。
- **不新增相依套件**：`WidgetsBindingObserver` 來自 `flutter/widgets.dart`，已 import。

## 破壞性分析

**預期為零。** 逐項論證：

| 面向 | 影響 | 理由 |
|------|------|------|
| 公開建構參數 | 無 | 新增**可選**參數 `captureLifecycleEvents = false`，既有呼叫端一字不改仍可編譯，行為完全相同 |
| `logEntries` 內容 | 無 | flag off 時不註冊 observer，不產生任何新 log |
| `detach()` 行為 | 無 | flag off 時沒有 observer 可移除，執行路徑與現況等價 |
| 宿主的 observer | 無 | `addObserver` 是加入 list，非覆寫；宿主的 `didChangeAppLifecycleState` 照常被呼叫 |
| 既有測試 | 無 | 所有既有測試皆以預設參數建構 inspector |
| Buffer 容量 | 極小 | lifecycle 事件頻率低（人為切換），`bufferSize` 預設 500，不構成擠壓風險 |

唯一需要留意的是 `captureUncaughtErrors` dartdoc 中對 `detach()` 的描述需修訂措辭（見 (b)）——文件精確性，非行為破壞。

## 重用清單

不新增任何資料模型、UI、相依。全部重用既有零件：

- `FlutterInspector.log()` — 寫入 log buffer 的唯一入口
- `LogEntry` / `LogLevel.info` — 既有資料模型
- `typedef LogCallback`（`lib/src/core/uncaught_error_handler.dart` 已定義並匯出）— handler 收 log 回呼的既有簽章
- `mergedTimeline()` — 時序交錯，免費疊加
- `UncaughtErrorHandler` 的**模式**（非程式碼）：獨立 handler class、建構式收 `LogCallback onLog`、`_attached` 旗標做 idempotent、內部 try-catch 保護宿主
- `WidgetsBindingObserver` + `WidgetsBinding.instance.addObserver/removeObserver` — Flutter framework 內建
- `test/core/uncaught_error_handler_test.dart` 的**測試模式**：`TestWidgetsFlutterBinding.ensureInitialized()`、注入 counting `onLog` 直接驗證行為
- 文件三處既有慣例對齊：`README.md`（`captureUncaughtErrors: true` 範例附近）、`CHANGELOG.md`、`example/lib/main.dart`

## 不確定 / 待決事項

1. **message 文字格式**：規格採 `App lifecycle: resumed`（brainstorm 原提案）。實作時若 enum 的 `.name` 直接輸出更簡潔，可在不影響驗收條件 2「message 可辨識狀態名稱」的前提下微調。
2. **`detached` 的可觀測性**：Android 上 `detached` 後 log 未必來得及被讀取（進程即將終止）。這是平台限制，不是實作缺陷；規格不承諾 `detached` 的 log 在真機上一定能被撈到，但仍要記錄（測試環境可驗證）。
