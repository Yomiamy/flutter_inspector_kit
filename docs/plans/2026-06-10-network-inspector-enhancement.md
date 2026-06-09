# 實作計畫：Network Inspector 強化（對齊 alice）

- **日期**：2026-06-10
- **Workflow ID**：wf-1781023458-df59
- **功能規格**：`docs/features/2026-06-10-network-inspector-enhancement.md`
- **狀態**：STAGE 0b — 待確認

---

## 1. 設計總覽

核心策略：**先把「資料」與「純函式」做扎實（可測），UI 與第三方依賴疊在上面**。資料模型加欄位、抽出純 util（size 格式化 / JSON 美化 / curl 生成 / 搜尋過濾），再重寫 UI，最後掛 notification 與 sharing 兩個帶依賴的功能。

### 資料結構決策

`NetworkEntry` 目前已涵蓋多數欄位。**不新增多餘欄位**，而是用既有資料 + 純函式 derive 出 alice 風格的呈現：

- `requestSize` / `responseSize` → 由 `requestBody` / `responseBody` 字串 byte 長度 derive，**不存欄位**（避免重複狀態，符合「消滅多餘狀態」）。
- `queryParameters` → 由 `url` 解析 derive，不存欄位。
- `contentType` → 由 `requestHeaders` / `responseHeaders` 取 `content-type` derive，不存欄位。

> 理由：這些全是既有資料的視圖，存成欄位等於製造可能不一致的副本。用 getter / util 即時 derive 是更乾淨的資料流。唯一例外見 T1 的 `isTruncated` 標記。

### 新增依賴

```yaml
dependencies:
  flutter_local_notifications: ^18.0.0   # US-3，實際版本以 pub 最新穩定為準
  share_plus: ^10.0.0                    # US-4 系統分享
```

## 2. 檔案異動清單

| 檔案 | 動作 | 任務 |
|------|------|------|
| `lib/src/models/network_entry.dart` | 改：新增 derived getter（size/queryParams/contentType/isJsonBody）+ `isTruncated` | T1 |
| `lib/src/utils/network_formatters.dart` | **新增**：純函式（byteSize 格式化、JSON 美化、curl 生成、純文字匯出、搜尋過濾述詞） | T2 |
| `lib/src/utils/network_search.dart` | **新增**：搜尋/篩選資料模型（`NetworkFilter`）+ 過濾函式 | T3 |
| `lib/src/ui/dashboard/tabs/network_tab.dart` | 改：重寫為搜尋框 + 篩選 chip + 結構化 list item | T4, T7 |
| `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | **新增**：Request/Response 分段詳情 + 分享入口 | T5 |
| `lib/src/ui/widgets/key_value_table.dart` | **新增**：headers/query 鍵值表 widget（可複用） | T5 |
| `lib/src/notifications/network_notifier.dart` | **新增**：通知封裝（含未授權降級） | T6 |
| `lib/src/core/flutter_inspector_impl.dart` | 改：建構子加 `showNetworkNotification`，呼叫 notifier；可能加 `navigatorKey` 供通知點擊導頁 | T6 |
| `lib/src/inspectors/network_inspector.dart` | 改：`add()` 時觸發 notifier callback（透過 registry/inspector 注入，不讓 inspector 依賴 UI） | T6 |
| `lib/flutter_inspector.dart` | 改：export 新公開型別（如 `NetworkFilter` 若公開） | T5/T6 |
| `pubspec.yaml` | 改：加 2 依賴（**唯一 owner = T6**；T2/T3 不碰） | T6 |
| `example/lib/main.dart` | 改：示範 `showNetworkNotification: true` | T8 |
| `test/...` | 新增：formatters / search / entry getter 單元測試 | T2, T3, T1 |

## 3. 任務拆分（含複雜度分級與寫入 scope）

> 分級對齊 implementer 的 model 策略：🟢 機械性=快/便宜｜🟡 整合=標準｜🔴 設計判斷/跨層=最強。

### T1 — `NetworkEntry` derived getters 🟡 標準
- **寫入**：`lib/src/models/network_entry.dart`、`test/models/network_entry_test.dart`
- 新增：`int get requestSizeBytes` / `int get responseSizeBytes`（UTF-8 byte 長度）、`Map<String,String> get queryParameters`（解析 url）、`String? get contentType`、`bool get isRequestJson`/`isResponseJson`、`bool isTruncated`（body 含截斷標記時為 true）。
- 不改既有欄位與 `copyWith` / `==`（除非新增的是 getter，無需動）。

### T2 — `network_formatters.dart` 純函式 🟡 標準
- **寫入**：`lib/src/utils/network_formatters.dart`、`test/utils/network_formatters_test.dart`
- 函式：
  - `formatBytes(int)` → `"0 B"` / `"1.2 KB"` / `"3.4 MB"`。
  - `prettyJson(String)` → 合法 JSON 縮排美化；非 JSON 回傳原字串。
  - `buildCurl(NetworkEntry)` → 正確 curl 字串。
  - `buildPlainText(NetworkEntry)` → 完整文字匯出。
- 全部純函式、無 Flutter 依賴 → 100% 可單測。

### T3 — `network_search.dart` 搜尋/篩選 🟢 機械性
- **寫入**：`lib/src/utils/network_search.dart`、`test/utils/network_search_test.dart`
- `NetworkFilter`（keyword + 可選 method set + 可選 status 區間）+ `List<NetworkEntry> applyFilter(List, NetworkFilter)`，大小寫不敏感比對 url/method/status。

### T4 — Network tab 搜尋 UI 骨架 🟡 標準
- **寫入**：`lib/src/ui/dashboard/tabs/network_tab.dart`
- 頂部加搜尋框 + 篩選 chip，state 持有 `NetworkFilter`，套用 T3 的 `applyFilter`。
- 保留既有 refresh / clear。**此任務先用既有的展開呈現**，詳情重寫留給 T5/T7（避免與 T5 撞同檔——見排序）。

> ⚠️ T4 與 T7 同寫 `network_tab.dart` → **不可並行**，T7 接在 T4 後序列。

### T5 — Request/Response 詳情 view + 鍵值表 🔴 設計判斷
- **寫入**：`lib/src/ui/dashboard/tabs/network/network_detail_view.dart`、`lib/src/ui/widgets/key_value_table.dart`、`lib/flutter_inspector.dart`(export)
- 分段卡片：General / Query Parameters / Headers / Body（用 T1 getter + T2 美化）。
- 內含「分享」入口（menu：Copy as cURL / Copy as text / Share），呼叫 T2 的 `buildCurl`/`buildPlainText` + `Clipboard` + `share_plus`。
- status 顏色語意。

### T6 — Notification 整合 🔴 跨層
- **寫入**：`lib/src/notifications/network_notifier.dart`、`lib/src/core/flutter_inspector_impl.dart`、`lib/src/inspectors/network_inspector.dart`、`pubspec.yaml`(唯一 owner)、`lib/flutter_inspector.dart`
- `NetworkNotifier`：init / showOrUpdate(entry, totalCount) / 權限降級。
- inspector 建構子加 `bool showNetworkNotification = false`；`NetworkInspector.add` 透過注入的 callback 通知（inspector 不直接 import notifier，保持單向依賴）。
- 點擊通知導向 Network tab（若 `navigatorKey` 可用）。

### T7 — Network tab list item 結構化 + 接詳情 🟡 標準
- **寫入**：`lib/src/ui/dashboard/tabs/network_tab.dart`（接 T4 之後）
- list item 改為結構化（method badge、url、狀態著色、size、time），點擊推 T5 的 `NetworkDetailView`。

### T8 — example 示範 + README 段落 🟢 機械性
- **寫入**：`example/lib/main.dart`、`README.md`
- 示範 `showNetworkNotification: true`，README 補 Notification 平台設定說明。

## 4. 執行順序與並行判斷

```
T1 ─┐
T2 ─┼─ 路徑不重疊、無依賴 → 🟢 可並行（未 opt-in workflow → 序列跑）
T3 ─┘
       ↓ 完成後
T4（network_tab 骨架）
       ↓ 序列（同檔）
T5（detail view，依賴 T1/T2）  ← 也依賴 pubspec 的 share_plus（見下方共享檔處理）
T6（notification，唯一 owner of pubspec）
       ↓
T7（network_tab item，接 T4，依賴 T5 的 detail view）
       ↓
T8（example + README）
```

### 共享檔處理（並行三規則之規則 2）

- `pubspec.yaml`：唯一 owner = **T6**。但 T5 需要 `share_plus`。
  → **解法**：把「加依賴」全部前置到 T6 之前先做（或在 T5 開始前由 implementer 統一加好 2 個依賴並 `pub get`），讓 pubspec 只被動一次。實作時 implementer 在進入 T5 前先補依賴，T6 不再重複加。
- `lib/flutter_inspector.dart`：T5 與 T6 都可能 export → 序列（T5 先、T6 後），不並行。

**結論**：因未 opt-in Claude Workflow，全程**序列逐任務**執行，每任務（或 T1–T3 這組）完成後暫停確認。

## 5. 測試策略

- **純函式（T1/T2/T3）**：完整單元測試——formatBytes 邊界、prettyJson 對非法 JSON 的容錯、buildCurl 對含/不含 body、applyFilter 大小寫與多條件。
- **UI（T4/T5/T7）**：widget test 驗證搜尋過濾後 item 數、詳情分段存在、空狀態。
- **Notification（T6）**：以 callback 注入點做單測（不實際發系統通知），驗證「啟用才觸發、未授權不崩潰」。
- 每任務結束跑 `flutter analyze` + 相關 `flutter test`。

## 6. 風險與緩解

| 風險 | 緩解 |
|------|------|
| `flutter_local_notifications` 平台設定繁瑣 | 預設關閉；README 寫清楚；未授權降級不崩潰 |
| pubspec 被多任務搶 | 依賴前置統一加，唯一 owner |
| size 在截斷後失真 | `isTruncated` 為 true 時 UI 標註「(truncated)」 |
| share_plus 在 desktop/web 行為差異 | 以 try/catch 包覆，失敗回退為「複製到剪貼簿」 |

---

## 確認

請確認此實作計畫（8 個任務、序列執行、檔案異動與測試策略）。確認後進入 **STAGE 1** 建立 Issue + 分支。
