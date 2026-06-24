# 實作計畫：網路請求重放（Replay / Resend）

- **日期**：2026-06-25
- **狀態**：STAGE 0b — 實作計畫（v2，第一批已完成，部分回退中）
- **規格來源**：`docs/features/2026-06-25-network-request-replay.md`
- **已拍板決策（現行 v2）**：
  - **OQ-1（v2 修訂）**：**每筆 entry 記住它的來源 Dio，replay 用原 Dio。** interceptor 持有來源 Dio 並在記錄 entry 時帶進去；`NetworkEntry` 持有 transient `sourceDio`；`NetworkDetailView` 讀 `entry.sourceDio` 重送。`entry.sourceDio == null`（或 entry 未完成）→ Resend 灰掉。**不再使用** 單一 `FlutterInspector(dio:)`。**絕不改動** `FlutterInspectorDioInterceptor` 既有公開建構簽章——新增的 `sourceDio` 為**可選具名**參數。
  - **OQ-2**：MVP **只做原樣重送**，不做 header/body 編輯。

---

## 設計修訂紀錄

### v2（2026-06-25，第一批 review 後）— 單一 dio → per-dio sourceDio

**為何推翻 v1 的 `FlutterInspector(dio:)`**：

v1 假設「整個 app 一個 Dio」。真實情況是**多 Dio app**——不同 baseUrl / auth 的多個 `Dio` 實例（例如 `dioAuth` 走帶 token 的 API、`dioPublic` 走公開 CDN）。v1 用單一 `FlutterInspector(dio:)` 重送所有請求會**失真**：`dioPublic` 攔到的請求被 `dioAuth` 重送，baseUrl 與 auth header 都可能不對，重送結果不再等價於原請求——這直接戳破 Replay 的價值主張（「同一個請求現在還錯不錯」變成「另一個請求錯不錯」）。

**v2 的修正**：請求的「來源 Dio」是逐請求的事實，不是全 app 單例。所以把來源綁在**記錄這筆請求的那條路徑**上：

- interceptor 知道自己掛在哪個 Dio 上（建構時傳入 `sourceDio`）。
- 它記每筆 `NetworkEntry` 時，把這個 `sourceDio` 一起帶進去。
- replay 時就用 `entry.sourceDio` 重送——保證用**原本那個 Dio**，baseUrl / interceptors / auth 全對。

**v2 對 v1 已完成成果的影響**：

| v1 成果 | v2 處置 |
|---|---|
| T1 `NetworkEntry.isReplay`（bool，含 copyWith/==/hashCode）✅ | **保留**，另加 transient `sourceDio`（且 sourceDio **不進** ==/hashCode/序列化） |
| T2 `buildReplayRequest()` + `ReplayRequest` ✅ | **不受影響，保留** |
| T3 `FlutterInspector(dio:)` 單一 dio 欄位 ✅ | **回退**（移除欄位、建構參數、相關 import、相關測試），由 v2 的 interceptor sourceDio + entry sourceDio 取代 |
| T6 調查（呼叫端 `network_tab.dart:188` 已持有 inspector）✅ | 結論仍有效，且 v2 下呼叫端**更簡單**：entry 自帶 sourceDio，呼叫端連 dio 都不用傳 |

**v2 的關鍵不變量**：`sourceDio` 是 **runtime reference，不是資料**。它**不得**進入 `operator ==` / `hashCode` / 任何序列化（cURL / plain text / 診斷報告）。理由：兩筆內容相同但來自不同 Dio 的 entry，在「資料相等」的意義上仍應相等（`RingBuffer.replace` 的 pending→complete 比對、既有 equality 測試都依賴此語意）；且 Dio 實例無法序列化也不該出現在匯出文字裡。

---

## 1. 核心設計判斷（開工前先看懂這一段）

實作前必須先看懂兩個交織的判斷：**replay 結果怎麼帶標記**（v1 已定，沿用）與 **replay 用哪個 Dio**（v2 新定）。

### 1.1 用 `RequestOptions.extra` 旗標讓 interceptor 認得 replay（沿用 v1）

宿主 Dio 已接 `FlutterInspectorDioInterceptor`，所以重送時請求會**再次流經** interceptor 的 `onRequest`/`onResponse`/`onError`，自動記成一筆新 `NetworkEntry`。但 interceptor 是通用的，不知道「這次是重送」。

解法：Dio 的 `RequestOptions.extra`（`Map<String, dynamic>`）會原封從 `onRequest` 流到 `onResponse`/`onError`（既有 code 已用它存 `_inspector_start_time` / `_inspector_pending_entry`）。重送時在 `Options.extra` 放旗標 `_inspector_is_replay: true`，interceptor 建 entry 時讀它設 `isReplay`。replay 標記由**同一條記錄路徑**產生，不另手動記錄，不製造重複 entry。

### 1.2 replay 用 `entry.sourceDio`（v2 新定）

- interceptor 建構時可選傳入它所掛的 `sourceDio`。
- interceptor 記每筆 entry 時，把 `sourceDio` 帶進 `NetworkEntry.sourceDio`（transient）。
- `NetworkDetailView` 重送時用 `entry.sourceDio!.request(...)`（帶 1.1 的 replay `extra` 旗標）。
- `entry.sourceDio == null`（interceptor 沒給 sourceDio，例如舊接線只傳單參數）→ Resend 灰掉。

> 為何 transient 而非一般欄位：`sourceDio` 是 reference 不是值。它若進 `==`/`hashCode`，會讓「pending entry」與「complete entry」即使同一請求也因 Dio 比對而被視為不同，破壞 `RingBuffer.replace` 的就地替換語意，也破壞既有 equality 測試。所以它存在於物件上、但對相等性與序列化「隱形」。

> 重複記錄的反例（已否決，同 v1）：UI 層自己 catch Dio 結果再手動 `logNetwork` → 與 interceptor 自動記錄重複。故 UI 的 catch 只負責不讓例外逸出 + 給回饋，不另記。

---

## 2. 資料結構異動（v2）

### 2.1 `NetworkEntry` — 保留 `isReplay`，新增 transient `sourceDio`

`lib/src/models/network_entry.dart`

- **保留**（v1 已完成）：`final bool isReplay`（建構參數 `this.isReplay = false`），已同步進 `copyWith` / `==` / `hashCode`。
- **新增**：`final Dio? sourceDio`（建構參數 `this.sourceDio`，預設 `null`）。
  - import `package:dio/dio.dart`（本檔目前無 dio 依賴；新增此 import 把 `Dio` 型別引入 model 層——這是 v2 接受的耦合，model 因此會依賴 dio，但 pubspec 已有 dio，且 `sourceDio` 對相等性隱形，不污染既有語意）。
  - **`copyWith`**：加 `Dio? sourceDio` 參數，`sourceDio: sourceDio ?? this.sourceDio`。
  - **`operator ==`**：**不加** `sourceDio` 比對（transient，相等性隱形）。
  - **`hashCode`**：**不納入** `sourceDio`（與 `==` 一致）。
  - **序列化**：`buildCurl` / `buildPlainText` / 任何匯出**不碰** `sourceDio`（無須改動，因它們本就不讀此欄位）。
  - 文件註解明確標注：`sourceDio` 是 transient runtime reference，刻意排除於 equality / hashCode / serialization 之外。

> 註：model 層引入 dio 依賴是 v2 的取捨。替代方案（如把 sourceDio 存在 entry 之外的 side-map）會引入第二份真相與生命週期管理，複雜度更高。直接放 entry 上、對相等性隱形，是最樸素且符合「沿用既有記錄路徑」的做法。

### 2.2 `FlutterInspectorDioInterceptor` — 新增可選具名 `sourceDio`（向後相容）

`lib/src/interceptors/dio_interceptor.dart`

- 建構簽章：`FlutterInspectorDioInterceptor(this._inspector, {this.sourceDio})` —— **新增可選具名參數**，存 `final Dio? sourceDio;`。
- **向後相容鐵律**：既有 `FlutterInspectorDioInterceptor(inspector)`（單參數）必須照常編譯與運作（`sourceDio` 為 `null` → 該路徑記的 entry 不帶 sourceDio → 那些 entry 的 Resend 灰掉，但既有自動記錄行為完全不變）。
- `onRequest` / `onResponse` / `onError` 建 `NetworkEntry` 時：
  - 帶入 `sourceDio: sourceDio`（把自己持有的來源 Dio 寫進 entry）。
  - 讀 `options.extra['_inspector_is_replay']`（或對應 requestOptions）設 `isReplay`。

### 2.3 `FlutterInspector(dio:)` — 回退（v2 移除）

`lib/src/core/flutter_inspector.dart`

- **移除**建構參數 `this.dio,`（目前在第 36 行）與對應的 `final Dio? dio;` 欄位。
- 檢查 `import 'package:dio/dio.dart';`（目前第 1 行）：回退後若 inspector.dart 不再用到任何 dio 型別，**一併移除該 import**（`logNetwork` 用的是 `NetworkEntry`，不需 Dio 型別）。
- 移除 T3 對應的測試（`inspector.dio == null` / 傳入取回那兩個案例）。

---

## 3. 請求重組邏輯（沿用 v1，未變）

`buildReplayRequest(entry)`（`lib/src/utils/network_formatters.dart`）已抽出並回傳 `ReplayRequest`（method / url / headers / body），`buildCurl` 已改基於它。**v2 不動此部分。** 重送執行層拿這四要素組 Dio：

```
entry.sourceDio!.request<dynamic>(
  url,
  data: body,
  options: Options(method: method, headers: headers,
                   extra: {'_inspector_is_replay': true}),
)
```

`requestBody` 已是字串，原樣當 `data`（MVP 不重新解析/序列化）。

---

## 4. 重送執行流程（v2：改用 entry.sourceDio）

### 4.1 觸發與守衛

- `NetworkDetailView` 新增 Resend 動作。
- **守衛（v2）**：
  - `entry.sourceDio == null` → Resend disabled（灰掉）。涵蓋「interceptor 沒給 sourceDio」與「舊單參數接線」。
  - `entry.isComplete == false` → disabled（pending 重送無意義）。
- `NetworkDetailView` **不再收外部 `Dio? dio`**——重送依賴全來自 `entry.sourceDio`，呼叫端因此更簡單（連 dio 都不用傳）。
- 為承載「進行中」狀態，`NetworkDetailView` 轉 `StatefulWidget`（或抽一個只包 Resend 按鈕 + 狀態的子元件，最小化改動面）。

### 4.2 執行序（成功/失敗都記回 buffer）

1. 點 Resend → 進入進行中（按鈕 disabled + loading）。
2. `buildReplayRequest(entry)` 取四要素 → `entry.sourceDio!.request(...)`（帶 replay `extra` 旗標）。
3. **成功**：Dio 回 `Response` → interceptor `onResponse` 自動記成 `isReplay=true` 且帶該 sourceDio 的新 entry → UI 退出進行中 → SnackBar 成功。
4. **失敗**：Dio 拋 `DioException` → interceptor `onError` 自動記成 `isReplay=true` 的 error entry → UI `try/catch` 接住例外（不逸出）→ 退出進行中 → SnackBar 失敗。UI 的 catch **不另記**。
5. `finally` 確保退出進行中（按鈕不卡 disabled）。

### 4.3 UI 狀態回饋（US-3）

| 狀態 | 回饋 |
|---|---|
| 可重送（`sourceDio != null` 且 `isComplete`） | Resend enabled |
| `sourceDio == null` 或未完成 | Resend disabled（灰掉） |
| 進行中 | disabled + loading（防連點 → 多筆重送） |
| 成功 | 退出進行中；SnackBar 成功 |
| 失敗（含傳輸層） | 退出進行中；SnackBar 失敗；**app 不 crash** |

---

## 5. 逐檔異動清單（v2）

| # | 檔案 | 動作 | 職責 |
|---|---|---|---|
| F1 | `lib/src/models/network_entry.dart` | 修改 | 新增 transient `sourceDio`（+ import dio、copyWith 帶入；**不**進 ==/hashCode/序列化）。`isReplay` 已存在 |
| F2 | `lib/src/utils/network_formatters.dart` | — | v1 已完成 `buildReplayRequest`/`ReplayRequest`，**不動** |
| F3 | `lib/src/core/flutter_inspector.dart` | **回退** | 移除 `dio` 參數/欄位；視情況移除 dio import |
| F4 | `lib/src/interceptors/dio_interceptor.dart` | 修改 | 新增可選 `sourceDio` 參數；三 handler 記 entry 時帶 `sourceDio` + 讀 replay 旗標設 `isReplay` |
| F5 | `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | 修改 | 轉 Stateful；Resend 動作讀 `entry.sourceDio` 重送 + 守衛 + 狀態回饋 |
| F6 | `lib/src/ui/dashboard/tabs/network/network_tab.dart`（呼叫端，T6 已定位 ~line 188） | 修改（簡化或無改動） | 開啟 `NetworkDetailView` 之處：v2 不需傳 dio，僅確認傳 entry 即可。若 v1 曾為傳 dio 加參數，**回退該參數** |
| F7 | `example/lib/main.dart` | 修改 | 範例接線改示範 `FlutterInspectorDioInterceptor(inspector, sourceDio: _dio)`（讓 Resend 可用）；若 v1 曾示範 `FlutterInspector(dio: _dio)`，**回退** |

---

## 6. 任務拆分（v2）

> 複雜度等級：**機械性** / **整合** / **設計判斷**。每任務標 TDD 順序與寫入檔案 scope。
> 狀態標記：✅ 已完成（v1）｜ ♻️ 回退｜ 🔧 改動／擴大｜ ➕ 新增。

### 已完成且保留（無須再動）

- **T1 ✅ 保留** — `NetworkEntry.isReplay`（bool + copyWith/==/hashCode）。v2 的 sourceDio 由新任務 T9 處理，不回頭改 T1 既有部分。
- **T2 ✅ 保留** — `buildReplayRequest()` + `buildCurl` 基於它。v2 完全不動。

### 回退任務

- **T3 ♻️ 回退 — 移除 `FlutterInspector(dio:)`**
  - 複雜度：**機械性**
  - 寫入 scope：`lib/src/core/flutter_inspector.dart` + `test/core/flutter_inspector_test.dart`
  - 步驟：移除 `dio` 參數/欄位 → 移除對應兩個測試 → 確認並（若無其他用途）移除 dio import → `flutter analyze` 無未用 import 警告。
  - 依賴：無（可立即做）。

### 新增任務（v2 資料結構）

- **T9 ➕ `NetworkEntry` transient `sourceDio`**
  - 複雜度：**設計判斷**（決定 transient 語意：進 copyWith、**不**進 ==/hashCode/序列化）
  - 寫入 scope：`lib/src/models/network_entry.dart` + `test/models/network_entry_test.dart`
  - 步驟：先補測試（見 7.1：兩 entry 僅 sourceDio 不同仍 `==` 且 hashCode 相同；copyWith 帶入 sourceDio；buildCurl/plainText 不含 dio）→ 加欄位 + import + copyWith；**不**改 ==/hashCode。
  - 依賴：無（與 T3 並行，scope 不重疊）。

### 改動／擴大任務

- **T4 🔧 擴大 — interceptor 持有 sourceDio + 記進 entry + 讀 replay 旗標**
  - 複雜度：**整合**（理解 `extra` 流向 + sourceDio 透傳；守住向後相容）
  - 寫入 scope：`lib/src/interceptors/dio_interceptor.dart` + `test/interceptors/dio_interceptor_test.dart`
  - 步驟：先補測試（見 7.3：單參數呼叫照常編譯且 entry `sourceDio==null`；傳 `sourceDio` → 三 handler 產出的 entry 帶該 dio；replay 旗標 → `isReplay==true`）→ 加可選 `sourceDio` 參數 → 三 handler 帶 `sourceDio` + 讀旗標。
  - 依賴：T9（需 entry 有 `sourceDio` 欄位）、T1（`isReplay` 已存在）。

- **T5 🔧 改動 — `NetworkDetailView` 改讀 `entry.sourceDio`**
  - 複雜度：**設計判斷**（Stateful 改造、狀態機、守衛改用 sourceDio、SnackBar）
  - 寫入 scope：`lib/src/ui/dashboard/tabs/network/network_detail_view.dart` + `test/ui/tabs/network_detail_view_test.dart`
  - 步驟：先補 widget 測試（見 7.5）→ 轉 Stateful → 守衛 `entry.sourceDio == null || !entry.isComplete` → `entry.sourceDio!.request(...)` + try/catch/finally + 狀態回饋。**不收外部 dio 參數。**
  - 依賴：T2（重組）、T4（重送結果帶 sourceDio + 標記）、T9（entry.sourceDio 存在）。

- **T7 🔧 簡化 — 呼叫端**
  - 複雜度：**機械性**
  - 寫入 scope：`lib/src/ui/dashboard/tabs/network/network_tab.dart`（+ 對應 widget 測試若有）
  - 步驟：v2 下 `NetworkDetailView` 不需 dio，確認呼叫端僅傳 entry；若 v1 曾為傳 dio 改過此處，回退。
  - 依賴：T5（簽章定案後）。

- **T8 🔧 改動 — example 接線**
  - 複雜度：**機械性**
  - 寫入 scope：`example/lib/main.dart`
  - 步驟：改 `FlutterInspectorDioInterceptor(inspector, sourceDio: _dio)`；若 v1 曾示範 `FlutterInspector(dio: _dio)`，回退。
  - 依賴：T4（sourceDio 參數定案後）。

### 依賴順序圖（v2）

```
T3 (♻️回退, 獨立) ─────────────────────────────────┐
T9 (➕ entry.sourceDio) ─> T4 (🔧 interceptor) ─┬─> T5 (🔧 detail view) ─> T7 (簡化呼叫端)
                                                └─> T8 (example, 僅需 T4)
T2 (✅) ───────────────────────────────────────────> T5
```

- **可並行**：T3（回退）與 T9（新增）寫入 scope 不重疊，可同時做。
- **序列瓶頸**：T4 等 T9；T5 等 T4 + T9 + T2（已完成）。
- **T8** 只需 T4。

### 複雜度分布（v2 待辦，共 6 個任務）

- 機械性：T3、T7、T8（3 項）
- 整合：T4（1 項）
- 設計判斷：T9、T5（2 項）
- （T1、T2 已完成，不計入待辦。）

---

## 7. 測試計畫（v2）

依既有風格（`flutter_test`；interceptor 直接呼叫 handler；UI 用 `testWidgets`；model/util 用純 `test`）。

### 7.1 Model（`test/models/network_entry_test.dart`，對應 T9）

- **transient sourceDio 不影響 equality**：兩個 entry 內容相同、僅 `sourceDio` 不同（一個給 Dio、一個 null，或給不同 Dio 實例）→ 仍 `==` 且 `hashCode` 相同。
- `copyWith(sourceDio: dio)` 正確帶入，其餘欄位不變；`copyWith` 不傳 sourceDio 時保留原值。
- `buildCurl(entry)` / `buildPlainText(entry)` 的輸出**不含** Dio 任何痕跡（沿用既有 util 測試斷言即可，無 dio 字樣）。
- （既有 `isReplay` 測試保留全綠。）

### 7.2 Core（`test/core/flutter_inspector_test.dart`，對應 T3 回退）

- 移除 v1 的 `inspector.dio == null` / 傳入取回兩案例。
- 確認 `FlutterInspector()` 既有其他建構/行為測試仍全綠（回退不影響其餘 API）。

### 7.3 Interceptor（`test/interceptors/dio_interceptor_test.dart`，對應 T4）

- **向後相容**：`FlutterInspectorDioInterceptor(inspector)`（單參數）照常運作，產出的 entry `sourceDio == null`（既有四個測試不得破，沿用現有 setUp 風格）。
- **帶 sourceDio**：`FlutterInspectorDioInterceptor(inspector, sourceDio: dio)` → `onRequest` / `onResponse` / `onError` 產出的 entry `sourceDio` 為同一 Dio 實例。
- **replay 旗標**：`RequestOptions(extra: {'_inspector_is_replay': true})` → 三 handler 產出 entry `isReplay == true`；無旗標 → `isReplay == false`。
- `onError` 沿用既有對 handler future 的觀察寫法，避免例外逸出 test zone。

### 7.4 Util（`test/utils/network_formatters_test.dart`，對應 T2，已完成）

- v1 既有 `buildReplayRequest` / `buildCurl` 測試保留全綠，v2 不新增。

### 7.5 Widget（`test/ui/tabs/network_detail_view_test.dart`，對應 T5）

- **無 sourceDio → Resend 灰掉**：以 `sourceDio == null` 的 entry 建 detail view → Resend 動作存在但 disabled。
- **未完成 → Resend 灰掉**：`isComplete == false` 的 entry → disabled。
- **重送成功記回 buffer**：entry 帶一個假 Dio（接了 `FlutterInspectorDioInterceptor(inspector, sourceDio: thatDio)` + mock adapter 回 `Response`）→ 點 Resend → buffer 多一筆 `isReplay == true` 且 `sourceDio` 為該 Dio 的結果；UI 顯示成功。
- **重送失敗也記回 buffer**：假 Dio 拋 `DioException` → 點 Resend → buffer 多一筆 `isReplay == true` 的 error entry；UI 顯示失敗；**測試不因未捕捉例外失敗**（驗證 try/catch）。
- **進行中防連點**：點 Resend 後、future 未完成前，動作 disabled。
- **回歸保護**：既有兩個 detail view 測試（renders all sections / copy as cURL）全綠。

> 假 Dio 策略：優先用「真 interceptor（帶 sourceDio）+ mock adapter」，以同時涵蓋 1.1 的 `extra` 旗標串接與 1.2 的 sourceDio 透傳，而非繞過 interceptor 直接 stub。

---

## 8. 執行方式選擇（v2）

- **Subagent-driven（建議）**：T3（回退）與 T9（新增 entry.sourceDio）scope 不重疊可並行起跑；隨後 T4 → T5 → T7 序列收尾，T8 在 T4 後即可做。並行收益集中在起跑階段（T3 + T9）。
- **Parallel session**：(a) 回退 + 資料層 T3 + T9、(b) 記錄路徑 T4、(c) UI T5 + T7、(d) example T8，依 6 節依賴圖排程，T5 待 T4/T9 齊備再開工。

---

## 9. 風險點與開工前確認（v2）

| 風險 | 說明 | 緩解 |
|---|---|---|
| transient 滲入相等性 | 若不慎把 `sourceDio` 加進 `==`/`hashCode`，會破壞 `RingBuffer.replace` 的 pending→complete 就地替換與既有 equality 測試 | 7.1 有專測守住「僅 sourceDio 不同仍相等」；計畫 2.1 明令不進 ==/hashCode |
| 向後相容 | interceptor 新增參數若非可選具名，會破壞既有 `FlutterInspectorDioInterceptor(inspector)` | 強制可選具名 `{Dio? sourceDio}`；7.3 有單參數照常運作的回歸測試 |
| T3 回退殘留 | 移除 `dio` 後遺留未用 import 或測試 | T3 步驟含 `flutter analyze` 檢查未用 import；移除對應測試 |
| model 引入 dio 依賴 | `network_entry.dart` 新增 `import dio` 讓 model 耦合 dio | 已知取捨（2.1 註）；pubspec 已含 dio；sourceDio 對相等性/序列化隱形，不污染既有語意 |
| 重複記錄 | UI 在 interceptor 外另記 → 兩筆 | 同 v1：只走 interceptor 自動記錄，UI catch 不另記 |
| 重複 sourceDio | 一個 Dio 掛多個 interceptor（罕見）或多 interceptor 共用 → entry 帶哪個 dio | 每個 interceptor 各帶自己的 sourceDio；同一 Dio 上通常僅一個 inspector interceptor，非常見情境，非阻塞 |
| body 保真 / 截斷 | 字串化 body、截斷 body 重送（同 v1 已知邊界） | MVP 接受，與 cURL 匯出同限制，非阻塞 |

**結論**：v2 的核心可行性（per-dio 來源透過 interceptor → entry.sourceDio → replay）清晰，向後相容以可選具名參數守住，transient 語意以專測守住。回退（T3）為機械性。**無阻塞，可繼續實作。**
