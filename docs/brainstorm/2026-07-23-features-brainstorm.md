# 🩺 Flutter Inspector 錯誤問題排查與分析：功能腦力激盪報告

> **建立日期**：2026-06-25（原始檔名）｜**最後更新**：2026-07-24（**#1 去重機制修復完成**——PR #96 合入 main（merge `5d2b37d`），`UncaughtErrorHandler` 改以 object-identity（`identical` 比對上一筆 `FlutterErrorDetails`）去重，消滅同一 build 崩潰在 Console 的重複記錄，§D2 由待辦轉為已完成。**另補記**：文件此前漏列的既有「網路系統通知」基建（`showNetworkNotification` opt-in，自 v0.1.0，`flutter_local_notifications` 已在相依）已補進完成度總覽與 §P1，修正「通知類未實作」的誤判。前次更新：2026-07-23 新增 **第四部分：功能缺口深度分析與新功能提案**——對照 v1.7.0 codebase 盤點全部 10 項原始功能的實際缺口，並提出 9 項新功能提案 P1–P9，聚焦「快速排查 / 輔助定位錯誤」；更新完成度總覽與實作路徑為四階段 Phase Plan。更早：2026-07-18 新增 #10 WebView Inline Debugging 提案並完成）

> 「好代碼沒有特殊情況。」 —— Linus Torvalds
>
> 這份報告**只聚焦一件事**：當 app 出錯時，`flutter_inspector_kit` 能不能讓開發者/QA 用最少的步驟「看見錯誤、關聯原因、帶走證據」。
> 我們不重彈上一份 [`brainstorm/2026-06-18-feature_brainstorming.md`](../../brainstorm/2026-06-18-feature_brainstorming.md) 的泛用優化清單，而是用排查（troubleshooting）這把尺，重新審視每個缺口。凡是偏離「排查」核心、或為了理論完美而增加複雜度的，一律砍掉。

---

## 📊 完成度總覽（截至 2026-07-23 · v1.7.0）

> 以下狀態依實際 codebase 與 git history 核對標注。✅ 完成 ｜ 🟡 部分完成 ｜ ⬜ 未實作。
> **更新說明（2026-07-23）**：對照 v1.7.0 codebase 完成全面缺口分析。確認 **#1 去重機制實質未實作**（`UncaughtErrorHandler` 的 `FlutterError.onError` 與 `ErrorWidget.builder` 各自觸發 `_logFlutterError`，同一 build 崩潰重複記錄兩次）——**已於 2026-07-24 PR #96 修復**（object-identity 去重）；**#5 ConsoleTab** 的 `InspectorSearchBar` 元件已存在但未接入、`entriesAtLevel()` 在 UI 層零呼叫、errors-only 邏輯僅存在於 `diagnostic_report.dart` 未暴露至 Console UI。**#2 做法 A（±5s 側欄）** 完全無程式碼。新增第四部分提出 9 項新功能提案。
> **歷史更新**：v1.1.0（PR #40 / #42）把 console 重構為真正的混合時間軸後，**#2 由 ⬜ 升級為 🟡**（時序關聯的主體已落地）。PR #51 完成 **#8 當前路由堆疊可視化**，由 ⬜ 升級為 ✅。v1.3.0 完成 **#4 Dio 結構化錯誤捕捉**，由 🟡 升級為 ✅，並修正了 **#7 錯誤聚合摘要** 的狀態為 ✅。最新檢視 codebase (v1.5.0) 發現 **#3 一鍵診斷報告** 也已完成（`buildDiagnosticReport` 及 `ExportReportSheet`），由 ⬜ 升級為 ✅。**#9 診斷報告 Timeline 重設計** 已於 PR #87（2026-07-17 合入 main）完成，由 ⬜ 升級為 ✅。**#10 WebView Inline Debugging** 於 PR #91 完成，由 ⬜ 升級為 ✅。**#1 去重機制**於 PR #96（2026-07-24 合入 main，merge `5d2b37d`）修復，由 ✅⚠️（帶缺陷完成）升級為 ✅。

| # | 功能 | 狀態 | 備註 |
|---|------|:---:|------|
| **#9** | **診斷報告 Timeline 重設計** | **✅** | PR #87：`## Logs` → 按 `timestamp` 降序交錯四層的 `## Timeline` 混合串流；新增 `buildLogOneLiner`/`buildNetworkOneLiner` 單行 formatter，`errorsOnly` 升級為過濾整條 stream，`## Network`/`## Navigation`/`## Database` detail section 不動 |
| #1 | 全局未捕捉例外捕捉 | ✅ | PR #30：`captureUncaughtErrors`(default off) + 三掛點 chain。**去重已補（PR #96）**：`FlutterError.onError` 與 `ErrorWidget.builder` 對同一 build 崩潰收到同一 `FlutterErrorDetails`，`_logFlutterError` 以 object-identity（`identical`）去重，Console 只記錄一次（見第四部分 §D2） |
| #6 | 網路請求重放 | ✅ | PR #36 / v1.0.0 已完成：支援 per-Dio 原樣重送、`isReplay` 標記、狀態回饋與防連點保護 |
| #8 | 當前路由堆疊可視化 | ✅ | PR #51（Issue #50）：新增 `NavigatorStackResolver` 純 Dart 重播器，`NavigatorTab` 以 `ChoiceChip` 切換「當前堆疊」（垂直卡片）與「事件歷史」 |
| #2 | 跨 Inspector 時序關聯 | 🟡 | **v1.1.0 大幅推進**：ConsoleTab 已改用 `mergedTimeline`（四 buffer 按 `timestamp` 歸併排序），即文件「做法 B：Timeline 視圖」的本體已成；**缺** 做法 A（detail view 的 ±5s 同時段側欄，完全無程式碼） |
| #4 | Dio 結構化錯誤捕捉 | ✅ | v1.3.0：`NetworkEntry.errorType`(`DioExceptionType`)/`errorStackTrace` 欄位、`response==null` 傳輸層失敗 vs `!=null` server 錯誤的分類判斷、`NetworkDetailView` 的 Exception Details section、純文字匯出皆已落地 |
| #5 | ConsoleTab 排查化 | 🟡 | `LogDetailView`(stackTrace/data/分享) 完成；**缺** 搜尋欄（`InspectorSearchBar` 元件存在但未接入）/ LogLevel FilterChip（完全不存在）/ errors-only 過濾（邏輯僅在 `diagnostic_report.dart`，UI 未暴露）——`entriesAtLevel()` 在 UI 層**零呼叫**（見第四部分 §D1） |
| #3 | 一鍵診斷報告 | ✅ | 已實作：提供 `buildDiagnosticReport` 產生 Markdown 報告，並在 Dashboard 實作 `ExportReportSheet` 匯出 |
| #7 | 錯誤聚合摘要 | ✅ | v1.3.0 已實作：新增 NetworkErrorGroup 聚合模型與 _ErrorSummaryBanner / _ErrorGroupCard UI 元件 |
| #10 | WebView Inline Debugging（觀測層） | ✅ | PR #91：JS payload + host-injection bridge，把 WebView 的 console/error/fetch 映射為既有 `LogEntry`/`NetworkEntry` 入列 Timeline——零新相依、零 schema 變更（見第三部分） |

**Anti-features**（Profiler / 落盤 crash history / HAR timing / API mocking / WebView B 級除錯器 / 第五 source enum）— ✅ 正確地皆未實作，守住「不走向微核心」。

> **⚠️ 文件此前漏列的既有基建（2026-07-24 補記）**：對照實際 codebase 發現，`flutter_local_notifications: ^22.0.0` **早已是相依**（`pubspec.yaml`），且自 **v0.1.0（pub.dev 首發）** 就有 **opt-in 系統通知**功能——入口 `FlutterInspector(showNetworkNotification: false)`（default off）+ `NetworkNotifier`（`lib/src/notifications/network_notifier.dart` 及 `_io`/`_web` 平台分支）+ `AlertThrottler`（2 秒節流窗）。行為：一則**持續更新的單一系統通知**，摘要「最新一筆網路呼叫 + 總數」，點擊開 Network tab；初始化/權限失敗時安全降級為 no-op，web build 為 no-op stub（保 WASM 相容）。此前的缺口分析（含 anti-feature 判斷與下方 §P1）**未盤點到這塊**，造成「通知類＝未實作／需引入新相依」的誤判——實際上**相依與節流器都已就位**，任何「錯誤告警」提案都是對既有基建的**擴充**，而非新建。

**進度結論（v1.7.0，含 2026-07-24 更新）**：原始 10 項裡 9 項完全完成（#1、#3、#4、#6、#7、#8、#9、#10，以及 v1.1.0 實質完成的 #2 時序軸主體；#1 去重缺陷已由 PR #96 修復），**1 項半成品**（#5 console 搜尋/過濾）。第四部分另提出 9 項新功能提案。

---

## 🐧 三個鐵律問題

> 本節為初始設計階段的核心分析，保留作為決策紀錄。

1. **這是真實問題，還是腦補？**
   - 真實。掃描現有 codebase 後確認：**inspector 目前完全看不到「它沒被手動餵進來」的錯誤**——沒有任何全局例外捕捉，沒有 widget build error 攔截，Dio error 只存 `err.toString()` 丟掉了 stackTrace。錯誤排查工具卻是「錯誤的盲人」。
2. **有沒有更簡單的方法？**
   - 有，而且核心抽象都已存在。`RingBuffer`、`InspectorRegistry`、各 `*Inspector` 的 `add()`、`@immutable` 的 entry models、`LogEntry.stackTrace`（已定義卻沒人用）、共用 `timestamp`——排查能力幾乎都能靠**組合既有零件**長出來，不需要新框架。
3. **這會破壞什麼嗎？**
   - 不會。全部以擴充式設計：新增可選建構參數（default off）、新增 getter、新增 UI section。**絕不改動既有 `FlutterInspector` 公開 API 的行為**。

---

## 🔍 排查能力現況盤點

> **當前現況快照（v1.7.0，含 2026-07-24 更新）**：相較於初期有四個紅燈的盲區，經過多次迭代後，目前排查基礎建設已大幅補齊。紅燈僅剩 Console 搜尋/過濾；黃燈僅剩 ±5s 側欄（error 去重已由 PR #96 修復）。

| 排查環節 | 現況 (v1.7.0) | 評級 |
|---|---|---|
| 看見「我主動 log 的」錯誤 | `inspector.log()` 正常記錄；`LogDetailView` 支援點擊展開、複製與分享 stackTrace | ✅ 完善 |
| 看見「未捕捉」的例外 | 已實作 `captureUncaughtErrors`，覆蓋 `FlutterError.onError`、`PlatformDispatcher` 與 `ErrorWidget.builder`；同一 build 崩潰的重複記錄已由 object-identity 去重消除（PR #96） | ✅ 完善 |
| 看見網路失敗的根因 | 成功擷取 `err.type` 與 `stackTrace`，能精準區分「傳輸層失敗」與「Server 錯誤回應」 | ✅ 已修復 |
| 關聯「錯誤前後發生了什麼」 | `mergedTimeline` 將四個 buffer 歸併，跨層時序主體已成；但仍缺單筆 detail view 的 ±5s 聚焦側欄 | 🟡 尚欠聚焦 |
| 帶走排查證據 | `buildDiagnosticReport`／`ExportReportSheet` 已落地，且 #9（PR #87）將 `## Logs` 換為 `## Timeline` 混合串流，四層事件按 `timestamp` 降序交錯——報告可直接看出跨層因果 | ✅ 完善 |
| 過濾定位 error log | `LogInspector.entriesAtLevel()` 仍未被 UI 呼叫，ConsoleTab 依然缺乏搜尋欄與 LogLevel FilterChip；`InspectorSearchBar` 元件存在但僅用於 NetworkTab | 🔴 依然不足 |
| 看見 WebView 內的事件（console / JS error / fetch） | v1.7.0 實作 `WebViewBridgeAdapter` 及 JS injection 腳本，無縫將 web 端日誌網路請求轉接入 Inspector；新增 `NetworkOrigin` provenance 標記 | ✅ 完善 |

> 結論：排查鏈條上的七個環節，如今**五個綠燈、一個黃燈、一個紅燈**。#1 去重缺陷已於 PR #96（2026-07-24）修復並回升綠燈；黃燈僅剩 ±5s 同時段側欄，紅燈僅剩 Console 搜尋/過濾。

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
* **✅ 實作現況**：PR #30 已完成。`FlutterInspector(captureUncaughtErrors: false)` 入口 + `UncaughtErrorHandler` 三掛點（`FlutterError.onError` chain、`PlatformDispatcher.onError`、`ErrorWidget.builder`）皆落地。`runGuarded` 已移除改用 `PlatformDispatcher.onError`。
* **✅ 去重已補（PR #96 · 2026-07-24 合入 main）**：原缺陷為 `_logFlutterError(details)` 同時被 `FlutterError.onError` 與 `ErrorWidget.builder` 呼叫、`_attached` 旗標只防重複 `attach()` 不防重複 log，同一 build 崩潰產生 2 筆重複 error log。修復採 **object-identity 去重**：新增 `_lastLoggedDetails` 欄位，`_logFlutterError` 入口 `if (identical(details, _lastLoggedDetails)) return;`。同一 build 崩潰兩個 hook 收到的是同一物件（identity 恆真 → 吞第二筆）；兩次獨立崩潰即使訊息相同也是不同物件（identity 恆假 → 各自記錄），不誤吞短時間內的獨立錯誤。詳見 §D2。

### 2. 跨 Inspector 時序關聯（Correlated Timeline）— 🟡 部分完成（原 🔴 排查的靈魂）
* **痛點**：錯誤幾乎都是跨層的——「點了某按鈕（nav）→ 發了某 API（network）→ 5xx → 印了某 error log」。但現在這四件事躺在四個孤立 buffer 裡，開發者得在四個 tab 之間用肉眼對時間戳，這是排查最大的摩擦。
* **好品味設計**：
  > 四個 buffer 共用 `timestamp`——這個共通欄位就是答案，不需要新資料管線。
  - **做法 A（先做，低成本）**：在 `NetworkDetailView` 與（規劃中的）`LogDetailView` 裡，加一個「同時段事件（±5s）」側欄。一個 `_eventsAround(timestamp, window)` 工具函式掃 registry 的各 buffer，按時序列出，點擊跳轉。
  - **做法 B（後做，高價值）**：新增 **Timeline 視圖**——一個 `TimelineEvent`（type: log/network/nav/db 的薄 union）按 `timestamp` merge-sort 後的混合時間軸，`error` 級事件標紅旗。這是把「故障全景」一眼攤開。
* **重用**：各 entry 的 `timestamp`、`InspectorRegistry` 已持有四個 buffer、`LogLevel` 配色、`KeyValueTable`。
* **品味守則**：`TimelineEvent` 只是**指標包裝**（指向既有 entry），不複製資料、不引入第二份真相。
* **Effort**：A=low / B=medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **🟡 實作現況（v1.1.0 / PR #40 #42）**：**做法 B 已落地，且實作得比原構想更乾淨**——沒有引入 `TimelineEvent` union，而是讓四個 entry model 共同實作 `TimestampedEntry` 介面，由 `InspectorRegistry.mergedTimeline()` 把四個 `RingBuffer` 拍扁後依 `timestamp` 降序歸併排序，`ConsoleTab` 直接渲染（`ConsoleTab` 的 `build()` 內呼叫 `inspector.mergedTimeline(sources: _selected)`），按 entry runtime type 動態分派渲染、點 Network 列跳 `NetworkDetailView`。這同時消滅了 v1.1.0 前「鏡射到 console log 的廉價替代」（見本文件頂部與 overview 的歷史演進）。**未完成**：做法 A 的「±5s 同時段側欄」尚未做——**codebase 中完全無對應程式碼**（2026-07-23 確認），現為整條混合時間軸，無以單筆為中心的時間窗聚焦。**實作方案見第四部分 §D3**。

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
* **✅ 實作現況（v1.3.0）**：`dio_interceptor.onError` 已擷取 `err.type` 存入 `NetworkEntry.errorType`(`DioExceptionType`) 與 `err.stackTrace` 存入 `errorStackTrace`，連同既有的 `statusCode`/`responseHeaders`/`responseBody`。`NetworkDetailView` 新增「Exception Details」section，依 `entry.statusCode == null` 明確分流顯示「傳輸層失敗 (transport failure — request did not reach server)」或「Server 錯誤回應 (server responded with error)」，消滅了原先「Failed 到底是斷網還是後端壞了」的猜謎；純文字匯出（`network_formatters.dart`）亦包含 `Error Type` 與 stack trace。設計完全依照原規劃落地，無偏離。

### 5. ConsoleTab 排查化：stackTrace 詳情 + error 過濾 — 🟡 部分完成
* **痛點**：error log 的 `stackTrace` 與 `data` 在 UI 完全看不到，列表項點了沒反應，500 條 log 無搜尋無過濾，error 跟 info 混成一片。
* **好品味設計**：
  - `LogDetailView`（仿 `NetworkDetailView`）：點 log 展開 message / level / **可複製 stackTrace** / `data`（用 `KeyValueTable`）。
  - 搜尋欄 + LogLevel FilterChip + 「errors only」快捷——直接套 `NetworkTab` 的搜尋/chip 模式與 `applyNetworkFilter` 邏輯框架，error log 終於能秒定位。
* **重用**：`NetworkTab` 搜尋 bar + FilterChip、`LogInspector.entriesAtLevel()`（已存在）、`KeyValueTable`、`NetworkDetailView` 佈局。
* **注意**：搜尋/過濾/詳情面板在上一份 brainstorm（已歸檔）中已列入。**此處只強調其排查價值並與 #2 的時序側欄、#3 的報告打包對齊**，避免重複規劃；實作時應一併考量。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐
* **🟡 實作現況**：`LogDetailView` 已完成（點擊展開、可複製 stackTrace 區段、Data 區段、分享），Console 列已加 chevron 標記可展開。**未完成**：ConsoleTab 的搜尋欄、LogLevel FilterChip、errors-only 過濾尚未實作，`entriesAtLevel()` 仍未被使用。**詳細缺口分析與實作方案見第四部分 §D1**。

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

### 10. WebView Inline Debugging（WebView 觀測層）— ✅ 已完成 (PR #91)
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
* **✅ 實作現況（PR #91 · v1.7.0）**：已完成實作。包含提供 JS injection payload、`WebViewBridgeAdapter` 轉換層，能將 console 訊息與 XHR/fetch 網路請求平滑轉入 `LogEntry` 與 `NetworkEntry` 中，並順暢整合進現有 Timeline。新增 `NetworkOrigin` enum 區分 `dio` / `webview` / `http` 來源。

---

## 🔬 第四部分：功能缺口深度分析與新功能提案（2026-07-23 新增）

> 本節基於 v1.7.0 codebase 的全面比對分析，包含三類內容：
> - **§D1–D4**：原始 10 項功能中的殘留缺口，附實作方案
> - **§P1–P9**：新功能提案，全部聚焦「快速排查 / 輔助定位錯誤」
> - **完整優先順序總表**：13 項合併排序
>
> 核心原則不變：**不是新系統，是既有零件的重新組合**。零新模型、零新相依。

### §D1. ConsoleTab 搜尋 + LogLevel 過濾（#5 剩餘缺口）— 🔴 最高優先

> **這是排查鏈上唯一的紅燈。** 500+ 條混合 timeline，error log 跟 info/debug 混成一片，開發者只能肉眼掃描。

**缺口明細（v1.7.0 實查）**：

| 缺口 | 現況 | 參考實作 |
|------|------|----------|
| 搜尋欄 | ❌ `_SearchBar` 元件已存在於 `network_tab.dart` 但 ConsoleTab 未接入 | `NetworkTab._SearchBar` 的 `TextField` + `onChanged` 模式 |
| LogLevel FilterChip | ❌ 完全不存在 | NetworkTab 的 `_FilterChips`（HTTP Method + Status Group） |
| errors-only 快捷切換 | ❌ `errorsOnly` 邏輯僅存在於 `diagnostic_report.dart`，UI 未暴露 | `ExportReportSheet` 的 Checkbox |
| `entriesAtLevel()` | ❌ 定義於 `LogInspector`（L20）且有測試，但**零 UI 呼叫** | — |

**設計方向**（Linus 式「偷懶」策略——直接鏡射 NetworkTab 的搜尋/過濾架構）：
- ConsoleTab 頂部加 `_SearchBar`（搜尋 `message` / `stackTrace` / `url` 內容）
- LogLevel 作為 `FilterChip` 一排（verbose / debug / info / warning / error），支援多選
- 新增 `errors-only` 快捷 Chip（等價於只選 `warning` + `error` level + 失敗網路請求）
- 搜尋 + 來源過濾 + LogLevel 過濾三者正交疊加
- 建立 `ConsoleFilter` + `applyConsoleFilter()` 純函式（鏡射 `NetworkFilter` / `applyNetworkFilter()`）
- **影響範圍**：`lib/src/ui/dashboard/tabs/console_tab.dart`（主改）、可選新增 `lib/src/utils/console_utils.dart`（過濾邏輯）
- **Effort**：low–medium ｜ **排查價值**：⭐⭐⭐⭐⭐

### §D2. 未捕捉例外去重修復（#1 殘留缺陷）— ✅ 已完成（PR #96 · 2026-07-24）

> 同一個 widget build 崩潰，`FlutterError.onError` 和 `ErrorWidget.builder` 各觸發一次 `_logFlutterError`，Console 出現兩筆完全相同的 error log，干擾判斷「是一次還是兩次」。

**原缺陷確認**：`UncaughtErrorHandler`（`lib/src/core/uncaught_error_handler.dart`）的 `attach()` 中，`FlutterError.onError` 與 `ErrorWidget.builder` 各自呼叫 `_logFlutterError(details, ...)`，`_attached` 旗標只防重複 `attach()`，**不防同一 exception 被兩個 hook 重複 log**。

**實際實作（PR #96，刻意偏離原構想）**：原設計提議 hashCode + 2 秒時間窗的 dedup ring，實作時判定那是為不存在的情境過度設計——framework 對同一 build 崩潰傳給兩個 hook 的是**同一個 `FlutterErrorDetails` 物件**，用 object identity 一步到位；且時間窗反而會誤吞「2 秒內兩次訊息相同的獨立崩潰」（各自是新物件，本該分別記錄）。最終方案（消滅特殊情況而非新增判斷）：
- 新增單一欄位 `FlutterErrorDetails? _lastLoggedDetails`
- `_logFlutterError` 入口：`if (identical(details, _lastLoggedDetails)) return;`，通過後更新 `_lastLoggedDetails`
- 無 Queue、無 hashCode、無時鐘、無魔術數字
- **影響範圍**：`lib/src/core/uncaught_error_handler.dart`（+ `test/core/uncaught_error_handler_test.dart` 新增 `dedup` / `no dedup` 兩測試）
- **Effort**：low（實際 low）｜ **排查價值**：⭐⭐⭐⭐
- **文件**：規格 [`docs/features/2026-07-23-uncaught-error-dedup.md`](../features/2026-07-23-uncaught-error-dedup.md)、計畫 [`docs/plans/2026-07-23-uncaught-error-dedup.md`](../plans/2026-07-23-uncaught-error-dedup.md)

### §D3. Detail View ±5s 同時段側欄（#2 做法 A）

> 看到一筆 error log 後，想知道「這前後 5 秒內發生了什麼 API 呼叫、什麼路由跳轉」——目前只能回到 Console Timeline 肉眼搜。

**設計方向**：
- 在 `LogDetailView` / `NetworkDetailView` 底部加 `_NearbyEventsSection`
- 工具函式 `eventsAround(InspectorRegistry registry, DateTime center, Duration window)` 掃四個 buffer
- 展示 ±5s 內的其他事件（排除自身），點擊可跳轉對應 detail view
- 作為 `ExpansionTile` 預設收合，不影響既有頁面的載入效能
- **影響範圍**：`log_detail_view.dart`、`network_detail_view.dart`、可選新增共用 widget
- **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐

### §D4. DatabaseTab 搜尋 / 過濾

> `DatabaseTab`（131 行）目前是四個 tab 中最原始的——純列表，無搜尋、無過濾、無聚合。

**設計方向**：
- 加入 `_SearchBar`（搜尋 table name / SQL operation）
- `DatabaseOperation` 作為 `FilterChip`（query / insert / update / delete）
- 模式完全對齊 NetworkTab
- **影響範圍**：`lib/src/ui/dashboard/tabs/database_tab.dart`
- **Effort**：low ｜ **排查價值**：⭐⭐⭐

---

### §P1. 錯誤爆發偵測 + 視覺警報（Error Spike Detection）— 🆕

> **痛點**：短時間內湧入大量 error（如 API 全面 5xx、WebView JS 狂報錯），Console 被淹沒但沒有任何**錯誤**告警機制（**釐清**：既有 `NetworkNotifier` 系統通知只摘要網路活動、不辨識 error）。開發者可能在看別的 tab、甚至把 app 切到背景，錯過爆發窗口。

* **設計**：
  - 在 `FlutterInspector` 層追蹤「最近 N 秒內的 error-level entry 計數」
  - 超過閾值（如 10 筆/30s）時，Dashboard 頂部彈出 `MaterialBanner`——「⚠️ 過去 30 秒偵測到 {N} 筆錯誤」，點擊跳轉 Console 並自動套用 errors-only 過濾
  - 零新模型，只是一個 `ValueNotifier<int>` + 閾值比較
* **重用**：既有 `RingBuffer` 的 timestamp 掃描、`LogLevel.error` 判別、`NetworkEntry` 的 error 判別（`statusCode >= 400 || error != null`）；**以及既有 `NetworkNotifier` + `AlertThrottler` 系統通知基建**（自 v0.1.0，`flutter_local_notifications` 已在相依）——`MaterialBanner` 只在前景可見時有效，據此基建可低成本延伸「app 在背景時的**系統通知**告警」，補上前景盲區。
* **品味守則**：告警是**讀取既有 buffer 的衍生狀態**，不引入第二份計數器。用 `AlertThrottler` 防止 banner 本身的爆發（該節流器已存在於通知模組，直接複用）。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐⭐

### §P2. 錯誤上下文快照（Error Context Snapshot）— 🆕

> **痛點**：error log 或 network failure 發生時，有些**瞬態上下文**事後無法還原——「當時的路由堆疊是什麼」、「最後成功的 API 是哪個」。

* **設計**：
  - 每當捕捉到 error-level entry 時，自動快照 `NavigatorStackResolver.currentStack` 和最後一筆成功 `NetworkEntry`
  - 把快照塞入 `LogEntry.data`（`{'routeStack': [...], 'lastSuccessfulApi': '...'}`）
  - `LogDetailView` 的 Data section 已能渲染 Map——**零 UI 改動**
  - `buildDiagnosticReport` 的 Timeline 條目自然會包含這些 data
* **重用**：`NavigatorStackResolver`（已存在）、`LogEntry.data` Map（已定義）、`KeyValueTable`（已能渲染 Map）
* **品味守則**：快照**讀取既有資料結構**（NavigatorEntry buffer + NetworkEntry buffer），不維護自己的狀態。限制快照頻率（如 debounce 500ms 或只在首次 error 時快照）防高頻 error 場景效能問題。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐⭐

### §P3. Timeline 書籤 / 標記（Bookmark / Pin）— 🆕

> **痛點**：QA 重現 bug 時，想在 timeline 上標記「就是這裡出問題」，但匯出報告後，那個關鍵時刻淹沒在幾百筆事件裡。

* **設計**：
  - Timeline 列表項長按 → 標記為 📌 bookmark
  - 匯出報告時 bookmark 條目加 `📌` 前綴，方便 grep
  - Bookmark 作為一個獨立的 `Set<DateTime>` 存在 `_ConsoleTabState` 中（不修改 entry model——好品味：UI 狀態不汙染資料模型）
  - ConsoleTab 加一個 FilterChip「Bookmarks Only」
* **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐

### §P4. 快速複製 Diagnostic Snippet（一鍵複製 cURL + Error Payload）— 🆕

> **痛點**：開發者看到 API 失敗後，需要手動從 `NetworkDetailView` 複製 cURL、再從 error response 複製 body、再手動拼成一段完整的 bug report——步驟太多。

* **設計**：
  - `NetworkDetailView` 新增「Copy Diagnostic Snippet」按鈕
  - 一鍵組合：cURL + response status + error body + error type + timestamp → clipboard
  - 格式：Markdown fenced block（直接貼到 GitHub Issue / Slack）
* **重用**：`buildCurl()`、`buildPlainText()`、`share_text.dart`
* **Effort**：low ｜ **排查價值**：⭐⭐⭐

### §P5. Console Timeline 自動跳轉最新 Error（Jump to Latest Error）— 🆕

> **痛點**：Timeline 按時序排列（newest first），但最新 error 可能不在最頂（之後有新的 info/debug log 進來）。需要手動滾動找紅點。

* **設計**：
  - ConsoleTab 浮動按鈕（FAB）「⬆ Jump to Latest Error」
  - 掃描 `_filteredTimeline()` 找第一筆 error-level entry 的 index，`ScrollController.animateTo`
  - 無 error 時 FAB 隱藏
* **Effort**：low ｜ **排查價值**：⭐⭐⭐

### §P6. Dashboard 錯誤計數 Badge（Error Count Badge on Tabs）— 🆕

> **痛點**：Dashboard 底部 tab 沒有任何數字提示。使用者不知道 Network 裡有多少筆失敗、Console 裡有多少筆 error——得逐 tab 點進去看。

* **設計**：
  - Tab label 旁加 `Badge`（Material 3 `Badge` widget）
  - Network tab：顯示 error count（`statusCode >= 400 || error != null`）
  - Console/Timeline tab：顯示 error/warning log count
  - Count 為 0 時隱藏 badge
  - 用 `ValueListenableBuilder` 監聽 buffer 變化，局部重建
* **Effort**：low ｜ **排查價值**：⭐⭐⭐

### §P7. Error 高亮強化（Error Visual Enhancement）— 🆕

> **痛點**：目前 error log 只靠 `StatusColorIndicator` 的小色點區分（實際上 ConsoleTab 用 `TextStyle(color: entry.level.color)` 染文字色），在 500 條 timeline 裡不夠醒目。

* **設計**：
  - error/warning level 的 `_LogEntryRow` 加微妙的背景色（`ListTile` 外包 `Container` + `color: ThemeColor.colorF44336.withValues(alpha: 0.08)`）
  - 網路失敗的 `_NetworkEntryRow` 同理
  - 效果：error 條目帶淡紅底色，一眼從滾動列表中跳出
* **Effort**：trivial ｜ **排查價值**：⭐⭐⭐

### §P8. 網路請求耗時慢查詢標記（Slow Request Indicator）— 🆕

> **痛點**：API 回了 200 但花了 8 秒——不是 error 但確實是問題。目前無法快速識別慢請求。

* **設計**：
  - `NetworkEntry` 的 `duration` 超過可設定閾值（如 3000ms）時，列表項加 🐢 或黃色 `Chip("Slow")`
  - `_ErrorSummaryBanner` 可選顯示慢請求計數
  - 不修改 entry model，純 presentation 層判斷
* **Effort**：trivial ｜ **排查價值**：⭐⭐

### §P9. Diagnostic Report JSON 結構化輸出 — 🆕

> **痛點**：目前 `buildDiagnosticReport` 只輸出 Markdown。某些團隊需要結構化 JSON 以便自動化分析（如 CI 報告、Slack bot 解析）。

* **設計**：
  - 新增 `buildDiagnosticReportJson()` 回傳 `Map<String, dynamic>`
  - `ExportReportSheet` 加格式切換（Markdown / JSON）
  - JSON 結構直接映射既有 section，不引入新 schema
* **Effort**：medium ｜ **排查價值**：⭐⭐

---

### 完整優先順序總表

| 優先序 | 項目 | 來源 | Effort | 排查價值 |
|:---:|------|------|:---:|:---:|
| **1** | ConsoleTab 搜尋 + LogLevel 過濾 | §D1（#5 缺口） | low–med | ⭐⭐⭐⭐⭐ |
| **2** | 錯誤爆發偵測 + 視覺警報 | §P1 新提案 | low | ⭐⭐⭐⭐⭐ |
| **3** | 錯誤上下文快照 | §P2 新提案 | low | ⭐⭐⭐⭐⭐ |
| ~~4~~ | 未捕捉例外去重修復 — ✅ 已完成（PR #96） | §D2（#1 缺陷） | low | ⭐⭐⭐⭐ |
| **5** | Detail View ±5s 同時段側欄 | §D3（#2 做法 A） | med | ⭐⭐⭐⭐ |
| **6** | Timeline 書籤 / 標記 | §P3 新提案 | low | ⭐⭐⭐⭐ |
| **7** | Dashboard 錯誤計數 Badge | §P6 新提案 | low | ⭐⭐⭐ |
| **8** | Error 高亮強化 | §P7 新提案 | trivial | ⭐⭐⭐ |
| **9** | 快速複製 Diagnostic Snippet | §P4 新提案 | low | ⭐⭐⭐ |
| **10** | Jump to Latest Error FAB | §P5 新提案 | low | ⭐⭐⭐ |
| **11** | DatabaseTab 搜尋 / 過濾 | §D4 缺口 | low | ⭐⭐⭐ |
| **12** | 慢請求標記 | §P8 新提案 | trivial | ⭐⭐ |
| **13** | Diagnostic Report JSON 輸出 | §P9 新提案 | med | ⭐⭐ |

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

5. **B 級 WebView 除錯器（breakpoint / step / DOM inspector / profiler / JS REPL）**
   - *拒絕*：breakpoint/profiler 需要 CDP，inline 模擬是假貨；DOM inspector 工程量爆炸且 Eruda 頁內已有（#10 Phase 0 食譜即覆蓋此需求）；JS REPL（從 dashboard 對 WebView 執行任意 JS）技術上可行但那是「操控」不是「觀測」，跨越產品邊界且有安全面問題。README 直接指路 chrome://inspect 與 Safari Inspector。**砍**（REPL 若未來需求真實再議）。

6. **WebView 專屬 tab / 第五個 TimelineSource**
   - *拒絕*：WebView log 就是 log、fetch 就是 network。加 enum、開新 tab 是為不存在的區別打補丁，會讓 filter / 報告 / UI 全鏈路長出特殊情況。provenance 用 `NetworkOrigin` + `LogEntry.data` 標記足矣。**砍**。

7. **直接相依 webview 套件（提供包裝好的 InspectorWebView widget）**
   - *拒絕*：綁死 `webview_flutter` 或 `flutter_inappwebview` 其一，就把另一半使用者關在門外（inappwebview_inspector 正是此坑）；兩個都支援則相依翻倍、版本矩陣地獄。host-injection 模式已驗證兩次（`DiagnosticInfoSource`、`DatabaseBrowserSource`），沒有理由背棄。**砍**。同理**跨 iframe / Service Worker 橋接**——複雜度與受眾完全不成比例，**砍**。

*（以下隨第四部分新增 · 2026-07-23）*

8. **State 檢查器 / Widget Tree 瀏覽器**
   - *拒絕*：DevTools 已有且做得更好。in-app 重造需要反射或大量 Element tree walk，代價高且永遠是 DevTools 的子集。**砍**。

9. **自動化測試整合**
   - *拒絕*：超出 debug inspector 邊界。inspector 的使用者是人（開發者/QA），不是 CI。如果測試需要讀 inspector 資料，那是消費端的事，不該改變 inspector 的設計重心。**砍**。

---

## 📅 下一步實作路徑（2026-07-23 更新 · 四階段 Phase Plan）

排序原則：**🔴 先滅紅燈 → 修 bug → 主動告警 → 深度排查 → 體驗打磨**。

### Phase 1 · 排查紅燈滅火（最高優先）

| 項目 | 內容 | 寫入路徑 |
|------|------|----------|
| **§D1** ConsoleTab 搜尋/過濾 | 搜尋欄 + LogLevel FilterChip + errors-only 快捷 | `console_tab.dart` + 可選 `console_utils.dart` |
| **§D2** 未捕捉例外去重 — ✅ 已完成 | object-identity 去重（PR #96，2026-07-24 合入 main） | `uncaught_error_handler.dart` |

> 消滅排查鏈上最後一個 🔴 紅燈 + 修復一個長期噪音 bug。**§D2 去重已由 PR #96 完成**，Phase 1 僅剩 §D1 ConsoleTab 搜尋/過濾。

### Phase 2 · 主動告警 + 視覺強化

| 項目 | 內容 | 寫入路徑 |
|------|------|----------|
| **§P1** 錯誤爆發偵測 | error 計數 + MaterialBanner 告警 | `flutter_inspector.dart` + `dashboard_modal.dart` |
| **§P7** Error 高亮強化 | error 行淡紅底色 | `console_tab.dart` 的 `_LogEntryRow` / `_NetworkEntryRow` |
| **§P6** Dashboard Badge | tab 的 error count badge | `dashboard_modal.dart` |

> 從「被動翻找」升級為「主動告知」。三項皆 effort=low/trivial，可一次釋出。

### Phase 3 · 深度排查

| 項目 | 內容 | 寫入路徑 |
|------|------|----------|
| **§P2** 錯誤上下文快照 | error 時自動快照路由堆疊 + 最後成功 API | `uncaught_error_handler.dart` + `flutter_inspector.dart` |
| **§D3** ±5s 同時段側欄 | detail view 底部跨層事件關聯 | `log_detail_view.dart` + `network_detail_view.dart` |
| **§P3** Timeline 書籤 | 長按標記 + bookmark-only 過濾 + 報告前綴 | `console_tab.dart` + `diagnostic_report.dart` |

> 提供「為什麼出錯」的深度線索。需 Phase 1 的搜尋/過濾基建先完成。

### Phase 4 · 體驗打磨（依回饋排程）

| 項目 | 內容 |
|------|------|
| **§P4** 快速複製 Diagnostic Snippet | NetworkDetailView 一鍵 cURL + error payload |
| **§P5** Jump to Latest Error FAB | ConsoleTab 浮動按鈕跳轉最新 error |
| **§P8** 慢請求標記 | NetworkTab 的 duration 閾值 + 🐢 標記 |
| **§P9** Diagnostic Report JSON | 結構化 JSON 匯出格式 |
| **§D4** DatabaseTab 搜尋/過濾 | 搜尋 + operation FilterChip |

> 每一項都是獨立增量，且彼此寫入路徑不重疊，適合並行推進。

---

> **收尾建議（2026-07-24 更新）**：排查鏈的基礎建設已近完備（10 項原始功能中 9 項完成，#1 去重已由 PR #96 修復）。**Phase 1 僅剩 §D1 ConsoleTab 搜尋/過濾紅燈**（去重 bug §D2 已完成），預估 effort=low–medium。Phase 2–4 依實際回饋與優先級排程。全部 13 項的設計都遵循「重用既有零件」原則——零新相依、零新模型，只是把已經存在的資料用更聰明的方式呈現。

> 每一階段都是獨立可上線的增量，且彼此寫入路徑不重疊（§D1 動 console_tab、§D2 動 uncaught_error_handler、§P1 動 flutter_inspector + dashboard、§D3 動 detail views），適合並行推進。
