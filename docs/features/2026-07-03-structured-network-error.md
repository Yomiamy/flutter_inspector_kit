# 功能規格：Dio 結構化錯誤捕捉（Structured Network Error）

> **建立日期**：2026-07-03
> **狀態**：規格草案（待確認）
> **對應 brainstorm**：`docs/brainstorm/2026-07-12-features-brainstorm.md` #4（✅ 已完成，v1.3.0）
> **Effort 評級**：low–medium ｜ **排查價值**：⭐⭐⭐⭐

> 本文件只描述 **What & Why**（要什麼、為什麼要），不含實作步驟與程式碼。實作計畫另立於 `docs/plans/`。

---

## 1. 背景與問題

`FlutterInspectorDioInterceptor` 目前在 `onError` 中已擷取相當多結構化資訊：`statusCode`、`requestHeaders`、`requestBody`、`responseHeaders`、`responseBody`、`isReplay`。但錯誤的**根因分類**卻被丟棄——第 99 行仍是 `error: err.toString()`，這行把 `DioException` 壓縮成一坨純文字，同時丟掉了兩個關鍵欄位：

- `err.type`（`DioExceptionType`）——錯誤的**機器可讀分類**（connectionTimeout / sendTimeout / receiveTimeout / badCertificate / connectionError / cancel / badResponse / unknown）。
- `err.stackTrace`——錯誤發生點的呼叫堆疊，排查非 HTTP 語意失敗時的唯一線索。

### 核心痛點

對於 **4xx / 5xx 錯誤**，`statusCode` 已顯示在 `NetworkDetailView` 的 General section，開發者可以辨識（是 server 回了錯誤碼）。**真正的盲區是 `statusCode == null` 的傳輸層失敗**：斷網、DNS 解析失敗、SSL 握手錯誤、connection timeout、request cancel。這些情況下：

- General section 的 Status 只顯示 `-`（因 `statusCode == null`）。
- Error section 只有一坨 `err.toString()` 字串。

開發者無法從 UI 分辨「這筆 Failed 到底是**斷網（傳輸層沒到 server）**，還是**後端回了錯誤（server 有回應）**」。這是排查網路問題時最基本、也最常需要的一刀切分，目前卻要靠肉眼從 toString() 字串裡猜。

### 為什麼值得做

- **消滅猜謎**：一條清楚的判斷——`response == null` → 傳輸層失敗；`response != null` → server 回了錯誤碼——就能把「Failed 是斷網還是後端壞了」這個高頻疑問變成 UI 上一眼可辨的事實。
- **零新框架**：核心抽象都已存在（`@immutable` 的 `NetworkEntry`、`DioExceptionType` enum、`NetworkDetailView` 的 card 分層 section、`LogDetailView` 已證明的可複製 stackTrace 區段）。這是**組合既有零件**，不是造新輪子。
- **擴充式、零破壞**：只新增可選欄位與新的 UI section，不改動任何既有公開 API 行為。

---

## 2. 使用者故事

1. **作為開發者**，當我的請求因斷網 / DNS 失敗而失敗時，我想在 `NetworkDetailView` 一眼看出「這是傳輸層失敗，根本沒到 server」，而不是對著一坨 toString() 字串猜是網路問題還是後端問題。

2. **作為 QA**，當我回報一筆網路錯誤時，我想知道錯誤的**分類名稱**（例如 connectionTimeout、badCertificate），這樣我在 bug ticket 上能寫出精確的根因描述，而不是貼一段看不懂的例外文字。

3. **作為開發者**，當請求因非 HTTP 語意的例外（例如 response 解析失敗、SSL 錯誤）而失敗時，我想展開並**複製 stackTrace**，定位到程式碼中真正出錯的位置——就像我在 `LogDetailView` 對 error log 做的一樣。

4. **作為開發者**，當 server 回了 4xx/5xx 時，我想在同一個 section 同時看到「錯誤分類」「status code」「server 回傳的錯誤說明（response body）」，把「傳輸成功但語意失敗」的完整脈絡收在一處。

---

## 3. 功能需求

### 3.1 資料模型：`NetworkEntry` 新增結構化錯誤欄位

在 `NetworkEntry`（`@immutable`）新增兩個**可選**欄位，用來承載被丟棄的結構化資訊：

- **`errorType`**：錯誤的機器可讀分類，型別為 `DioExceptionType?`（`package:dio` 已導出的 enum）。傳輸層失敗與 server 錯誤都會帶此欄位；成功請求為 `null`。
- **`errorStackTrace`**：錯誤發生點的呼叫堆疊，型別為 `StackTrace?`（或其字串化形式，實作時決定；規格層面只要求「可展示、可複製的堆疊文字」）。成功請求為 `null`。

**相容性硬性要求**：兩個新欄位必須是**可選且具預設值 `null`**，使既有所有 `NetworkEntry(...)` 建構呼叫（含測試、含 example）無需修改即可編譯通過。`copyWith`、`operator ==`、`hashCode`、`toString` 需一併把新欄位納入，維持 value-equality 語意的一致性。

> **註**：`error`（`String?`）欄位**保留**。它承載人類可讀的錯誤摘要文字，與 `errorType`（機器分類）並存、不互斥。既有依賴 `entry.error != null` 判斷「是否失敗」的邏輯（例如 `statusColorFor`）不受影響。

### 3.2 擷取：`dio_interceptor.onError` 保留結構化欄位

`onError` 建立失敗的 `NetworkEntry` 時，除既有欄位外，額外帶入：

- `errorType: err.type`
- `errorStackTrace: err.stackTrace`

`error` 欄位的填法可維持人類可讀摘要（實作決定是否仍用 `err.toString()` 或改用更精簡的 `err.message`）——規格層面**不強制**改動 `error` 的內容，只要求**不再丟棄** `err.type` 與 `err.stackTrace`。

`onResponse`（成功路徑）不受影響，`errorType` / `errorStackTrace` 保持 `null`。

### 3.3 UI：`NetworkDetailView` 新增「Exception Details」section

當 entry 代表一筆失敗（判準見下）時，`NetworkDetailView` 新增一個 **Exception Details** card section，取代或補強現有的單一 `Error` section，分層展示：

- **錯誤類別標題**：明確標示這是**傳輸層失敗**還是 **server 錯誤回應**（見 3.4 的判斷規則）。
- **Error Type**：`errorType` 的可讀名稱（例如 `connectionTimeout`、`badCertificate`、`badResponse`）。`null` 時不顯示該列。
- **錯誤訊息**：既有 `error` 文字（沿用目前 `_errorSection` 的呈現）。
- **Stack Trace**：`errorStackTrace` 的**可複製**區段，沿用 `LogDetailView` 已有的可複製 stackTrace 呈現慣例。`null` 時不顯示該區段。

呈現須沿用既有的 `_section` card 分層與 `_kv` / `KeyValueTable` 排版慣例，維持 detail view 的視覺一致性。

### 3.4 傳輸層失敗 vs server 錯誤：呈現上的區分

核心判斷一條，貫穿 General section 與 Exception Details section：

- **`response == null`（即 `statusCode == null` 且 `errorType != null`）→ 傳輸層失敗**：請求根本沒到 server（斷網、DNS、SSL、timeout、cancel）。Exception Details 標題明確標為「傳輸層失敗」語意；此時**不應**顯示或誤導性呈現一個假的 status。
- **`response != null`（即 `statusCode != null`）→ server 回了錯誤碼**：傳輸成功，是應用層/語意失敗。Exception Details 與既有的 Response Headers / Response Body section 並存，讓「server 回傳的錯誤說明」可被看見。

此區分只需依現有欄位（`statusCode` 是否為 `null`）加上新的 `errorType` 即可判定，**不需要**新增額外的布林旗標。既有的 `statusColorFor(statusCode, error != null)` 已能正確著色（`statusCode == null && hasError` → 紅色），不需改動。

---

## 4. 驗收條件

以下為可測試的具體條件：

### 資料模型層

- [ ] `NetworkEntry` 具備 `errorType`（`DioExceptionType?`）與 `errorStackTrace`（`StackTrace?` 或等效可展示形式）兩個可選欄位，預設值均為 `null`。
- [ ] 既有不帶新欄位的 `NetworkEntry(...)` 建構呼叫**無需修改**即可編譯（相容性測試：任一既有測試 fixture 不改動仍通過）。
- [ ] `copyWith` 能正確帶入/保留 `errorType` 與 `errorStackTrace`。
- [ ] `operator ==` 與 `hashCode` 已將新欄位納入：兩筆 `errorType` 不同的 entry 不相等；`errorType` 相同的其餘欄位相同時相等。

### 擷取層

- [ ] 給定一個 `err.response == null` 的 `DioException`（例如 `DioExceptionType.connectionError`），`onError` 產生的 `NetworkEntry` 之 `errorType == DioExceptionType.connectionError` 且 `statusCode == null`。
- [ ] 給定一個 `err.response != null`（例如 500）的 `DioException`（`DioExceptionType.badResponse`），`onError` 產生的 `NetworkEntry` 之 `errorType == DioExceptionType.badResponse` 且 `statusCode == 500`。
- [ ] `onError` 產生的 `NetworkEntry` 之 `errorStackTrace` 非 `null`（當 `err.stackTrace` 存在時）。
- [ ] 成功請求（`onResponse` 路徑）產生的 `NetworkEntry` 之 `errorType == null` 且 `errorStackTrace == null`。

### UI 層

- [ ] 當 `errorType != null` 且 `statusCode == null` 時，`NetworkDetailView` 顯示標示為「傳輸層失敗」語意的 Exception Details section。
- [ ] 當 `errorType != null` 且 `statusCode != null` 時，`NetworkDetailView` 顯示標示為「server 錯誤回應」語意的 Exception Details section，且與 Response Headers / Response Body section 並存。
- [ ] Exception Details section 顯示 `errorType` 的可讀名稱。
- [ ] `errorStackTrace != null` 時，Exception Details section 提供**可複製**的 stackTrace 區段。
- [ ] `errorType == null`（成功請求）時，**不**顯示 Exception Details section。
- [ ] 既有的 General section Status 著色行為不變（`statusCode == null && error != null` 仍為紅色）。

---

## 5. 範圍邊界（Out of Scope）

以下**明確排除**，避免範圍蔓延：

1. **#7 錯誤聚合摘要（Error Aggregation）**：本規格只負責在**單筆** entry 上補齊 `errorType` 這個分組所需的欄位；「按 `(statusCode, errorType)` 分組計數 + 首末時間 + Error Summary 卡」屬 #7，不在本規格範圍。本規格為 #7 提供地基，但不實作 #7 本身。
2. **HAR timing waterfall（DNS/TLS/TTFB 分段）**：明確為 anti-feature。Dio 多版本拿不到可靠分段 timing，硬湊是假精度。保留既有 total duration + timeout 分類已足夠，不追 timing 瀑布。
3. **API mocking / 動態回應改寫**：明確為 anti-feature，違反 Never break userspace，交給外部 proxy。
4. **不破壞既有 `NetworkEntry` 建構參數相容性**：新欄位必為可選具預設值。任何要求既有呼叫端修改建構參數的方案都不接受。
5. **不改動既有公開 API 行為**：`FlutterInspector` 對外行為、`error` 欄位既有語意（`error != null` 代表失敗）皆不變。
6. **不新增額外相依**：`DioExceptionType` 來自既有的 `package:dio`，無需引入新 package。

---

## 6. 對既有功能的影響評估

| 既有功能 | 是否受影響 | 說明 / 需跟進項 |
|---|:---:|---|
| **Resend（`_ResendAction`）** | 否 | Resend 邏輯只依賴 `sourceDio`、`isComplete`、`isRequestTruncated`，不觸及新欄位。新欄位純為記錄用，重送不需帶入。重送結果作為新 `NetworkEntry` 記回，其 `errorType` / `errorStackTrace` 由 `onError` 自然填入。**無需修改**。 |
| **Redaction（`redactSensitiveData`）** | 需評估 | `redactSensitiveData` 目前只作用於**分享/匯出路徑**（`buildCurl` / `buildPlainText`），不影響畫面顯示。`errorType` 是 enum、`errorStackTrace` 是呼叫堆疊，**通常不含使用者輸入的敏感資料**，預設不需遮蔽。**但**：任何跳轉 `NetworkDetailView` 的入口都必須沿用既有慣例傳入 `redactSensitiveData`（否則 opt-out 行為分歧）——新增 Exception Details section **不改變**此入口約定。若日後 stackTrace 被納入分享文字，需一併評估遮蔽策略（見下）。 |
| **Console mergedTimeline** | 否（自動受益） | `NetworkEntry` 實作 `TimestampedEntry`，console 混合時間軸依 `timestamp` 排序，新增欄位不影響排序。console Network 列點擊仍跳 `NetworkDetailView`，自動獲得 Exception Details 呈現，無需改動 console 端程式碼。 |
| **序列化 / 分享文字（`buildPlainText` / `buildCurl`）** | 需決策 | 目前 `buildPlainText` 是否納入 `errorType` / `errorStackTrace` 需一項決策：**建議**在 `buildPlainText` 加入 `errorType`（純分類、無敏感風險），提升 QA 分享的排查價值；`errorStackTrace` 是否納入分享文字則需權衡（可能很長、且需確認遮蔽策略）。`buildCurl` 只描述請求，**不涉及**錯誤欄位，無需改動。此項為**建議的跟進**，非本規格核心驗收條件——可在計畫階段決定是否納入首版。 |
| **`statusColorFor` 著色** | 否 | 既有簽章 `statusColorFor(statusCode, error != null)` 已能正確處理 `statusCode == null && hasError` → 紅色。新增 `errorType` 不改變著色輸入。**無需修改**。 |

---

## 附錄：關鍵設計判準摘要

- **一條核心判斷**：`response == null` → 傳輸層失敗；`response != null` → server 回錯。此判斷用既有 `statusCode == null` + 新 `errorType != null` 即可推導，**不新增布林旗標**（消滅特殊情況）。
- **`error` 與 `errorType` 並存**：`error` 是人類可讀摘要，`errorType` 是機器分類，兩者不互斥、不取代。既有 `error != null` 判斷失敗的語意完全保留。
- **新欄位可選具預設值**：這是相容性的地基，也是「Never break userspace」在本功能上的具體落實。
