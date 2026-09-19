# P17 · 原生折疊式 JSON 樹狀檢視器（JsonTreeViewer）

> **來源**：`docs/brainstorm/2026-09-19-features-brainstorm.md` §P17
> **狀態**：功能規格（What & Why）· 2026-09-19
> **範圍**：`NetworkDetailView` 的 Request/Response Body、`LogDetailView` 的 Data 區塊

---

## 1. What & Why

目前 Inspector 呈現結構化資料的方式，在巢狀層級一深就失效：

- **Network 側**：`NetworkDetailView` 的 Request/Response Body 走
  `prettyJson()`（`lib/src/utils/network_formatters.dart:62`，僅
  `JsonEncoder.withIndent('  ')`），輸出是一坨扁平縮排純文字，塞進
  `SelectableText`。3 層以上的 payload 無法折疊無關分支，只能靠捲動與肉眼掃描找欄位。
- **Log 側**：`LogDetailView` 的 `Data` 區塊用 `KeyValueTable` 渲染
  `entry.data`。`key_value_table.dart:15` 的註解明載「Values are rendered via
  `toString()`」——巢狀 Map/List 被壓成 `{a: {b: ...}}` 的單行 blob，
  直接不可讀。

本功能導入一個**專案自製、零新增外部相依**的折疊式 JSON 樹狀檢視器
`JsonTreeViewer`，讓開發者能逐節點展開/折疊、搜尋定位、複製欄位路徑，
把「捲動找欄位」換成「折疊無關分支後直接看」。

---

## 2. 使用者故事（User Stories）

1. 身為一位前端開發者，我在 app 內開啟 Inspector → Network 分頁 → 點進某筆 API
   請求，看到 Response Body 是一棵可折疊的樹，**預設只展開前 2 層**，這樣我一眼就能
   掌握 payload 的輪廓，而不是被三百行縮排文字淹沒。
2. 身為一位前端開發者，我想檢視 `data.users[0].profile.settings` 這種深層欄位，
   我可以把其他無關分支折疊起來，只保留我在追的那條路徑展開。
3. 身為一位前端開發者，我找到有問題的欄位後，想把它的**路徑與值複製**下來
   （如 `data.users[0].id`），貼到程式碼或 issue 裡，不必手動拼字串。
4. 身為一位前端開發者，面對欄位很多的 payload，我想**輸入關鍵字搜尋**，
   讓命中的節點被高亮、非命中的被過濾掉，直接跳到我要的欄位。
5. 身為一位前端開發者，我在 Console 分頁點進一筆 log，希望 `Data` 區塊的巢狀
   Map 也用同一棵樹呈現，而不是 `toString()` 壓出來的單行 blob。
6. 身為一位前端開發者，我在檢視上千個節點的大型 payload 時，捲動應該保持順暢，
   不因為節點數量而卡頓。

---

## 3. 驗收條件（Acceptance Criteria）

1. **折疊/展開**：JSON 的每個 object / array 節點皆可獨立展開或折疊；
   葉節點（primitive 值）不提供展開 affordance。
2. **預設展開深度**：初次渲染時**預設展開前 2 層**，第 3 層（含）以下預設折疊。
3. **複製路徑與值**：可對單一節點觸發複製（點擊或長按），複製內容包含該節點的
   **完整路徑**（object 用 `.key`、array 用 `[index]`，如 `data.users[0].id`）
   與其值。
4. **搜尋過濾與高亮**：提供文字搜尋輸入；命中的節點（key 或值符合）需被高亮，
   非命中的分支被過濾隱藏；命中節點的祖先鏈需保持可見，否則使用者失去上下文。
5. **大型 payload 效能**：渲染採**扁平化節點清單 + `ListView.builder`**，
   展開/折疊/搜尋不得造成 O(N²) 重建，捲動時僅建構可視範圍內的節點。
6. **文字一律黑色（刻意決策）**：所有節點文字使用單一前景色（沿用主題預設的
   一般文字色），**不做任何語法色彩高亮**。結構感完全由**縮排、展開/折疊
   affordance、樹狀佈局**承載。搜尋高亮為唯一例外（那是狀態指示，非語法著色）。
7. **Network 側接線**：`NetworkDetailView` 的 Request Body 與 Response Body
   在 `isJson` 為 true 時改由 `JsonTreeViewer` 呈現；非 JSON 內容維持原有
   純文字呈現路徑不變。
8. **Log 側接線**：`LogDetailView` 的 `Data` 區塊改由 `JsonTreeViewer` 呈現
   `entry.data`；`data` 為 null 或空時維持既有的 `(no data)` 空狀態語意。
9. **零新增外部相依**：`pubspec.yaml` 的 dependencies 不得新增任何項目
   （尤其禁止第三方 json viewer 套件、禁止 BLoC/Riverpod/Provider）。
10. **既有行為零破壞**：`prettyJson()` 不被移除或改變語意；分享/複製全文與
    `buildNetworkPlainText` 仍走既有純文字路徑，輸出逐字不變。
11. **核心不變式不受影響**：不觸碰 `RingBuffer` / `mergedTimeline` /
    `InspectorRegistry`。本功能純屬 UI 呈現層。
12. **驗證基準**：`flutter test` 全綠；`flutter analyze lib/ test/`
    不超出既有 7 個 info 基準（新增任何 warning/info 皆視為本次引入的問題）。

---

## 4. 範圍邊界（Scope & Boundaries）

### 4.1 包含（Included）
- 折疊式樹狀渲染、預設展開 2 層
- 節點路徑 + 值的複製
- 文字搜尋、過濾與命中高亮
- 扁平化 + `ListView.builder` 的大型 payload 渲染策略
- `NetworkDetailView`（Request/Response Body）與 `LogDetailView`（Data）兩處接線

### 4.2 排除（Excluded）
- **不做語法色彩高亮——文字一律黑色**。
  這是**刻意決策，不是遺漏的需求**。理由：(a) 使用者明確要求
  「先都一律用黑色，不需要這麼花花綠綠的東西」；(b) 本套件是輕量除錯工具，
  型別著色會引入色票管理與深/淺色主題對比度的額外維護面；
  (c) 折疊與縮排已足以承載結構感，著色是錦上添花而非解決本問題的必要條件。
  若日後有實證需求，可另立 feature 追加。
- **不做 JSON 編輯**——本元件唯讀。
- **不做 schema 驗證**。
- **不做 JSON diff**（跨請求比對不在本次範圍）。
- **不取代 `prettyJson()`**——分享、複製全文、`buildNetworkPlainText`
  維持純文字路徑。樹狀檢視只加在「畫面上看」這條路。
- **不動核心不變式**——`RingBuffer` / `mergedTimeline` /
  `InspectorRegistry` / 條件匯出（`_io.dart` / `_web.dart`）皆不修改。

---

## 5. 兩個接線點的形狀差異（重要）

`docs/brainstorm/2026-09-19-features-brainstorm.md:1133` 把痛點描述成
「兩個 detail view 都有 JSON 顯示問題」。**實查結果顯示這是不精確的**——
兩側的輸入形狀根本不同，規格必須誠實反映，否則實作會做出錯的 API：

| | Network 側 | Log 側 |
|:---|:---|:---|
| **接線點** | `network_detail_view.dart:177`，`_bodySection(context, title, body, isJson)` 內的 `final rendered = isJson ? prettyJson(body) : body;` → `SelectableText(...)` | `log_detail_view.dart` 的 `_dataSection`（約 :139），現為 `KeyValueTable(data: widget.entry.data, emptyLabel: '(no data)')` |
| **呼叫端** | :94（Request Body）、:105（Response Body） | 單一處 |
| **判定旗標** | `entry.isRequestJson` / `entry.isResponseJson` | 無旗標；`data` 恆為結構化 |
| **輸入型別** | **JSON 字串**（`String? body`），需 decode | **已解析的 `Map<String, dynamic>?`**（`log_entry.dart:33`），**不需 decode** |
| **失效形狀** | 扁平縮排純文字、無法折疊 | `toString()` 把巢狀壓成單行 blob |
| **非 JSON 的路徑** | `isJson == false` 時維持純文字，不進樹 | 不存在此情況 |

**對規格的意涵**：`JsonTreeViewer` 必須同時服務「字串」與「已解析物件」兩種來源。
這暗示元件核心應接受**已解析的資料**，由呼叫端負責 decode——但
**具體 API 形狀（建構式、命名建構式、參數設計）留給 STAGE 0b 實作計畫決定**，
本規格不寫死。

---

## 6. 風險與未決事項

| # | 項目 | 說明 | 處置 |
|:---|:---|:---|:---|
| R1 | Network 側 decode 失敗 | `isJson` 旗標為 true 但 body 實際無法 `jsonDecode`（截斷、編碼異常） | 需定義 fallback：退回既有純文字呈現，不得拋例外炸掉 detail view。實作計畫須涵蓋此分支與其測試 |
| R2 | `SelectableText` 行為退化 | 現況 Network body 可自由選取任意文字；改成樹狀後選取行為必然改變 | 已由「不取代 `prettyJson()`」緩解——分享/複製全文路徑仍在。是否額外保留「切回純文字」的開關，列為 STAGE 0b 的開放選項 |
| R3 | 搜尋過濾與折疊狀態的互動 | 搜尋時強制展開命中路徑，清除搜尋後應回到什麼折疊狀態？ | 未決。行為選項（還原搜尋前狀態 / 重置為預設 2 層）留給 STAGE 0b 定案，但需明確選一個並寫測試 |
| R4 | 極端深度 / 循環引用 | `LogEntry.data` 由 Host 提供，理論上可能極深或含自我引用 | 需設定深度上限或循環偵測，避免無限展開。屬防禦性需求，實作計畫須明確處理 |
| R5 | 非 JSON 原生型別 | `LogEntry.data` 的值可能是 `DateTime`、自訂物件等非 JSON primitive | 葉節點一律以 `toString()` 呈現即可（與現況 `KeyValueTable` 行為一致，無退化） |

---

## 7. 相關檔案（實查基準）

- `lib/src/utils/network_formatters.dart:62` — `prettyJson(String? body)`
- `lib/src/ui/dashboard/tabs/network/network_detail_view.dart:94, :105, :177`
- `lib/src/ui/dashboard/tabs/console/log_detail_view.dart:139` — `_dataSection`
- `lib/src/models/log_entry.dart:33` — `final Map<String, dynamic>? data;`
- `lib/src/ui/widgets/key_value_table.dart:15` — `toString()` 渲染的根因註解
- `lib/src/ui/widgets/` — 現有元件：`confirm_dialog` / `detail_section` /
  `error_card` / `inspector_fab` / `key_value_table` / `magical_tap`
  （**`JsonTreeViewer` 不存在，為全新元件**）
