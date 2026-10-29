# 實作計畫：README「非 Dio 傳輸」排查食譜（gRPC 與 WebSocket）（§Z4-3）

- **日期**：2026-10-29
- **規格**：[`docs/features/2026-10-29-readme-non-dio-transport-recipes.md`](../features/2026-10-29-readme-non-dio-transport-recipes.md)
- **來源**：`docs/brainstorm/2026-10-22-features-brainstorm.md` §Z4-3
- **Effort**：low

---

## 1. 資料結構與設計方向 Trade-off

**`lib/` 原始碼保持零改動。不新增任何類別、不新增 enum、不新增套件依賴。**

### 方案比較

1. **方案 A（採用）：純文檔食譜（Recipes in README.md）**
   - **實作方式**：在 `README.md` 中詳細提供可供宿主 App 直接複製貼上的範例代碼，包含 gRPC `ClientInterceptor` 與 WebSocket 事件日誌記錄，並以顯眼的警告區塊指出協定狀態碼與 enum 擴充的陷阱。
   - **優點**：
     - **Good Taste & Never Break Userspace**：不污染本套件的 public API，不增加依賴負擔（避免強行引入 `grpc` 或 `web_socket_channel`）。
     - **零運行時開銷**：完全由宿主 App 在邊界層進行轉接，本套件維持輕量與純粹。
     - **明確防禦**：直接在文件根源處防範開發者誤用 `statusCode` 與破壞 `NetworkOrigin` 的反模式。
2. **方案 B（不採用）：在 `lib/` 內建 `FlutterInspectorGrpcInterceptor` 與 WebSocket 支援**
   - **缺點**：
     - 需要在 `pubspec.yaml` 引入 `grpc`、`protobuf`、`web_socket_channel` 等重量級第三方套件，增加數十個傳遞依賴。
     - 對於只用 Dio 或 HTTP 的 App 造成嚴重的依賴膨脹與版本衝突風險。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 說明 |
|:---|:---:|:---|
| `README.md` | 修改 | 在 `#### With other HTTP clients` 擴充 gRPC `ClientInterceptor` 範例、WebSocket 記錄建議以及兩大陷阱說明 |

---

## 3. 任務拆分

**總任務數：1（單一任務 `[快/便宜]`）**

### Task 1 `[快/便宜]`：擴充 `README.md` 之 gRPC 與 WebSocket 排查食譜及協定狀態碼陷阱

**寫入路徑**：
- `README.md`

**實作步驟**：
1. 定位 `README.md` 的 `#### With other HTTP clients` 區塊（約 L180-195）。
2. 將其整理為結構化子章節：
   - **With other HTTP clients**：保留通用 `NetworkEntry` 與 `replaces: pending` 的基礎用法。
   - **With gRPC (`ClientInterceptor`)**：
     - 撰寫 `FlutterInspectorGrpcInterceptor implements ClientInterceptor` 範例。
     - 涵蓋 `interceptUnary` 的發起、成功回調（`replaces`）與例外處理（捕獲 `GrpcError`）。
     - 指導如何序列化 protobuf message（如 `request.toProto3Json()` 或 `writeToJsonMap()`）。
   - **With WebSocket**：
     - 說明 WebSocket 作為長連線的排查思路：推薦透過 `inspector.log()` 記錄連線建立、中斷、錯誤與關閉事件。
   - **Gotchas: Protocol Status Codes & NetworkOrigin**：
     - **協定狀態碼切勿放進 `statusCode`**：詳細解說 `NetworkEntry.isFailed` 判定公式（`statusCode >= 400`）與 HTTP 篩選晶片（2xx/3xx/4xx/5xx）的工作原理。gRPC 狀態碼（0..16）及 WebSocket 關閉碼（1000+）若填入會造成嚴重邏輯扭曲。說明應將協定狀態碼放入 `responseHeaders`（如 `grpc-status`）或 `error`。
     - **切勿擴充 `NetworkOrigin` enum**：維持使用者的 switch 窮舉安全，保持 `lib/` 零改動。
3. 驗證代碼區塊語法高亮、Markdown 格式排版與排版整潔度。
4. 執行 `flutter analyze` 與 `flutter test` 確保工作目錄無任何異常。

---

## 4. 驗收契約

- **文檔檢查**：`README.md` 中代碼標記正確、無死鏈、階層結構清晰。
- **測試指令**：`flutter test`（既有 752+ tests 全綠）
- **靜態檢查**：`flutter analyze`（0 errors, 0 新增警告）
