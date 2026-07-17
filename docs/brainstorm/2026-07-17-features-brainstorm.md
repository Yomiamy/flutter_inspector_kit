# 🩺 Flutter Inspector 錯誤問題排查與分析：功能腦力激盪報告

> **建立日期**：2026-06-25（原始檔名）｜**最後更新**：2026-07-18（新增 **#10 WebView Inline Debugging** 提案，見第三部分；2026-07-17：#9 診斷報告 Timeline 重設計已於 PR #87 完成並合入 main，由 ⬜ 升級為 ✅）

> 「好代碼沒有特殊情況。」 —— Linus Torvalds
>
> 這份報告**只聚焦一件事**：當 app 出錯時，`flutter_inspector_kit` 能不能讓開發者/QA 用最少的步驟「看見錯誤、關聯原因、帶走證據」。
> 我們不重彈上一份 [`brainstorm/2026-06-18-feature_brainstorming.md`](../../brainstorm/2026-06-18-feature_brainstorming.md) 的泛用優化清單，而是用排查（troubleshooting）這把尺，重新審視每個缺口。凡是偏離「排查」核心、或為了理論完美而增加複雜度的，一律砍掉。

---

## 📊 完成度總覽（截至 2026-07-17 · 含 v1.5.0）

> 以下狀態依實際 codebase 與 git history 核對標注。✅ 完成 ｜ 🟡 部分完成 ｜ ⬜ 未實作。
> **更新說明**：v1.1.0（PR #40 / #42）把 console 重構為真正的混合時間軸後，**#2 由 ⬜ 升級為 🟡**（時序關聯的主體已落地）。PR #51 完成 **#8 當前路由堆疊可視化**，由 ⬜ 升級為 ✅。v1.3.0 完成 **#4 Dio 結構化錯誤捕捉**，由 🟡 升級為 ✅，並修正了 **#7 錯誤聚合摘要** 的狀態為 ✅。最新檢視 codebase (v1.5.0) 發現 **#3 一鍵診斷報告** 也已完成（`buildDiagnosticReport` 及 `ExportReportSheet`），由 ⬜ 升級為 ✅。**#9 診斷報告 Timeline 重設計** 已於 PR #87（2026-07-17 合入 main）完成，由 ⬜ 升級為 ✅——匯出報告的 `## Logs` 已改為按 `timestamp` 降序交錯四層事件的 `## Timeline` 混合串流。總計已完成 8 項。**2026-07-18 新增 #10 WebView Inline Debugging 提案**（⬜ 未實作，見第三部分）。

| # | 功能 | 狀態 | 備註 |
|---|------|:---:|------|
| **#9** | **診斷報告 Timeline 重設計** | **✅** | PR #87：`## Logs` → 按 `timestamp` 降序交錯四層的 `## Timeline` 混合串流；新增 `buildLogOneLiner`/`buildNetworkOneLiner` 單行 formatter，`errorsOnly` 升級為過濾整條 stream，`## Network`/`## Navigation`/`## Database` detail section 不動 |
| #1 | 全局未捕捉例外捕捉 | ✅ | PR #30：`captureUncaughtErrors`(default off) + 三掛點 chain，含去重（去重實質上未實作，onError 與 errorWidget.builder 仍會重複觸發） |
| #6 | 網路請求重放 | ✅ | PR #36 / v1.0.0 已完成：支援 per-Dio 原樣重送、`isReplay` 標記、狀態回饋與防連點保護 |
| #8 | 當前路由堆疊可視化 | ✅ | PR #51（Issue #50）：新增 `NavigatorStackResolver` 純 Dart 重播器，`NavigatorTab` 以 `ChoiceChip` 切換「當前堆疊」（垂直卡片）與「事件歷史」 |
| #2 | 跨 Inspector 時序關聯 | 🟡 | **v1.1.0 大幅推進**：ConsoleTab 已改用 `mergedTimeline`（四 buffer 按 `timestamp` 歸併排序），即文件「做法 B：Timeline 視圖」的本體已成；**缺** 做法 A（detail view 的 ±5s 同時段側欄） |
| #4 | Dio 結構化錯誤捕捉 | ✅ | v1.3.0：`NetworkEntry.errorType`(`DioExceptionType`)/`errorStackTrace` 欄位、`response==null` 傳輸層失敗 vs `!=null` server 錯誤的分類判斷、`NetworkDetailView` 的 Exception Details section、純文字匯出皆已落地 |
| #5 | ConsoleTab 排查化 | 🟡 | `LogDetailView`(stackTrace/data/分享) 完成；**缺** 搜尋欄 / LogLevel FilterChip / errors-only 過濾——現有 `FilterChip` 是 timeline **來源**過濾（All/Log/Network/Nav/DB），非 LogLevel 過濾，`entriesAtLevel()` 仍未被使用 |
| #3 | 一鍵診斷報告 | ✅ | 已實作：提供 `buildDiagnosticReport` 產生 Markdown 報告，並在 Dashboard 實作 `ExportReportSheet` 匯出 |
| #7 | 錯誤聚合摘要 | ✅ | v1.3.0 已實作：新增 NetworkErrorGroup 聚合模型與 _ErrorSummaryBanner / _ErrorGroupCard UI 元件 |
| #10 | WebView Inline Debugging（觀測層） | ⬜ | 2026-07-18 新提案：JS payload + host-injection bridge，把 WebView 的 console/error/fetch 映射為既有 `LogEntry`/`NetworkEntry` 入列 Timeline——零新相依、零 schema 變更（見第三部分） |

**Anti-features**（Profiler / 落盤 crash history / HAR timing / API mocking）— ✅ 正確地皆未實作，守住「不走向微核心」。

**進度結論**：9 項裡 8 項完成（#1、#3、#4、#6、#7、#8、**#9**，以及 v1.1.0 實質完成的 #2 時序軸主體），僅剩 1 項半成品（#5 console 搜尋/過濾）。2026-07-18 新增 **#10 WebView 觀測**（⬜ 新提案），清單增為 10 項。

---

## 🐧 三個鐵律問題

1. **這是真實問題，還是腦補？**
   - 真實。掃描現有 codebase 後確認：**inspector 目前完全看不到「它沒被手動餵進來」的錯誤**——沒有任何全局例外捕捉，沒有 widget build error 攔截，Dio error 只存 `err.toString()` 丟掉了 stackTrace。錯誤排查工具卻是「錯誤的盲人」。
2. **有沒有更簡單的方法？**
   - 有，而且核心抽象都已存在。`RingBuffer`、`InspectorRegistry`、各 `*Inspector` 的 `add()`、`@immutable` 的 entry models、`LogEntry.stackTrace`（已定義卻沒人用）、共用 `timestamp`——排查能力幾乎都能靠**組合既有零件**長出來，不需要新框架。
3. **這會破壞什麼嗎？**
   - 不會。全部以擴充式設計：新增可選建構參數（default off）、新增 getter、新增 UI section。**絕不改動既有 `FlutterInspector` 公開 API 的行為**。

---

## 🔍 排查能力現況盤點

> **當前現況快照（v1.5.0）**：相較於初期有四個紅燈的盲區，經過多次迭代後，目前排查基礎建設已大幅補齊，僅剩 Console 的搜尋/過濾仍待優化。

| 排查環節 | 現況 (v1.5.0) | 評級 |
|---|---|---|
| 看見「我主動 log 的」錯誤 | `inspector.log()` 正常記錄；`LogDetailView` 支援點擊展開、複製與分享 stackTrace | ✅ 完善 |
| 看見「未捕捉」的例外 | 已實作 `captureUncaughtErrors`，完整覆蓋 `FlutterError.onError`、`PlatformDispatcher` 與 `ErrorWidget.builder` | ✅ 已捕捉 |
| 看見網路失敗的根因 | 成功擷取 `err.type` 與 `stackTrace`，能精準區分「傳輸層失敗」與「Server 錯誤回應」 | ✅ 已修復 |
| 關聯「錯誤前後發生了什麼」 | `mergedTimeline` 將四個 buffer 歸併，跨層時序主體已成；但仍缺單筆 detail view 的 ±5s 聚焦側欄 | 🟡 尚欠聚焦 |
| 帶走排查證據 | `buildDiagnosticReport`／`ExportReportSheet` 已落地，且 #9（PR #87）將 `## Logs` 換為 `## Timeline` 混合串流，四層事件按 `timestamp` 降序交錯——報告可直接看出跨層因果 | ✅ 完善 |
| 過濾定位 error log | `LogInspector.entriesAtLevel()` 仍未被 UI 呼叫，ConsoleTab 依然缺乏搜尋欄與 LogLevel FilterChip | 🔴 依然不足 |
| 看見 WebView 內的事件（console / JS error / fetch） | 零能力——`lib/` 無任何 webview 程式碼，宿主 app 嵌的 H5 頁對 inspector 完全隱形 | 🔴 全盲（#10 新提案） |

> 結論：排查鏈條上的六個環節，如今**四個綠燈、一個黃燈、一個紅燈**。#9（PR #87）補上診斷報告的跨層混合時序後，僅剩單筆 detail view 的 ±5s 聚焦側欄（黃燈）與 ConsoleTab 篩選體驗（紅燈）兩個摩擦點。**2026-07-18 盤入第七個環節：WebView 觀測——混合開發場景下的新盲區（🔴 全盲），由 #10 提案補上。**

---

## ✅ 第零部分：診斷報告 Timeline 重設計（已完成 · PR #87）

### 9. 診斷報告 Timeline 重設計（Diagnostic Report Timeline Redesign）— ✅ 已完成（PR #87）
* **痛點**：`v1.5.0` 的 `buildDiagnosticReport` 將 LogEntry、NetworkEntry、NavigatorEntry、DatabaseEntry 輸出為四個獨立 section。排查時最關鍵的跨層因果關係（例：按鈕點擊 → API 呼叫 → 5xx → error log）在報告中完全斷裂，QA 拿到報告後仍需人工對齊時間戳才能還原事件脈絡。此外 `## Logs` section 格式冗長（每筆都含 General / StackTrace / Data 區塊），90% 無 stackTrace 的 entry 佔據大量垂直空間。
* **好品味設計（核心洞察）**：
  > 四個 buffer 的 entry 都已實作 `TimestampedEntry` 介面，共用 `timestamp` 欄位——這個共通基礎就是答案。不需要新資料模型。
  - 將 `## Logs` section 替換為 `## Timeline` section，以 `mergedTimeline()` 相同的歸併排序邏輯，將四層事件按 `timestamp` 降序交錯排列。
  - 每筆事件以**高密度單行格式**呈現，加上來源 tag：
    - `[HH:mm:ss] [LOG/{level}] {message}` — 有 stackTrace 時附加最多 3 行縮排
    - `[HH:mm:ss] [NET] {method} {path} → {status} ({duration}ms)` — 無 statusCode 時 `✗ {errorType}`
    - `[HH:mm:ss] [NAV] {action} {routeName}`
    - `[HH:mm:ss] [DB] {operation} {tableName} ({rows} rows)`
  - `errorsOnly` 旗標從「僅過濾 log」升級為「過濾整條 Timeline 串流」：只保留 error/warning log + 錯誤網路請求（`statusCode >= 400` 或 `errorType != null`）。
  - 獨立的 `## Network`、`## Navigation`、`## Database` detail section **保留不動**，提供完整 request/response payload。
* **重用**：`TimestampedEntry` 介面、各 entry model 的 `displayTime`、既有 `_writeSection` 工具函式、`buildCurl`/`buildPlainText` 序列化。
* **品味守則**：Timeline 只是既有 entry 的**格式化投影**，不複製資料、不引入新模型。section rename 是語義升級而非結構重構。
* **Effort**：low–medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **實作計畫**：見 [`docs/plans/2026-07-16-diagnostic-report-timeline-design.md`](../plans/2026-07-16-diagnostic-report-timeline-design.md)（design spec）與 [`docs/plans/2026-07-16-diagnostic-report-timeline-plan.md`](../plans/2026-07-16-diagnostic-report-timeline-plan.md)（implementation plan），兩個 Chunk：
  - **Chunk 1**：建立 `buildLogOneLiner()` / `buildNetworkOneLiner()` single-line formatters（修改 `log_formatters.dart` + `network_formatters.dart`）
  - **Chunk 2**：重構 `buildDiagnosticReport()`——移除獨立 Logs block、新增混合 Timeline builder、升級 `errorsOnly` 過濾邏輯
* **影響範圍**：`lib/src/utils/log_formatters.dart`、`lib/src/utils/network_formatters.dart`、`lib/src/utils/diagnostic_report.dart`、`test/utils/diagnostic_report_test.dart`
* **破壞性分析**：`buildDiagnosticReport()` 的輸出格式會改變（`## Logs` → `## Timeline`），但此函式目前僅供 `ExportReportSheet` 內部消費，**無外部 API 合約**，零破壞風險。
* **✅ 實作現況（PR #87 · 2026-07-17 合入 main）**：兩個 TDD commit 落地——`buildLogOneLiner`/`buildNetworkOneLiner` 單行 formatter（`log_formatters.dart`/`network_formatters.dart`），`buildDiagnosticReport` 的 `## Logs` 換為 `## Timeline` 混合串流（依 `sections` 合流四源 → `inWindow` 時窗 → `timestamp` 降序 → 逐筆單行）。與原設計的差異：時間戳復用既有 `displayTime` extension 故為毫秒級 `[HH:mm:ss.mmm]`；Timeline 以 `- {oneLiner}` inline list item 呈現（非 fenced block）並把 log 訊息換行壓平，結構上杜絕訊息內含 ``` 撐破 markdown。code review 另補強：CRLF／孤立 `\r` 一併壓平、`Uri.tryParse` 失敗時 fallback 於首個 `?`/`#` 截斷避免 query secret 外洩。`## Network`/`## Navigation`/`## Database` detail section 未動；log 的 `data` 與完整 stacktrace 不再進報告（僅 message + 前 3 frame）為刻意取捨。

---

## 🛠️ 第一部分：補上排查盲區（高優先 · 真正的缺口）

### 1. 全局未捕捉例外捕捉（Uncaught Error Capture）— ✅ 已完成（原 🔴 最大盲區）
* **痛點**：async error、widget build error、`onPressed` 裡漏接的 exception——這些**最常導致線上問題**的錯誤，inspector 一個都看不到，全靠開發者記得手動 try-catch + log。覆蓋率取決於人的自律，等於沒有。
* **好品味設計（關鍵洞察）**：
  > 不要為「捕捉錯誤」發明新的儲存與 UI。捕捉到的例外**就是一條 `LogLevel.error` 的 log**。
  - 新增**可選**入口 `FlutterInspector(captureUncaughtErrors: true)`（default **off**，絕不強制接管宿主 app 的錯誤流）。
  - 內部設置三個標準掛點，把例外轉成 `inspector.log(msg, level: error, stackTrace: ...)`：
    - `FlutterError.onError`（**chain 既有 handler**，不取代）→ framework 層 build/layout/paint error
    - `PlatformDispatcher.instance.onError` → 未捕捉的 async error
    - `ErrorWidget.builder` → 包裝既有 builder，記錄是哪個 widget build 失敗後再轉交原 builder
  - 對需要 `runZonedGuarded` 的情境，提供 `FlutterInspector.runGuarded(() => runApp(...))` 薄包裝，**不污染** `main()`。
* **重用**：`inspector.log()` + `LogEntry.stackTrace`（終於有人用它了）+ `RingBuffer`。零新模型。
* **品味守則**：chain 而非覆蓋既有 handler。捕捉後**必須**把錯誤往下游傳（`FlutterError.presentError` / 重拋），否則就違反「Never break userspace」——debug 工具不該吞掉宿主的崩潰。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **✅ 實作現況**：PR #30 已完成。`FlutterInspector(captureUncaughtErrors: false)` 入口 + `setupErrorHandlers()` 三掛點（`FlutterError.onError` chain、`PlatformDispatcher.onError`、`ErrorWidget.builder`）皆落地，並補上同一例外的去重（註：例外去重實際上並未在 UncaughtErrorHandler 中實施，同一個 build 崩潰仍會重複記錄二次）；`runGuarded` 已移除改用 `PlatformDispatcher.onError`。

### 2. 跨 Inspector 時序關聯（Correlated Timeline）— 🟡 部分完成（原 🔴 排查的靈魂）
* **痛點**：錯誤幾乎都是跨層的——「點了某按鈕（nav）→ 發了某 API（network）→ 5xx → 印了某 error log」。但現在這四件事躺在四個孤立 buffer 裡，開發者得在四個 tab 之間用肉眼對時間戳，這是排查最大的摩擦。
* **好品味設計**：
  > 四個 buffer 共用 `timestamp`——這個共通欄位就是答案，不需要新資料管線。
  - **做法 A（先做，低成本）**：在 `NetworkDetailView` 與（規劃中的）`LogDetailView` 裡，加一個「同時段事件（±5s）」側欄。一個 `_eventsAround(timestamp, window)` 工具函式掃 registry 的各 buffer，按時序列出，點擊跳轉。
  - **做法 B（後做，高價值）**：新增 **Timeline 視圖**——一個 `TimelineEvent`（type: log/network/nav/db 的薄 union）按 `timestamp` merge-sort 後的混合時間軸，`error` 級事件標紅旗。這是把「故障全景」一眼攤開。
* **重用**：各 entry 的 `timestamp`、`InspectorRegistry` 已持有四個 buffer、`LogLevel` 配色、`KeyValueTable`。
* **品味守則**：`TimelineEvent` 只是**指標包裝**（指向既有 entry），不複製資料、不引入第二份真相。
* **Effort**：A=low / B=medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **🟡 實作現況（v1.1.0 / PR #40 #42）**：**做法 B 已落地，且實作得比原構想更乾淨**——沒有引入 `TimelineEvent` union，而是讓四個 entry model 共同實作 `TimestampedEntry` 介面，由 `InspectorRegistry.mergedTimeline()` 把四個 `RingBuffer` 拍扁後依 `timestamp` 降序歸併排序，`ConsoleTab` 直接渲染（`ConsoleTab` 的 `build()` 內呼叫 `inspector.mergedTimeline(sources: _selected)`），按 entry runtime type 動態分派渲染、點 Network 列跳 `NetworkDetailView`。這同時消滅了 v1.1.0 前「鏡射到 console log 的廉價替代」（見本文件頂部與 overview 的歷史演進）。**未完成**：做法 A 的「±5s 同時段側欄」尚未做（現為整條混合時間軸，無以單筆為中心的時間窗聚焦）。

### 3. 一鍵診斷報告（Diagnostic Report）— ✅ 已完成（原 🔴 QA 提 bug 的剛需）
* **痛點**：QA 重現 bug 後，要手動切四個 tab、逐筆截圖/複製、再手打 device/OS/版本資訊。耗時且容易漏，回報品質參差。
* **好品味設計**：
  - 新增 `buildDiagnosticReport(inspector, {timeRange, sections})`，輸出一份 **Markdown / JSON** 報告：device & app info 表頭 + 選定時間窗內的 log / network / nav / db 各區段。
  - Dashboard AppBar 新增「Export Diagnostic Report」action → 勾選區段 + 時間範圍（last 5m / 1h / all）+ 格式 → 走系統分享。
  - device/app info 用官方維護的 `package_info_plus` + `device_info_plus`（**可選相依**，未安裝時該區段降級為「N/A」，絕不崩）。
* **重用**：`network_formatters.dart` 的 `buildPlainText`/`buildCurl` 序列化模式、`share_text.dart` 平台自適應分享、各 buffer 的 newest-first snapshot getter。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **✅ 實作現況**：已於 `utils/diagnostic_report.dart` 實作 `buildDiagnosticReport`，並在 Dashboard AppBar 提供 `ExportReportSheet` 以匯出（包含時間範圍與錯誤篩選選項）。
* **✅ 缺口已補（v1.5.0 → PR #87）**：原匯出報告的 `## Logs` section 只含 `LogEntry`、四層各自獨立、無法看出跨層因果——此缺口已由 **#9 診斷報告 Timeline 重設計**（PR #87，2026-07-17 合入 main）解決：`## Logs` 換為按時序交錯四層的 `## Timeline` 混合串流。

### 4. Dio 錯誤的結構化捕捉（Structured Network Error）— ✅ 已完成
* **痛點**：`onError()` 只存 `err.toString()`，把 `DioException` 的結構資訊大部分丟了：**根因類型**（connectionTimeout / DNS / SSL / parse / cancel）與 `err.stackTrace`。注意：`statusCode` 已顯示在 `NetworkDetailView` 的 General section，4xx/5xx 錯誤是可辨識的；**真正的盲區是 `statusCode == null` 的傳輸層失敗**（斷網、DNS 失敗、SSL 握手錯誤、request cancel 等），目前這些一律只顯示一坨 toString() 字串，無法從 UI 分辨根因。
* **好品味設計**：
  - `dio_interceptor.onError` 改為擷取結構化欄位：`err.type`（分類）、`err.stackTrace`、`err.response?.statusCode`、保住 `err.response?.data`（伺服器的錯誤說明）。
  - 核心區分一條：**`response == null` → 傳輸層失敗（沒到 server）**；**`response != null` → server 回了錯誤碼**。這條判斷消滅了「Failed 到底是斷網還是後端壞了」的猜謎。
  - `NetworkDetailView` 新增「Exception Details」section 分層展示。
* **重用**：擴充 `NetworkEntry.error`（或加 `errorType` / `errorStackTrace` 欄位，保持 `@immutable`）、`DioExceptionType` enum、既有 detail view 的 card 分層。
* **Effort**：low–medium ｜ **排查價值**：⭐⭐⭐⭐
* **✅ 實作現況（v1.3.0 · PR：`feat(network): capture DioException type and stack trace in interceptor` 等三連 commit）**：`dio_interceptor.onError` 已擷取 `err.type` 存入 `NetworkEntry.errorType`(`DioExceptionType`) 與 `err.stackTrace` 存入 `errorStackTrace`，連同既有的 `statusCode`/`responseHeaders`/`responseBody`。`NetworkDetailView` 新增「Exception Details」section，依 `entry.statusCode == null` 明確分流顯示「傳輸層失敗 (transport failure — request did not reach server)」或「Server 錯誤回應 (server responded with error)」，消滅了原先「Failed 到底是斷網還是後端壞了」的猜謎；純文字匯出（`network_formatters.dart`）亦包含 `Error Type` 與 stack trace。設計完全依照原規劃落地，無偏離。

### 5. ConsoleTab 排查化：stackTrace 詳情 + error 過濾 — 🟡 部分完成
* **痛點**：error log 的 `stackTrace` 與 `data` 在 UI 完全看不到，列表項點了沒反應，500 條 log 無搜尋無過濾，error 跟 info 混成一片。
* **好品味設計**：
  - `LogDetailView`（仿 `NetworkDetailView`）：點 log 展開 message / level / **可複製 stackTrace** / `data`（用 `KeyValueTable`）。
  - 搜尋欄 + LogLevel FilterChip + 「errors only」快捷——直接套 `NetworkTab` 的搜尋/chip 模式與 `applyNetworkFilter` 邏輯框架，error log 終於能秒定位。
* **重用**：`NetworkTab` 搜尋 bar + FilterChip、`LogInspector.entriesAtLevel()`（已存在）、`KeyValueTable`、`NetworkDetailView` 佈局。
* **注意**：搜尋/過濾/詳情面板在上一份 brainstorm（已歸檔）中已列入。**此處只強調其排查價值並與 #2 的時序側欄、#3 的報告打包對齊**，避免重複規劃；實作時應一併考量。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐
* **🟡 實作現況**：`LogDetailView` 已完成（點擊展開、可複製 stackTrace 區段、Data 區段、分享），Console 列已加 chevron 標記可展開。**未完成**：ConsoleTab 的搜尋欄、LogLevel FilterChip、errors-only 過濾尚未實作，`entriesAtLevel()` 仍未被使用。

---

## 🚀 第二部分：加分但非核心（中優先）

### 6. 網路請求重放（Replay / Resend）— ✅ 已完成（PR #36 / v1.0.0）
* **價值**：API 出錯時，原地重送（可改 header/body）即時確認「是否仍重現 / server 是否恢復」，免去複製 cURL 跳終端的 context switch。
* **設計**：`NetworkDetailView` 加「Resend」按鈕，從 entry 重建請求（沿用 `buildCurl()` 已證明的請求重組邏輯）經注入的 Dio 重送，結果作為新 `NetworkEntry` 記回 buffer。
* **重用**：`buildCurl()` 的請求重組、init 時傳入的 Dio client。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐
* **邊界**：只「重送原請求」。**不**做 mocking、不做腳本化改寫——那是 Proxyman/Charles 的地盤（見 anti-features）。
* **✅ 實作現況**：PR #36 / v1.0.0 已完成。`NetworkDetailView` 的「Resend」按鈕經原始 `sourceDio`（`WeakReference<Dio>`）原樣重送，重送結果以 `isReplay` 標記記回 buffer，並含狀態回饋與防連點保護。

### 7. 錯誤聚合摘要（Error Aggregation）— ✅ 已完成
* **價值**：同一個 502 每 30 秒打一次 → 現在是 500 條各自獨立的列表項。聚合成「502 Bad Gateway × N 次，最近 5 分鐘」一張卡，一眼看出是「持續故障」還是「偶發」。
* **設計**：`NetworkTab` 頂部「Error Summary」卡，按 `(statusCode, errorType)` 分組計數 + 首末時間。
* **重用**：`NetworkStatusGroup.matches()` 分組邏輯、`RingBuffer` 作資料源.
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐
* **✅ 實作現況**：v1.3.0 已實作。新增 `NetworkErrorGroup` 聚合模型與 `aggregateNetworkErrors(entries)` 聚合邏輯（定義於 `lib/src/utils/network_utils.dart`），並在 `lib/src/ui/dashboard/tabs/network_tab.dart` 中以 `_ErrorSummaryBanner`（包含 `_ErrorGroupCard` 元件）實作，支援折疊/展開顯示，以及點擊進行過濾篩選。

### 8. 當前路由堆疊可視化（Active Navigation Stack）— ✅ 已完成（PR #51）
* **價值**：排查「頁面有沒有被重複 push / 該 pop 沒 pop（記憶體洩漏前兆）」。錯誤發生時的路由堆疊也是 #3 診斷報告的關鍵 context。
* **設計**：`NavigatorObserver` 即時維護 `currentStack`，`NavigatorTab` 頂部以麵包屑顯示 Root→Top，偵測重複 push 時標 warning。
* **重用**：既有 push/pop/replace 回調、`KeyValueTable`。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐
* **註**：與上一份 brainstorm 的「Navigator Stack Visualizer」同一構想，此處定位為「為診斷報告提供 crash 當下路由快照」。
* **✅ 實作現況**：PR #51（Issue #50）已完成。新增 `NavigatorStackResolver`（`lib/src/inspectors/navigator_stack_resolver.dart`）純 Dart 重播器，將 `navigatorEntries`（newest-first）反轉回時序後重播 push/pop/replace/remove，推導出 top-first 當前堆疊；`NavigatorTab` 以 `ChoiceChip`（`_Tab` 私有元件）在「當前堆疊」（垂直卡片，顯示 `displayName` + `routeName`，頂部路由標 `Current` 標籤 + `visibility` 圖示）與既有「事件歷史」之間切換，模式切換器與 refresh / delete 工具列並排於同一 Row。採**垂直卡片**而非麵包屑（經 STAGE 0a 規格確認調整，理由見 `docs/features/2026-07-01-navigator-active-stack.md`）；replace/remove 的歧義情況採明確可預測的 best-effort 規則，不做 nested Navigator 多樹精確還原。

---

## 🕸️ 第三部分：新戰場——WebView 觀測層（新提案 · 2026-07-18）

### 10. WebView Inline Debugging（WebView 觀測層）— ⬜ 新提案
* **痛點**：宿主 app 一旦嵌了 WebView（H5 活動頁、支付頁、混合頁），inspector 就瞎了：頁內 `console.log`、JS error、`fetch` 全部隱形。開發者被迫外接 chrome://inspect（Android）或 Safari Web Inspector（iOS 16.4+ 還得逐 WebView opt-in），QA 裝置上完全無解。[flutter/flutter#32908](https://github.com/flutter/flutter/issues/32908) 在許願此能力；本 repo `lib/` 零 webview 程式碼——真盲區，非重複造輪。
* **先拆穿一件事**：「WebView debug」是兩個等級——**A 觀測層**（console / JS error / fetch，JS 注入即可，vConsole / Eruda / iOS WebDebug 類 app 全是這套）與 **B 除錯器層**（breakpoint / step / DOM inspector / profiler，需要 CDP，inline 做不到也不該模擬）。本提案**只做 A**；B 進 anti-features（#5）。
* **好品味設計（核心洞察）**：
  > WebView 的 `console.log` **就是**一筆 `LogEntry`；WebView 的 `fetch` **就是**一筆 `NetworkEntry`。這是「多一個事件來源」，不是「多一個系統」——#2/#9 的 `TimestampedEntry` + `mergedTimeline()` 地基讓 Console tab、Network tab、#7 error aggregation、#3 匯出報告**全部免費得到 WebView 支援**。
  - 映射**零 schema 變更**：`console.*` → `LogEntry`（`level` ← console method；provenance 塞既有 `data` Map：`{'origin': 'webview', 'pageUrl': ...}`，UI 要不要加小圖示是 presentation 層的事，資料層無感）；`window.onerror` / `unhandledrejection` → error 級 `LogEntry`（JS stack 入 `stackTrace`）；`fetch` / XHR → `NetworkEntry`（`errorType` / `sourceDio` 本為 nullable，填 null 即入列；副作用：**Replay 對 WebView 請求自然不可用**——正確的降級而非缺陷，UI 既有 null 檢查已處理）。
  - 三個件、**零新相依**（host-injection 模式第三次複用，前兩次：`DiagnosticInfoSource`、`DatabaseBrowserSource`）：
    1. `inspectorWebViewBridgeJs`（Dart 常數字串）——hook `console.*` / `window.onerror` / `unhandledrejection` / `fetch` / XHR，統一 JSON 訊息協定 postMessage 給 native，**JS 端截斷大 payload**（與 `RingBuffer` 同哲學：上限在源頭）
    2. `WebViewBridgeAdapter`——decode → 轉 `LogEntry` / `NetworkEntry` → 進 registry，headers/body 過既有 redaction 管線，不開後門
    3. README 雙套件接線範例（webview_flutter / flutter_inappwebview 各一段，宿主端約五行：建 JavaScriptChannel → onMessage 轉 adapter → 載入時注入）
  - **Phase 0 零成本先行**：README 加「Eruda 快速接線」食譜（`runJavaScript` 一行載 CDN，立刻獲得頁內 debug 面板）——先服務需求並驗證熱度；頁內面板與 native timeline 無關聯，**不取代 bridge，只是墊檔**。
* **競品缺口（2026-07 調查）**：[inappwebview_inspector](https://pub.dev/packages/inappwebview_inspector) 僅 console + JS REPL 且綁死 flutter_inappwebview；[vConsole](https://github.com/Tencent/vConsole) / [Eruda](https://github.com/liriliri/eruda) 面板畫在網頁裡、換頁即重置、與 native 世界隔絕。**「native 事件與 WebView fetch 同一條時間軸」沒有人做**——恰是頁內工具結構上做不到、又恰是本套件 Timeline 地基的自然延伸。
* **重用**：`InspectorRegistry` 的 log/network buffer、`redaction.dart`、`LogLevel` 對應、`mergedTimeline()` / 報告全鏈路。
* **品味守則**：adapter 是**翻譯器不是系統**——不持有 buffer、不做 UI、不引入第二份真相。不加第五個 source enum、不開 WebView 專屬 tab（見 anti-features #6）。
* **風險（plan 階段逐一處理）**：① **注入時機**——`runJavaScript` 於頁面載入後執行會漏早期 log，吃到全部需 documentStart 注入（flutter_inappwebview 的 `UserScript` 完整支援；webview_flutter 抽象層較弱）——host 接線文檔明示各自能與不能，套件不吞；② **敏感資料**——WebView fetch 的 headers/body 必過 `redactSensitiveData` 管線，任何入口不得繞過 opt-out 行為；③ **bridge 流量**——大 response body 序列化過 channel 會卡 UI thread，JS 端截斷（如 body 上限 32KB + `truncated` 旗標），非 Dart 端事後補救；④ **不可信輸入**——WebView 內容視同惡意來源，走 #9 已加固的 CRLF / malformed-URL 清洗路徑並補驗證；⑤ **iframe 不支援**——注入只作用於 main frame，v1 明文不支援（README 註明），不偷做跨 frame 橋接；⑥ **`setOnConsoleMessage` 誘惑**——webview_flutter 4.x 原生可收 console 看似免注入，但 [iOS 有遞迴物件 logging bug](https://github.com/flutter/flutter/issues/144535) 且只覆蓋 console（無 fetch/error），只能當降級備援，不能當主路徑。
* **Effort**：Phase 0=trivial / bridge 主體=medium ｜ **排查價值**：⭐⭐⭐⭐⭐（混合開發場景的最後盲區）

---

## ❌ 拒絕實現的「垃圾」功能（Anti-Features）

堅守「不走向微核心 / 過度工程」：

1. **完整效能 / Jank / 記憶體 Profiler**
   - *拒絕*：FPS 追蹤、frame drop、記憶體 profiling 是**另一個產品維度**，不是「錯誤排查」。Flutter 官方 DevTools 已有強大的 Performance/Memory view，in-app 重造只會是低配輪子。偏離主線，effort=high，**砍**。

2. **跨 session 持久化 / 本機落盤的 crash history**
   - *拒絕*：把 buffer 定期寫 SQLite/Hive、重啟後還原——聽起來很美，但引入磁碟 IO、序列化版本相容、隱私（log 含敏感資料落盤）三重複雜度與風險。**排查的證據用 #3 的「一鍵匯出」帶走即可**，不需要工具自己當資料庫。違反「砍掉一半再砍一半」。**砍**。

3. **完整 HAR timing waterfall（DNS/TLS/TTFB 分段）**
   - *拒絕*：Dio 在多數版本拿不到可靠的分段 timing，硬湊出來的瀑布圖是**假精度**，反而誤導排查。保留 #4 的 total duration + timeout 判斷已足夠。匯出走標準 JSON 即可，不追 HAR 的完整 timings 物件。**砍**（HAR 匯出本身可選保留，但不偽造 timing）。

4. **API Mocking / 動態回應改寫**
   - *拒絕*：同上一份 brainstorm 的判斷——在 debug overlay 裡注入 mock 規則會讓工具代碼翻倍，且極易因 debug 庫 bug 中斷宿主的正式網路流。**嚴重違反「Never break userspace」**。交給外部 proxy。**砍**。

*（以下三條隨 #10 WebView 提案新增 · 2026-07-18）*

5. **B 級 WebView 除錯器（breakpoint / step / DOM inspector / profiler / JS REPL）**
   - *拒絕*：breakpoint/profiler 需要 CDP，inline 模擬是假貨；DOM inspector 工程量爆炸且 Eruda 頁內已有（#10 Phase 0 食譜即覆蓋此需求）；JS REPL（從 dashboard 對 WebView 執行任意 JS）技術上可行但那是「操控」不是「觀測」，跨越產品邊界且有安全面問題。README 直接指路 chrome://inspect 與 Safari Inspector。**砍**（REPL 若未來需求真實再議）。

6. **WebView 專屬 tab / 第五個 TimelineSource**
   - *拒絕*：WebView log 就是 log、fetch 就是 network。加 enum、開新 tab 是為不存在的區別打補丁，會讓 filter / 報告 / UI 全鏈路長出特殊情況。provenance 用 `LogEntry.data` 標記足矣。**砍**。

7. **直接相依 webview 套件（提供包裝好的 InspectorWebView widget）**
   - *拒絕*：綁死 `webview_flutter` 或 `flutter_inappwebview` 其一，就把另一半使用者關在門外（inappwebview_inspector 正是此坑）；兩個都支援則相依翻倍、版本矩陣地獄。host-injection 模式已驗證兩次（`DiagnosticInfoSource`、`DatabaseBrowserSource`），沒有理由背棄。**砍**。同理**跨 iframe / Service Worker 橋接**——複雜度與受眾完全不成比例，**砍**。

---

## 📅 下一步實作路徑（依排查價值排序）

排序原則：**🔴 最高優先 → 先補盲區（看得見錯誤）→ 再建關聯（看得懂錯誤）→ 最後打包（帶得走證據）**。

0. **✅ 第零階段 · 診斷報告 Timeline 重設計**（已完成 · PR #87，2026-07-17 合入 main）：**#9** 已將 `## Logs` 改為按時序交錯的 `## Timeline` 混合串流，消滅匯出報告中跨層因果斷裂的最後一塊拼圖。[design spec](../plans/2026-07-16-diagnostic-report-timeline-design.md) 與 [implementation plan](../plans/2026-07-16-diagnostic-report-timeline-plan.md) 皆已落地。
1. **第一階段 · 點亮盲區**（✅ 已完成）：**#1 全局未捕捉例外捕捉** ✅ + **#4 Dio 結構化錯誤捕捉** ✅（v1.3.0 落地）。inspector 現在真正「看得見」錯誤。
2. **第二階段 · ConsoleTab 排查化**（🟡 進行中 · 僅剩缺口）：實作 **#5**（stackTrace 詳情 ✅ + error 搜尋/過濾 ⬜ 待補：搜尋欄、LogLevel FilterChip、errors-only 快捷），讓捕捉到的錯誤可被秒速定位與檢視。
3. **第三階段 · 建立關聯**（🟡 主體已完成）：**#2 做法 B（Timeline 混合視圖）已於 v1.1.0 落地** ✅（`mergedTimeline` + `TimestampedEntry`）；僅剩 **做法 A**（detail view 的 ±5s 同時段側欄 ⬜）尚未做，可視回饋決定是否補上。
4. **第四階段 · 帶走證據**（✅ 已完成）：實作 **#3 一鍵診斷報告**（device info；路由堆疊快照可直接複用已完成的 #8 `NavigatorStackResolver`）。QA 提 bug 的剛需在此閉環。
5. 第五階段 · 加分項（✅ 部分完成）：#6 Replay 已於 v1.0.0 完成實作、**#8 路由堆疊可視化已於 PR #51 完成**；後續可視回饋實作 #7 錯誤聚合摘要。
6. **第六階段 · WebView 觀測（⬜ 新提案 · 2026-07-18）**：**#10** 依 Phase 推進——**Phase 0**（README「Eruda 快速接線」食譜，trivial，可隨任何 docs PR 先行）→ **Phase 1+2**（bridge 主體：console/error → `LogEntry`、fetch/XHR → `NetworkEntry` 過 redaction；同一條資料管線，可併一個 PR）→ **Phase 3**（webview_flutter / flutter_inappwebview 雙套件接線文檔 + example 示範頁）。

> **收尾建議（2026-07-17 更新）**：**#9 診斷報告 Timeline 重設計**已於 PR #87 完成並合入 main，最高優先項目結清。排查鏈剩下兩個明確缺口——**#5 的搜尋/過濾**（LogLevel FilterChip + errors-only + 搜尋欄）與 **#2 做法 A**（detail view 的 ±5s 同時段側欄），皆為可視回饋後再決定的加分項。**2026-07-18 補充**：**#10 WebView 觀測**開啟新戰場——Phase 0 食譜零成本先行驗證需求熱度，bridge 主體視回饋排程。

> 每一階段都是獨立可上線的增量，且彼此寫入路徑不重疊（#9 動 formatters + report builder、#5 動 console UI、#2A 動 detail view、#10 動全新 bridge 檔案 + README），適合並行推進。
