# 功能規格：Dio `ResponseBody` 與原始 `Stream` 安全友善佔位（§P34）

- **日期**：2026-11-07
- **來源**：`docs/brainstorm/2026-11-04-features-brainstorm.md` §P34（源自 §Z1-8）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在 App 中用 `ResponseType.stream` 下載大檔或接 SSE、或是用 `Stream<List<int>>` 直接上傳的開發者／QA，打開 Network 詳情查看該筆請求時，
> 我希望 **Body 欄位直接告訴我「這是串流」**，而不是一串看不懂的 `Instance of 'ResponseBody'`，
> 而且 Inspector 絕不能碰到這條串流，讓我的下載或上傳照常完成。

### 為什麼需要這項改進

`lib/src/interceptors/dio_interceptor.dart:21-35` 的 `_stringifyData` 只處理 `null`、`String`、`Uint8List`、`Map`/`List`，其餘一律 `toString()`。實查 dio 5.11.1（`pubspec.lock`）：

- `ResponseType.stream` 時，transformer 原封不動回傳 `ResponseBody`（`transformers/fused_transformer.dart`、`sync_transformer.dart`），所以 `response.data` 就是 `ResponseBody`。
- `ResponseBody`（`src/adapter.dart:68`）是普通 class，沒有覆寫 `toString()`，所以 Response Body 顯示的是 `Instance of 'ResponseBody'`。
- 上傳時 `options.data` 若是 `Stream<List<int>>`，Request Body 則會顯示類似 `Instance of '_ControllerStream<List<int>>'` 的字串。

現行 `toString()` 不會讀取串流，所以真正的痛點只是**看不懂**。「不得讀取串流」是新實作必須遵守的約束：業務端的串流多半是 single-subscription，Inspector 只要 `listen` 一次，宿主之後再 `listen` 就會拋 `StateError`，下載或上傳會直接壞掉。

---

## 2. 輸出格式契約（使用者可見行為）

`data is ResponseBody || data is Stream` 時，`_stringifyData` 回傳固定字串：

```
[stream]...[truncated]
```

（`...[truncated]` 即 `kTruncatedMarker`。）request 與 response 兩側、`onRequest`／`onResponse`／`onError` 三處都輸出同一個字串。

### 開放問題的決定

| # | 問題 | 決定 | 理由 |
|:---:|:---|:---|:---|
| 1 | 佔位字串格式 | 用 `[stream]`，**不採用** `[stream response]` 或 `[stream response (ResponseBody)]`，也**不附** statusCode／contentLength | `_stringifyData` 同時處理 request 與 response；Q2 也包含 request 為 `Stream` 的上傳情境，在 Request Body 顯示 `[stream response]` 是錯的。方向已由詳情頁的 Request Body／Response Body 標題表達，SSE 或下載可從 `Content-Type` header 看出，`ResponseBody` 型別名是 Dio 內部細節，加上去沒有資訊量。statusCode 在 `NetworkEntry.statusCode` 已有；`ResponseBody.contentLength` 內部會 `int.parse` header，header 格式不對時會拋例外，而 `Content-Length` 本來就列在 Response Headers。風格與 `[binary N bytes]` 一致（`[型別名詞]` 加標記），只是串流長度未知，所以不帶數字。 |
| 2 | 是否附 `kTruncatedMarker` | **附** | 與 `Uint8List` 佔位相同。request 為 `Stream` 時 `isRequestTruncated == true`，Resend 自動停用：串流已被 Dio 讀完，本來就無法重送，送出佔位字串更是錯的。response 側讓 `isTruncated == true`，詳情頁會顯示「Body truncated — size reflects the truncated value」，語意正確（body 沒有被擷取，size 只是佔位字串的大小）。 |
| 3 | 判斷式 | 寫成 `data is ResponseBody \|\| data is Stream`，兩者都需要 | `ResponseBody` 沒有繼承也沒有實作 `Stream`，串流只放在 `Stream<Uint8List> stream` 欄位裡（`src/adapter.dart:68-136`，欄位在 :108），只寫 `is Stream` 抓不到它。`is Stream` 用不帶型別參數的寫法：Dio 雖然在 `_transformData` 拒絕非 `Stream<List<int>>` 的資料，但 request interceptor 在那之前就會執行，Inspector 應該對任何 `Stream` 都安全。`is` 檢查不會呼叫串流的任何方法。 |

### 說明

- 全程**禁止**呼叫任何會讀取或訂閱串流的 API（`listen`、`toList`、`drain`、`first`、`length`、`pipe`、`asBroadcastStream` 等），也**禁止**替換或包裝宿主的 `data`（例如用 tee／`StreamSplitter` 分流）：替換 `data` 等於改動宿主的請求或回應物件。
- `ResponseBody` 與 `Stream` 都不是 `Uint8List`／`Map`／`List`，與既有分支互斥，新分支放在哪個位置都不影響其他分支的結果；放在最後的 `toString()` 之前即可。
- **已知限制（沿用既有行為，本項不處理）**：`ResponseType.stream` 時 Dio 收到 header 就觸發 `onResponse`，所以 entry 的 `duration` 是「到 header 抵達」的時間，不是串流讀完的時間；SSE 連線還在進行時，entry 就已經是 `isComplete == true`。

---

## 3. 範圍邊界

### ✅ 做

- `lib/src/interceptors/dio_interceptor.dart`：`_stringifyData` 新增一個分支 `data is ResponseBody || data is Stream`，回傳 `'[stream]$kTruncatedMarker'`。
- `test/interceptors/dio_interceptor_test.dart`：補齊第 4 節驗收條件對應的單元測試。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 擷取或預覽串流內容（前 N bytes、SSE 事件） | Q4 範圍外；讀取就會消耗宿主的串流 |
| 用 tee／`StreamSplitter` 替換 `data` 以旁路擷取 | 改寫宿主物件，違反 Never break userspace |
| 佔位附 statusCode／contentLength／型別名 | 見第 2 節決定 1 |
| 修改 `NetworkEntry` model | Q4 範圍外；現有 `kTruncatedMarker` 機制已能停用 Resend |
| `http` package／WebView 來源 | Q4 範圍外 |
| 修正 stream 回應的 `duration`／`isComplete` 語意 | 既有行為，另案 |
| README、CHANGELOG 更新（README 已有 `[binary N bytes]` 敘述） | 依專案慣例，於 release commit 統一處理 |

### 合併注意

§P33（PR #243，尚未合併）也在 `_stringifyData` 新增 `data is FormData` 分支。`FormData` 不是 `Stream`，兩個分支互斥、邏輯上沒有衝突，但文字位置相鄰，合併時預期會有 git 衝突，保留兩個分支即可。

---

## 4. 驗收條件

測試用的串流一律用 single-subscription 的 `StreamController`（帶 `onListen` 旗標），這樣 Inspector 只要訂閱過一次，業務端再訂閱就會拋 `StateError`，測試會直接失敗。

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | `onResponse`：`response.data` 為 `ResponseBody` 時，`responseBody == '[stream]$kTruncatedMarker'` | 單元測試 |
| 2 | `onError`：`err.response.data` 為 `ResponseBody` 時，`responseBody == '[stream]$kTruncatedMarker'` | 單元測試 |
| 3 | `onRequest`：`options.data` 為 `Stream<List<int>>` 時，`requestBody == '[stream]$kTruncatedMarker'`，且 `entry.isRequestTruncated == true`（Resend 停用） | 單元測試 |
| 4 | request 為 `Stream` 時，`onResponse` 與 `onError` 產生的 `requestBody` 與 `onRequest` 逐字相同 | 單元測試 |
| 5 | 不讀取串流：條件 1–4 跑完之後 `onListen` 旗標仍是 false，業務端接著對該串流（request `Stream` 與 `ResponseBody.stream`）呼叫 `toList()`，可以完整取回全部寫入的資料 | 單元測試 |
| 6 | 既有測試全數通過（`flutter test`），`flutter analyze lib/ test/` 不超過既有 7 個 info | 指令執行驗證 |
