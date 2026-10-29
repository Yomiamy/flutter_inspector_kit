# 功能規格：README「非 Dio 傳輸」排查食譜（gRPC 與 WebSocket）（§Z4-3）

- **日期**：2026-10-29
- **來源**：`docs/brainstorm/2026-10-22-features-brainstorm.md` §Z4 第 3 項
- **Effort**：low ｜ **排查價值**：⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在宿主 App 中使用 Flutter Inspector Kit 的開發者，
> 當我的 App 除了 Dio 之外，還使用了 **gRPC**（RPC 呼叫）或 **WebSocket**（雙向長連線）進行資料傳輸時，
> 我希望**在 README 中有一份清楚且可直接套用的排查食譜（Recipes），指導如何手動建構 `NetworkEntry` 或記錄生命週期事件**，
> 並且**明確指出協定狀態碼與 `statusCode` 不相容的陷阱**，
> 這樣我就能將所有網路流量無縫整合到同一個 Inspector 儀表板，同時避免因狀態碼誤用導致 UI 篩選與錯誤判定失真。

### 為什麼需要這項改進

目前 `README.md` 的網路章節中，除了詳細的 Dio 攔截器說明外，對於非 Dio 客戶端僅有 4 行簡略的示意：
```dart
final pending = inspector.logNetwork(NetworkEntry(method: 'GET', url: url));
// ...after the response arrives:
inspector.logNetwork(completedEntry, replaces: pending);
```

但在真實世界的 Flutter 專案中：
1. **gRPC 串接**：開發者需要一個具體的 `ClientInterceptor` 實作範例，了解如何在 `interceptUnary` 與 `interceptStreaming` 中發起 pending 記錄、在回應到達時以 `replaces` 覆蓋、以及如何捕獲 `GrpcError`。
2. **WebSocket 串接**：WebSocket 是持續性的長連線雙向串流，與短暫的 Request-Response 請求不同。開發者常疑惑「該用 `logNetwork` 還是 `log`」，需要推薦的最佳實踐（連線建立、連線關閉與異常時記錄到 Console，或將連線生命週期登錄至 Network）。
3. **兩大關鍵陷阱（Gotchas）**：
   - **協定狀態碼不可放進 `statusCode`**：`NetworkEntry.isFailed` 判定規則為 `(statusCode ?? 0) >= 400 || error != null || errorType != null`。
     - gRPC 的狀態碼為 0 到 16（如 0=OK, 1=CANCELLED, 16=UNAUTHENTICATED），若直接塞進 `statusCode`，由於全小於 400，失敗呼叫（如 CANCELLED）將無法被 `isFailed` 標記為錯誤！
     - WebSocket 的標準關閉碼為 1000..4999（如 1000=Normal Closure），若塞進 `statusCode`，因為 `1000 >= 400`，正常的連線關閉反而會被判定為失敗！
     - 此外，Network Tab 的狀態篩選晶片（2xx/3xx/4xx/5xx）是以 HTTP 為標準，非 HTTP 數值會破壞篩選邏輯。
   - **切勿擴充 `NetworkOrigin` enum**：`NetworkOrigin` 是公開列舉（目前僅有 `dio` 與 `webview`）。若嘗試新增 `grpc` 或 `websocket`，會破壞宿主 App 對 enum 的窮舉 `switch`（違反 Never break userspace）。非 Dio/WebView 流量維持預設值或不額外指定即可。
4. **保持純淨**：本套件堅持純 Dart 與零多餘相依性，`lib/` 原始碼不需要也不應該新增任何 gRPC 或 WebSocket 專屬邏輯，純靠優質文件指導宿主端完成對接。

---

## 2. 範圍邊界

### ✅ 做

- 在 `README.md` 擴充非 Dio 客戶端章節（在 `#### With other HTTP clients` 之後新增）：
  - **`#### With gRPC (ClientInterceptor)`**：
    - 提供實作 `package:grpc` 的 `ClientInterceptor` 範例代碼。
    - 展示單向呼叫（Unary RPC）的生命週期：發起前建立 pending entry，完成後以 `replaces: pending` 更新結果。
    - 展示錯誤處理：捕獲 `GrpcError`，填入 `error: e.message` 或 `e.toString()`，將 gRPC status（如 `e.codeName` 或 `e.code`）放入 headers 或 body，而非 `statusCode`。
  - **`#### With WebSocket`**：
    - 說明 WebSocket 連線的推薦排查模式：以 `inspector.log()` 記錄連線建立、中斷、錯誤與關閉事件（包含 `closeCode` 與 `reason`）。
    - 示範如何記錄結構化事件至 Console。
  - **`#### Protocol Pitfalls & Best Practices`**（協定陷阱與最佳實踐）：
    - 標注 **Trap 1: Never put protocol status codes into `statusCode`**，詳細解釋 `isFailed` 與 HTTP chip 的工作原理，說明 gRPC code (0..16) 與 WebSocket close code (1000+) 的衝突，並給出替代方案（放入 `responseHeaders` 或 `error`）。
    - 標注 **Trap 2: Do not add or expect new `NetworkOrigin` enum values**，說明公開 enum 向後相容性。
- 確保所有提供的 Dart 範例代碼語法正確、符合 Dart 3.0+ 最佳實踐。

### ❌ 不做

- `lib/` 程式碼零改動（零架構變更、零新增 enum、零破壞性改動）。
- 不在 `pubspec.yaml` 新增 `grpc` 或 `web_socket_channel` 依賴。
- 不新增 runtime 的 gRPC/WebSocket 攔截器類別。

---

## 3. 驗收條件

1. **食譜齊備度**：`README.md` 包含完整、清晰且可直接套用的 gRPC `ClientInterceptor` 與 WebSocket 排查食譜。
2. **陷阱警示明確**：針對 `statusCode` 與 `NetworkOrigin` 的兩大陷阱有顯眼的警示區塊與技術原因說明。
3. **無破壞性**：`lib/` 零改動，不影響既有 public API。
4. **測試與靜態分析**：既有所有單元測試與靜態分析 `flutter analyze` 100% 通過。
