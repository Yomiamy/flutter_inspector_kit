# 🩺 Flutter Inspector 錯誤問題排查與分析：功能腦力激盪報告

> **建立日期**：2026-06-25（原始檔名）｜**最後更新**：2026-07-02（同步 v1.2.1／PR #55：Console tab clear 按鈕修正，四來源一併清除）

> 「好代碼沒有特殊情況。」 —— Linus Torvalds
>
> 這份報告**只聚焦一件事**：當 app 出錯時，`flutter_inspector_kit` 能不能讓開發者/QA 用最少的步驟「看見錯誤、關聯原因、帶走證據」。
> 我們不重彈上一份 [`brainstorm/2026-06-18-feature_brainstorming.md`](../../brainstorm/2026-06-18-feature_brainstorming.md) 的泛用優化清單，而是用排查（troubleshooting）這把尺，重新審視每個缺口。凡是偏離「排查」核心、或為了理論完美而增加複雜度的，一律砍掉。

---

## 📊 完成度總覽（截至 2026-07-02 · 含 v1.1.0～v1.2.1）

> 以下狀態依實際 codebase 與 git history 核對標注。✅ 完成 ｜ 🟡 部分完成 ｜ ⬜ 未實作。
> **更新說明**：v1.1.0（PR #40 / #42）把 console 重構為真正的混合時間軸後，**#2 由 ⬜ 升級為 🟡**（時序關聯的主體已落地）。v1.2.0（PR #51）完成 **#8 當前路由堆疊可視化**，由 ⬜ 升級為 ✅。v1.2.1（PR #55）修正 Console tab 的 clear 按鈕，使其連動清除 mergedTimeline 的四個底層來源——這是對 **#2** 既有 🟡 狀態的正確性補強，完成度評級不變（仍缺做法 A 的 ±5s 側欄）。

| # | 功能 | 狀態 | 備註 |
|---|------|:---:|------|
| #1 | 全局未捕捉例外捕捉 | ✅ | PR #30：`captureUncaughtErrors`(default off) + 三掛點 chain，含去重 |
| #6 | 網路請求重放 | ✅ | PR #36 / v1.0.0 已完成：支援 per-Dio 原樣重送、`isReplay` 標記、狀態回饋與防連點保護 |
| #8 | 當前路由堆疊可視化 | ✅ | PR #51（Issue #50，v1.2.0）：新增 `NavigatorStackResolver` 純 Dart 重播器，`NavigatorTab` 以 `SegmentedButton` 切換「當前堆疊」（垂直卡片）與「事件歷史」 |
| #2 | 跨 Inspector 時序關聯 | 🟡 | **v1.1.0 大幅推進**：ConsoleTab 已改用 `mergedTimeline`（四 buffer 按 `timestamp` 歸併排序），即文件「做法 B：Timeline 視圖」的本體已成；**v1.2.1（PR #55）** 修正 clear 按鈕連動清除 log/network/navigator/database 四來源，補上先前「清除後殘留資料重新浮現」的缺陷；**缺** 做法 A（detail view 的 ±5s 同時段側欄） |
| #4 | Dio 結構化錯誤捕捉 | 🟡 | 已抓 statusCode/headers/body；**缺** `errorType`/`errorStackTrace` 結構化分類與 Exception Details section |
| #5 | ConsoleTab 排查化 | 🟡 | `LogDetailView`(stackTrace/data/分享) 完成；**缺** 搜尋欄 / LogLevel FilterChip / errors-only 過濾（`utils/` 下仍無 log_search） |
| #3 | 一鍵診斷報告 | ⬜ | 未實作（查無 `buildDiagnosticReport`） |
| #7 | 錯誤聚合摘要 | ⬜ | 未實作（查無 `ErrorSummary`） |

**Anti-features**（Profiler / 落盤 crash history / HAR timing / API mocking）— ✅ 正確地皆未實作，守住「不走向微核心」。

**進度結論**：8 項裡 **4 項完成**（#1、#6、#8，以及 v1.1.0 實質完成的 **#2 時序軸主體**），**2 項半成品**（#4 結構化錯誤、#5 console 搜尋/過濾），**2 項未動**（#3、#7）。下一刀應收尾 **#4 結構化分類** 與 **#5 console 搜尋/過濾**——這兩項是 console 排查化僅剩的缺口。

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

> **這是 v1.1.0 之前的原始盤點快照**，保留以記錄各功能當初的動機。實際現況請以本文件頂部的「完成度總覽」為準——下表多列已因後續實作而改變（例如 #1 例外捕捉已完成、#2 時序軸主體已落地）。

| 排查環節 | 現況 | 評級 |
|---|---|---|
| 看見「我主動 log 的」錯誤 | `inspector.log(..., level: error, stackTrace: ...)` 可記錄；`LogDetailView` 已可點擊展開並複製 stackTrace（截至 2026-07-01 核對） | ✅ 已可展示 |
| 看見「未捕捉」的例外 | **無**任何 `FlutterError.onError` / `runZonedGuarded` / `PlatformDispatcher.onError` / `ErrorWidget.builder` | 🔴 盲區 |
| 看見網路失敗的根因 | Dio `onError` 只存 `err.toString()`，丟掉 `err.type`/`err.stackTrace`/`err.response` | 🟡 失真 |
| 關聯「錯誤前後發生了什麼」 | 4 個 buffer（log/network/nav/db）共用 `timestamp` 卻**完全孤立**，無跨層時序 | 🔴 斷裂 |
| 帶走排查證據 | 只能匯出**單筆** network（cURL/分享）；log 無任何匯出；無診斷報告打包 | 🔴 殘缺 |
| 過濾定位 error log | `LogInspector.entriesAtLevel()` 已存在，`ConsoleTab` **從不使用**，無搜尋無過濾 | 🔴 垃圾 |

> 結論：排查鏈條上的六個環節，**四個是紅燈**。這不是優化問題，是這個「debug 工具」在錯誤排查這條主線上幾乎沒鋪設。

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
* **✅ 實作現況**：PR #30 已完成。`FlutterInspector(captureUncaughtErrors: false)` 入口 + `setupErrorHandlers()` 三掛點（`FlutterError.onError` chain、`PlatformDispatcher.onError`、`ErrorWidget.builder`）皆落地，並補上同一例外的去重；`runGuarded` 已移除改用 `PlatformDispatcher.onError`。

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
* **🟡 v1.2.1 修正（PR #55，Issue #54）**：`ConsoleTab` 的 clear 按鈕原本只呼叫 `inspector.clearLogs()`，但 mergedTimeline 渲染的 network/navigator/database entries 仍留在各自的 buffer 裡，清除後會重新出現在時間軸——對「四來源共享同一時間軸」的架構而言，這是不完整的清除語意。修正後 `onPressed` 改為同時呼叫 `clearLogs()` / `clearNetwork()` / `clearNavigator()` / `clearDatabase()`，四個來源一併清空。純正確性修補，不影響 #2 的完成度評級。

### 3. 一鍵診斷報告（Diagnostic Report）— ⬜ 未實作（原 🔴 QA 提 bug 的剛需）
* **痛點**：QA 重現 bug 後，要手動切四個 tab、逐筆截圖/複製、再手打 device/OS/版本資訊。耗時且容易漏，回報品質參差。
* **好品味設計**：
  - 新增 `buildDiagnosticReport(inspector, {timeRange, sections})`，輸出一份 **Markdown / JSON** 報告：device & app info 表頭 + 選定時間窗內的 log / network / nav / db 各區段。
  - Dashboard AppBar 新增「Export Diagnostic Report」action → 勾選區段 + 時間範圍（last 5m / 1h / all）+ 格式 → 走系統分享。
  - device/app info 用官方維護的 `package_info_plus` + `device_info_plus`（**可選相依**，未安裝時該區段降級為「N/A」，絕不崩）。
* **重用**：`network_formatters.dart` 的 `buildPlainText`/`buildCurl` 序列化模式、`share_text.dart` 平台自適應分享、各 buffer 的 newest-first snapshot getter。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐⭐

### 4. Dio 錯誤的結構化捕捉（Structured Network Error）— 🟡 部分完成
* **痛點**：`onError()` 只存 `err.toString()`，把 `DioException` 的精華全丟了：**根因類型**（connectionTimeout / DNS / SSL / parse / cancel）、`err.stackTrace`、以及**伺服器回傳的 error body**。開發者看到一坨字串，分不清是「斷網」還是「server 5xx」。
* **好品味設計**：
  - `dio_interceptor.onError` 改為擷取結構化欄位：`err.type`（分類）、`err.stackTrace`、`err.response?.statusCode`、保住 `err.response?.data`（伺服器的錯誤說明）。
  - 核心區分一條：**`response == null` → 傳輸層失敗（沒到 server）**；**`response != null` → server 回了錯誤碼**。這條判斷消滅了「Failed 到底是斷網還是後端壞了」的猜謎。
  - `NetworkDetailView` 新增「Exception Details」section 分層展示。
* **重用**：擴充 `NetworkEntry.error`（或加 `errorType` / `errorStackTrace` 欄位，保持 `@immutable`）、`DioExceptionType` enum、既有 detail view 的 card 分層。
* **Effort**：low–medium ｜ **排查價值**：⭐⭐⭐⭐
* **🟡 實作現況**：`onError` 已擷取 `statusCode` / `responseHeaders` / `responseBody`（不再只存 `toString()`）。**未完成**：`NetworkEntry` 仍無 `errorType`(DioExceptionType) 與 `errorStackTrace` 欄位，`error` 仍是 `err.toString()`；「`response==null` → 傳輸層失敗 vs server 回錯」的結構化分類與 `NetworkDetailView` 的「Exception Details」section 尚未做。

### 5. ConsoleTab 排查化：stackTrace 詳情 + error 過濾 — 🟡 部分完成
* **痛點**：error log 的 `stackTrace` 與 `data` 在 UI 完全看不到，列表項點了沒反應，500 條 log 無搜尋無過濾，error 跟 info 混成一片。
* **好品味設計**：
  - `LogDetailView`（仿 `NetworkDetailView`）：點 log 展開 message / level / **可複製 stackTrace** / `data`（用 `KeyValueTable`）。
  - 搜尋欄 + LogLevel FilterChip + 「errors only」快捷——直接套 `NetworkTab` 的搜尋/chip 模式與 `applyNetworkFilter` 邏輯框架，error log 終於能秒定位。
* **重用**：`NetworkTab` 搜尋 bar + FilterChip、`LogInspector.entriesAtLevel()`（已存在）、`KeyValueTable`、`NetworkDetailView` 佈局。
* **注意**：搜尋/過濾/詳情面板在 [上一份 brainstorm](../../brainstorm/2026-06-18-feature_brainstorming.md) 已列入。**此處只強調其排查價值並與 #2 的時序側欄、#3 的報告打包對齊**，避免重複規劃；實作時應一併考量。
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

### 7. 錯誤聚合摘要（Error Aggregation）— ⬜ 未實作
* **價值**：同一個 502 每 30 秒打一次 → 現在是 500 條各自獨立的列表項。聚合成「502 Bad Gateway × N 次，最近 5 分鐘」一張卡，一眼看出是「持續故障」還是「偶發」。
* **設計**：`NetworkTab` 頂部「Error Summary」卡，按 `(statusCode, errorType)` 分組計數 + 首末時間。
* **重用**：`NetworkStatusGroup.matches()` 分組邏輯、`RingBuffer` 作資料源。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐

### 8. 當前路由堆疊可視化（Active Navigation Stack）— ✅ 已完成（PR #51）
* **價值**：排查「頁面有沒有被重複 push / 該 pop 沒 pop（記憶體洩漏前兆）」。錯誤發生時的路由堆疊也是 #3 診斷報告的關鍵 context。
* **設計**：`NavigatorObserver` 即時維護 `currentStack`，`NavigatorTab` 頂部以麵包屑顯示 Root→Top，偵測重複 push 時標 warning。
* **重用**：既有 push/pop/replace 回調、`KeyValueTable`。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐
* **註**：與上一份 brainstorm 的「Navigator Stack Visualizer」同一構想，此處定位為「為診斷報告提供 crash 當下路由快照」。
* **✅ 實作現況**：PR #51（Issue #50）已完成。新增 `NavigatorStackResolver`（`lib/src/inspectors/navigator_stack_resolver.dart`）純 Dart 重播器，將 `navigatorEntries`（newest-first）反轉回時序後重播 push/pop/replace/remove，推導出 top-first 當前堆疊；`NavigatorTab` 以 `SegmentedButton` 在「當前堆疊」（垂直卡片，顯示 `displayName` + `routeName`）與既有「事件歷史」之間切換。採**垂直卡片**而非麵包屑（經 STAGE 0a 規格確認調整，理由見 `docs/features/2026-07-01-navigator-active-stack.md`）；replace/remove 的歧義情況採明確可預測的 best-effort 規則，不做 nested Navigator 多樹精確還原。

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

---

## 📅 下一步實作路徑（依排查價值排序）

排序原則：**先補盲區（看得見錯誤）→ 再建關聯（看得懂錯誤）→ 最後打包（帶得走證據）**。

1. **第一階段 · 點亮盲區**（🟡 進行中）：實作 **#1 全局未捕捉例外捕捉**（可選 default-off）✅ + **#4 Dio 結構化錯誤捕捉** 🟡（結構化分類欄位待補）。此後 inspector 才真正「看得見」錯誤。
2. **第二階段 · ConsoleTab 排查化**（🟡 進行中）：實作 **#5**（stackTrace 詳情 ✅ + error 搜尋/過濾 ⬜ 待補），讓捕捉到的錯誤可被秒速定位與檢視。
3. **第三階段 · 建立關聯**（🟡 主體已完成）：**#2 做法 B（Timeline 混合視圖）已於 v1.1.0 落地** ✅（`mergedTimeline` + `TimestampedEntry`）；僅剩 **做法 A**（detail view 的 ±5s 同時段側欄 ⬜）尚未做，可視回饋決定是否補上。
4. **第四階段 · 帶走證據**（⬜ 未開始）：實作 **#3 一鍵診斷報告**（device info；路由堆疊快照可直接複用已完成的 #8 `NavigatorStackResolver`）。QA 提 bug 的剛需在此閉環。
5. 第五階段 · 加分項（✅ 部分完成）：#6 Replay 已於 v1.0.0 完成實作、**#8 路由堆疊可視化已於 PR #51 完成**；後續可視回饋實作 #7 錯誤聚合摘要。

> **收尾建議（截至 2026-06-29）**：console 排查鏈只剩兩個明確缺口——**#4 的結構化錯誤分類** 與 **#5 的搜尋/過濾**。兩者寫入路徑不重疊（#4 動 interceptor + model、#5 動 console UI），可並行收掉，console 排查化即閉環。其後再進第四階段 #3 診斷報告。

> 每一階段都是獨立可上線的增量，且彼此寫入路徑不重疊（#1 動 core、#4 動 interceptor、#5 動 console UI、#3 動 utils + dashboard），適合並行推進。
