# 功能規格：Dio 回傳 bytes 時以二進位佔位字串取代 jsonEncode（§Z1-1）

- **日期**：2026-10-18
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §Z1 第 1 項（既有缺陷 · Dio 回傳 bytes 時未截斷先 jsonEncode 造成記憶體尖峰）
- **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在宿主 App 中整合 `FlutterInspectorDioInterceptor` 的開發者，當 App 透過 Dio 下載或上傳二進位資料（如圖片、檔案、`ResponseType.bytes`，即 `Uint8List`）時，
> 我希望**攔截器直接將 `Uint8List` 轉為 `'[binary N bytes]...[truncated]'` 佔位字串，而不是先把整塊 bytes 經 `jsonEncode` 展開成百萬字元的 `[137,80,…]` JSON 字串再截斷**，
> 這樣大檔傳輸時不會因監控工具自身產生數十 MB 的字串配置尖峰與 UI 執行緒卡頓（觀察者效應），同時在詳細頁能清楚看到二進位資料的 byte 長度並自動停用不可還原的 Resend 操作。

### 為什麼需要這項改進

在 Dart 中，`Uint8List` 實作了 `List<int>`（繼承自 `List`）。目前 `FlutterInspectorDioInterceptor._stringifyData` 的判斷順序為：
1. `data == null` → `null`
2. `data is String` → `data`
3. `data is Map || data is List` → `jsonEncode(data)`

當 Dio 設定 `ResponseType.bytes` 回傳 `Uint8List`（或 `RequestOptions.data` 傳入 `Uint8List`）時，會命中 `data is List` 分支，先把整段位元組陣列完整序列化為十進位數字陣列字串（例如 5 MB 的 `Uint8List` 會瞬間配置約 20 MB 的 `String`），之後進到 `NetworkInspector.add` 才被 `NetworkEntry.truncateBody` 截斷至 10 KB。這在大型檔案下載時會造成嚴重的記憶體尖峰與同步阻塞。

---

## 2. 範圍邊界

### ✅ 做

- 在 `lib/src/interceptors/dio_interceptor.dart` 的 `_stringifyData` 開頭（於 `data is Map || data is List` 之前）判斷 `data is Uint8List`：
  - 命中時直接回傳 `'[binary ${data.length} bytes]$kTruncatedMarker'`（例如 4 bytes 回傳 `'[binary 4 bytes]...[truncated]'`）。
  - 刻意只判斷 `data is Uint8List` 而**不**判斷 `data is List<int>`，避免將宿主傳入的一般 JSON 整數陣列（如 `[1, 2, 3]`）誤判為二進位資料。
- 佔位字串以 `kTruncatedMarker`（`'...[truncated]'`）結尾，直接沿用既有 `NetworkEntry.isRequestTruncated` 與 `NetworkEntry.isTruncated` 機制：
  - 當 `requestBody` 為 `Uint8List` 時，`isRequestTruncated` 為 `true`，`NetworkDetailView` 的 Resend 按鈕自動停用（避免把佔位字串當成真實 payload 重送出去）。
  - `NetworkDetailView` 自動顯示既有截斷提示。
- 於 `test/interceptors/dio_interceptor_test.dart` 補齊單元測試，驗證：
  - `onResponse` 收到 `Uint8List` 時，`responseBody` 為 `'[binary N bytes]...[truncated]'` 且 `isTruncated` 為 `true`。
  - `onRequest` 傳入 `Uint8List` 時，`requestBody` 為 `'[binary N bytes]...[truncated]'` 且 `isRequestTruncated` 為 `true`。
  - `onError` 的 `err.response?.data` 為 `Uint8List` 時，`responseBody` 同樣為 `'[binary N bytes]...[truncated]'`。
  - 一般 `List<int>`（非 `Uint8List`，例如 `<int>[1, 2, 3]`）仍走 `jsonEncode` 序列化為 `'[1,2,3]'`。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 攔截 `List<int>` 或 `Stream<List<int>>`（`ResponseType.stream`） | `List<int>` 會誤傷宿主的普通 JSON 整數陣列；`ResponseBody` stream 並非 `List`，原本就走 `toString()`，不在 §Z1-1 範圍內 |
| 新增 `NetworkEntry.isBinary` 欄位或修改 `NetworkEntry` / `NetworkInspector` | 佔位字串尾綴 `kTruncatedMarker` 已完整相容既有 `isTruncated` 與 `isRequestTruncated` 契約，零模型改動即可達成目標 |
| 二進位內容的 Hex dump 或圖片預覽 | 屬獨立功能範疇，非本缺陷修復目標 |

---

## 3. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | `Response.data` 為 `Uint8List`（含空 `Uint8List(0)` 與非空）時，`entry.responseBody` 為 `'[binary <N> bytes]...[truncated]'`，不經過 `jsonEncode` | 單元測試（`dio_interceptor_test.dart`） |
| 2 | `RequestOptions.data` 為 `Uint8List` 時，`entry.requestBody` 為 `'[binary <N> bytes]...[truncated]'`，且 `entry.isRequestTruncated` 為 `true` | 單元測試（`dio_interceptor_test.dart`） |
| 3 | `DioException.response?.data` 為 `Uint8List` 時，`entry.responseBody` 為 `'[binary <N> bytes]...[truncated]'` | 單元測試（`dio_interceptor_test.dart`） |
| 4 | 普通 `List<int>`（如 `<int>[1, 2, 3]`）不被誤判為 binary，仍正常輸出 `'[1,2,3]'` | 單元測試（`dio_interceptor_test.dart`） |
| 5 | 全部測試通過（`flutter test`）且靜態分析無新增警告（`flutter analyze lib/ test/`） | 指令執行驗證 |
