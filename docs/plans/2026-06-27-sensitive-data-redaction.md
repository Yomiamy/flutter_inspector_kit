# 實作計畫：機敏資料遮罩（Sensitive Data Redaction）UI 接線

- **日期**：2026-06-27
- **階段**：STAGE 0b — 實作計畫（只寫 How）
- **對應規格**：`docs/features/2026-06-27-sensitive-data-redaction.md`（source of truth）
- **性質**：既有未 commit 改動「正規化」＋ UI 接線「缺口補完」。本計畫不重新設計遮罩機制，核心工作是把一個 dead field（`FlutterInspector.redactSensitiveData`）接成 live field。

---

## 1. 資料流 / 傳遞鏈設計

### 1.1 現況（flag 是死的）

```
FlutterInspector.redactSensitiveData (true, 已文件化)
        │
        ✗ 斷點：沒有任何 widget 讀這個值
        │
NetworkTab (持有 widget.inspector)
        │  network_tab.dart:188
        ▼
NetworkDetailView(entry: entry)          ← 建構子只有 entry，拿不到 flag
        │
        ▼
_onShare → buildCurl(entry)              ← 沒傳 redact，靠 formatters 預設 true 才碰巧遮罩
          buildPlainText(entry)          ← 同上
```

預設之所以還能遮罩，純粹是 formatters 參數預設 `true`，**與 flag 無關**。宿主設 `redactSensitiveData: false` 完全無效。

### 1.2 目標（flag 真正生效）

把 flag 值沿現成的 widget tree 一路傳到 4 個 build 呼叫點。**不需要 InheritedWidget，不需要全域 singleton**——`NetworkTab` 已持有 `widget.inspector`，`redactSensitiveData` 是其公開欄位。

```
FlutterInspector.redactSensitiveData
        │
NetworkTab._NetworkTabState
        │  widget.inspector.redactSensitiveData
        ▼
NetworkDetailView(entry: entry, redactSensitiveData: widget.inspector.redactSensitiveData)
        │  this.redactSensitiveData
        ▼
_onShare → buildCurl(entry, redact: redactSensitiveData)
          buildPlainText(entry, redact: redactSensitiveData)   × 3 處（text / share / fallback）
```

### 1.3 逐檔簽章異動（before → after）

#### A. `lib/src/ui/dashboard/tabs/network/network_detail_view.dart`

**建構子**（新增一個有預設值的具名參數，維持向後相容）：

```dart
// before
const NetworkDetailView({required this.entry, super.key});

// after
const NetworkDetailView({
  required this.entry,
  this.redactSensitiveData = true,
  super.key,
});
```

**欄位**（新增）：

```dart
// after（在 `final NetworkEntry entry;` 之後新增一行）
final NetworkEntry entry;

/// Whether share/export paths mask sensitive headers. Mirrors
/// [FlutterInspector.redactSensitiveData]. Defaults to `true` (secure by
/// default) so a NetworkDetailView built without this value still redacts.
final bool redactSensitiveData;
```

**`_onShare` 內 4 個呼叫點**（把 flag 作為 `redact` 傳入）：

```dart
// before → after
buildCurl(entry)                  → buildCurl(entry, redact: redactSensitiveData)        // line 227
buildPlainText(entry)             → buildPlainText(entry, redact: redactSensitiveData)   // line 232
shareText(buildPlainText(entry))  → shareText(buildPlainText(entry, redact: redactSensitiveData))  // line 238
buildPlainText(entry)             → buildPlainText(entry, redact: redactSensitiveData)   // line 241 (share fail fallback)
```

> 注意：`_ResendAction._resend` 用的是 `buildReplayRequest(widget.entry)`（line 318），**不經過 buildCurl/buildPlainText、不套 redactHeaders**。Resend 路徑天然不受影響，本計畫不碰它（符合規格 §3 Resend out-of-scope）。

#### B. `lib/src/ui/dashboard/tabs/network_tab.dart`

**建立 NetworkDetailView 處**（line 188）：

```dart
// before
MaterialPageRoute(builder: (_) => NetworkDetailView(entry: entry)),

// after
MaterialPageRoute(
  builder: (_) => NetworkDetailView(
    entry: entry,
    redactSensitiveData: widget.inspector.redactSensitiveData,
  ),
),
```

`_NetworkTabState` 已透過 `widget.inspector` 存取 inspector（見 `network_tab.dart:13/57/118`），不需任何新欄位或依賴注入。

#### C. 不需改動的檔案（僅正規化／納入 commit）

- `lib/src/utils/redaction.dart`（新增、未追蹤）：簽章正確，不改。
- `lib/src/utils/network_formatters.dart`（已修改）：`buildCurl` / `buildPlainText` / `_writeHeaders` 的 `{bool redact = true}` 已就位，不改。
- `lib/src/core/flutter_inspector.dart`（已修改）：`redactSensitiveData = true` 欄位與文件註解已就位，不改。

---

## 2. 檔案異動清單

| 檔案 | 類別 | 改什麼 | 為何改 |
|---|---|---|---|
| `lib/src/utils/redaction.dart` | 正規化（未追蹤→納入） | 不改內容，僅 `git add` | pure module 已完成且有測試覆蓋 |
| `lib/src/utils/network_formatters.dart` | 正規化（已改→納入） | 不改內容 | redact 參數已就位且有測試 |
| `lib/src/core/flutter_inspector.dart` | 正規化（已改→納入） | 不改內容 | flag 欄位＋文件已就位 |
| `test/utils/redaction_test.dart` | 正規化（未追蹤→納入） | 不改內容 | 已覆蓋 redaction 全行為 |
| `test/utils/network_formatters_test.dart` | 正規化（已改→納入） | 不改內容 | 已覆蓋 formatters redact true/false |
| `test/core/flutter_inspector_test.dart` | 正規化（已改→納入） | 不改內容 | 已覆蓋 flag default/opt-out |
| **`lib/src/ui/dashboard/tabs/network/network_detail_view.dart`** | **接線（新改動）** | 建構子加 `redactSensitiveData = true`、加同名欄位、`_onShare` 4 處傳 `redact:` | 讓 flag 能被分享呼叫點讀取（主要工作） |
| **`lib/src/ui/dashboard/tabs/network_tab.dart`** | **接線（新改動）** | line 188 建立 NetworkDetailView 時傳 `widget.inspector.redactSensitiveData` | 把 flag 值注入詳情頁 |
| **`test/ui/tabs/network_detail_view_test.dart`** | **接線（新測試）** | 新增 widget test：opt-out 路徑輸出未遮罩、預設路徑遮罩（覆蓋三條分享路徑） | 補 flag 生效驗證缺口（規格 US-2） |

> 「正規化」六檔在最終 commit 一併納入，內容零改動；implementer 不需動筆，僅確認測試綠燈後一起 commit。真正的程式碼改動只有兩支 lib 檔 + 一支 test 檔。

---

## 3. 任務拆分（TDD）

複雜度分級對照（供 STAGE 2 implementer 選 model）：

- **機械性**：照既定簽章改字面，無設計判斷。
- **整合**：跨檔接線、需理解既有測試慣例。
- **設計判斷**：需要做取捨或設計決策。

> 並行限制：T2 與 T3 都寫入 `network_detail_view.dart`，**不可並行**，必須序列。T4（測試）依賴 T2/T3 完成的簽章。T1（正規化驗證）與 T2 互不寫入同檔，可並行。

### T1 — 正規化既有改動：確認 baseline 測試綠燈

- **目標**：確認既有未 commit 改動（redaction / formatters / flag）的測試全綠，建立 baseline，不改任何程式。
- **驗收條件**：
  - `flutter test test/utils/redaction_test.dart test/utils/network_formatters_test.dart test/core/flutter_inspector_test.dart` 全綠。
  - 不對上述 lib/test 檔做任何內容修改。
- **觸及檔案（寫入 scope）**：無（唯讀驗證）。
- **複雜度**：機械性。
- **依賴**：無。可與 T2 並行。

### T2 — `NetworkDetailView` 接受並傳遞 flag（含 TDD 測試先行）

- **目標**：`NetworkDetailView` 新增 `redactSensitiveData`（預設 `true`）建構子參數與欄位，`_onShare` 4 個呼叫點以該值作 `redact`。
- **TDD 順序**：
  1. 先在 `network_detail_view_test.dart` 寫一個 failing widget test：建構 `NetworkDetailView(entry: <含 Authorization 的 entry>, redactSensitiveData: false)`，點 Copy as cURL，斷言 clipboard 內含原始 token（未遮罩）。此測試在改 code 前必失敗（目前無此參數，編譯不過 = red）。
  2. 改 `network_detail_view.dart` 讓測試轉綠。
- **驗收條件**：
  - 建構子簽章為 `const NetworkDetailView({required this.entry, this.redactSensitiveData = true, super.key});`。
  - `_onShare` 的 curl / text / share / fallback 4 處皆傳 `redact: redactSensitiveData`。
  - 新增的 opt-out widget test 綠燈；既有 `network_detail_view_test.dart` 既有測試（renders all sections、copy as cURL、Resend 群組）全部維持綠燈。
- **觸及檔案（寫入 scope）**：`lib/src/ui/dashboard/tabs/network/network_detail_view.dart`、`test/ui/tabs/network_detail_view_test.dart`。
- **複雜度**：整合（需懂既有 widget test 的 clipboard mock 慣例與 PopupMenuButton 點擊流程）。
- **依賴**：無。與 T1 並行；**必須在 T3 之前**（兩者同寫 detail_view，序列）。

### T3 — `NetworkTab` 注入 flag 值

- **目標**：`network_tab.dart:188` 建立 `NetworkDetailView` 時傳 `redactSensitiveData: widget.inspector.redactSensitiveData`。
- **驗收條件**：
  - line 188 的 builder 改為帶 `redactSensitiveData: widget.inspector.redactSensitiveData`。
  - `flutter test test/ui/tabs/network_tab_test.dart` 綠燈（既有 `findsOneWidget` 導航測試不受影響）。
- **觸及檔案（寫入 scope）**：`lib/src/ui/dashboard/tabs/network_tab.dart`。
- **複雜度**：機械性。
- **依賴**：依賴 T2（NetworkDetailView 新參數需先存在，否則編譯不過）。**不可與 T2 並行**（雖寫不同檔，但編譯相依）。

### T4 — 預設遮罩路徑的端到端驗證測試

- **目標**：補一個 widget test 證明預設（`redactSensitiveData` 省略 = `true`）下，三條分享路徑輸出皆遮罩，鎖住 US-1 行為。
- **TDD 順序**：先寫測試（在 T2 改完簽章後，此測試應直接綠燈，作為 regression guard）；若不綠則回查接線。
- **驗收條件**：
  - 新測試：`NetworkDetailView(entry: <含 Authorization/Cookie 的 entry>)`（不帶 redactSensitiveData），分別觸發 Copy as cURL 與 Copy as text，斷言 clipboard 內容含 `••••`、不含原始 secret。
  - 對 share 路徑：可斷言 Copy as text fallback 行為（避免依賴平台 share sheet），或以 `buildPlainText` 既有 unit 覆蓋為準（見 §4，share 與 text 共用同一格式化函式，不重複造輪子）。
- **觸及檔案（寫入 scope）**：`test/ui/tabs/network_detail_view_test.dart`。
- **複雜度**：整合。
- **依賴**：依賴 T2（簽章與接線需就位）。與 T3 可並行（寫不同檔、且 T4 不依賴 NetworkTab）。

### 任務依賴圖

```
T1 (唯讀驗證) ─┐
               ├─ 可並行
T2 (detail_view: 簽章+opt-out test) ─┬─→ T3 (network_tab 注入)   ┐
                                     └─→ T4 (預設遮罩 regression) ┴─ T3/T4 可並行
```

序列關鍵路徑：**T2 → T3**（同碼相依）。T1 全程可獨立並行；T4 可與 T3 並行。

---

## 4. 測試策略

### 4.1 已覆蓋、不重寫

- **redaction.dart**：`redaction_test.dart` 已覆蓋大小寫、多值、非敏感不動、不 mutate、保留 key 大小寫。→ 不動。
- **formatters 的 redact 開關**：`network_formatters_test.dart` 已覆蓋 `buildCurl` / `buildPlainText` 在 `redact: true`（預設遮）與 `redact: false`（不遮）兩條。→ 不動。
- **flag 欄位本身**：`flutter_inspector_test.dart` 已覆蓋 default true 與 explicit false。→ 不動。

這三層已證明「能遮罩」與「開關參數有效」。本功能的測試缺口**只在 UI 接線**：flag 是否真的被讀取、opt-out 是否可觀察。

### 4.2 新缺口的測試層級建議

採 **widget test**，理由與專案慣例對齊：

- 既有 `network_detail_view_test.dart` 已用 widget test + `SystemChannels.platform` 的 `Clipboard.setData` mock 攔截剪貼簿輸出（line 82-105），這正是觀察「分享輸出內容」最直接的手段。沿用同一 pattern 即可，不需新基礎建設。
- `_onShare` 是 `NetworkDetailView` 的私有方法，**不建議**為了測試把它抽成 top-level 函式——那會為了測試破壞封裝，且 widget test 已能透過點擊 PopupMenuItem + clipboard mock 完整觀察其輸出，沒有抽函式的必要（YAGNI）。

具體新增測試（都放 `test/ui/tabs/network_detail_view_test.dart`）：

1. **opt-out 可觀察**（US-2，屬 T2）：`redactSensitiveData: false` + Copy as cURL → clipboard 含原始 `Bearer secret-token`。
2. **預設遮罩 cURL**（US-1，屬 T4）：省略參數 + Copy as cURL → clipboard 含 `Authorization: ••••`、不含 token。
3. **預設遮罩 text**（US-1，屬 T4）：省略參數 + Copy as text → clipboard 含 `••••`、不含 secret。

> share 路徑（`_ShareAction.share`）呼叫 `shareText`（平台 channel），在 widget test 難以穩定攔截系統 share sheet。它與 Copy as text 共用 `buildPlainText(entry, redact: redactSensitiveData)`，redact 行為已由 formatters unit test + 上述 text widget test 雙重覆蓋；**不需**為 share 再造平台 mock（避免脆弱測試）。share fallback（line 241）走的也是同一條 `buildPlainText`，行為等價。

### 4.3 回歸保護

- 既有 `network_detail_view_test.dart` 的 `copy as cURL writes to clipboard`、`renders all sections`、整個 `Resend action` group 必須維持綠燈——驗證接線未破壞既有行為（US-4）。
- 新參數有預設值 `true`，既有測試呼叫 `NetworkDetailView(entry: ...)` 不需修改即可編譯（向後相容，見 §5）。

---

## 5. 風險與破壞性分析

### 5.1 既有呼叫端會不會被破壞？

`NetworkDetailView` 目前有 5 個呼叫端：

- `network_tab.dart:188`（lib，T3 會更新）。
- `test/ui/tabs/network_detail_view_test.dart` 共 4 處（line 55、71、95，及 `pumpView` 內）。

**對策：新參數 `redactSensitiveData` 給預設值 `true`**。所有既有 `NetworkDetailView(entry: ...)` 呼叫無需修改即可繼續編譯與通過——零破壞。這同時維持 secure-by-default：即使某呼叫端忘了傳 flag，也是「遮罩」這個安全側。

### 5.2 secure-by-default 是否維持？

維持。三道預設都站在「遮罩」一側：

- `FlutterInspector.redactSensitiveData = true`（core 預設）。
- `NetworkDetailView.redactSensitiveData = true`（新建構子預設）。
- `buildCurl/buildPlainText/_writeHeaders` 的 `redact = true`（formatters 預設）。

唯一能關閉的途徑是宿主顯式 `FlutterInspector(redactSensitiveData: false)`，符合規格「opt-out 必須是明確選擇」。

### 5.3 Resend 路徑會不會被誤遮？

不會。`_ResendAction._resend`（line 308-349）用 `buildReplayRequest(widget.entry)` 取得 `req.headers`（原始 header），直接送 `dio.request`，**完全不經過 `redactHeaders` / `buildCurl` / `buildPlainText`**。本計畫不碰 `_ResendAction`，Resend 永遠用真實 header（否則重送會帶 `••••` 必然失敗）。符合規格 §3 Resend out-of-scope 與 US-4 驗收條件。

### 5.4 範圍邊界守則（不擴張）

- **只遮 4 個 header key**，URL query / request body / response body 一律照原樣輸出——本計畫不新增任何 body/query 遮罩邏輯。
- 畫面顯示（`KeyValueTable`）不動，螢幕永遠顯示真實值（US-3）。`NetworkDetailView.build` 內的 headers section（line 54-70）不在改動範圍。
- 不開放自訂敏感 key 清單。

### 5.5 殘餘風險

- **低**：share 路徑無直接 widget 斷言（靠共用 `buildPlainText` 的間接覆蓋）。可接受——避免引入脆弱的平台 channel mock，且 formatters unit test 已直接驗證 `buildPlainText` 的 redact 行為。
- **低**：若未來有人新增第三條走 `buildReplayRequest` 以外的分享路徑而忘了傳 `redact`，formatters 預設 `true` 仍會兜底遮罩，不會洩漏。

---

## 6. 執行方式選項

- **subagent-driven（建議）**：T1 + T2 第一波並行（T1 唯讀、T2 寫 detail_view，不衝突）；T2 完成後 T3 + T4 第二波並行（寫不同檔）。關鍵序列僅 T2→T3。整體 2 波即可收斂。
- **parallel session**：因 T2/T3/T4 都圍繞同一條接線且 T3 編譯相依 T2，平行 session 收益有限，反而增加 detail_view 檔的合併衝突風險。除非要把「正規化納入 commit（T1 範疇）」與「接線（T2-T4）」拆給兩個人，否則單 session 序列執行更穩。
