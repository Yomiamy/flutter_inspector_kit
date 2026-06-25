# 功能規格：全局未捕捉例外捕捉 + Console 錯誤詳情可展開

- **日期**：2026-06-20
- **狀態**：STAGE 0a — 待確認
- **來源**：`docs/brainstorm/2026-06-25-features-brainstorm.md` 的 #1（全局未捕捉例外捕捉）+ #5 的 LogDetailView 部分（ConsoleTab 排查化中「error 詳情可展開」這一半）
- **類型**：功能新增（可選、預設關閉）+ Console UI 強化

---

## 1. 背景與動機（Why）

`flutter_inspector_kit` 自我定位為 debug／排查工具，但目前是「錯誤的盲人」：

- **看不到未捕捉的例外**：codebase 中沒有任何 `FlutterError.onError`、`PlatformDispatcher.instance.onError`、`ErrorWidget.builder` 或 `runZonedGuarded` 掛點。最常導致線上問題的錯誤——async error、widget build error、`onPressed` 裡漏接的 exception——inspector 一個都看不到，全靠開發者記得手動 `try-catch` + `inspector.log()`。覆蓋率取決於人的自律，等於沒有覆蓋。
- **看得到也展不開**：`LogEntry` 早已定義 `stackTrace` 與 `data` 兩個欄位（`lib/src/models/log_entry.dart`），但 `ConsoleTab`（`lib/src/ui/dashboard/tabs/console_tab.dart`）只渲染 `message` 著色 + `timestamp`，列表項**點擊無反應**，`stackTrace` 與 `data` 在 UI 上完全看不到。捕捉到例外卻無法在 UI 展開 stackTrace，等於白捕捉。

這兩件事必須**綁在一起做**才形成完整排查閉環：

> 捕捉（看見錯誤）→ 詳情可展開（看懂錯誤的 stackTrace 與 context）

兩者都只動 Console 區塊，scope 內聚；任何一半單獨上線都不構成可用的排查能力。

### 設計核心（已拍板的關鍵決策）

> 不要為「捕捉錯誤」發明新的儲存與 UI。捕捉到的例外**就是一條 `LogLevel.error` 的 log**。

- **零新資料模型**：捕捉到的例外經由既有的 `inspector.log(message, level: LogLevel.error, stackTrace: ..., data: ...)` 記成一條 `LogEntry`，重用既有 `RingBuffer`。
- **零新 tab**：不開「Errors」分頁。捕捉到的例外就在 Console tab 裡，以 `LogLevel.error` 的紅色 log 呈現。
- **詳情就地展開**：Console 的 error log 點擊可展開，呈現 `message` / `level` / 可複製的 `stackTrace` / `data`。

### 現況關鍵檔案

| 檔案 | 角色 | 現值 |
|---|---|---|
| `lib/src/core/flutter_inspector.dart` | 建構子 + `log()` 入口 | 建構子已有 `customTab` / `magicalTapCount` / `showNetworkNotification` / `navigatorKey` / `bufferSize` / `notifier` / `databaseSources`；`log(message, {level, stackTrace, data})` 已存在 |
| `lib/src/models/log_entry.dart` | 資料模型 | `message` / `level` / `stackTrace(String?)` / `data(Map?)` / `timestamp` 皆已存在；`stackTrace`、`data` **無人使用** |
| `lib/src/ui/dashboard/tabs/console_tab.dart` | Console UI | `ListTile` 只顯示 `message` + `timestamp`，**點擊無反應**；已有 `_getColorForLevel()` |
| `lib/src/ui/widgets/key_value_table.dart` | 可重用 widget | 用於詳情頁展示 `data` |
| `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | 詳情頁佈局範本 | `SelectableText` 可複製、card 分層、`PopupMenuButton` share menu |
| `lib/src/utils/share_text.dart`（既有 share 工具） | 分享 | 平台自適應分享文字 |
| `LogInspector.entriesAtLevel(level)` | 既有 getter | 已存在但 UI **未使用** |

---

## 2. 使用者故事與驗收條件

### US-1：開發者捕捉 widget build／layout／paint 錯誤

> 身為開發者，當某個 widget 在 build／layout／paint 階段拋出例外時，我希望這個 framework 層錯誤自動成為 Console tab 裡一條紅色 error log，不必我手動 try-catch。

**驗收條件：**

- [ ] 啟用捕捉後，`FlutterError.onError` 觸發的錯誤被轉成一條 `LogLevel.error` 的 `LogEntry`，`message` 含錯誤摘要，`stackTrace` 含 framework 提供的堆疊。
- [ ] **錯誤仍往下游傳**：捕捉 handler **chain（鏈接）** 既有 `FlutterError.onError`（若宿主已設）；若宿主未設，則仍呼叫 `FlutterError.presentError` 走預設呈現。debug console 的紅屏／既有錯誤輸出行為不消失。
- [ ] 該錯誤出現在 Console tab，顏色為紅色（沿用 `_getColorForLevel(LogLevel.error)`）。

### US-2：開發者捕捉未處理的 async 例外

> 身為開發者，當 `Future`／async 流程中拋出未被 `catchError` 接住的例外時，我希望它自動成為一條 error log，而不是只在 platform console 一閃而過。

**驗收條件：**

- [ ] 啟用捕捉後，`PlatformDispatcher.instance.onError` 觸發的未捕捉 async error 被轉成一條 `LogLevel.error` 的 `LogEntry`，含 `stackTrace`。
- [ ] **錯誤仍往下游傳**：捕捉 handler chain 既有 `PlatformDispatcher.instance.onError`（若宿主已設）。handler 的回傳值維持原本「是否視為已處理」的語意，不改變宿主對未處理錯誤的後續流程。
- [ ] 需要 zone 級捕捉（例如 `runZonedGuarded` 才攔得到的 error）的情境，由 US-5 的 `runGuarded` 入口涵蓋。

### US-3：開發者知道是哪個 widget build 失敗

> 身為開發者，當某 widget build 失敗顯示錯誤佔位 widget（紅屏）時，我希望 Console 留下一條 error log 記錄是哪個 widget 失敗，方便回溯。

**驗收條件：**

- [ ] 啟用捕捉後，`ErrorWidget.builder` 被**包裝**（wrap）而非取代：先記一條 `LogLevel.error` log（含 build 失敗的 `FlutterErrorDetails` 摘要與 stackTrace），**再轉交原本的 `ErrorWidget.builder` 產出原本的錯誤佔位 widget**。
- [ ] 畫面上實際顯示的錯誤佔位 widget 與未啟用本功能時一致（不破壞既有紅屏／release 灰屏呈現）。

### US-4：開發者／QA 展開 error log 看 stackTrace 與 data

> 身為開發者或 QA，當我在 Console tab 看到一條 error log，我希望點它就能展開詳情，看到完整可複製的 stackTrace 與附帶的 data，把證據帶走。

**驗收條件：**

- [ ] 在 Console tab 點擊一條含 `stackTrace` 或 `data` 的 error log，開啟詳情視圖（仿 `NetworkDetailView` 佈局：card 分層）。
- [ ] 詳情視圖呈現 `message`、`level`、`timestamp`、`stackTrace`（以 `SelectableText` 呈現，**可選取複製**）、`data`（以 `KeyValueTable` 呈現）。
- [ ] 詳情視圖提供分享入口（`PopupMenuButton` / share），透過既有 `share_text` 工具把詳情以純文字分享出去。
- [ ] 當 log 的 `stackTrace` 與 `data` 皆為 `null`（例如純 `info` log），列表項可不可點或點擊後詳情頁對應區段顯示為空／省略——不得崩潰。

### US-5：開發者用薄包裝入口啟用 zone 級捕捉

> 身為開發者，當我需要連 zone 內的同步錯誤都捕捉時，我希望有一個薄包裝入口包住 `runApp`，而不必自己在 `main()` 裡手寫 `runZonedGuarded` 並接線三個 handler。

**驗收條件：**

- [ ] 提供一個薄包裝入口（形狀見 §4），開發者以它包住 `runApp(...)` 即可在同一個 guarded zone 內完成三個標準掛點接線 + zone error 捕捉。
- [ ] 入口**不取代宿主 `main()` 的其他內容**：開發者仍可在入口外自行做初始化；入口只負責「在 guarded zone 中執行傳入的 callback 並接好掛點」。
- [ ] 入口捕捉到的 zone error 同樣轉成 `LogLevel.error` log 且**往下游傳**（不吞掉）。

### US-6：預設關閉，不啟用時行為完全不變（Never break userspace）

> 身為既有使用者，我沒有要求這個功能，我希望升級套件後我的 app 錯誤流、UI、API 行為一個位元都不變。

**驗收條件：**

- [ ] 新增的捕捉功能由建構子可選參數控制，**預設 off**。不傳該參數時，套件**完全不接管** `FlutterError.onError` / `PlatformDispatcher.instance.onError` / `ErrorWidget.builder`，宿主錯誤流維持原樣。
- [ ] 既有 `FlutterInspector(...)` 的呼叫端不需任何改動即可編譯（新參數有預設值）。
- [ ] 既有 `inspector.log()` 簽名與語意不變。
- [ ] Console tab 對既有非 error log（info／warning 等）的呈現不退化；只是新增「可展開詳情」這個能力。

---

## 3. 範圍邊界（Scope）

### In Scope（做什麼）

1. **三個標準掛點 + 一個薄包裝入口**，以**可選、預設 off** 的建構子參數啟用：
   - `FlutterError.onError`（chain，不取代）
   - `PlatformDispatcher.instance.onError`（chain，不取代）
   - `ErrorWidget.builder`（wrap，先記 log 再轉交原 builder）
   - zone 級捕捉的薄包裝入口（包住 `runApp`，不污染 `main()`）
2. **捕捉到的例外 = 一條 `LogLevel.error` log**：重用 `inspector.log()` + `LogEntry`（`stackTrace` / `data`），零新資料模型、零新 tab。
3. **Console error log 詳情可展開**：點擊 log 開詳情視圖，呈現 `message` / `level` / `timestamp` / 可複製 `stackTrace` / `data`（`KeyValueTable`），並提供分享入口。

### Out of Scope（不做什麼）

- **不開新 tab**：捕捉到的例外不另立「Errors」分頁，就在 Console tab 裡當一條 error log。
- **不做 ConsoleTab 的搜尋／過濾**：搜尋欄、`LogLevel` FilterChip、「errors only」快捷是 brainstorm #5 的**另一半**，不在本功能。本功能只做「error 詳情可展開」與「捕捉」。
- **不做跨 session 持久化**：不把捕捉到的錯誤寫入磁碟、不做重啟後還原的 crash history（brainstorm anti-feature #2，違反「砍掉一半再砍一半」，且引入磁碟 IO／序列化相容／隱私三重風險）。
- **不做效能監控**：FPS、frame drop、記憶體 profiling 不在範圍（brainstorm anti-feature #1，屬另一產品維度，Flutter DevTools 已有）。
- **不取代宿主的任何 handler**：所有掛點皆 chain／wrap 既有 handler，**絕不**覆蓋或吞掉宿主 app 的崩潰。
- **不做 #4（Dio 結構化錯誤捕捉）**：那動 `dio_interceptor`，寫入路徑與本功能不重疊，屬第一階段的另一項，獨立規劃。
- **不做 #2（跨 Inspector 時序關聯／±5s 側欄）**：詳情視圖此次**不**加「同時段事件」側欄，留待後續階段。

---

## 4. 公開 API 變更草案（對外契約，不寫實作）

> 僅描述對外契約。實際命名與細節以 STAGE 0b 實作計畫為準；以下為提案。

### 4.1 建構子新增可選參數（預設 off）

```dart
FlutterInspector({
  // ...既有參數不變...
  bool captureUncaughtErrors = false, // ← 新增，預設 false
});
```

- `captureUncaughtErrors`：是否啟用全局未捕捉例外捕捉。
  - `false`（預設）：套件不接管任何錯誤掛點，行為與現況完全一致（US-6）。
  - `true`：套件 chain `FlutterError.onError`、chain `PlatformDispatcher.instance.onError`、wrap `ErrorWidget.builder`，把捕捉到的例外記成 `LogLevel.error` log。**捕捉後一律把錯誤往下游傳**。

### 4.2 zone 級捕捉的薄包裝入口（提案形狀）

```dart
// 提案：包住 runApp 的薄包裝；在 guarded zone 內接好三個掛點 + 捕捉 zone error。
// callback 內呼叫 runApp(...)。捕捉到的 error 轉成 error log 後仍往下游傳。
static void runGuarded(
  void Function() body, {
  required FlutterInspector inspector,
});
```

- 對外契約要點：
  - 接受一個 `body`（內含 `runApp(...)`），在 guarded zone 中執行。
  - 需要一個已建立的 `inspector` 實例作為 log 接收端。
  - 等價於「為開發者代寫 `runZonedGuarded` + 接線三個掛點」的薄包裝，**不**強迫改寫宿主 `main()` 的其他內容。
  - 捕捉到的 zone error 轉成 `LogLevel.error` log 後**往下游傳**（不吞）。

> 註：`runGuarded` 與 `captureUncaughtErrors` 的職責邊界、以及「同時用兩者是否會重複接線」的去重策略，屬實作細節，由 STAGE 0b 決定；規格層面的硬約束是：**任一路徑捕捉到的錯誤都必須往下游傳，且預設不啟用。**

### 4.3 不變更的契約

- `inspector.log(message, {level, stackTrace, data})`：簽名與語意**不變**，捕捉路徑直接複用。
- `LogEntry` / `LogLevel`：**不新增欄位**。
- `ConsoleTab` 的對外建構（`ConsoleTab(inspector: ...)`）：不變，僅內部新增「點擊展開詳情」行為。

---

## 5. 跨領域驗收

- [ ] `flutter analyze` 零新增 issue。
- [ ] `flutter test` 全綠；新增測試涵蓋：(a) 捕捉路徑把例外轉成 `LogLevel.error` log；(b) chain 行為——既有 handler 仍被呼叫（錯誤往下游傳）；(c) `captureUncaughtErrors: false` 時不接管任何掛點。
- [ ] 對外公開 API 無破壞性變更（既有呼叫端零改動即可編譯）。
- [ ] example app 可編譯，並能示範 `captureUncaughtErrors: true` 或 `runGuarded` 捕捉到一條 error log 並在 Console 展開其 stackTrace。
- [ ] README 補充「Uncaught error capture」段，說明可選啟用方式、預設關閉、以及「捕捉後錯誤仍往下游傳」的保證。

---

## 6. 風險與待解

- **掛點去重**：同時啟用 `captureUncaughtErrors: true` 與 `runGuarded` 是否導致同一掛點被接兩次（→ 一條錯誤記成兩條 log）。需在 STAGE 0b 定義去重策略；規格層要求是「不得因此漏傳錯誤往下游」。
- **chain 順序**：chain 既有 handler 時，是「先記 log 再呼叫原 handler」或反之，影響 debug console 輸出順序；不影響正確性，但需在實作明確並測試。
- **`PlatformDispatcher.onError` 回傳語意**：該 handler 回傳 `bool` 表示「是否已處理」。本功能 chain 後的回傳值必須維持宿主原意，避免意外改變宿主對未處理錯誤的後續行為（例如吞掉了本該上報的 error）。
- **release 模式呈現**：`ErrorWidget.builder` 在 release 下的灰屏 vs debug 紅屏行為，包裝後須維持一致。

---

## 確認

請確認以上功能規格（使用者故事、驗收條件、範圍邊界、公開 API 變更草案）。確認後進入 **STAGE 0b** 產出實作計畫。
