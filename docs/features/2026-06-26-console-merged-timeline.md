# 功能規格：Console 升級為跨層混合時序軸（Cross-Layer Merged Timeline）

- **日期**：2026-06-26
- **狀態**：STAGE 0a — 待確認（設計已定稿，無待拍板的開放問題）
- **來源**：`docs/brainstorm/2026-06-25-features-brainstorm.md` 的 #2（跨 Inspector 時序關聯，現況「⬜ 未實作，現僅有 nav/network 鏡射到 console log 的廉價替代」）與 #5（ConsoleTab 排查化）
- **類型**：既有功能升級（Console tab 的呈現模型重構 + 移除複製式鏡射）

---

## 1. 功能概述（What & Why）

### 一句話本質

Console 不再靠「把事件複製成字串塞進 log buffer」來假裝呈現綜合情境，改成**在渲染當下讀取四個 buffer（log / network / nav / db）、按 `timestamp` merge-sort、引用原 entry 顯示**。預設顯示 All（四種混合）。

### 為什麼要做（Why，已查證的現況事實）

現況的 Console 其實已經在「假裝」做混合軸，但用的是劣化版做法——把其他層的事件**複製成字串**塞進 log buffer：

- `lib/src/interceptors/dio_interceptor.dart`：每筆 network 請求在 `onResponse`、`onError` 各額外塞一條 `LogLevel.debug` 字串 log 進 console buffer（已核對：`onResponse` 與 `onError` 各一處 `_inspector.log(...)`）。
- `lib/src/observers/navigator_observer.dart`：每次 push / pop / replace / remove 都額外塞一條 `LogLevel.warning` 字串 log 進 console buffer（已核對：`_record()` 內一處 `_inspector.log(..., level: LogLevel.warning)`，且 class doc 明白寫著這是刻意「mirroring the interceptor」的設計）。
- database 操作則**完全沒有鏡射**（已核對：`FlutterInspector.database()` 只寫 `_registry.database`，無任何 `log()` 呼叫），所以「綜合情境」一直缺 db 那一塊。

這個複製式做法有三個必須解決的問題：

1. **第二份真相**：複製的是字串快照。network entry 後續會由 pending 更新為 completed（`logNetwork(entry, replaces: pending)`），但 console 那份字串快照不會跟著更新，導致兩份對不上；而且點進去也看不到完整結構（network 的 headers / body、nav 的 arguments、db 的 rows）。
2. **偽造 level**：nav 事件用 `LogLevel.warning` 純粹是為了在 Console 有顏色，污染了真實的 level 語意。使用者想撈真正的 warning 時，會撈到一堆 navigation 雜訊。
3. **吃 buffer 配額**：四個 inspector 各自獨立、各 500 格（已核對 `InspectorRegistry`：四個 inspector 都以同一 `bufferSize` 建立），但複製式做法把 network + nav 的字串灌進 log buffer，把真正的 error log 擠出 500 格的視窗，反而看不到完整情境。

### 設計核心（已定稿）

> 混合只發生在「渲染讀取」當下，不發生在「寫入」當下。Console 不再擁有第二份資料，而是**引用四個既有 buffer 的原始 entry**，按 `timestamp` 排序後攤在同一條軸上。

這同時對齊了 brainstorm 的品味守則：「只是指標包裝（指向既有 entry），不複製資料、不引入第二份真相。」

四個 model 都已具備排序所需的 `timestamp` 欄位（已核對：`LogEntry` / `NetworkEntry` / `NavigatorEntry` / `DatabaseEntry` 皆有 `final DateTime timestamp`），因此 merge-sort 的排序鍵天然存在，無需新增欄位。

---

## 2. 使用者故事與驗收條件

> 以排查場景為主：開發者 / QA 如何用這條時序軸定位「跨層」問題。

### US-1：開發者用一條軸看清「故障前後到底發生了什麼」

> 身為開發者，當某個操作出錯時，我希望在同一個 Console tab 裡，按時間順序看到「使用者點了什麼（nav）→ 發了什麼 API（network）→ 印了什麼 log → 做了什麼 db 操作」，而不必在四個孤立的 tab 之間用肉眼對時間戳。

**驗收條件：**

- [ ] Console tab 預設顯示 All：同時呈現 log / network / nav / db 四種來源的事件。
- [ ] 所有來源的事件以單一時間順序（依各 entry 的 `timestamp`）交錯排列在同一個清單中，使用者能直接讀出跨層事件的先後關係。
- [ ] 每一列能被辨識出它的來源類別（log / network / nav / db），使用者一眼分得出這列是哪一層的事件。

### US-2：開發者點任一事件都能看到「完整且最新」的詳情

> 身為開發者，當我在時序軸上看到一筆 network 請求時，我希望點進去看到的是完整的 headers / body / 狀態，而且是它最新的狀態（pending 已更新為 completed），不是一張過時的字串快照。

**驗收條件：**

- [ ] 時序軸上的每一列**引用原始 entry**，而非字串快照；點擊可進入該來源既有的詳情呈現（network 看 headers / body、nav 看 arguments、db 看 rows、log 看 stackTrace / data）。
- [ ] 當某筆 network entry 由 pending 更新為 completed 後，下一次渲染時序軸時，該列反映的是更新後的最新狀態（不存在「軸上一份、詳情頁另一份」的對不上）。

### US-3：QA 在不被雜訊干擾的情況下只看某一層

> 身為 QA，當我只想專注看 API 流量（或只看 navigation、只看 error log）時，我希望能一鍵切換來源，把其他層暫時收起來，而不是被混合視圖淹沒。

**驗收條件：**

- [ ] Console tab 頂部提供 source filter chip：`[All] [Log] [Network] [Nav] [DB]`，預設選中 `All`。
- [ ] 切換到任一單一來源時，時序軸只顯示該來源的事件；切回 `All` 時恢復四種混合。
- [ ] filter 一併滿足 Console 原本缺的「errors-only / 過濾」需求：切到 `Log` 時，呈現的就是純粹的 console log 視圖（不再混入 network / nav 的鏡射雜訊）。

### US-4：開發者撈「真正的 warning / debug」時不再撈到鏡射雜訊

> 身為開發者，當我想找真正的 `LogLevel.warning` 或 `LogLevel.debug` 訊息時，我希望結果只有我自己（或框架）真正記下的 log，而不是被 navigation（偽造的 warning）和 network（偽造的 debug）鏡射訊息污染。

**驗收條件：**

- [ ] interceptor 不再為 network 請求額外寫入 `LogLevel.debug` 的鏡射字串 log。
- [ ] navigator observer 不再為 navigation 事件額外寫入 `LogLevel.warning` 的鏡射字串 log。
- [ ] 移除鏡射後，log buffer 內 `debug` / `warning` 等級的內容只反映真實的 log 來源，navigation 與 network 事件改由時序軸從各自 buffer 直接呈現。

### US-5：既有使用者不因升級而失去原本的 Console 觀感

> 身為既有的套件使用者，我希望升級後既有接線與既有「看 console log」的行為仍可用，必要時能還原成升級前的觀感。

**驗收條件：**

- [ ] 既有 `FlutterInspector.logEntries` getter 與其語意保留可用（不破壞既有依賴它的程式碼）。
- [ ] 將 source filter 切到 `Log` only 時，Console 還原為「只看 log buffer」的舊觀感（等同升級前去掉鏡射雜訊後的 console）。
- [ ] 既有四個 tab（Network / Navigator / Database）的各自呈現不受本功能影響。

---

## 3. 範圍邊界（Scope）

### In-Scope

- Console tab 改為「渲染當下讀取四個 buffer → 依 `timestamp` merge-sort → 引用原 entry」的混合時序軸，預設 All。
- 每一列引用原始 entry，點擊進入該來源既有的詳情呈現（不複製資料、不產生第二份真相）。
- 頂部新增 source filter chip `[All] [Log] [Network] [Nav] [DB]`，預設 All；filter 順帶解決 Console 原本缺的過濾 / errors-only 需求。
- 移除 `dio_interceptor.dart` 中 network 的複製式 `LogLevel.debug` log（`onResponse` / `onError` 兩處）。
- 移除 `navigator_observer.dart` 中 nav 的複製式 `LogLevel.warning` log（`_record()` 一處）。
- 保留 `logEntries` getter 與舊 console 行為（filter 切 `Log` only 即還原）。

### Out-of-Scope（明確排除）

- **敏感資料遮罩**：已切成獨立後續工作，不在本功能範圍。
- **buffer 合併成單一資料源**：四個 buffer 維持各自獨立（各 500 格），混合只發生在渲染讀取當下——這正是解決「配額互吃」的關鍵設計，不可改為合併。
- **RingBuffer 效能優化**：500 格非真問題，不在本次處理。
- **獨立的 Timeline tab**：brainstorm #2 做法 B 曾構想新增獨立 Timeline 視圖；本功能直接把混合時序軸做進 Console，已取代「獨立 Timeline tab」的需求，故不另開 tab。

---

## 4. 向後相容性聲明

本功能定位為「既有 Console 的升級」，必須維持向後相容：

- **公開 API 保留**：`FlutterInspector.logEntries`（讀 log buffer）與 `clearLogs()` 等既有 getter / 方法語意不變，既有依賴它們的宿主程式碼不受影響。
- **舊觀感可還原**：source filter 切到 `Log` only 即還原為「只看 log buffer」的升級前觀感（差別僅在於不再有 network / nav 的鏡射雜訊——而那本來就是要修掉的劣化）。
- **行為改變的範圍受控且為正向**：移除鏡射後，唯一「行為改變」是 Console 預設不再混入偽造 level 的 network / debug 與 nav / warning 字串 log；這些資訊改由時序軸從各自 buffer 直接、且以正確語意呈現，資訊不減反增，且 level 語意被修正。
- **其他 tab 不受影響**：Network / Navigator / Database 三個 tab 的既有呈現與資料來源完全不動。

---

## 5. 與現況的查證對照（規格依據）

| 規格描述 | 現況事實（已逐檔核對） | 一致性 |
|---|---|---|
| interceptor 複製式 `debug` log（兩處） | `dio_interceptor.dart` `onResponse` 與 `onError` 各一處 `_inspector.log(..., level: LogLevel.debug)` | ✅ 一致 |
| observer 複製式 `warning` log（一處） | `navigator_observer.dart` `_record()` 一處 `_inspector.log(..., level: LogLevel.warning)`，class doc 明載刻意鏡射 | ✅ 一致 |
| db 完全沒鏡射 | `FlutterInspector.database()` 只寫 `_registry.database`，無 `log()` 呼叫 | ✅ 一致 |
| 四個 buffer 各自獨立、各 500 格 | `InspectorRegistry` 四個 inspector 以同一 `bufferSize`（預設 500）各自建立，無合併 | ✅ 一致 |
| 四個 model 皆有排序鍵 `timestamp` | `LogEntry` / `NetworkEntry` / `NavigatorEntry` / `DatabaseEntry` 皆有 `final DateTime timestamp` | ✅ 一致 |
| 向後相容基礎存在 | `FlutterInspector.logEntries` getter 存在（讀 `_registry.log.entries`），Console tab 現直接渲染它 | ✅ 一致 |

> 查證結論：規格描述與現況**完全一致**，未發現任何不符。

---

## 6. 規格出口條件

本規格通過確認的標準：

- US-1 ～ US-5 的驗收條件被接受為「可測試、可驗收」。
- 範圍邊界（特別是「不合併 buffer、不複製資料、移除鏡射、預設 All」這四項定稿決策）被確認。
- 向後相容性聲明（`logEntries` getter 保留、filter 切 Log only 還原舊觀感）被確認。

確認後進入 STAGE 0b（實作計畫），屆時才細化：時序軸列的資料表示（指標包裝的形狀）、四 buffer merge-sort 的讀取與排序邏輯、filter chip 的 UI 與狀態管理、各來源列的詳情跳轉接線，以及對應的 TDD 任務拆解與逐檔異動清單。
