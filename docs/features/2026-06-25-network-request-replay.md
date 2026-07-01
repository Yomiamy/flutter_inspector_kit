# 功能規格：網路請求重放（Replay / Resend）

- **日期**：2026-06-25
- **狀態**：STAGE 0a — 待確認（含 2 項必須拍板的開放問題）
- **來源**：`docs/brainstorm/2026-07-01-features-brainstorm.md` 的 #6（網路請求重放 Replay / Resend），現況「⬜ 未實作」
- **類型**：功能新增（Network 詳情頁新增動作）

---

## 1. 背景與動機（Why）

API 出錯時，開發者目前的排查動線是：在 Network tab 點開出錯的請求 → `Copy as cURL` → 切到終端機 → 貼上執行 → 看結果。這條動線的痛點不是「不能重送」，而是 **context switch**：人得離開 app、切到終端、再切回來，只為了回答兩個很基本的問題：

> 1.「這個錯誤現在還會不會重現？」（是偶發還是持續故障）
> 2.「server 恢復了沒？」（後端修好了嗎，還是還在 5xx）

`flutter_inspector_kit` 已經有 `buildCurl()` 把一筆 `NetworkEntry` 重組成可執行請求的能力（`lib/src/utils/network_formatters.dart`），證明「從 entry 重建請求」這件事是可行且已被驗證的。Replay 的本質，就是把這條「重建請求」的邏輯從「產出 cURL 字串給人去終端跑」改成「就地用 app 自己的網路層再送一次」，把答案直接帶回 Network tab。

### 設計核心（沿用報告定調）

> 不要為「重送」發明新的網路管線或新的結果儲存。重送就是「重建一次請求 → 用既有 Dio 送出 → 結果記成一條新的 `NetworkEntry`」。

- **重用請求重組**：沿用 `buildCurl()` 已證明的「從 entry 取 method / url / headers / body」的重組邏輯來源。
- **重用網路層**：經由已接線 `FlutterInspectorDioInterceptor` 的 Dio 送出（細節見開放問題 OQ-1）。
- **重用結果儲存**：重送的回應透過既有 interceptor 自動記成一筆新的 `NetworkEntry`，落入既有 `RingBuffer`，免費獲得 Network tab 的列表、詳情、cURL 匯出等所有既有能力。

### 現況關鍵檔案

| 檔案 | 角色 | 現值 |
|---|---|---|
| `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | 詳情頁 | `StatelessWidget`，AppBar 已有 share `PopupMenuButton`（cURL / text / share）；**Resend 動作要加在這** |
| `lib/src/models/network_entry.dart` | 資料模型 | `@immutable`，持有 method / url / requestHeaders / requestBody 等，是重建請求的資料來源；**目前無任何「這是 replay 出來的」標記欄位** |
| `lib/src/utils/network_formatters.dart` | 請求重組 | `buildCurl(entry)` 已從 entry 取 method / headers / body / url 重組請求，是要沿用的重組邏輯 |
| `lib/src/interceptors/dio_interceptor.dart` | 自動記錄 | `onRequest` / `onResponse` / `onError` 把流經的請求記成 `NetworkEntry` 餵回 inspector；重送的請求若經此 interceptor，會**自動**被記錄 |
| `lib/src/inspectors/network_inspector.dart` | buffer 管理 | `add(entry, {replaces})` 將 entry 入 `RingBuffer` |
| `lib/src/core/flutter_inspector.dart` | 核心入口 | 建構子持有 `customTab` / `magicalTapCount` / `showNetworkNotification` 等；**目前不持有任何 Dio 實例** |
| `example/lib/main.dart` | 接線範例 | 宿主自建 `Dio()` 後 `_dio.interceptors.add(FlutterInspectorDioInterceptor(inspector))`——**Dio 由宿主持有，inspector 只拿到單向餵 entry 的 interceptor** |

---

## 2. 使用者故事與驗收條件

### US-1：開發者就地重送一筆出錯的請求

> 身為開發者，當我在 Network 詳情頁看到一筆出錯（4xx／5xx／傳輸失敗）的請求時，我希望能在這個頁面直接點一下「Resend」就把原請求再送一次，不必複製 cURL 跳去終端。

**驗收條件：**

- [ ] `NetworkDetailView` 提供一個「Resend」動作（按鈕或選單項），對任何一筆已完成（`isComplete == true`）的 entry 皆可觸發。
- [ ] 觸發後，以原 entry 的 method / url / request headers / request body 重建一次請求並送出（**原樣重送**，不修改任何欄位，見範圍邊界）。
- [ ] 重送的請求與回應，作為一筆**新的** `NetworkEntry` 出現在 Network tab 列表中（不覆寫、不修改原始那筆）。

### US-2：開發者分辨哪筆是 replay 出來的

> 身為開發者，當我重送後回到 Network tab，我希望一眼分得出「哪一筆是我手動重送出來的」vs「app 正常流量產生的」，才不會把 replay 結果誤判成真實使用者行為。

**驗收條件：**

- [ ] 重送產生的 `NetworkEntry` 帶有可被識別為「replay」的標記，使用者在列表或詳情頁能分辨它與一般請求的差異。
- [ ] 標記方式（視覺呈現／文案）需在實作計畫階段定案，但規格層要求：**不得**讓 replay 結果與一般請求視覺上完全無差別。

### US-3：開發者得到重送進行中／成功／失敗的回饋

> 身為開發者，當我點下 Resend，我希望知道它「正在送」「送成功了」「送失敗了」，而不是點完沒反應、不知道發生什麼事。

**驗收條件：**

- [ ] 重送進行中，UI 給出「進行中」的回饋（例如動作禁用、loading 指示），避免重複連點造成多筆重送。
- [ ] 重送完成（無論成功或 server 回錯）後，UI 給出明確回饋（例如 SnackBar），並讓使用者能看到結果那筆 entry。
- [ ] 重送在傳輸層失敗（例如斷網、連線逾時、根本沒到 server）時，**不得讓 app crash**；UI 回饋此次重送失敗，且這個失敗本身也應比照一般失敗被記錄成一筆 entry（與既有 `onError` 行為一致）。

### US-4：重送不破壞既有詳情頁與分享行為

> 身為使用者，我希望加入 Resend 後，詳情頁原本的 Copy as cURL / Copy as text / Share 等功能完全不變。

**驗收條件：**

- [ ] 既有 share `PopupMenuButton`（cURL / text / share）行為與位置不受影響。
- [ ] `NetworkDetailView` 既有的所有 section 渲染（General / Query / Headers / Body / Error）維持原樣。

---

## 3. 範圍邊界（Scope）

### In-Scope（MVP）

- 在 `NetworkDetailView` 新增「Resend」動作。
- **原樣重送**：以原 entry 的 method / url / headers / body 不加修改地重送一次。
- 重送結果記成一筆新的、**可被識別為 replay** 的 `NetworkEntry`。
- 重送進行中／成功／失敗的 UI 狀態回饋。
- 重送失敗（含傳輸層失敗）不導致 app crash。

### Out-of-Scope（明確排除）

- **編輯 header／body 後重送**：報告原文寫「可改 header/body」，但本規格建議 **MVP 先不做可編輯**（理由見 OQ-2）。「可改」列為後續可選迭代，不在本次範圍。
- **API mocking／動態回應改寫**：明確排除。在 debug overlay 注入 mock 規則會讓工具代碼翻倍，且極易因 debug 庫 bug 中斷宿主正式網路流——這是 Proxyman/Charles 的地盤，違反「Never break userspace」。（對應報告 anti-features #4）
- **腳本化／批次重送、重送排程、retry 自動化**：非排查核心，不做。
- **不依賴 Dio 的請求引擎（例如自帶 http client）**：本功能定位為「重送 app 自己經 Dio 發出的那一類請求」，不另造平行網路層。

---

## 4. 開放問題（需使用者拍板）

> 以下兩項會直接影響功能可行性與 API 形狀，屬規格層決策，**不在規格內擅自決定**，列出供拍板。

### 🔴 OQ-1：重送用的 Dio 從哪來？（可行性核心，必須拍板）

**現況事實**：經實地核對 codebase，**inspector 目前並不持有任何 Dio 實例**。接線方式是宿主 app 自建 `Dio()`，再 `dio.interceptors.add(FlutterInspectorDioInterceptor(inspector))`（見 `example/lib/main.dart`）。Interceptor 是「把流經宿主 Dio 的請求餵回 inspector」的**單向**通道，inspector 拿不到那個 Dio 的 reference。

換言之，報告寫的「經注入的 Dio 重送」——**那個 Dio 目前根本沒被注入到 inspector**。要做 Replay，得先決定「重送時要用哪個 Dio」。規格層的選項（trade-off 留實作計畫細化）：

- **選項 A — 新增可選建構參數 `FlutterInspector(dio: ...)`**：宿主把同一個 Dio 也交給 inspector。重送時用它，請求自然再次流經既有 interceptor → 自動被記錄。語意最乾淨（重送走的是宿主真實網路層，含 baseUrl / 既有 interceptors / auth）。代價：宿主接線多一步，且為可選；未提供時 Resend 動作降級為不可用（灰掉）。
- **選項 B — 重送時臨時 new 一個 Dio**：不需要宿主提供。代價：拿不到宿主 Dio 的 baseUrl／攔截器／憑證設定，對「需要 auth header 才會成功」的請求容易產生與原請求不對等的結果，排查價值打折；且這個臨時 Dio 沒接 interceptor，結果不會自動記錄，得另外手動記回 buffer。
- **選項 C — 讓 interceptor 持有並回傳其所屬 Dio**：由 `FlutterInspectorDioInterceptor` 在建構時要求傳入它所屬的 Dio。代價：改動既有 interceptor 的建構簽章（既有宿主接線要跟著改），需評估向後相容。

**需拍板**：採哪個來源策略？這決定了公開 API 是否新增參數、以及「未提供重送來源時 Resend 是否降級隱藏／灰掉」的產品行為。

### 🔴 OQ-2：MVP 要不要納入「可改 header/body」？（範圍取捨，必須拍板）

**現況事實**：報告原文寫「原地重送（**可改 header/body**）」。但「可編輯後重送」會引入：請求編輯表單 UI、header/body 的解析與重新序列化（尤其 JSON body）、輸入驗證、改動後與原請求的對照呈現——這是一塊明顯比「原樣重送」大得多的工作量。

**建議（Linus 實用主義：先做最小可用）**：MVP **先做原樣重送**，把「可編輯」列為後續迭代。理由：

- 「原樣重送」已能回答兩個核心問題——「是否仍重現」「server 是否恢復」——這正是 Replay 的價值主張。
- 「可編輯」更接近「構造新請求做實驗」，邊界上更靠近被排除的 mocking/改寫；在排查主線上，先驗證「同一個請求現在還錯不錯」才是剛需。
- 原樣重送的 UI 極簡（一個動作 + 狀態回饋），可編輯則需整套表單，兩者複雜度不在同一量級。

**需拍板**：接受「MVP 原樣重送、可編輯延後」，還是堅持 MVP 即納入可編輯？

> 其餘較次要的設計點（replay 標記的具體呈現、結果那筆 entry 的標記欄位設計）屬實作細節，留 STAGE 0b 實作計畫處理。

---

## 5. 重用既有零件清單

| 既有零件 | 位置 | 在本功能的角色 |
|---|---|---|
| `buildCurl(entry)` 的請求重組邏輯 | `lib/src/utils/network_formatters.dart` | 「從 entry 取 method / url / headers / body 重建請求」的已驗證來源，重送的重組沿用同一資料取法 |
| `NetworkEntry`（含 method / url / requestHeaders / requestBody / `isComplete`） | `lib/src/models/network_entry.dart` | 重建請求的資料來源；結果也記成新的一筆 `NetworkEntry` |
| `FlutterInspectorDioInterceptor`（`onRequest`/`onResponse`/`onError`） | `lib/src/interceptors/dio_interceptor.dart` | 若重送走的 Dio 已接此 interceptor，結果自動記成新 entry，免手寫記錄 |
| `NetworkInspector.add` / `FlutterInspector.logNetwork` | `lib/src/inspectors/network_inspector.dart`、`lib/src/core/flutter_inspector.dart` | 結果 entry 落入 `RingBuffer` 的既有入口 |
| 已接線的 Dio client | 由宿主在 `example/lib/main.dart` 模式接線 | 重送的網路層（**前提是先解決 OQ-1：inspector 目前並未持有它**） |
| `NetworkDetailView` 既有 AppBar / `PopupMenuButton` / SnackBar 模式 | `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | Resend 動作的承載位置與狀態回饋（SnackBar）的既有範式 |

---

## 6. 規格出口條件

本規格通過確認的標準：

- OQ-1（Dio 來源策略）與 OQ-2（MVP 是否含可編輯）已由使用者拍板。
- US-1～US-4 的驗收條件被接受為「可測試、可驗收」。
- 範圍邊界（特別是排除 mocking／改寫、以及 MVP 不含可編輯的取捨）被確認。

確認後進入 STAGE 0b（實作計畫），屆時才細化資料模型欄位、逐檔異動與 TDD 任務拆解。
