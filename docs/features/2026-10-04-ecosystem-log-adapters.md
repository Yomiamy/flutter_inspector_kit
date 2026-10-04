# P16 · 生態日誌適配器（logger / talker / logging）

> **來源**：`docs/brainstorm/2026-09-19-features-brainstorm.md` §P16（第 1090–1130 行）
> **狀態**：功能規格（What & Why）· 2026-10-04
> **範圍**：`README.md` 接線食譜 + `example/` 實際接線；`lib/` 零改動
> **Effort**：trivial～low ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. What & Why

很多既有專案早就用 `package:logger`、`package:talker` 或官方
`package:logging` 打日誌。要它們改呼叫 `FlutterInspector.log()`，等於要求宿主
改寫散落全專案的呼叫點，導入摩擦高到多數人乾脆不接。結果是 Console 混合時間軸
只看得到 network / nav / db 與少數手動 log，**宿主原本最有資訊量的那條日誌流
不在鏈上**，鏈推斷從一開始就斷了一截。

本功能**不往套件裡加任何程式碼**。外部日誌庫的一個事件只是一筆 `LogEntry` 的
原料：在宿主端掛一個同步轉送點，把事件攤成 `FlutterInspector.log(message,
level:, stackTrace:)` 一次呼叫即可。交付物是 README 三段可直接複製的接線食譜，
再加上 `example/` 裡實際接好、可編譯、可執行的對照實作。

實查（2026-10-04）：`lib/`、`README.md`、`example/lib`、`example/pubspec.yaml`、
根 `pubspec.yaml` 中 `talker` / `package:logger` / `package:logging` /
`LogOutput` / `TalkerObserver` 皆零命中，屬全新內容。

---

## 2. 使用者故事（User Stories）

1. 身為一位已在用 `package:logger` 的開發者，導入本套件時我只想在 `main()` 多寫
   **一處接線**，不改任何既有 `logger.i(...)` 呼叫點，終端機輸出也維持原樣。之後
   這些日誌會出現在 Console 時間軸上，和 network / nav / db 事件依時間交錯。
2. 身為一位 `package:talker` 使用者，`talker.handle(e, st)` 捕捉到的例外要在時間軸
   上呈現為 error 等級、列底紅色；點進去後 stack trace 可以在 concise / raw 間切換，
   和套件自己記錄的錯誤一樣。
3. 身為一位 `package:logging` 使用者（也包括透過 `logging` 打日誌的第三方套件），
   我要在時間軸列上直接看到 `loggerName`（例如 `[Auth] token expired`），這樣不必
   點進去就能分辨是哪個模組發出的。
4. 身為開發者，Console 既有的 Level chips、`⚡ Errors only`、搜尋、書籤與
   tap-to-jump 要對這些轉送進來的日誌**照常生效**，不需要任何特殊對待。
5. 身為開發者，我在宿主端設定的過濾（logger 的 `Logger.level` / filter、
   logging 的 `Logger.root.level`、talker 的 filter / `enabled`）要原樣作用在
   Inspector 上：宿主靜音的東西，不應該擠進時間軸。

---

## 3. 驗收條件（Acceptance Criteria）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | **`lib/` 零改動** | `git diff --stat main -- lib/` 輸出為空 |
| 2 | **根 `pubspec.yaml` 零改動**（`dependencies` 與 `dev_dependencies` 皆不新增） | `git diff main -- pubspec.yaml` 輸出為空 |
| 3 | 根套件既有基準不退化 | `flutter test` 全綠（606 tests，數量不變）；`flutter analyze lib/ test/` 不超出既有 7 個 info |
| 4 | `example/pubspec.yaml` 新增 `logger`、`talker`、`logging` 三個相依，`example/` 三條接線全部啟用 | 檢視 diff；`cd example && flutter analyze` 輸出 `No issues found!`（2026-10-04 實測現況即為此值） |
| 5 | README 在 `### Log messages` 之後新增一節，含三段接線食譜（每個套件一段），每段的轉送程式碼與 `example/` 對應檔案**逐字一致**（import 行除外） | 人工逐段比對 |
| 6 | **一個來源事件恰好產生一筆 `LogEntry`**。logger 在預設 `PrettyPrinter` 下一次輸出多行（`OutputEvent.lines` 長度 > 1），仍只產生 1 筆 | example 測試：發一筆 logger 日誌，斷言 log 數量 +1 |
| 7 | logger 轉送的 `message` 不含 ANSI escape（`\x1B`）與框線字元（`┌` `│` `└`），內容為原始訊息本體 | example 測試 |
| 8 | **等級對應**符合 §5.3 對應表，三套件的每個非 deprecated 等級皆有斷言 | example 測試：逐等級發送，斷言 `LogEntry.level` |
| 9 | 來源事件帶有 `StackTrace` 時，`LogEntry.stackTrace == st.toString()`；不帶時為 `null`（logger、talker、logging 各一例） | example 測試 |
| 10 | 來源事件帶有 error / exception 物件時，其 `toString()` 以換行附加在 `message` 後（logger 的 `LogEvent.error`、logging 的 `LogRecord.error`、talker 的 `exception` / `error`） | example 測試 |
| 11 | logging：`loggerName` 非空時 `message` 以 `[loggerName] ` 開頭；root logger（名稱為空字串）不加前綴 | example 測試 |
| 12 | talker 三個 callback 全數轉送：`talker.handle(Exception)` → `onException`、`talker.handle(Error)` → `onError`、`talker.info()` 等 → `onLog`，產出的 entry 等級皆正確 | example 測試 |
| 13 | **時序不錯位**：透過適配器發一筆日誌後**立刻**呼叫 `inspector.log('marker')`，`mergedTimeline()` 中適配器那筆的 `timestamp` 不晚於 marker | example 測試（三套件各一例） |
| 14 | **尊重宿主過濾**：`Logger(level: Level.warning)` 的 `logger.i()` 不會產生 entry（這能證明接線點在 filter 之後） | example 測試 |
| 15 | example App 首頁有一個觸發按鈕，三套件各送出每個等級一筆，外加各一筆帶 stack trace 的錯誤；Console 中顏色、紅底與 `⚡ Errors only` 的結果正確 | 手動：`cd example && flutter run` 後目視確認 |

> 驗收 6–14 的測試放在 `example/test/` 的**單一新檔**，用
> `cd example && flutter test test/<新檔>.dart` 單檔執行。它**不**納入根套件
> `flutter test` 的 606 基準。注意：現存的 `example/test/widget_test.dart` 是預設
> 樣板，2026-10-04 實測**已經會失敗**（`MyApp` 依賴的 `late final inspector`
> 未初始化），因此不可用 `cd example && flutter test` 跑整個目錄來驗收。

---

## 4. 範圍邊界（Scope & Boundaries）

### 4.1 包含（Included）
- README 新增一節（建議標題 `### Bridge existing loggers`），內含三段食譜：
  logger / talker / logging。
- `example/pubspec.yaml` 加入三個套件；`example/lib` 加入三份轉送實作，並在
  `main()` 接線。
- example 首頁加一個觸發按鈕，用來手動驗收（驗收 15）。
- `example/test/` 加一個測試檔（驗收 6–14）。
- README 說明各套件的宿主過濾如何影響 Inspector 能看到的內容（特別是 logging
  的 root 預設等級為 `INFO`）。

### 4.2 排除（Excluded）

| 排除項 | 理由 |
|:---|:---|
| 修改 `lib/` 任何檔案（含新增 export） | 本套件不能 import 外部日誌庫，否則就得加相依。轉送程式碼本質上是宿主端的程式碼 |
| 根 `pubspec.yaml` 新增相依（含 dev_dependencies） | 核心不變式 #5：保持輕量。測試因此放在 `example/test/`，不放根 `test/` |
| 改 `log()` 簽章（例如讓 `stackTrace` 接 `StackTrace`、加 `timestamp` 參數） | Never break userspace。食譜一律用 `?.toString()` |
| 擴充 `LogLevel`（例如新增 `fatal` / `critical`） | 等於動 `lib/`，而且所有 `switch` 消費端都得跟著改。嚴重度折疊的代價見 R1 |
| 拆出獨立 adapter 套件（例如 `flutter_inspector_kit_talker`） | 每個 adapter 只有十幾行，為此開一個 package 再加一條發版流程，不划算 |
| talker 生態擴充（`talker_dio_logger`、`talker_bloc_logger`、`talker_flutter` UI） | Network 已經由 `FlutterInspectorDioInterceptor` 負責；BLoC 違反不變式 #5 的精神 |
| 使用 `LogEntry.data` 欄位承載來源中繼資料（如 logger `LogEvent.time`、logging `sequenceNumber`、talker `key`/`title`） | YAGNI。而且只要 `data` 非空，該列就會變成可點擊，會改變既有 tap affordance 的語意 |
| logger 的 Map / Iterable 訊息轉成 `data`（交給 JSON tree 呈現） | YAGNI；先用 `toString()`，有實證需求再做 |
| 反向橋接（Inspector → 外部日誌庫） | 沒有需求 |
| 版本號變更 | `lib/` 零改動，不需發版。CHANGELOG 是否補條目見 O1 |

---

## 5. 設計決定

### 5.1 logger 的多行 `OutputEvent`：一個事件一筆，文字取自 `origin`，不取 `lines`

這裡有三個選項：

| 選項 | 做法 | 判定 |
|:---|:---|:---|
| A. 逐行一筆 | `for (line in event.lines) inspector.log(line)`（brainstorm 草稿寫法） | ❌ 否決 |
| B. 合併一筆 | `inspector.log(event.lines.join('\n'))` | ❌ 否決 |
| **C. 一事件一筆、取結構化來源** | 讀 `event.origin`（`LogEvent`）：`message` 放進 message、`error` 換行附加、`stackTrace?.toString()` 放進 `stackTrace` 欄位、`level` 依對應表轉換 | ✅ **採用** |

**否決 A 的理由（直接違反「鏈推斷、不切斷前後文」）**：
- 一次 `logger.i()` 在預設 `PrettyPrinter` 下約有 5 行輸出，`logger.e()` 帶
  `errorMethodCount: 8` 則超過 15 行。這等於用 5–15 倍速度消耗共用的
  `RingBuffer(500)`，**真正的前後文會被自己的框線擠出緩衝區**。
- 同一事件的各行時間戳幾乎相同，而 `mergedTimeline()` 用 `List.sort`
  （`inspector_registry.dart:71`），Dart 不保證排序穩定，所以碎片可能亂序。
  Web 平台的 `DateTime` 只有毫秒精度，問題更嚴重。
- 搜尋、書籤、tap-to-jump 只會命中某個碎片（例如一條框線），看不到完整事件。

**否決 B 的理由（看起來合併了，實際上把終端機排版硬塞進 UI）**：
- `PrettyPrinter` 預設 `colors: true`，每行都帶 ANSI escape。Flutter `Text`
  不會解讀它們，只會顯示成亂碼。
- 第一行是 `┌────…` 框線，而 `_LogEntryRow` 會把 `entry.message` 整段渲染且
  **不設 `maxLines`**（`console_tab.dart` `_LogEntryRow`）。結果每筆 logger 日誌
  在時間軸上都是 10 行以上的框，一眼掃不完。
- 即使是 info 等級，`methodCount: 2` 也會把 `StackTrace.current` 的幀印進
  `lines`。堆疊只會混在 message 裡，`stackTrace` 欄位是空的，所以列不可點擊
  （`canTap` 看的是 `stackTrace` / `data`），concise / raw 檢視也用不上。

**C 的代價**：宿主自訂 printer 額外加上的資訊（前綴、類名）不會進 Inspector，
見 R5。`lines` 是 printer 給終端機看的排版，Inspector 本來就有自己的呈現層
（等級色、紅底、concise stack trace），兩邊不需要重複。這是對的切分。

### 5.2 三個套件的接線點

| 套件 | 採用的接線點 | 否決的替代方案 | 理由 |
|:---|:---|:---|:---|
| logger | `Logger.addOutputListener(OutputCallback)`（靜態，對所有 `Logger` 實例生效） | (a) `LogOutput` 子類別 + `MultiOutput`；(b) `Logger.addLogListener` | 選定方案只需一行，宿主既有的 `output:`（Console / File）原封不動，而且已經建好的 `Logger` 實例也涵蓋得到。(a) 佔用每個實例的 `output` 槽位，宿主必須逐一改建構式，或在任何 `Logger` 建構前設好 `Logger.defaultOutput`，有初始化順序陷阱。(b) 在 `filter.shouldLog` **之前**觸發（`logger.dart:179`），會繞過宿主過濾與 release 模式靜音，違反故事 5 |
| talker | `TalkerObserver`（同步）：`Talker(observer: …)` 或 `talker.configure(observer: …)` | `talker.stream.listen` | `stream` 底層是 `StreamController.broadcast()`（非 sync），會在 microtask 才送達。在那之前，同步發生的 `inspector.log` / network 事件已經先蓋了時間戳，**時間軸順序會錯位**。observer 由 `_handleLogData` / `_handleErrorData` 同步呼叫，不會有這問題 |
| logging | `Logger.root.onRecord.listen` | — | `onRecord` 底層是 `StreamController.broadcast(sync: true)`，本身就是同步送達。root 在 `hierarchicalLoggingEnabled == false`（預設）時會收到所有 logger 的 record |

**共通原則**：三條接線**都必須同步**。`log()` 沒有 timestamp 參數，時間戳由它
在呼叫當下自己蓋（`LogEntry` 預設 `DateTime.now()`）。只有同步轉送能讓這個時間戳
貼近來源事件時間（差距在微秒級），並維持與其他時間軸事件的先後關係。因此來源的
`LogEvent.time` / `TalkerData.time` / `LogRecord.time` 都不使用，也不需要使用。

### 5.3 等級對應表

| Inspector `LogLevel` | logger `Level`（依 `value` 閾值） | logging `Level`（依 `value` 閾值） | talker `LogLevel`（窮盡 `switch`） |
|:---|:---|:---|:---|
| `error` | ≥ `error`(5000)：`error`、`wtf`†(5999)、`fatal`(6000) | ≥ `SEVERE`(1000)：`SEVERE`、`SHOUT`(1200) | `error`、`critical` |
| `warning` | ≥ `warning`(4000) | ≥ `WARNING`(900) | `warning` |
| `info` | ≥ `info`(3000) | ≥ `INFO`(800) | `info` |
| `debug` | ≥ `debug`(2000) | ≥ `FINE`(500)：`FINE`、`CONFIG`(700) | `debug`、**`null`** |
| `verbose` | 其餘：`trace`(1000)、`verbose`†(999) | 其餘：`FINER`(400)、`FINEST`(300) | `verbose` |

† 上游已標 `@Deprecated`。

- **logger 用閾值而非逐值 `switch`**：`Level` 雖然是 enum，但窮盡 switch 必須寫出
  `verbose` / `wtf` / `nothing` 三個 deprecated 值，會觸發 `deprecated_member_use`，
  example 的 `No issues found!` 基準就破了。用閾值時 deprecated 值自然落入正確
  區間，不必另寫特殊情況。`all` / `off` / `nothing` 不可能出現在 `LogEvent`
  （建構子會拋 `ArgumentError`，`log_event.dart`）。
- **logging 只能用閾值**：`Level` 是 class 而非 enum，有公開的 const 建構子，
  宿主可以自訂如 `Level('AUDIT', 850)` 的等級。閾值是唯一能涵蓋所有可能值的做法，
  `ALL` / `OFF` 這類極端值也自然有歸屬，不需特判。
- **talker 用窮盡 `switch`**：`LogLevel` 是沒有數值的 enum。窮盡 switch 讓上游日後
  新增等級時，**在宿主端以編譯錯誤提早失敗**，不會被靜默歸類。
- **talker `null` → `debug`**：`TalkerData.logLevel` 型別是 `LogLevel?`（例如
  `logCustom` 自建的 `TalkerLog` 可能不帶等級）。`debug` 與 talker 自身的回退一致：
  `Talker.log()` 預設 `LogLevel.debug`，`_handleForOutputs` 用 `?? LogLevel.debug`。
- **嚴重度上限折疊到 `error`**：`fatal` / `critical` / `SHOUT` 都映成 `error`，見 R1。

### 5.4 欄位對應

| `log()` 參數 | logger（`OutputEvent.origin` = `LogEvent`） | talker（`TalkerData`，三個 callback 共用同一轉送函式） | logging（`LogRecord`） |
|:---|:---|:---|:---|
| `message` | `message` 字串化（`Function` 先求值，對齊 `PrettyPrinter.stringifyMessage`）；`error` 非 null 時換行附加 `error.toString()` | `message`、`exception`、`error` 三者中非 null 且非空者以換行串接 | `loggerName` 非空時加 `[loggerName] ` 前綴 + `message`；`error` 非 null 時換行附加 |
| `level` | §5.3 | §5.3 | §5.3 |
| `stackTrace` | `stackTrace?.toString()` | `stackTrace?.toString()` | `stackTrace?.toString()` |
| `data` | 不使用 | 不使用 | 不使用 |

- **talker 三個 callback 共用同一個轉送函式**。`TalkerError` / `TalkerException`
  都是 `TalkerData` 的子類，`logLevel` 預設為 `error`，所以不需要為
  `onError` / `onException` 另寫分支，也不像 brainstorm 草稿那樣把等級寫死成
  `LogLevel.error`（那樣會忽略宿主自訂的 `logLevel`）。
- **talker 不帶 `title`**：預設 title 就是等級名（`info` / `error` …），對
  Inspector 是冗餘資訊，而等級已經由顏色表達。
- **logging 帶 `loggerName`**：它和等級是不同維度（「哪個模組」），是 logging
  使用者分辨來源的主要依據。放在 message 前綴而不放 `data`，因為前綴在時間軸列上
  看得到、搜得到，也不會讓列變成可點擊（見 §4.2）。
- **食譜形狀**：每個套件提供「一個轉送函式（來源事件 → 一次 `inspector.log` 呼叫）
  + 一行接線」。talker 只有一個 observer 槽位，已有自家 observer 的宿主可以在自己
  的 observer 裡直接呼叫轉送函式（見 R3）。具體函式名與 import 寫法交給
  STAGE 0b 決定。

### 5.5 識別字撞名（食譜必須處理）

以三套件的公開型別名與 `flutter_inspector_kit` 匯出求交集（2026-10-04 實查）：

| 撞名 | 來源 | 影響 |
|:---|:---|:---|
| `LogLevel` | `talker`（re-export 自 `talker_logger`）× `flutter_inspector_kit` | talker 食譜與 kit 同檔匯入時會出現 `ambiguous_import`，**brainstorm 草稿無法編譯**。食譜必須用 import prefix 或 `show` / `hide` 處理，並在 README 明示 |
| `Logger`、`Level` | `logger` × `logging` | 兩個套件不能在同一檔無前綴匯入。example 每個套件獨立一個檔即可避開；README 加一句提示 |
| （無） | `logger` × kit、`logging` × kit | kit 內部的 `LogCallback`（`uncaught_error_handler.dart`）沒有被匯出，不衝突 |

---

## 6. 外部 API 事實（2026-10-04 實查）

查證方式：pub.dev API 取最新版本，再下載該版 tarball 直接讀原始碼，不憑記憶。

### 6.1 `logger` **2.8.0**（2026-09-05 發布，SDK `>=2.17.0 <4.0.0`）

- `abstract class LogOutput { Future<void> init(); void output(OutputEvent event); Future<void> destroy(); }`
- `class OutputEvent { final List<String> lines; final LogEvent origin; Level get level; }`。
  `origin` 自 1.2.0 起提供。
- `class LogEvent { final Level level; final dynamic message; final Object? error; final StackTrace? stackTrace; final DateTime time; }`。
  建構子在 `error is StackTrace` 或 level 為 `all` / `off` / `nothing` 時拋 `ArgumentError`。
- `enum Level { all(0), verbose†(999), trace(1000), debug(2000), info(3000), warning(4000), error(5000), wtf†(5999), fatal(6000), nothing†(9999), off(10000) }`，
  帶 `final int value`；`< <= > >=` 運算子自 2.6.0 起提供；`trace` / `fatal` 自 2.0.0 起提供。
- `static void addOutputListener(OutputCallback)` / `static bool removeOutputListener(…)`，
  其中 `typedef OutputCallback = void Function(OutputEvent)`。觸發點在
  `filter.shouldLog` 與 `printer.log` 之後，並與 `_output.output` 包在**同一個
  try-catch** 裡（例外只會被 `print`，不會傳回宿主），只在 printer 輸出非空時觸發。
- `static void addLogListener(LogCallback)` 在 filter **之前**觸發（因此否決）。
- 預設元件：`DevelopmentFilter`（release 模式全部丟棄）、`PrettyPrinter`
  （`colors: true`、`methodCount: 2`、`errorMethodCount: 8`、`printEmojis: true`、
  帶框線）、`ConsoleOutput`（`event.lines.forEach(print)`）。

### 6.2 `talker` **5.1.20**（2026-07-28 發布，SDK `>=2.17.0 <4.0.0`，相依 `talker_logger ^5.1.20`，純 Dart）

- `abstract class TalkerObserver { const TalkerObserver(); void onError(TalkerError err) {} void onException(TalkerException err) {} void onLog(TalkerData log) {} }`。
  三個方法預設都是 no-op。
- `class TalkerData { final String? message; final LogLevel? logLevel; final Object? exception; final Error? error; final StackTrace? stackTrace; String? title; final String? key; DateTime get time; AnsiPen? pen; String generateTextMessage({TimeFormat timeFormat}); }`。
  `generateTextMessage()` 的輸出 = `[title] | 時間 | ` + message (+ exception/error) + `\nStackTrace: …`。
- `TalkerError extends TalkerData`（`logLevel` 預設 `error`）、
  `TalkerException extends TalkerData`（`logLevel` 預設 `error`）、
  `TalkerLog extends TalkerData`。
- `enum LogLevel { error, critical, info, debug, verbose, warning }`（定義於
  `talker_logger`，由 `talker` re-export）。
- 派發路徑：`onError` / `onException` **只會**由 `talker.handle()` 經
  `_handleErrorData` 觸發；`talker.error()` / `critical()` / `info()` / `log()` /
  `logCustom()` 都走 `_handleLogData` → `onLog`。observer 是**同步呼叫**，**沒有**
  try-catch 包覆；`settings.enabled == false` 或 filter 拒絕時不會呼叫。
- 只有**單一 observer 槽位**：`Talker({TalkerObserver? observer})` /
  `configure({TalkerObserver? observer})`。
- `talker.stream` 底層是 `StreamController<TalkerData>.broadcast()`，非 sync（因此否決）。

### 6.3 `logging` **1.3.0**（2024-10-17 發布，截至 2026-10-04 仍是最新版，SDK `^3.4.0`）

- `class Level implements Comparable<Level> { final String name; final int value; const Level(this.name, this.value); }`。
  常數：`ALL` 0、`FINEST` 300、`FINER` 400、`FINE` 500、`CONFIG` 700、`INFO` 800、
  `WARNING` 900、`SEVERE` 1000、`SHOUT` 1200、`OFF` 2000。支援比較運算子。
- `class LogRecord { final Level level; final String message; final Object? object; final String loggerName; final DateTime time; final int sequenceNumber; final Object? error; final StackTrace? stackTrace; final Zone? zone; }`。
- `Logger.onRecord` 底層是 `StreamController<LogRecord>.broadcast(sync: true)`，同步送達。
- root 預設等級是 `Level.INFO`（`defaultLevel`），所以宿主不調降的話，
  `FINE` / `FINER` / `FINEST` **不會**送出。`hierarchicalLoggingEnabled` 預設
  false，此時所有 record 都發佈在 root 上。
- `log()` 會先對 `Function` 型 message 求值；非 `String` 的 message 會 `toString()`，
  原物件保留在 `object`。

---

## 7. brainstorm 草稿勘誤（§P16，第 1094–1128 行）

草稿裡的三段範例**都無法直接編譯或行為有誤**，不可以照抄進 README：

| # | 位置 | 問題 | 修正 |
|:---:|:---|:---|:---|
| 1 | L1118、L1120 | `stackTrace: err.stackTrace` / `exc.stackTrace` 把 `StackTrace?` 傳給 `String?` 參數，**編譯錯誤** | `stackTrace: data.stackTrace?.toString()` |
| 2 | L1126 | `stackTrace: record.stackTrace`，同上 | `record.stackTrace?.toString()` |
| 3 | L1118、L1120 | `err.message` 型別是 `String?`，傳給 `log(String message)` 會**違反 null safety**。另外 `talker.handle(e)` 沒帶 msg 時 `message` 就是 null，錯誤本體在 `error` / `exception` 欄位，草稿只取 `message`，**主體會遺失** | 依 §5.4 串接 message / exception / error |
| 4 | L1116 | `onLog` 用 `generateTextMessage()`，把 `[title] \| 時間 \|` 和 `\nStackTrace: …` 塞進 message：時間和 Inspector 自己的時間戳重複，堆疊也進不了 `stackTrace` 欄位 | 不使用 `generateTextMessage()`，改讀結構化欄位 |
| 5 | L1103–1105 | 逐行 `for (line in event.lines)` 會讓一個事件變成多筆 | §5.1 方案 C |
| 6 | L1116 | `_mapLevel(log.logLevel)` 忽略 `logLevel` 可為 null | §5.3 `null → debug` |
| 7 | L1118、L1120 | `onError` / `onException` 把等級寫死為 `LogLevel.error`，忽略宿主自訂的 `logLevel` | 三個 callback 共用轉送函式，依 `logLevel` 對應 |
| 8 | L1126 | 沒帶 `record.error` 和 `record.loggerName`，錯誤物件與模組名都會遺失 | §5.4 |
| 9 | L1097 | 宣稱「宿主端 5 行接線」，但 `_mapLevel` 未定義，talker `LogLevel` 撞名也沒處理 | §5.5；食譜必須是完整、可編譯的程式碼 |
| 10 | L1095–1107 | 用 `LogOutput` 子類別接線 | §5.2 改用 `Logger.addOutputListener` |

---

## 8. 風險與未決事項

| # | 項目 | 說明 | 處置 |
|:---|:---|:---|:---|
| R1 | 嚴重度折疊 | `fatal` / `critical` / `SHOUT` 與 `error` 在 Inspector 中無法區分 | 接受。`LogLevel` 已經以 `error` 為頂，紅底與 `⚡ Errors only` 都能命中；要擴充 `LogLevel` 就得動 `lib/`，超出範圍 |
| R2 | 共用 `RingBuffer(500)` | 多話的 `trace` / `FINEST` 可能把較早的前後文擠出緩衝區 | 接線點刻意放在宿主過濾**之後**（§5.2），由宿主的等級設定控制流量；README 提醒 |
| R3 | talker 單一 observer 槽位 | 宿主若已經有 observer（例如上報 Crashlytics），照抄食譜會把它覆蓋掉 | 食譜採「轉送函式 + 薄 observer」形狀，README 示範如何在既有 observer 中呼叫轉送函式 |
| R4 | 重複記錄 | 宿主同時開了 `captureUncaughtErrors: true`，又在自己的 `FlutterError.onError` 鏈裡呼叫 `talker.handle()` / `logger.e()`，同一個錯誤會出現兩筆 | 不處理（兩條上報路徑各記一次是真實情況）。README 註明擇一即可 |
| R5 | logger 自訂 printer 的資訊遺失 | §5.1 方案 C 只讀 `origin`，宿主自訂 printer 加上的前綴或類名不會進 Inspector | 接受。printer 的輸出是終端機排版，不是事件資料 |
| R6 | logger `Function` 訊息被求值兩次 | printer 求值一次，轉送函式再求值一次 | 接受。lazy message 本來就不該有副作用 |
| R7 | talker observer 沒有例外隔離 | talker 不會 try-catch observer，轉送函式拋出的例外會傳回宿主的 `talker.info()` 呼叫點 | 轉送函式只做字串組合加 `inspector.log`，不引入任何可能拋例外的操作 |
| R8 | 上游 API 漂移 | logger 3.x / talker 6.x 可能改簽章，讓 README 食譜失效 | 由 `example/` 實際編譯把關（驗收 4）；README 註明驗證過的版本 |
| R9 | logger 靜態 listener 重複註冊 | `addOutputListener` 底層是 `Set<OutputCallback>`，每次呼叫接線都產生新 closure，不會去重，重複呼叫會重複轉送 | 食譜指明在 `main()` 建好 inspector 後呼叫一次（hot reload 不重跑 `main()`，hot restart 會重置 static，兩者都安全） |
| R10 | `example/test/widget_test.dart` 樣板已失效 | 2026-10-04 實測失敗，與本功能無關 | 不在本次修正；新測試以單檔執行（見 §3 註） |
| O1 | CHANGELOG 條目 | `lib/` 零改動、不發版，但 README 新增了一節 | **未決**：建議下次發版時補一條 Docs 條目；本 feature 不動四處版本號 |

---

## 9. 相關檔案（實查基準）

- `lib/src/core/flutter_inspector.dart:385` — `void log(String message, {LogLevel level = LogLevel.info, String? stackTrace, Map<String, dynamic>? data})`
- `lib/src/models/log_level.dart` — `enum LogLevel { verbose, debug, info, warning, error }`
- `lib/src/models/log_entry.dart` — `timestamp` 預設 `DateTime.now()`；`stackTrace` 為 `String?`
- `lib/src/core/inspector_registry.dart:71` — `mergedTimeline()` 以 `List.sort` 依 timestamp 降冪排序
- `lib/src/ui/dashboard/tabs/console_tab.dart` `_LogEntryRow` — message 整段渲染、不設 `maxLines`；`canTap` 看的是 `stackTrace` / `data` 是否非空
- `README.md:386` — `### Log messages`（新一節插入點）
- `example/pubspec.yaml` — 目前沒有任何日誌套件
- `example/lib/main.dart` — `main()` 建構 inspector 的位置（接線點）；`example/lib/demos/` 為既有 demo 慣例
- `example/test/widget_test.dart` — 失效樣板（R10）
