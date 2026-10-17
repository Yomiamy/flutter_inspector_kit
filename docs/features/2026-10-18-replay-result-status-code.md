# 功能規格：Replay 結果顯示狀態碼（§Z4-2）

- **日期**：2026-10-18
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §Z4 第 2 項（新提案 · Replay 結果顯示狀態碼）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在 `NetworkDetailView` 點擊「Resend」重送請求以驗證後端修復或重現問題的開發者／QA，
> 我希望**重送完成後的 SnackBar 直接顯示回應的 HTTP 狀態碼（如 `Resent → 200`、`Resent → 500`）或失敗原因類型（如 `Resend failed: connectionError`）**，
> 這樣我不必退回 `NetworkTab` 列表尋找新產生的 replay 項目，當下就能在詳細頁得知重送結果。

### 為什麼需要這項改進

目前 `_ResendActionState._resend` 在請求成功（2xx）與伺服器錯誤回應（`DioExceptionType.badResponse`，如 4xx/5xx）時，皆只顯示無差別的 `'Request resent'`；在傳輸層失敗（如 `connectionError`、`connectionTimeout`）時也只顯示 `'Resend failed'`。
排查者在詳細頁按下 Resend 後，無法從 SnackBar 分辨重送是拿到 `200` 還是 `500`，或是哪種傳輸層錯誤，必須手動返回列表查看最新一筆紀錄。將狀態碼與 `DioExceptionType.name` 直接帶入 SnackBar，能以零新模型、零結構變更的最小成本補齊即時回饋。

---

## 2. 範圍邊界

### ✅ 做

- `NetworkDetailView` 內 `_ResendActionState._resend` 的結果 SnackBar 訊息改為：
  - 取得 HTTP 回應狀態碼時（含 2xx 正常返回與 `DioExceptionType.badResponse` 帶 `e.response?.statusCode`）：顯示 `Resent → <statusCode>`（例如 `Resent → 200`、`Resent → 500`）。
  - 若回應物件未帶狀態碼（`statusCode == null` 防禦性回退）：維持顯示 `Request resent`。
  - 非 `badResponse` 的 `DioException`（傳輸層失敗／取消／逾時等）：顯示 `Resend failed: <type>`，其中 `<type>` 為 `e.type.name`（例如 `Resend failed: connectionError`）。
  - 非 `DioException` 的未預期例外（`catch (_)`）：維持顯示 `Resend failed`。
  - `sourceDio?.target == null` 前置檢查：維持既有 `Resend failed: source Dio not available`。
- 更新 `test/ui/tabs/network_detail_view_test.dart` 內 `Resend action` 群組的三處字串斷言（`Resent → 200`、`Resent → 500`、`Resend failed: connectionError`）。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 在 SnackBar 顯示耗時（ms） | §Z4-2 明確規定「不顯示 ms」；耗時可在列表與詳細頁查看，SnackBar 保持短小精悍 |
| 修改 `Options.validateStatus` 將 4xx/5xx 轉為非例外 | 會導致宿主 `Dio` 掛載的 `FlutterInspectorDioInterceptor` 不再走 `onError`，破壞 4xx/5xx 重送紀錄的 `error` / `errorType` 擷取 |
| 自動跳轉至新產生的 replay `NetworkDetailView` | 超出本次範圍，且保留在原詳細頁比對前後差異是常見排查習慣 |

---

## 3. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | 重送成功且回應帶狀態碼（如 `200`）時，SnackBar 顯示 `Resent → 200` | Widget 測試斷言（`network_detail_view_test.dart` Test 3） |
| 2 | 重送回傳 `DioExceptionType.badResponse` 且帶狀態碼（如 `500`）時，攔截器照常記錄 error entry，且 SnackBar 顯示 `Resent → 500` | Widget 測試斷言（`network_detail_view_test.dart` Test 4） |
| 3 | 重送發生非 `badResponse` 的 `DioException`（如 `connectionError`）時，SnackBar 顯示 `Resend failed: connectionError` | Widget 測試斷言（`network_detail_view_test.dart` Test 4b） |
| 4 | 回應無狀態碼（`statusCode == null`）時安全回退至 `Request resent`，不顯示 `null`；非 `DioException` 例外維持 `Resend failed` | 代碼審查與防禦性分支確認 |
| 5 | 全部測試通過（`flutter test`）且靜態分析無新增警告（`flutter analyze lib/ test/`） | 指令執行驗證 |
