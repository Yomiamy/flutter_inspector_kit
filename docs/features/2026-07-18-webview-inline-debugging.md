# 功能規格：WebView Inline Debugging（WebView 觀測層）

- **日期**：2026-07-18
- **狀態**：STAGE 4 — 已完成 (PR #91)
- **來源**：`docs/brainstorm/2026-07-17-features-brainstorm.md`「第三部分：新戰場——WebView 觀測層」`### 10.`（已定案核心設計）
- **類型**：新事件來源接入（不新增 UI tab、不新增資料模型；WebView 事件併入既有 log / network 管線）
- **本次範圍**：Phase 1 + 2 + 3（完整 bridge + 雙套件接線文檔 + example 示範頁）。**不含** Phase 0（Eruda README 食譜）。

---

## 1. 功能概述（What & Why）

### 一句話本質

宿主 app 嵌的 WebView 目前對 inspector **完全隱形**。本功能提供一段可注入的 JS bridge 與一個 adapter，把 WebView 內的 `console.*`、JS error、`fetch`/`XHR` **翻譯成既有的 `LogEntry` 與 `NetworkEntry`**，讓它們和 native 事件出現在**同一條 timeline** 上——這是「多一個事件來源」，不是「多一個系統」。

### 為什麼要做（Why，已逐檔核對的現況事實）

- **`lib/` 零 webview 程式碼**：掃描確認套件目前完全沒有 WebView 觀測能力。宿主 app 一旦嵌 H5 活動頁 / 支付頁 / 混合頁，頁內的 `console.log`、JS error、`fetch` 全部隱形。
- **既有資料模型天生容納 WebView 事件（零 schema 變更）**：
  - `lib/src/models/log_entry.dart`：`LogEntry` 欄位為 `timestamp` / `level`(`LogLevel`) / `message` / `stackTrace`(`String?`) / `data`(`Map<String, dynamic>?`)。WebView 的 console 訊息與 JS error 完整對應，來源標記（`origin: webview`、`pageUrl`）可塞進既有 `data` map，**不需新增欄位**。
  - `lib/src/models/network_entry.dart`：`NetworkEntry` 的 `errorType`(`DioExceptionType?`) 與 `sourceDio`(`WeakReference<Dio>?`) 本為 nullable。WebView 的 `fetch` 填 null 即可入列——**天生容納非 Dio 來源**。
  - `lib/src/models/timestamped_entry.dart`：`LogEntry` 與 `NetworkEntry` 皆已實作 `TimestampedEntry`，故 `mergedTimeline()`、Console tab、Network tab、#7 error aggregation、#3/#9 診斷報告 Timeline **不需任何改動即免費支援 WebView 事件**。
- **host-injection 範式已驗證兩次**：`DiagnosticInfoSource`（`lib/src/models/diagnostic_info.dart`）與 `DatabaseBrowserSource`（`lib/src/models/database_browser_source.dart`）都讓宿主 app 注入能力、而套件本身零第三方相依。本功能是此範式的**第三次複用**——套件只提供 JS payload + adapter + 訊息協定，宿主自備 webview 套件並接線。

現況的痛點：

> 「native 端發了某通知之後，WebView 裡哪個 fetch 失敗了」——這種**跨層因果**，開發者現在完全看不到。外接 chrome://inspect（Android）或 Safari Web Inspector（iOS 16.4+ 還得逐 WebView opt-in）只能看 WebView 內部、且與 native 世界隔絕；QA 裝置上更是無解。競品（`inappwebview_inspector` 綁死單一套件且只有 console；vConsole / Eruda 面板畫在網頁裡、換頁即重置）**沒有一個做到跨層時間軸關聯**。

### 設計核心（本規格提議、待確認）

> WebView 事件是既有 timeline 的**新來源**，不是新真相。adapter 是**翻譯器不是系統**——收 WebView 訊息、翻成既有 `LogEntry`/`NetworkEntry`、交給既有 registry，**不持有 buffer、不做 UI、不引入第二份資料**。

對齊專案既有品味守則：**不加第五個 `TimelineSource` enum、不開 WebView 專屬 tab**。WebView 的 log 就是 log、fetch 就是 network，加區別是為不存在的差異打補丁，會讓 filter / 報告 / UI 全鏈路長出特殊情況。來源標記走 `LogEntry.data` / `NetworkEntry` 既有欄位，UI 是否為 WebView 事件加小圖示屬 presentation 層的可選判斷，資料層無感。

---

## 2. 使用者故事與驗收條件

### US-1：WebView console 與 JS error 併入同一條 timeline（Phase 1）

> 身為除錯混合頁的開發者 / QA，我希望 WebView 內的 `console.log/info/warn/error` 與未捕捉的 JS error 出現在 inspector 的 Console tab 與 mergedTimeline 上，和 native log 依時間交錯，讓我一眼看出跨層因果。

**驗收條件：**

- [ ] WebView 的 `console.log` / `console.info` / `console.warn` / `console.error` / `console.debug` 經注入的 bridge 傳回 native 後，成為 `LogEntry` 進入 registry，`level` 對應 console 方法（error→error、warn→warning，其餘→info/debug）。
- [ ] WebView 的 `window.onerror` 與 `unhandledrejection` 成為 **error 級** `LogEntry`，JS stack trace 進入 `LogEntry.stackTrace`。
- [ ] 這些 entry 出現在既有 Console tab、`mergedTimeline()` 與診斷報告 Timeline 中，與 native 事件依 `timestamp` 正確交錯，**不需修改上述任何既有 UI / 報告程式碼**。
- [ ] 每筆 WebView 來源的 `LogEntry` 帶有可辨識的來源標記（透過既有 `data` map，如 `{'origin': 'webview', 'pageUrl': ...}`），不新增 `LogEntry` 欄位。

### US-2：WebView 網路請求併入 Network tab（Phase 2）

> 身為開發者，我希望 WebView 內 `fetch` / `XMLHttpRequest` 的請求與失敗，出現在 inspector 的 Network tab，和 native Dio 請求一起被 #7 error aggregation 統計。

**驗收條件：**

- [ ] WebView 的 `fetch` 與 `XMLHttpRequest` 經 bridge 傳回後成為 `NetworkEntry`，`method` / `url` / `statusCode` / `duration` / headers / body 正確對應。
- [ ] WebView 網路請求出現在既有 Network tab 與 mergedTimeline；失敗請求（`statusCode >= 400` 或傳輸失敗）被既有 #7 error aggregation 一併統計。
- [ ] 非 Dio 來源的欄位（`errorType` / `sourceDio`）填 `null`，不偽造 Dio 專屬資訊。

### US-3：WebView 網路資料尊重 redaction（安全鐵律）

> 身為在意隱私的使用者，我啟用了 `redactSensitiveData`，我要求 WebView 的網路 headers/body 和 native 請求**用完全一樣的遮罩機制與時機**——不因為它來自 WebView 就多開一條後門，也不因此與 native 行為分歧。

**驗收條件（方案 B：display-time redaction，與 native 一致）：**

> 校正說明（STAGE 0b 已確認）：codebase 的 redaction 是 **display-time**——Dio interceptor 存的是**原始** headers/body，遮罩只發生在顯示/匯出邊界（`buildCurl` / `buildPlainText` / 診斷報告 / detail view 的 copy·share），且吃 `redactSensitiveData` 旗標；`redaction.dart` 只有 `redactHeaders`、無 body redaction。WebView 事件走**同一條路**：adapter 建原始 `NetworkEntry`，遮罩由同一組 formatter 自動繼承。原 STAGE 0a「ingest 前遮罩」措辭與此架構衝突（會與 native 分歧、無視 opt-out、且需憑空新造 body redaction），已改為以下方案 B。

- [ ] WebView `fetch`/`XHR` 的 `NetworkEntry` 由 adapter 以**原始** headers/body 建立（與 native Dio 請求存原始資料的行為逐字節一致），**不在 ingest 時遮罩**。
- [ ] 敏感資料的遮罩由**既有的顯示/匯出 formatter 自動繼承**（`buildCurl` / `buildPlainText` / 診斷報告 / detail view copy·share，吃 `redactSensitiveData` 旗標，`kRedactedValue = '••••'`）——WebView 事件與 native 事件經過**同一組** formatter，遮罩行為與時機完全一致。
- [ ] **不新增任何 WebView 專屬的 redaction 程式碼、不繞過既有管線**：正因為只有一條路，WebView 來源不可能成為敏感資料外洩的旁門；同時尊重 opt-out（`redactSensitiveData=false` 時 WebView 與 native 一樣顯示原始）。

### US-4：大 payload 有截斷，不卡 UI

> 身為開發者，我不希望 WebView 傳來一個超大 response body 把 bridge 塞爆、拖垮 UI thread。

**驗收條件：**

- [ ] 大型訊息（尤其 response body）在 **JS 端**於送過 bridge 前即截斷至上限，並帶明確的截斷標記（如 `truncated: true`），與既有 `RingBuffer`「上限在源頭」的哲學一致——不是在 Dart 端事後補救。
- [ ] 截斷上限為具名常數，不是魔術數字。

### US-5：WebView 網路請求優雅降級（Replay 正確地不可用）

> 身為使用者，我理解 WebView 的請求不是經 Dio 送出，所以 Network detail 的 Replay 對它不可用——但這該是明確、不崩的降級，不是隱藏的錯誤。

**驗收條件：**

- [ ] WebView 來源的 `NetworkEntry` 因 `sourceDio == null`，在 `NetworkDetailView` 上 Replay 功能**正確地不可用**（沿用既有對 `sourceDio == null` 的 null 檢查降級，不新增特殊分支、不崩）。
- [ ] 此降級不影響 native Dio 請求的 Replay 行為。

### US-6：零新相依、既有公開 API 不變（Never break userspace）

> 身為既有套件使用者，我希望加入 WebView 支援不讓套件多背任何第三方相依，也不改動我已依賴的 `FlutterInspector` API 行為。

**驗收條件：**

- [ ] 套件本體（`lib/`）**不新增任何 package 相依**（不 depend `webview_flutter` / `flutter_inappwebview`）。接線能力循 host-injection 範式：套件提供 JS payload 常數、訊息協定、adapter 進入點，宿主自備 webview 套件並接線。
- [ ] `FlutterInspector` 既有公開 API 行為不變；新增的接入點為**可選**，未接線的宿主完全不受影響（比照 `diagnosticInfoSource` / `databaseSources` 的可選注入形狀）。
- [ ] example app 若加入 webview 套件，僅加在 `example/pubspec.yaml`，**不污染套件本體的相依**。

### US-7：webview_flutter 與 flutter_inappwebview 雙套件皆可接線（Phase 3）

> 身為使用不同 webview 套件的開發者，我希望文檔告訴我，無論用 webview_flutter 還是 flutter_inappwebview，都能照抄接線這個 bridge。

**驗收條件：**

- [ ] README 提供 `webview_flutter` 與 `flutter_inappwebview` **各一段**接線範例（建立 JavaScriptChannel → onMessage 轉交 adapter → 頁面載入時注入 JS payload）。
- [ ] 文檔明示**注入時機**的差異與限制（見 §5）：`flutter_inappwebview` 的 `UserScript` 可於 documentStart 注入、吃得到早期 log；`webview_flutter` 抽象層較弱，`runJavaScript` 於載入後執行會漏早期 log——文檔誠實說明各自的能與不能，不假裝兩者等價。
- [ ] example app 新增一個 WebView 示範頁（落點 `example/lib/demos/webview_demo.dart`，對齊既有 `demos/network_demo.dart` 慣例），實際展示接線後 WebView 事件出現在 dashboard。

---

## 3. 範圍邊界（Scope）

### In-Scope

- **JS bridge payload**（Dart 常數字串）：hook `console.*` / `window.onerror` / `unhandledrejection` / `fetch` / `XMLHttpRequest`，統一 JSON 訊息協定 postMessage 給 native，JS 端截斷大 payload。
- **Bridge adapter**（Dart）：decode 訊息 → 轉 `LogEntry` / `NetworkEntry` → 進既有 registry；網路事件過既有 redaction 管線。
- **可選接入點**：循 host-injection 範式，讓宿主把 adapter 接上自己的 JavaScriptChannel（具體 API 形狀屬 STAGE 0b）。
- **雙套件 README 接線文檔** + 注入時機警告。
- **example 示範頁** `example/lib/demos/webview_demo.dart`（webview 套件加於 `example/pubspec.yaml`）。

### Out-of-Scope（明確排除）

- **B 級除錯器**：breakpoint / step through / profiler / 記憶體分析——需要 CDP，inline 模擬是假貨。文檔指路 chrome://inspect 與 Safari Inspector。
- **DOM inspector / element picker**：工程量與受眾不成比例（Eruda 頁內已覆蓋此需求，屬本次未做的 Phase 0）。
- **JS REPL**（從 dashboard 對 WebView 執行任意 JS）：屬「操控」非「觀測」，跨越產品邊界且有安全面問題；未來需求真實再議。
- **第五個 `TimelineSource` enum / WebView 專屬 tab**：WebView log 就是 log、fetch 就是 network，加區別是特殊情況繁殖。
- **直接相依 webview 套件**（提供包裝好的 InspectorWebView widget）：綁死其一即關掉另一半使用者，兩者都支援則相依翻倍。
- **iframe / Service Worker 橋接**：注入只作用於 main frame；跨 frame / SW 事件不收（README 明文註記）。
- **Phase 0（Eruda README 食譜）**：本次範圍外。

---

## 4. 向後相容性聲明

- **零新相依**：套件本體不新增任何第三方 package；WASM 相容性不因本功能破壞。
- **schema 僅做向後相容擴充**（2026-07-18 修訂，見決策紀錄 #6）：`LogEntry` / `TimestampedEntry` 公開形狀不變；`NetworkEntry` 新增 `origin`（預設 `NetworkOrigin.dio`）與 `pageUrl`（預設 `null`）兩個**帶預設值的可選欄位**——既有建構呼叫、Dio interceptor、Replay 皆零改動，不破壞任何現有使用者。
- **既有公開 API 不動**：`FlutterInspector` 現有建構參數與行為不變，新增接入點為可選；未接線宿主零影響。
- **既有 UI / 報告零改動即受益**：Console tab / Network tab / mergedTimeline / #7 error aggregation / #3·#9 診斷報告 Timeline 不需修改即支援 WebView 事件——唯一「行為改變」是接線後多出一個事件來源，資訊只增不減。

---

## 5. 技術限制與誠實邊界（規格依據）

本節誠實標註 WebView inline 觀測的先天限制與必守約束，避免驗收條件承諾做不到的事：

| 限制 / 風險 | 規格層級約束 |
|---|---|
| **注入時機**：`runJavaScript` 於頁面載入後執行會漏早期 log。documentStart 注入需 `flutter_inappwebview` 的 `UserScript`；`webview_flutter` 抽象層較弱（iOS 底層有 `WKUserScript` 但未完整暴露）。 | 文檔明示各套件的注入時機能與不能；套件不吞這個平台差異，交由宿主依文檔選擇接線方式。 |
| **敏感資料**：WebView 內容是不可信來源，網路 headers/body 可能含 token。 | redaction 為 **display-time**（既有架構）：adapter 存原始 `NetworkEntry`，遮罩由既有顯示/匯出 formatter 自動繼承、吃 `redactSensitiveData` 旗標。**不新增 WebView 專屬 redaction、不繞過既有管線**——WebView 與 native 走同一組 formatter（US-3 方案 B）。 |
| **bridge 流量**：大 response body 序列化過 JavaScriptChannel 會卡 UI thread。 | 大 payload 於 **JS 端**截斷（US-4），上限為具名常數；非 Dart 端事後補救。 |
| **不可信輸入（CRLF / malformed-URL）**：WebView 訊息可能含換行或畸形 URL，撐破報告格式或外洩 query secret。 | WebView 訊息走 #9 已加固的 CRLF / malformed-URL 清洗路徑（既有 one-liner formatter 的防護），並於實作補驗證。 |
| **iframe 不支援**：注入只作用於 main frame，iframe 內事件收不到。 | v1 明文不支援，README 註記；不偷做跨 frame 橋接。 |
| **`setOnConsoleMessage` 誘惑**：webview_flutter 4.x 原生可收 console 看似免注入，但 iOS 有遞迴物件 logging bug（flutter/flutter#144535），且只覆蓋 console（無 fetch/error）。 | 以 JS 注入為主路徑；原生 console 回呼僅可作為 console 的降級備援，不作為 fetch/error 的來源。 |

> 誠實結論：本功能可靠交付的是「A 級觀測層」——WebView 的 console / JS error / fetch/XHR，經注入 bridge 併入既有 timeline 並過 redaction。B 級除錯器能力（breakpoint / DOM / profiler）明確 Out-of-Scope，文檔指路平台原生工具。注入時機的完整覆蓋度取決於宿主選用的 webview 套件與接線方式，文檔誠實標註，不由套件假裝抹平。

---

## 6. 決策紀錄（已拍板）

1. **範圍**：Phase 1+2+3（完整 bridge + 雙套件接線文檔 + example 示範頁）；不含 Phase 0 Eruda 食譜。（使用者已確認）
2. **接入模式**：host-injection（套件零相依，宿主自備 webview 套件並接線），比照 `DiagnosticInfoSource` / `DatabaseBrowserSource`。
3. **不加第五 source enum、不開專屬 tab**：WebView 事件走既有 log / network 管線，來源標記用既有 `data` 欄位。
4. **redaction 採方案 B（display-time，與 native 一致）**：adapter 建原始 `NetworkEntry`，遮罩由既有顯示/匯出 formatter 自動繼承、尊重 `redactSensitiveData` opt-out；不新增 WebView 專屬 redaction、不繞過既有管線。（STAGE 0b 校正原「ingest 前遮罩」措辭，使用者已確認）
5. **截斷在 JS 端**：大 payload 上限在源頭，非 Dart 端事後處理。
6. **（2026-07-18 使用者修訂）network provenance 升級為第一級欄位**：`NetworkEntry` 新增 `origin`（`NetworkOrigin.dio | .webview`，預設 `dio`）與 `pageUrl`（WebView 請求的 `location.href`）。取代原「零 schema 變更、靠 `sourceDio == null` 推斷」的決策——`sourceDio` 是 `WeakReference`，Dio 實例被 GC 後 native 請求與 WebView 請求無法區分，顯式欄位修掉此歧義。預設 `dio` 使 Dio interceptor / Replay 零改動，向後相容不破壞。`NetworkDetailView` General 區顯示 Origin 與 Page URL。log 的標示維持既有 `LogEntry.data`（`origin`/`pageUrl`）不變。

---

## 7. 規格出口條件

- US-1 ～ US-7 的驗收條件經確認為可測試、可驗收。
- 範圍邊界（不加 source enum / 不開專屬 tab / 零新相依 / redaction 鐵律 / iframe 不支援 / 不做 B 級除錯器 / 不含 Phase 0）經確認。
- §5 技術限制與注入時機的誠實邊界經確認。

進入 STAGE 0b（實作計畫）將細化：JS bridge payload 的訊息協定與 hook 實作、adapter 的 Dart 資料表示與進入點 API、redaction 接線點、JS 端截斷上限、Phase 1/2 的任務拆分與逐檔異動、雙套件接線文檔與 example 示範頁，以及對應的 TDD 任務拆解。（2026-07-18 更新：實作與驗證已全數完成，見 PR #91）
