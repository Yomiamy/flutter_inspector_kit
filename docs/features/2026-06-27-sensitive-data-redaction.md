# 功能規格：機敏資料遮罩（Sensitive Data Redaction）

- **日期**：2026-06-27
- **狀態**：STAGE 0a — 待確認
- **類型**：功能正規化（既有未 commit 改動）＋ 缺口補完（UI 接線）
- **特殊性質**：這不是從零設計。`main` branch 上已有一批未追蹤／未 commit 的改動實作了大部分機制（pure module、formatters 參數、core flag），但 **flag 目前是死的（dead field）**。本規格涵蓋「既有改動正規化」＋「補完讓 flag 真正生效的 UI 接線」。

---

## 1. 背景與動機（Why）

`flutter_inspector_kit` 的 Network 詳情頁提供三條分享／匯出路徑（`NetworkDetailView` 的 share `PopupMenuButton`）：

1. **Copy as cURL** — 把一筆請求重組成可執行 cURL 字串，寫進剪貼簿。
2. **Copy as text** — 把整筆請求／回應導出成純文字，寫進剪貼簿。
3. **Share…** — 經系統 share sheet 把純文字外送（失敗時退回剪貼簿）。

這三條路徑會把 request／response headers 原封不動帶出去。問題在於 headers 裡常常藏著最敏感的東西：`Authorization: Bearer <token>`、`Cookie: session=...`、`Set-Cookie`、`X-Api-Key`。一旦開發者「複製 cURL 貼到 Slack 問同事」「截圖貼 issue」「share 到群組」，這些 secrets 就跟著外洩——**而且開發者多半不會意識到自己剛把 token 貼出去了**。這是一條安靜的洩漏面。

### 設計核心

> 分享路徑預設就該是安全的。要洩漏 secrets 必須是宿主**明確選擇**的結果，而不是預設行為的副作用。

- **Secure by default**：遮罩預設開啟，宿主要關得顯式 opt-out。
- **固定佔位字串**：遮罩後以固定字串取代，連「原值多長」都不洩漏。
- **只動分享路徑，不動畫面顯示**：詳情頁的 headers section 在螢幕上仍照常顯示真實值（開發者本來就需要看），遮罩只發生在「值會離開裝置／進剪貼簿／進截圖文字流」的分享匯出環節。

### 既有改動現況（已實地核對 codebase）

| 檔案 | 狀態 | 現況 |
|---|---|---|
| `lib/src/utils/redaction.dart` | **新增（未追蹤）** | pure module，無 Flutter 依賴。提供 `kRedactedValue = '••••'`、`kSensitiveHeaderKeys`（4 key，大小寫不敏感）、`redactHeaders(Map)`（回傳遮罩後副本，不改原 map） |
| `test/utils/redaction_test.dart` | **新增（未追蹤）** | 已覆蓋 redaction.dart：大小寫、多值 header、非敏感 header 不動、原 map 不被 mutate、保留原 key 大小寫 |
| `lib/src/utils/network_formatters.dart` | **已修改** | `buildCurl` / `buildPlainText` / `_writeHeaders` 都加了 `{bool redact = true}`，預設 true。redact 時對 headers 套 `redactHeaders` |
| `test/utils/network_formatters_test.dart` | **已修改** | 已覆蓋 formatters 的 redact 行為 |
| `lib/src/core/flutter_inspector.dart` | **已修改** | 建構子新增 `final bool redactSensitiveData`（預設 `true`），含文件註解承諾「secrets never leak unless host explicitly opts out」 |

### 🔴 核心缺口：`redactSensitiveData` 是一個死欄位

經實地核對 `lib/src/ui/dashboard/tabs/network/network_detail_view.dart`：

- `_onShare` 的三個呼叫點全部呼叫 `buildCurl(entry)` / `buildPlainText(entry)`，**完全沒有傳入 `redact` 參數**：
  - line 227：`buildCurl(entry)`
  - line 232：`buildPlainText(entry)`
  - line 238：`shareText(buildPlainText(entry))`
  - line 241：`buildPlainText(entry)`（share 失敗的剪貼簿 fallback）
- `NetworkDetailView` 是 `StatelessWidget`，建構子只有 `entry`（`const NetworkDetailView({required this.entry, super.key})`），**沒有任何途徑取得 `FlutterInspector` 實例或 `redactSensitiveData` 值**。
- 結果：`redactSensitiveData` 被宣告、被文件化，但**沒有任何程式碼讀它**。預設遮罩之所以還能生效，純粹是因為 formatters 參數預設 `true`，**與這個 flag 毫無關聯**。宿主設 `redactSensitiveData: false` 想關掉遮罩，會**完全無效**——文件承諾的 opt-out 是假的。

### 資料流可行性（已核對，傳遞鏈現成）

要讓 flag 真正生效，必須把 `redactSensitiveData` 的值送進 `NetworkDetailView` 的呼叫點。核對結果證明這條鏈是現成的，不需要新造任何全域機制：

- `NetworkDetailView` 由 `network_tab.dart:188` 建立：`NetworkDetailView(entry: entry)`。
- `NetworkTab` 已持有 `widget.inspector`（type `FlutterInspector`，見 `network_tab.dart:11/13`），而 `redactSensitiveData` 是 `FlutterInspector` 的公開欄位。
- 因此 flag 值可沿 `NetworkTab` → `NetworkDetailView` → `_onShare` 三個呼叫點傳遞，**不需要 `InheritedWidget`、不需要全域 singleton**。

---

## 2. 使用者故事與驗收條件

### US-1：宿主預設就受到保護，分享路徑不洩漏 secrets

> 身為使用此套件的 app 開發者，我希望在沒有特別設定的情況下，從 Network 詳情頁複製 cURL／複製文字／分享出去的內容，敏感 header 就已經被遮罩，這樣我隨手分享也不會把 token 洩漏出去。

**驗收條件：**

- [ ] 在預設設定（`redactSensitiveData == true`）下，**三條分享路徑全部**（Copy as cURL／Copy as text／Share，含 share 失敗的剪貼簿 fallback）輸出的內容中，`Authorization` / `Cookie` / `Set-Cookie` / `X-Api-Key` 的值都被替換為固定佔位字串 `••••`。
- [ ] 遮罩採固定字串，**不透露原值長度**（不可用 `*` 重複原長度之類的做法）。
- [ ] header 的 key（名稱）保留原樣，只有 value 被遮；非敏感 header 的 key 與 value 完全不變。
- [ ] 敏感 key 的比對**大小寫不敏感**（`Authorization` / `authorization` / `AUTHORIZATION` 都被遮）。

### US-2：宿主可顯式 opt-out 取得原始值（且 opt-out 真的生效）

> 身為需要把完整請求（含真實 token）導出去做深度除錯的開發者，我希望能明確關掉遮罩，拿到未遮罩的原始內容；而且這個開關必須真的有效，不能是個裝飾品。

**驗收條件：**

- [ ] 當宿主建構 `FlutterInspector(redactSensitiveData: false)` 時，三條分享路徑輸出的內容**不遮罩**，敏感 header 顯示真實值。
- [ ] **flag 真的被 UI 呼叫點讀取**：`NetworkDetailView` 的分享呼叫點所用的 `redact` 值，來源是 `FlutterInspector.redactSensitiveData`（而非寫死在 formatters 的預設值）。亦即把 flag 改成 `false` 必須能觀察到輸出差異——這是本功能相對既有改動最關鍵的補完點。

### US-3：開發者在螢幕上仍看得到真實 header 值

> 身為開發者，我在詳情頁本來就是要看真實的 header 內容來除錯，我不希望遮罩讓畫面上的值也被蓋掉變得沒法看。

**驗收條件：**

- [ ] 不論 `redactSensitiveData` 為 true 或 false，`NetworkDetailView` 畫面上的 Request Headers／Response Headers section（`KeyValueTable`）顯示的都是**真實值**，遮罩**不影響**螢幕渲染。
- [ ] 遮罩只發生在「值會離開裝置／進剪貼簿／進系統 share」的分享匯出路徑。

### US-4：遮罩不破壞既有 Network 功能

> 身為使用者，我希望加入遮罩接線後，詳情頁與既有匯出格式除了「敏感值被遮」之外，行為與輸出結構完全不變。

**驗收條件：**

- [ ] cURL 與純文字匯出的**整體結構**（區段順序、格式、非敏感欄位內容）維持原樣，差異僅限敏感 header 的 value。
- [ ] Resend 動作不受本功能影響（它走的是重建請求送出，不是分享匯出路徑；其重組仍使用真實 header，否則重送會帶著 `••••` 必然失敗——這點屬範圍邊界，見 §3）。
- [ ] 既有 `redaction.dart` / `network_formatters.dart` / 對應測試的行為不被回退或弱化。

---

## 3. 範圍邊界（Scope）

### In-Scope

- 正規化既有未 commit 改動：`redaction.dart`（pure module）、`network_formatters.dart`（redact 參數）、`flutter_inspector.dart`（`redactSensitiveData` flag）及其既有測試。
- **補完 UI 接線（本功能主要工作）**：讓 `redactSensitiveData` 的值流到 `NetworkDetailView` 的三條分享呼叫點，使 flag 真正生效（opt-out 可被觀察到）。
- **遮罩範圍：只遮 4 個 header key** —— `Authorization` / `Cookie` / `Set-Cookie` / `X-Api-Key`（大小寫不敏感），且只在分享／匯出路徑。

### Out-of-Scope（明確排除）

- **URL query string 內的 token**（例如 `?access_token=...`、`?sig=...`）：本次**不**遮罩。純文字匯出的 `=== Query Parameters ===` 與 cURL 的 URL 都照原樣輸出。列為後續可選迭代。
- **request／response body 內的敏感欄位**（例如 JSON body 裡的 `password` / `token` / `refresh_token`）：本次**不**遮罩。body 內容照原樣匯出。
- **畫面顯示遮罩**：詳情頁螢幕上的 headers/body 一律顯示真實值，不在遮罩範圍（見 US-3）。
- **log／console／database 等其他外洩面**：本功能只處理 Network 詳情頁的分享匯出路徑，不擴及其他 tab 或日誌輸出。
- **Resend（重送）路徑的遮罩**：重送需要真實 header 才能成功，**不可**遮罩；本功能不改動重送行為。
- **可設定的敏感 key 清單／自訂遮罩規則**：本次採固定 4 key 清單，不開放宿主自訂。列為後續可選迭代。

---

## 4. 既有改動盤點與缺口

| 項目 | 既有改動是否已具備 | 本功能要做的事 |
|---|---|---|
| pure redaction module（`redactHeaders` / 固定佔位字串 / 4 key 清單） | ✅ 已存在（`redaction.dart` + 測試） | 正規化納入本 flow，不需重寫 |
| formatters redact 參數（secure default `true`） | ✅ 已存在（`network_formatters.dart` + 測試） | 正規化納入本 flow，不需重寫 |
| `redactSensitiveData` core flag（預設 `true` + 文件承諾） | ✅ 已存在（`flutter_inspector.dart`） | 保留，不做反向改動 |
| **UI 呼叫點讀取 flag** | 🔴 **缺口（主要工作）** | 把 `redactSensitiveData` 沿 `NetworkTab → NetworkDetailView → _onShare` 傳遞，讓三條分享呼叫點以 flag 值作為 `redact` 參數 |
| flag 生效的驗證測試（opt-out 可被觀察） | 🔴 **缺口** | 補測試：`false` 時分享路徑輸出未遮罩、`true` 時遮罩（widget／整合層級，覆蓋三條分享路徑） |

> 重點：既有改動已備好「能遮罩」的零件，但少了「把開關接上線」這一步。本功能的價值不在發明新機制，而在**讓既有的、已被文件承諾的開關真正可用**——把一個 dead field 變成 live field。

---

## 5. 規格出口條件

本規格通過確認的標準：

- US-1～US-4 的驗收條件被接受為「可測試、可驗收」。
- 範圍邊界被確認，特別是：**只遮 header**、URL query／body／其他外洩面與 Resend 路徑明確排除、畫面顯示不遮。
- 既有改動盤點與「UI 接線為主要缺口」的認定被確認。

確認後進入 STAGE 0b（實作計畫），屆時才細化傳遞鏈的逐檔簽章異動、`NetworkDetailView` 新增參數的形狀、以及 TDD 任務拆解。
