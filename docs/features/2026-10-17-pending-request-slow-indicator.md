# 功能規格：無回應請求慢查詢標記與狀態指示（§Z1-3 / §P8 既有缺陷修正）

- **日期**：2026-10-17
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §Z1 第 3 項（既有缺陷 · 一直沒回應的請求永遠不會被標 🐢 SLOW）
- **關聯**：§P8 網路請求慢查詢標記（PR #111 / Issue #110）
- **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位使用 Flutter Inspector 排查網路效能的開發者，
> 我希望**仍在等待回應（Pending）且耗時已超過閾值的請求也能被標記為 `🐢 SLOW`，並在列表顯示如 `no response · 12s` 的已耗時間**，
> 這樣當後端服務 hang 住或網路無回應時，我能第一時間在 Network 與 Console Tab 捕捉到最嚴重的卡頓請求，而不是因為請求尚未結束而被系統當作正常請求忽略。

### 為什麼這件事需要修

PR #111 實現了 §P8 慢查詢標記功能，依據 `FlutterInspector.slowRequestThreshold`（預設 2 秒）在 NetworkTab 列表、摘要條與 ConsoleTab 時間軸上標示 `🐢 SLOW`。
然而當時的實作判定式嚴格要求 `entry.duration != null && entry.duration! >= slowRequestThreshold`。
在真實應用場景中：
1. Dio 預設並未設定 timeout；伺服器 hang 住或閘道未回傳時，請求會無限期處於 pending 狀態。
2. 進行中的請求其 `duration` 恆為 `null`，導致最嚴重的無回應延遲反而在各處判定中被短路漏標。
3. 列表行上的狀態僅顯示靜態且模糊的 `Pending · - ms`，無法得知該請求已經懸掛了多久。

---

## 2. 範圍邊界

### ✅ 做

- 在 `NetworkEntry` 上新增 `Duration elapsedAt(DateTime now) => duration ?? now.difference(timestamp);`
- 在 `network_tab.dart` 的 `_EntryTile` 中：
  - 以 `entry.elapsedAt(now) >= slowRequestThreshold` 判定是否顯示 `🐢 SLOW` 標籤。
  - 當請求尚未完成（`!entry.isComplete`）時，狀態標籤顯示為 `no response · ${entry.elapsedAt(now).inSeconds}s`，且副標題中省略無意義的 `- ms` 佔位符。
- 在 `network_tab.dart` 的 `_NetworkErrorSummaryHeader` 中：
  - 計算 `slowCount` 時改用 `entry.elapsedAt(now) >= slowRequestThreshold`，使懸掛超過閾值的 pending 請求一併計入摘要計數。
- 在 `console_tab.dart` 的 `_NetworkEventTile` 中：
  - 以 `entry.elapsedAt(now) >= inspector.slowRequestThreshold` 判定是否顯示 `🐢 SLOW` 標籤。
- 補充並更新單元測試與 Widget 測試（包含已完成與未完成請求的耗時推導與視覺標記斷言）。
- 更新 `CHANGELOG.md`。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 引入 Timer 每秒刷新 UI | 違反本套件輕量與零觀察者效應原則；不主動啟動無謂計時器消耗 CPU，在既有刷新或手動查看時計算即可 |
| 斷言請求已失敗或命名為 `STALLED` | 請求尚未完成，可能只是網路慢或伺服器處理時間長，使用中性的 `no response · Xs` 精確表達「尚未收到回應」的事實 |
| 自動中斷或逾時請求 | Inspector 僅做被動監控與呈現，絕不干預宿主 App 的網路連線生命週期 |
| 修改 `NetworkDetailView` 的 Status 欄位 | DetailView 專注於顯示原始網路協議元數據，維持既有格式與細節 |

---

## 3. 設計決策

**1. 資料結構與耗時計算（Good Taste）**：
不為 pending 請求新增複雜狀態，在 `NetworkEntry` 提供單一純函式：
```dart
Duration elapsedAt(DateTime now) => duration ?? now.difference(timestamp);
```
- 若請求已完成（`duration != null`），回傳實際的往返耗時。
- 若請求未完成（`duration == null`），以傳入的參考時間計算已等待時間。
- 消除 `if (duration != null)` 的條件特例，統一調用處的評估邏輯。

**2. 語意精確的視覺標示**：
- 未完成請求狀態：`no response · ${entry.elapsedAt(now).inSeconds}s`
- 副標題結構：
  - 完成時：`<status> · <duration> ms · <size> · <time>`
  - 未完成時：`no response · <elapsed>s · <size> · <time>`（去除無意義的 `- ms`）

---

## 4. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | `NetworkEntry.elapsedAt(now)` 在 `duration != null` 時回傳 `duration`，在 `duration == null` 時回傳 `now.difference(timestamp)` | 單元測試斷言 |
| 2 | 當請求未完成且發起時間距今已超過 `slowRequestThreshold` 時，NetworkTab 的項目顯示 `🐢 SLOW` | Widget 測試驗證 |
| 3 | 當請求未完成時，NetworkTab 項目的副標題顯示 `no response · <N>s`，且無 `- ms` 字樣 | Widget 測試驗證 |
| 4 | NetworkTab 的 Error Summary 慢查詢計數將超時的未完成請求一併計入 | Widget 測試驗證 |
| 5 | 當請求未完成且超時，ConsoleTab 的網路事件項目顯示 `🐢 SLOW` | Widget 測試驗證 |
| 6 | 所有既有測試全數通過（`flutter test`） | 指令執行驗證 |
| 7 | 程式碼靜態分析無任何 warning 或 error（`flutter analyze`） | 指令執行驗證 |
