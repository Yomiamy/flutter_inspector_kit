# 實作計畫：Dio 結構化錯誤捕捉（Structured Network Error）

- **日期**：2026-07-03
- **階段**：STAGE 0b — 實作計畫（只寫 How）
- **對應規格**：`docs/features/2026-07-03-structured-network-error.md`（source of truth）
- **性質**：純擴充式增補。在 `@immutable` 的 `NetworkEntry` 加兩個可選欄位、`onError` 停止丟棄 `err.type`/`err.stackTrace`、`NetworkDetailView` 補一個 Exception Details section。零新框架、零新相依、零破壞既有建構呼叫。

---

## 1. 拍板決策（規格 §3.1 §6 的兩個開放點）

### 決策 A：`errorStackTrace` 型別 → **`String?`**

**結論**：存字串化形式 `String?`，不存原生 `StackTrace?`。

**一行理由**：`LogEntry.stackTrace` 既有慣例就是 `String?`（`log_entry.dart:29`，UI 用 `SelectableText(entry.stackTrace!)` 直接展示、`buildLogPlainText` 直接寫入），`NetworkEntry` 是 `@immutable` 純資料模型、UI 只需展示與複製文字，保持與既有 stackTrace 慣例一致；`onError` 端以 `err.stackTrace?.toString()` 轉入。

**衍生規則**：`onError` 寫入時用 `err.stackTrace?.toString()`。`StackTrace.toString()` 對 `StackTrace.empty` 會回空字串，UI/formatter 沿用 `LogEntry` 慣例以 `?.isNotEmpty ?? false` 判空，空字串等同不顯示。

### 決策 B：`buildPlainText` 納入範圍 → **納入 `errorType`，納入 `errorStackTrace`**

**結論**：`buildPlainText` 的 Error section 補上 `Error Type:` 一行（`errorType != null` 時），並在其後新增 `=== Stack Trace ===` 區段（`errorStackTrace` 非空時），對齊 `buildLogPlainText` 已證明的結構。

**一行理由**：`errorType` 是純 enum 分類、無敏感風險，直接提升 QA 分享排查價值（規格 §6 「建議納入」）；`errorStackTrace` 已決定為字串、`buildLogPlainText` 早已把 stackTrace 納入分享文字且未遮蔽（stackTrace 是呼叫堆疊、非使用者輸入敏感資料），兩者一致納入不製造分歧。長度風險由既有 body 已可達 10KB 的現實吸收，不另設截斷（YAGNI，規格未要求）。

**遮蔽策略**：`errorType`/`errorStackTrace` 皆**不經 `redactHeaders`**——它們不是 header、不含使用者輸入敏感資料，與 `buildLogPlainText` 對 stackTrace 的處理一致。`redact` 參數對這兩個欄位無作用（不改變 redaction 既有約定）。

---

## 2. 資料結構變更：`NetworkEntry` 新增兩欄位

在 `lib/src/models/network_entry.dart` 加兩個可選欄位，全部具預設 `null`。

### 2.1 欄位定義

```dart
/// Machine-readable error classification from Dio, if the request failed.
final DioExceptionType? errorType;

/// Stringified stack trace captured at the point of failure, if any.
final String? errorStackTrace;
```

- `import 'package:dio/dio.dart';` — 檔案**已有此 import**（`network_entry.dart:3`，供 `sourceDio` 用），`DioExceptionType` 直接可用，零新相依。
- 建構子加兩個具預設值的具名參數：`this.errorType,` 與 `this.errorStackTrace,`，放在 `this.error` 之後、`this.isComplete` 之前，維持既有欄位排列直覺（錯誤相關欄位聚在一起）。

### 2.2 `copyWith`

在參數列加 `DioExceptionType? errorType,` 與 `String? errorStackTrace,`（`sourceDio` 之前，對齊欄位順序），body 加：

```dart
errorType: errorType ?? this.errorType,
errorStackTrace: errorStackTrace ?? this.errorStackTrace,
```

> **note**：沿用既有 `?? this.xxx` 慣例。這代表 `copyWith` 無法把已設值清回 `null`（既有所有欄位皆此語意，含 `error`），與現況一致、不引入新特殊情況。onError 是一次性建構完整 entry，不依賴 copyWith 清空。

### 2.3 `operator ==`

在既有比較鏈末端（`other.isReplay == isReplay` 之前或之後）加：

```dart
other.errorType == errorType &&
other.errorStackTrace == errorStackTrace &&
```

- `DioExceptionType` 是 enum，`==` 為 identity 比較，穩定可靠。
- `String?` 的 `==` 為值相等，穩定可靠。

### 2.4 `hashCode`

在 `Object.hash(...)` 參數列加 `errorType, errorStackTrace,`。

> **既有慣例確認**：現有 `hashCode` 刻意省略 `requestHeaders`/`responseHeaders`（map hash 不穩），但納入 `error`、`isReplay` 等穩定欄位。`errorType`（enum）與 `errorStackTrace`（String）皆為穩定 hash，納入符合既有慣例，且與 `==` 對齊（`==` 比的欄位 hashCode 應納入以維持契約）。

### 2.5 `toString`

`toString` 現況只印 `method/url/status/complete`（`network_entry.dart:213`）。**不改動**——它是除錯用簡短摘要，非驗收條件，加 errorType 會拉長且無明確需求（YAGNI）。

---

## 3. 任務拆分

每個任務標註：寫入檔案（scope）、複雜度（快/便宜｜標準｜最強）、驗收方式、依賴。

> **並行分組**：T1、T2 寫入路徑互不重疊（model vs interceptor），但 T2 建構 entry 時要帶新欄位、依賴 T1 的欄位存在 → T2 依賴 T1。T4（formatter）與 T5（UI）都依賴 T1，彼此寫入路徑不重疊可並行。整體關鍵路徑：T1 → {T2, T4, T5 並行} → T6（回歸驗證）。

---

### T1 — `NetworkEntry` 新增欄位 + copyWith/==/hashCode + 單元測試

- **scope**：
  - `lib/src/models/network_entry.dart`（改）
  - `test/models/network_entry_test.dart`（增測試 group）
- **複雜度**：**快/便宜**（機械性：照 §2 定義加欄位、比對鏈、hash 參數；測試照既有 group 模板複製）
- **內容**：實作 §2.1–§2.4。測試新增一個 `group('structured error fields')`，涵蓋：
  - 預設值：不帶新欄位建構 → `errorType == null && errorStackTrace == null`（驗收：規格 §4 「預設 null」）
  - 相容性：**沿用既有 fixture（如 `sample`/現有測試建構）不改動仍編譯通過並綠**（此為既有測試自然覆蓋，本任務不改任何既有測試）
  - `copyWith` 帶入：`base.copyWith(errorType: DioExceptionType.connectionError, errorStackTrace: 's')` → 兩欄位正確設入、其餘欄位不變
  - `copyWith` 保留：`base(帶 errorType).copyWith(isReplay: true)` → errorType 保留
  - `==`/`hashCode`：兩筆僅 `errorType` 不同 → `isNot(equals)` 且 hashCode 不同；兩筆 `errorType` 相同其餘相同 → 相等且 hashCode 相同
  - `==`：兩筆僅 `errorStackTrace` 不同 → 不相等
- **驗收**：`fvm flutter test test/models/network_entry_test.dart` 全綠（含既有所有 case 不改動仍通過）
- **依賴**：無（起點）

---

### T2 — `dio_interceptor.onError` 保留 `err.type` / `err.stackTrace` + 傳輸層/server 兩路徑測試

- **scope**：
  - `lib/src/interceptors/dio_interceptor.dart`（改：僅 `onError` 建構 entry 處）
  - `test/interceptors/dio_interceptor_test.dart`（增測試）
- **複雜度**：**標準**（整合：改建構、確認 `err.response == null` 分岔的 statusCode 與 errorType 對應正確；測試要用 `DioException` 帶不同 `type`/`response`）
- **內容**：
  - `onError` 建構 `NetworkEntry` 時，除既有欄位外加：
    ```dart
    errorType: err.type,
    errorStackTrace: err.stackTrace.toString(),
    ```
    > `err.stackTrace` 在 Dio 5.x 是 non-nullable `StackTrace`（`DioException.stackTrace`），`toString()` 直接可用。若為 `StackTrace.empty` 會得空字串，UI/formatter 以非空判斷自然略過（見決策 A 衍生規則）。
  - `error` 欄位**維持 `err.toString()`**（規格 §3.2「不強制改動 error 內容」，保留人類可讀摘要，避免動到既有 `entry.error != null` 判斷失敗的語意）。
  - `onResponse`/`onRequest` **不動**（成功路徑 errorType/errorStackTrace 自然為 null）。
- **新增測試**（沿用既有 `errorHandler.future.then((_){}, onError:(_){})` 觀察慣例，避免 unhandled）：
  - **傳輸層路徑**：`DioException(requestOptions, type: DioExceptionType.connectionError, error: 'x')`（`response == null`）→ entry `errorType == DioExceptionType.connectionError` 且 `statusCode == null`（驗收：規格 §4 擷取層第 1 條）
  - **server 路徑**：`DioException(requestOptions, type: DioExceptionType.badResponse, response: Response(statusCode: 500, requestOptions:...))` → entry `errorType == DioExceptionType.badResponse` 且 `statusCode == 500`（驗收：規格 §4 擷取層第 2 條）
  - **stackTrace 非 null**：帶 `stackTrace: StackTrace.current` 的 DioException → entry `errorStackTrace != null`（驗收：規格 §4 擷取層第 3 條）
  - **成功路徑**：`onResponse` 產生的 entry → `errorType == null && errorStackTrace == null`（驗收：規格 §4 擷取層第 4 條）
- **驗收**：`fvm flutter test test/interceptors/dio_interceptor_test.dart` 全綠（含既有 onError case，其斷言 `entry.error, isNotNull` 不受影響）
- **依賴**：**T1**（entry 需先有 errorType/errorStackTrace 欄位才能建構）

---

### T4 — `buildPlainText` 納入 errorType + stackTrace + formatter 測試

- **scope**：
  - `lib/src/utils/network_formatters.dart`（改：僅 `buildPlainText` 的 Error 尾段）
  - `test/utils/network_formatters_test.dart`（增測試）
- **複雜度**：**快/便宜**（機械性：照 `buildLogPlainText` 的 stackTrace 區段模板；純字串組裝）
- **內容**：改 `buildPlainText` 尾段（現 `if (entry.error != null)` 區塊，`network_formatters.dart:145-149`）：
  ```dart
  if (entry.error != null || entry.errorType != null) {
    b.writeln('\n=== Error ===');
    if (entry.errorType != null) {
      b.writeln('Error Type: ${entry.errorType!.name}');
    }
    if (entry.error != null) {
      b.writeln(entry.error);
    }
  }
  final st = entry.errorStackTrace;
  if (st != null && st.isNotEmpty) {
    b
      ..writeln('\n=== Stack Trace ===')
      ..writeln(st);
  }
  ```
  > `DioExceptionType.name`（enum `.name`）給可讀分類字串。stackTrace 區段沿用 `buildLogPlainText` 的 `!= null && isNotEmpty` 判空慣例。**不經 redact**（見決策 B 遮蔽策略）。
- **新增測試**：
  - Error section 含 `Error Type:` 行：entry 帶 `errorType: DioExceptionType.connectionError, error: 'x'` → text 含 `'Error Type: connectionError'` 且含 `'x'`
  - Stack Trace section：entry 帶 `errorStackTrace: '#0 foo'` → text 含 `'=== Stack Trace ==='` 且含 `'#0 foo'`
  - 成功 entry（無 error/errorType/stackTrace）→ text **不含** `'=== Error ==='` 也不含 `'=== Stack Trace ==='`（驗證既有「無 error 不輸出 Error section」不回歸）
  - redaction 無作用於這兩欄：帶 stackTrace 的 entry，`buildPlainText(entry)` 與 `buildPlainText(entry, redact:false)` 的 stackTrace 段內容一致（不被遮蔽）
- **驗收**：`fvm flutter test test/utils/network_formatters_test.dart` 全綠（含既有 `buildPlainText` 「includes ... error sections」case，其 `error: 'Server error'` 仍輸出）
- **依賴**：**T1**（讀取 entry.errorType/errorStackTrace）。與 T2、T5 可並行（寫入路徑不重疊）

---

### T5 — `NetworkDetailView` 新增 Exception Details section + widget 測試

- **scope**：
  - `lib/src/ui/dashboard/tabs/network/network_detail_view.dart`（改：`build` 的 section 列 + 替換/補強 `_errorSection`）
  - `test/ui/tabs/network_detail_view_test.dart`（增測試 group）
- **複雜度**：**最強**（設計判斷：傳輸層 vs server 標題文案、section 何時取代既有 `_errorSection`、失敗判準的一致落地、stackTrace 可複製區段沿用 LogDetailView 慣例；牽涉 UX 呈現決策）
- **內容**：
  - **失敗判準**（規格 §3.4，不新增布林旗標）：定義局部 `final bool hasStructuredError = entry.errorType != null;`。
  - **section 掛載**：`build` 的 `children` 尾段，把現有 `if (entry.error != null) _errorSection(context)` 改為條件掛 Exception Details——當 `entry.errorType != null || entry.error != null` 時顯示 `_exceptionDetailsSection(context)`。
    > **相容性 note**：舊資料（來自舊版、只有 `error` 無 `errorType` 的 entry）仍能顯示（走 `error != null` 分支，標題退化為中性 'Exception Details'，只印 error 文字）。這確保 ring buffer 內既存 entry 不因升級而丟失 error 呈現。
  - **`_exceptionDetailsSection`**（新私有方法，取代 `_errorSection`）：一個 `_section(context, 'Exception Details', Column(...))`，內含（沿用 `_kv`/`_kvWidget` 與 `_bodySection` 的 stackTrace 容器慣例）：
    1. **類別標題列**（`_kv`）：
       - `entry.errorType != null && entry.statusCode == null` → `_kv(context, 'Kind', '傳輸層失敗 (transport failure — request did not reach server)')`
       - `entry.errorType != null && entry.statusCode != null` → `_kv(context, 'Kind', 'Server 錯誤回應 (server responded with error)')`
       - `entry.errorType == null`（僅舊 error）→ 不顯示 Kind 列
    2. **Error Type 列**：`entry.errorType != null` → `_kv(context, 'Error Type', entry.errorType!.name)`；null 時不顯示（規格 §3.3）
    3. **錯誤訊息**：`entry.error != null` → 沿用既有 `_errorSection` 的紅色 `SelectableText(entry.error!)` 呈現，包成一個 `_kvWidget` 或直接一列
    4. **Stack Trace 區段**：`entry.errorStackTrace` 非空 → 沿用 `LogDetailView._stackTraceSection` 的 monospace + `surfaceContainerHighest` 容器 + `SelectableText`（可複製），標題可用內嵌 'Stack Trace' 子標；null/空時不顯示（規格 §3.3）
  - **`_errorSection` 移除或內聯**：原 `_errorSection` 只印 error 文字，其職責併入 `_exceptionDetailsSection` 的第 3 點。移除 `_errorSection` 方法。
  - **General section 不動**：`statusColorFor(entry.statusCode, entry.error != null)` 著色輸入不變（規格 §3.4 明言不改），Status 顯示 `'${entry.statusCode ?? '-'}'` 不動——傳輸層失敗自然顯示 `-`，不造假 status。
  - **pump surface**：沿用既有 `physicalSize = Size(1200, 4000)` 避免 overflow。
- **新增測試 group `Exception Details section`**：
  - **傳輸層失敗**：entry `errorType: DioExceptionType.connectionError, statusCode: null, error: 'x'` → `find.text('Exception Details')` 一個、含「傳輸層失敗」文案、含 `'connectionError'`（驗收：規格 §4 UI 層第 1、3 條）
  - **server 錯誤**：entry `errorType: DioExceptionType.badResponse, statusCode: 500, error: 'x', responseHeaders:{...}, responseBody:'oops'` → 含「Server 錯誤回應」文案、`find.text('Response Headers')` 與 `find.text('Response Body')` 仍在（並存，驗收：規格 §4 UI 層第 2 條）
  - **stackTrace 可複製**：entry 帶 `errorStackTrace: '#0 foo\n#1 bar'` → section 內含該文字的 `SelectableText`（沿用 LogDetailView 測試「`find.byType(SelectableText)`」慣例）（驗收：規格 §4 UI 層第 4 條）
  - **成功不顯示**：`sample()`（errorType null、error null）→ `find.text('Exception Details')` findsNothing（驗收：規格 §4 UI 層第 5 條）
  - **General 著色不回歸**：既有 `statusColorFor` test 已覆蓋，本 group 額外斷言傳輸層失敗 entry 的 Status 文字為 `'-'`（不造假）
- **驗收**：`fvm flutter test test/ui/tabs/network_detail_view_test.dart` 全綠（含既有 'renders all sections'、redaction、Resend 全部 case）
- **依賴**：**T1**（讀 entry.errorType/errorStackTrace）。與 T2、T4 可並行

---

### T6 — 全套回歸 + 分析器

- **scope**：無新寫入（純驗證任務）
- **複雜度**：**快/便宜**（跑既有指令）
- **內容**：跑分析器與相關測試套件，確認零回歸。
- **驗收**：
  - `fvm flutter analyze`（或專案慣用 lint 指令）零 error/warning
  - `fvm flutter test test/models/ test/interceptors/ test/utils/ test/ui/tabs/network_detail_view_test.dart` 全綠
  - **console 跳轉不回歸**：確認 `test/ui/tabs/console_tab_test.dart`（若涵蓋 Network 列點擊跳 NetworkDetailView）仍綠；若無此覆蓋則手動確認 console mergedTimeline 端無 import 改動（本計畫未動 console 檔）
- **依賴**：T2、T4、T5 全部完成

> **測試效能守則（依 MEMORY）**：STAGE 3 review 不重跑已在 T1/T2/T4/T5 驗過的測試；`magical_tap_test` 有既有 10 分鐘 timeout，跑全套前先排除或單獨處理。本計畫 T6 只跑受影響套件，不必全 repo 掃。

---

## 4. 測試計畫（新增案例彙總）

| 層 | 檔案 | 新增案例 | 對應規格驗收 |
|---|---|---|---|
| model | `network_entry_test.dart` | 預設 null｜copyWith 帶入/保留｜`==`/`hashCode` errorType 差異｜`==` errorStackTrace 差異 | §4 資料模型層 4 條 |
| interceptor | `dio_interceptor_test.dart` | 傳輸層路徑（connectionError, status null）｜server 路徑（badResponse, 500）｜stackTrace 非 null｜成功路徑雙 null | §4 擷取層 4 條 |
| formatter | `network_formatters_test.dart` | Error Type 行｜Stack Trace 段｜成功無 Error/Stack 段｜redact 不作用於這兩欄 | 決策 B（規格 §6 建議） |
| UI | `network_detail_view_test.dart` | 傳輸層失敗標題+Error Type｜server 錯誤標題+並存 Response 段｜stackTrace 可複製｜成功不顯示｜Status 顯示 `-` 不造假 | §4 UI 層 6 條 |

**兩路徑核心區分測試（interceptor）**是本功能的技術重心：`response == null` → `statusCode == null` + `errorType != null`（傳輸層）；`response != null` → `statusCode != null` + `errorType != null`（server）。這兩條測試鎖住規格 §3.4 的「一條核心判斷」。

---

## 5. 風險與回歸檢查點（不可破壞的既有行為）

| # | 不可破壞項 | 為何有風險 | 檢查點 |
|---|---|---|---|
| R1 | **`NetworkEntry` 建構相容性** | 新欄位若無預設值，既有數十處 `NetworkEntry(...)` 呼叫（含所有測試 fixture、example）全部編譯失敗 | 兩欄位皆 `this.errorType,`/`this.errorStackTrace,` 具名可選、預設 null。T1 明令「既有 fixture 不改動仍綠」。`fvm flutter analyze` 零 error 即證 |
| R2 | **`error != null` 代表失敗的既有語意** | `statusColorFor(statusCode, error != null)`、任何依 `entry.error != null` 判失敗的邏輯 | `error` 欄位保留、`onError` 仍填 `err.toString()`（T2）。`error` 與 `errorType` 並存不互斥。既有 statusColorFor test 不改仍綠 |
| R3 | **Resend（`_ResendAction`）** | 若誤把新欄位塞進 replay 請求或 disabled 判斷 | Resend 只依賴 `sourceDio`/`isComplete`/`isRequestTruncated`（規格 §6 表列「否」）。本計畫**不碰** `_ResendAction`、`buildReplayRequest`。既有 Resend 全 case（T5 檔內）不改仍綠 |
| R4 | **Redaction 約定** | 若 Exception Details 入口漏傳 `redactSensitiveData`，或 stackTrace 被誤當 header 遮蔽 | 新 section 在既有 `NetworkDetailView` 內，**沿用同一 widget 的 `redactSensitiveData`**，不新增跳轉入口（不改入口約定）。errorType/stackTrace 不經 `redactHeaders`（決策 B）。既有 redaction test（cURL/text 遮蔽 Authorization/Cookie）不改仍綠 |
| R5 | **console mergedTimeline 跳轉** | 若動到 NetworkEntry 排序相關或 console 端 import | `NetworkEntry` 實作 `TimestampedEntry`，新欄位不影響 `timestamp` 排序。本計畫**不動** console 任何檔，Network 列點擊仍跳 `NetworkDetailView`，自動獲得新 section（規格 §6「自動受益」）。T6 確認 console 測試綠 |
| R6 | **`buildCurl` 只描述請求** | 若誤把錯誤欄位混進 cURL | 本計畫**不碰** `buildCurl`（規格 §6「不涉及錯誤欄位」）。既有 buildCurl test 全綠 |
| R7 | **`hashCode`/`==` 契約一致** | `==` 比的欄位若未同步進 hashCode，違反 equals/hashCode 契約 | T1 §2.3/§2.4 明令 errorType/errorStackTrace 同步進 `==` 與 `hashCode`（皆穩定 hash 型別）。T1 測試斷言兩者一致 |

---

## 6. 範圍邊界（本計畫明確不做）

對齊規格 §5 Out-of-Scope：

- **#7 錯誤聚合**：本計畫只在單筆 entry 補 `errorType` 欄位（為 #7 提供地基），**不**做 `(statusCode, errorType)` 分組計數/Error Summary 卡。
- **HAR timing waterfall**：不做（anti-feature）。
- **API mocking**：不做（anti-feature）。
- **改 `NetworkEntry` 既有建構參數 / 公開 API 行為**：不做（新欄位純可選增補）。
- **改 `toString`**：不做（§2.5，YAGNI）。
- **改 `buildCurl` / Resend / console**：不做（R3/R5/R6）。

---

## 7. 執行方式建議（供 orchestrator 選擇）

本計畫關鍵路徑短、任務界線清楚，兩種執行方式皆可：

### 方式一：subagent-driven（單 session 序列委派，推薦）

- 適合本計畫規模（5 個實作任務 + 1 驗證）。
- 順序：**T1（起點，必先）** → 委派 T2、T4、T5 給獨立 implementer subagent（三者僅共同依賴 T1、寫入路徑互不重疊，可並行委派）→ **T6 匯總回歸**。
- 好處：T1 完成後三個 subagent 可同時展開；主 session 只需在 T6 收斂驗證，context 負擔低。

### 方式二：parallel session（多 terminal 並行）

- T1 完成並 commit 後，開三個 session 分別跑 T2 / T4 / T5，各自 branch 或同 branch 不同檔（寫入路徑不重疊，無衝突）。
- 適合有多人或想壓縮 wall-clock 時間時。收斂時合流跑 T6。

**model 選型提示**（依複雜度標註）：

- T1、T4、T6 → **快/便宜 model**（機械性、有明確模板）
- T2 → **標準 model**（整合，需正確處理 response==null 分岔與 Dio API）
- T5 → **最強 model**（UX 呈現設計判斷、section 取代邏輯、stackTrace 慣例移植）
