# 實作計畫：網路請求重放（Replay / Resend）

- **日期**：2026-06-25
- **狀態**：STAGE 0b — 實作計畫（待開工）
- **規格來源**：`docs/features/2026-06-25-network-request-replay.md`
- **已拍板決策**：
  - **OQ-1**：`FlutterInspector` 新增可選建構參數 `Dio? dio`（default `null`）。重送用此 Dio（含宿主 baseUrl / interceptors / auth）。**無 dio 時 Resend 按鈕灰掉/不可點**。**絕不改動** `FlutterInspectorDioInterceptor` 既有公開建構簽章。
  - **OQ-2**：MVP **只做原樣重送**，不做 header/body 編輯。

---

## 0. 核心設計判斷（開工前先看懂這一段）

實作前必須先釐清一個張力，它決定整個 replay 標記怎麼落地：

### 張力：interceptor 會「自動」記錄重送，但它不知道那是重送

宿主傳入的 Dio 已接 `FlutterInspectorDioInterceptor`（這正是我們選擇用宿主 Dio 的好處——重送走真實網路層）。所以當我們用這個 Dio 重送時，請求會**再次流經 interceptor 的 `onRequest`/`onResponse`/`onError`**，自動產生一筆新的 `NetworkEntry` 落回 buffer。

**問題**：interceptor 是通用的，它不知道「這一次的請求是使用者按 Resend 觸發的重送」。它記出來的 entry 不會帶 `isReplay = true`。

### 解法：用 `RequestOptions.extra` 旗標，讓 interceptor 在記錄時認得 replay

Dio 的 `RequestOptions.extra` 是一個 `Map<String, dynamic>`，會原封不動從 `onRequest` 流到 `onResponse`/`onError`（既有 code 已用它存 `_inspector_start_time` 與 `_inspector_pending_entry`，見 `dio_interceptor.dart`）。

- 重送時，在發出請求的 `Options.extra` 放一個旗標 `_inspector_is_replay: true`。
- interceptor 的 `onRequest`/`onResponse`/`onError` 在建 `NetworkEntry` 時，讀這個旗標，據以設 `isReplay`。

這樣 replay 標記由**同一條記錄路徑**產生，不需要在 UI 層另外手動 `logNetwork`，不製造第二份真相，也不破壞 concurrent request 的既有處理（旗標跟著各自的 `RequestOptions` 走）。

> 對比方案（已否決）：「UI 層自己 catch Dio 的 response/error，手動 new 一筆 `NetworkEntry(isReplay: true)` 記回 buffer」——這會**和 interceptor 的自動記錄重複**，產生兩筆 entry（一筆無標記、一筆有標記）。除非繞過 interceptor，但繞過就拿不到宿主 Dio 的真實行為。故採 `extra` 旗標方案。

---

## 1. 資料結構異動

### 1.1 `FlutterInspector` 新增 `dio` 欄位

`lib/src/core/flutter_inspector.dart`

- 建構子新增可選具名參數 `Dio? dio`，存成 `final Dio? dio;`（公開，供 UI 層讀取與重送）。
- import `package:dio/dio.dart`（pubspec 已依賴 `dio: ^5.2.0`）。
- 不改任何既有建構參數順序與預設值（向後相容：既有呼叫端不傳 `dio` 即 `null`）。

### 1.2 `NetworkEntry` 新增 `isReplay` 標記

`lib/src/models/network_entry.dart`

依規格 US-2「replay 可分辨」需求，新增一個布林欄位（保持 `@immutable`）：

- 新增 `final bool isReplay;`，建構子參數 `this.isReplay = false`（預設 false → 既有所有建立點行為不變，向後相容）。
- 同步更新三處（**這是機械性但不可漏的同步**，既有測試 `network_entry_test.dart` 有 equality/copyWith 案例會抓漏）：
  - `copyWith`：加 `bool? isReplay` 參數，`isReplay: isReplay ?? this.isReplay`。
  - `operator ==`：加 `other.isReplay == isReplay`。
  - `hashCode`：把 `isReplay` 納入 `Object.hash(...)`。

> 為何用 `bool isReplay` 而非更花俏的 `enum source`：YAGNI。規格只要求「分得出 replay vs 一般請求」，一個布林就夠。未來若要區分更多來源再擴。

---

## 2. 請求重組邏輯（避免第二份真相）

### 2.1 問題：`buildCurl()` 的重組邏輯內嵌、輸出是字串

`buildCurl(entry)`（`lib/src/utils/network_formatters.dart`）內部已做了「從 entry 取 `method` / `requestHeaders` / `requestBody` / `url`」的重組，但它把結果**直接拼成 cURL 字串**，無法給 Dio 用。若 replay 另寫一份「從 entry 取那四樣」的程式，就會有兩份「請求重組」真相，日後 entry 欄位變動兩邊要各改一次。

### 2.2 解法：抽出共用的「entry → 請求三要素」純函式

在 `lib/src/utils/network_formatters.dart` 新增一個純函式（無 Flutter / 無 Dio 依賴，維持本檔「pure formatting helpers」定位），把重組結果表達成一個簡單的不可變載體：

- 新增函式 `ReplayRequest buildReplayRequest(NetworkEntry entry)`（或等價的輕量 record / 小類別），回傳：
  - `method`（`entry.method`）
  - `url`（`entry.url`）
  - `headers`（`entry.requestHeaders`，可空）
  - `body`（`entry.requestBody`，可空）
- `buildCurl()` 改為**先呼叫** `buildReplayRequest(entry)` 取這四樣，再拼 cURL 字串——讓「請求重組」只有一份真相，cURL 與 replay 共用。
- `buildReplayRequest` 不碰 cURL 的跳脫邏輯（那是 cURL 字串專屬，留在 `buildCurl`）。

> 載體型別建議用最樸素的形式（Dart record 或一個 `@immutable` 小類別），不引入 Dio 型別——保持本檔可純單元測試、不染 Dio 依賴。把「三要素 → Dio `Options`/`fetch` 參數」的轉換放在重送執行層（第 3 節），那層才碰 Dio。

### 2.3 重組 → Dio 呼叫

重送執行層（第 3 節）拿 `buildReplayRequest` 的四要素，組 Dio 請求：

- 用 `dio.request<dynamic>(url, data: body, options: Options(method: method, headers: headers, extra: {'_inspector_is_replay': true}))`。
- 不自行解析 / 重新序列化 body（MVP 原樣重送）：`requestBody` 已是字串，直接當 `data` 送。
- `extra` 帶 replay 旗標（見第 0 節）。

---

## 3. 重送執行流程

### 3.1 觸發與前置守衛

- `NetworkDetailView` AppBar 新增 Resend 動作（icon button 或加入既有 `PopupMenuButton`——擇一，見 4.1 職責）。
- **守衛（US-1 / OQ-1）**：
  - `inspector.dio == null` → Resend 不可點（灰掉 / disabled）。
  - `entry.isComplete == false` → 不可點（pending 的請求還沒成形，重送無意義）。
- 因為 `NetworkDetailView` 目前是 `StatelessWidget` 且不持有 inspector，需要：
  - 把 `NetworkDetailView` 改為持有重送所需依賴（`Dio? dio`）或 inspector reference（見 4.1）。
  - 為承載「進行中」狀態，將 `NetworkDetailView` 轉為 `StatefulWidget`（或抽一個 `StatefulWidget` 子元件只包 Resend 按鈕 + 狀態，最小化改動面）。

### 3.2 執行序（成功 / 失敗都記回 buffer）

1. 使用者點 Resend → 進入「進行中」狀態（按鈕 disabled + loading 指示）。
2. 呼叫 `buildReplayRequest(entry)` 取四要素 → 組 Dio `request(...)`（帶 replay `extra` 旗標）。
3. **成功路徑**：Dio 回 `Response` → interceptor 的 `onResponse` 自動記成一筆 `isReplay = true` 的新 entry 落回 buffer。UI 收到 Dio 的 future 完成 → 退出進行中 → SnackBar 回饋成功（例如「Resent — see new entry」）。
4. **失敗路徑**：Dio 拋 `DioException` → interceptor 的 `onError` 自動記成一筆 `isReplay = true` 的 error entry 落回 buffer。UI 端 `try/catch` 接住例外（**避免未捕捉例外**）→ 退出進行中 → SnackBar 回饋失敗。
   - 注意：interceptor 已負責「失敗也記一筆」，UI 的 `catch` 只負責**不讓例外逸出**與給回饋，**不**自己再記一筆（否則重複）。
5. 無論成功失敗，`finally` 確保退出進行中狀態（避免按鈕卡在 disabled）。

### 3.3 UI 狀態回饋（US-3）

| 狀態 | 回饋 |
|---|---|
| 可重送 | Resend 動作 enabled |
| dio 為 null / entry 未完成 | Resend 動作 disabled（灰掉），不可點 |
| 進行中 | 動作 disabled + loading 指示（避免重複連點 → 多筆重送） |
| 成功 | 退出進行中；SnackBar 提示成功 |
| 失敗（含傳輸層） | 退出進行中；SnackBar 提示失敗；**app 不 crash** |

---

## 4. 逐檔異動清單

| # | 檔案 | 新增/修改 | 職責 |
|---|---|---|---|
| F1 | `lib/src/models/network_entry.dart` | 修改 | 新增 `isReplay` 欄位 + 同步 `copyWith`/`==`/`hashCode` |
| F2 | `lib/src/utils/network_formatters.dart` | 修改 | 抽出 `buildReplayRequest(entry)` 共用重組；`buildCurl` 改為基於它 |
| F3 | `lib/src/core/flutter_inspector.dart` | 修改 | 建構子新增 `Dio? dio` 可選參數 + `final Dio? dio` 欄位 + import dio |
| F4 | `lib/src/interceptors/dio_interceptor.dart` | 修改 | `onRequest`/`onResponse`/`onError` 讀 `extra['_inspector_is_replay']`，據以設 `isReplay` |
| F5 | `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | 修改 | 轉 Stateful（或抽 Resend 子元件）；新增 Resend 動作 + 守衛 + 執行 + 狀態回饋 |
| F6 | `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` 的呼叫端 | 修改 | 開啟 `NetworkDetailView` 之處需把 `inspector.dio`（或 inspector）傳進去——查並更新呼叫點 |
| F7 | `example/lib/main.dart` | 修改 | 範例接線示範把 `dio` 傳給 `FlutterInspector(dio: _dio)`，讓 Resend 可用（示範用途，非核心邏輯） |

> F6 備註：需先查 `NetworkDetailView` 在何處被 push（`Navigator.push` / 列表 onTap）。網路 tab 目前只有 `network_detail_view.dart` 一檔，呼叫端可能在 dashboard 的 network tab 渲染處——任務 T6 先定位。

---

## 5. 任務拆分

> 複雜度等級：**機械性**（照樣改，無判斷）｜ **整合**（串接既有元件，需理解流向）｜ **設計判斷**（需權衡取捨）。
> 每個任務標 TDD 順序（先測試後實作）與寫入檔案 scope（供並行判斷）。

### Phase A：資料層（可先行，彼此獨立）

- **T1 — `NetworkEntry.isReplay` 欄位**
  - 複雜度：**機械性**
  - 寫入 scope：`lib/src/models/network_entry.dart` + `test/models/network_entry_test.dart`
  - 步驟：先補測試（預設 false、copyWith 帶入 true、equality 區分 isReplay 不同）→ 加欄位 + 同步 copyWith/==/hashCode。
  - 依賴：無。

- **T2 — `buildReplayRequest()` 抽出 + `buildCurl` 改基於它**
  - 複雜度：**設計判斷**（決定載體型別；確保 `buildCurl` 行為零變更）
  - 寫入 scope：`lib/src/utils/network_formatters.dart` + `test/utils/network_formatters_test.dart`
  - 步驟：先補 `buildReplayRequest` 測試（四要素正確、headers/body 可空）→ 抽函式 → 把 `buildCurl` 改為呼叫它；**既有 `buildCurl` 測試必須全綠（不得改既有 cURL 斷言）**。
  - 依賴：無。

- **T3 — `FlutterInspector(dio:)` 參數與欄位**
  - 複雜度：**機械性**
  - 寫入 scope：`lib/src/core/flutter_inspector.dart` + `test/core/flutter_inspector_test.dart`
  - 步驟：先補測試（不傳 dio → `inspector.dio == null`；傳入 → 取得同一實例）→ 加參數 + 欄位 + import。
  - 依賴：無。

### Phase B：記錄路徑（依賴 T1）

- **T4 — interceptor 讀 replay 旗標設 `isReplay`**
  - 複雜度：**整合**（理解 `extra` 從 onRequest 流到 onResponse/onError）
  - 寫入 scope：`lib/src/interceptors/dio_interceptor.dart` + `test/interceptors/dio_interceptor_test.dart`
  - 步驟：先補測試（`RequestOptions.extra['_inspector_is_replay']=true` → onRequest/onResponse/onError 產出的 entry `isReplay==true`；無旗標 → `isReplay==false`，沿用既有測試風格直接呼叫 handler）→ 三個 handler 讀旗標設 `isReplay`。
  - 依賴：T1（需 `isReplay` 欄位存在）。

### Phase C：UI 與接線（依賴 T2/T3/T4）

- **T6 — 定位 `NetworkDetailView` 呼叫端並決定依賴傳遞方式**
  - 複雜度：**設計判斷**（決定傳 `inspector.dio` 還是傳 inspector；決定 Stateful 改造範圍）
  - 寫入 scope：唯讀調查（grep 呼叫端）→ 產出微決策，無檔案寫入（或僅記在本計畫）
  - 依賴：無（可與 Phase A 並行調查），但其結論 gating T5。

- **T5 — `NetworkDetailView` Resend 動作 + 狀態 + 守衛**
  - 複雜度：**設計判斷**（Stateful 改造、loading/disabled 狀態機、SnackBar 回饋、守衛邏輯）
  - 寫入 scope：`lib/src/ui/dashboard/tabs/network/network_detail_view.dart` + `test/ui/tabs/network_detail_view_test.dart`
  - 步驟：先補 widget 測試（見第 6 節）→ 轉 Stateful / 抽子元件 → 接 `buildReplayRequest` + Dio `request` + `try/catch/finally` + 狀態回饋。
  - 依賴：T2（重組）、T3（拿 dio）、T4（重送結果帶標記）、T6（依賴傳遞方式）。

- **T7 — 呼叫端把 dio/inspector 傳入 `NetworkDetailView`**
  - 複雜度：**機械性**
  - 寫入 scope：T6 定位出的呼叫端檔案（+ 對應既有 widget 測試若有）
  - 依賴：T5（簽章定案後才改呼叫端）、T6（定位）。

- **T8 — `example/lib/main.dart` 示範 `FlutterInspector(dio: _dio)`**
  - 複雜度：**機械性**
  - 寫入 scope：`example/lib/main.dart`
  - 依賴：T3。

### 依賴順序圖

```
T1 ─┬─> T4 ─┐
T2 ─┼───────┼─> T5 ──> T7
T3 ─┴───────┘         └─> T8 (僅依賴 T3，可早做)
T6 (調查) ───────────> T5
```

- **可並行**：T1 / T2 / T3 / T6 四者寫入 scope 互不重疊，可同時進行。
- **序列瓶頸**：T5 是匯流點，等 T2/T3/T4/T6 齊備。
- **T8** 只依賴 T3，可在 Phase A 後立即做，不必等 UI。

### 複雜度分布

- 機械性：T1、T3、T7、T8（4 項）
- 整合：T4（1 項）
- 設計判斷：T2、T5、T6（3 項）
- 合計 **8 個任務**。

---

## 6. 測試計畫

依既有測試風格（`flutter_test`，interceptor 直接呼叫 handler，UI 用 `testWidgets` + mock channel，model/util 用純 `test`）：

### 6.1 Model（`test/models/network_entry_test.dart`，對應 T1）

- `isReplay` 預設為 `false`。
- `copyWith(isReplay: true)` 正確帶入，其餘欄位不變。
- 兩個 entry 僅 `isReplay` 不同 → `!=` 且 hashCode 可不同（沿用既有 equality 測試模式）。

### 6.2 Util（`test/utils/network_formatters_test.dart`，對應 T2）

- `buildReplayRequest` 從 entry 取出正確的 method / url / headers / body。
- headers 為 null、body 為 null 時不崩，四要素對應為空。
- **回歸保護**：既有 `buildCurl` 三個測試（GET 無 body / POST 有 body / 跳脫單引號）必須全綠，證明抽函式後 cURL 行為零變更。

### 6.3 Interceptor（`test/interceptors/dio_interceptor_test.dart`，對應 T4）

- `RequestOptions(extra: {'_inspector_is_replay': true})` → `onRequest` 產出 entry `isReplay == true`。
- 同旗標下 `onResponse` 完成的 entry `isReplay == true`。
- 同旗標下 `onError` 完成的 entry `isReplay == true`（沿用既有 `onError` 測試對 handler future 的觀察寫法，避免例外逸出 test zone）。
- **無旗標**（既有測試情境）→ entry `isReplay == false`（保護向後相容）。

### 6.4 Core（`test/core/flutter_inspector_test.dart`，對應 T3）

- `FlutterInspector()`（不傳 dio）→ `inspector.dio == null`。
- `FlutterInspector(dio: someDio)` → `inspector.dio` 為同一實例。

### 6.5 Widget（`test/ui/tabs/network_detail_view_test.dart`，對應 T5）

- **無 dio**：以「dio 為 null」建構 detail view → Resend 動作存在但 **disabled / 不可點**（規格 US-1 / OQ-1）。
- **重送成功記回 buffer**：注入一個假 Dio（攔截 `request` 回 `Response`，或用接了 interceptor 的 Dio 搭配 mock adapter）→ 點 Resend → 驗證 buffer 多一筆 `isReplay == true` 且來自重送結果；UI 顯示成功回饋。
- **重送失敗也記回 buffer**：假 Dio `request` 拋 `DioException` → 點 Resend → 驗證 buffer 多一筆 `isReplay == true` 的 error entry；UI 顯示失敗回饋；**測試不因未捕捉例外失敗**（驗證 `try/catch` 生效）。
- **進行中防連點**：點 Resend 後、future 未完成前，動作為 disabled（避免多筆重送）。
- **回歸保護**：既有兩個 detail view 測試（renders all sections / copy as cURL）必須全綠。

> 假 Dio 策略細節（用 `dio` 的 `HttpClientAdapter` mock，或包一層接了 `FlutterInspectorDioInterceptor` 的真實 Dio + mock adapter）於 T5 開工時定，以「能驗證 entry 確實經 interceptor 路徑帶上 `isReplay`」為準——優先用「真 interceptor + mock adapter」以涵蓋第 0 節的 `extra` 旗標串接，而非繞過 interceptor 直接 stub。

---

## 7. 執行方式選擇

- **Subagent-driven（建議）**：Phase A 的 T1 / T2 / T3 寫入 scope 完全不重疊，適合並行交給三個 subagent 各自 TDD 完成；T6 調查可並行。匯流到 T4 → T5 → T7 後序列收尾。預期並行收益集中在 Phase A（4 任務同時起跑）。
- **Parallel session**：若以人工多 session 推進，建議 session 切分為 (a) 資料層 T1+T2+T3、(b) 記錄路徑 T4、(c) UI T5+T6+T7、(d) example T8，依第 5 節依賴圖排程，避免 T5 在依賴未齊時開工。

---

## 8. 風險點與開工前確認

| 風險 | 說明 | 緩解 |
|---|---|---|
| 重複記錄 | 若 UI 層在 interceptor 之外又手動 `logNetwork`，會產生兩筆 | 第 0 節已定：**只走 interceptor 自動記錄**，UI 的 catch 不另記 |
| body 重送保真度 | `requestBody` 是 interceptor 用 `options.data?.toString()` 存的字串，重送時當 `data` 原樣送，對非字串原始 body（如 FormData / bytes）可能與原請求不完全等價 | MVP 接受此限制（原樣重送字串化 body）；屬已知邊界，非阻塞，可於 detail view 或文件註明 |
| `NetworkDetailView` 呼叫端 | 需把 dio/inspector 傳入，呼叫點位置待 T6 定位 | T6 先調查，gating T5 簽章 |
| 截斷 body 重送 | 若原 `requestBody` 曾被 `truncateBody` 截斷，重送的是截斷版 | MVP 已知限制（與 cURL 匯出同一限制，cURL 也是用截斷後 body），不阻塞 |

**結論**：核心可行性已由第 0 節的 `extra` 旗標方案解決，無阻塞性未知。唯一需在實作中即時定案的是 T6（呼叫端依賴傳遞）與 T5 的假 Dio 測試策略，兩者皆為實作層微決策、非規格層阻塞。**可進實作。**
