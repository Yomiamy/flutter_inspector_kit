# 功能規格：ConsoleTab 篩選標籤動態數量徽章（§P41）

- **日期**：2026-11-03
- **來源**：`docs/brainstorm/2026-10-31-features-brainstorm.md` §P41（【控制台互動】篩選標籤動態數量徽章）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐

---

## 1. 使用者故事

> 作為一位使用 `flutter_inspector` 進行 App 調試的開發者，當面臨大量且跨來源（Logs、Network、Navigation、Database）的混合事件流時，
> 我希望**控制台（ConsoleTab）頂部橫向滾動的所有 FilterChip 標籤能即時顯示各分類的動態事件數量徽章（如 `All (50)`、`Log (20)`、`Network (12)`、`📌 Bookmarks (2)`、`⚡ Errors only (4)`）**，
> 這樣我無需手動逐一切換標籤點擊查看，就能一眼掌握整個緩衝區中各來源事件與異常的分佈概況。

### 為什麼需要這項改進

目前 `ConsoleTab` 頂部的 `FilterChip` 標籤（包含 `All`、`Log`、`Network`、`Nav`、`DB`、`📌 Bookmarks`、`⚡ Errors only` 以及各 `LogLevel` 標籤）均為純靜態文字。
在真實除錯場景中：
1. 開發者無法預先得知切換至 `DB` 是否有資料，常常點進去才發現是空的。
2. 當發生問題時，無法直接確認當前是否有 `Error` 或失敗的網路請求，必須點擊 `⚡ Errors only` 才能確定。
3. 增加動態數量徽章能夠提供即時的全局可觀測性（Global Observability），顯著降低排查過程中的無效操作。

---

## 2. 範圍邊界

### ✅ 做

1. **頂部所有 FilterChip 動態數量標籤**：
   - `All`: 顯示 `All (<總事件數>)`。
   - `TimelineSource` 標籤：
     - `Log (<Log 數>)`
     - `Network (<Network 數>)`
     - `Nav (<Nav 數>)`
     - `DB (<DB 數>)`
   - `📌 Bookmarks`: 顯示 `📌 Bookmarks (<書籤數>)`。
   - `⚡ Errors only`: 顯示 `⚡ Errors only (<失敗與錯誤總數>)`（包含 `LogLevel.warning`、`LogLevel.error` 與 `NetworkEntry.isFailed`）。
   - 各 `LogLevel` 標籤（`logLevelLabels` 中的 `Verbose`、`Debug`、`Info`、`Warning`）：
     - 顯示 `<Level名稱> (<該等級Log數>)`。
2. **純無狀態投影計算（好品味設計）**：
   - 在 `ConsoleTab.build` 中，基於未受當前標籤篩選約束的原始緩衝區快照（`widget.inspector.mergedTimeline(sources: _all)`），進行單次 O(N) 遍歷統計所有徽章計數。
   - 零額外 State 欄位、零計時器、零快取過期問題、零跨層耦合。
3. **邊界處理**：
   - 緩衝區為空或特定分類計數為 0 時，統一明確顯示 `(0)`（例如 `DB (0)`）。
   - 清除日誌（點擊垃圾桶圖示清空）後，徽章同步全部歸零。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 引入額外 Flutter `Badge` widget 或自訂角標繪製 | 直接於 FilterChip label 內嵌 `(count)` 文字，斯巴達式簡潔，相容所有 Material 樣式與無障礙，零額外 Widget 巢狀 |
| 徽章數量受關鍵字搜尋過濾器聯動縮減 | FilterChip 徽章之核心價值在於提供「全局緩衝區總覽」，若隨搜尋即時連動會造成排查者失去全景視野，且增加額外計算複雜度 |
| 新增持久化狀態或推播架構 | ConsoleTab 既有 `setState` 與 `_refresh` 即可完整覆蓋重建需求，維持無狀態純粹性 |

---

## 3. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | `ConsoleTab` 渲染時，`All` 標籤顯示正確的全部事件總數，如 `All (4)` | Widget 測試（`console_tab_test.dart`） |
| 2 | 各來源分類標籤顯示該來源之事件數量，如 `Log (1)`、`Network (1)`、`Nav (1)`、`DB (1)` | Widget 測試 |
| 3 | `📌 Bookmarks` 標籤顯示當前被標記為書籤的事件數量，書籤切換時動態更新 | Widget 測試 |
| 4 | `⚡ Errors only` 標籤顯示錯誤與失敗數量（含 error/warning 日誌與失敗請求），如 `⚡ Errors only (2)` | Widget 測試 |
| 5 | 各 `LogLevel` 標籤（`Verbose`, `Debug`, `Info`, `Warning`）顯示該等級的 Log 數量 | Widget 測試 |
| 6 | 緩衝區為空時，所有晶片標籤皆顯示 `(0)`，如 `All (0)`、`DB (0)` | Widget 測試 |
| 7 | 全部測試通過（`flutter test`）且靜態分析無新增警告（`flutter analyze lib/ test/`） | 指令執行驗證 |
