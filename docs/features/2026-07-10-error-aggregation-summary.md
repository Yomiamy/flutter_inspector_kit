# 功能規格：錯誤聚合摘要（Error Aggregation Summary）

> **來源**：[brainstorm #7](../brainstorm/2026-07-12-features-brainstorm.md)（`docs/brainstorm/2026-07-12-features-brainstorm.md` 第 131–135 行）
> **日期**：2026-07-10
> **狀態**：Draft — 待使用者確認

---

## 問題

同一個 `502 Bad Gateway` 每 30 秒被打一次 → `NetworkTab` 列表裡出現 500 條各自獨立的行。開發者/QA 被迫在一片紅色列表項中肉眼數數，無法秒判「這是持續故障還是偶發失敗」。

**核心矛盾**：buffer 存了 500 筆、每筆都有 `statusCode` 和 `errorType`——分類資訊完整，卻沒有任何人幫開發者做 `groupBy + count` 這件最基本的統計。

---

## 解決方案（一句話）

在 `NetworkTab` 頂部（搜尋欄與過濾 chips 之間）插入一列可展開收起的 **Error Summary 橫幅**，按 `(statusCode, errorType)` 分組，顯示「錯誤類別 × 次數 · 時間跨度」，一眼判斷故障模式。

---

## 使用者故事

### US-1：一眼看出故障全景
> 身為 Flutter 開發者，  
> 我打開 NetworkTab 時，若 buffer 中存在錯誤請求，  
> 我希望立即看到一列 Error Summary 橫幅，把錯誤按類型聚合顯示，  
> 好讓我在 2 秒內判斷「持續故障 vs 偶發錯誤」。

### US-2：點擊摘要卡片快速過濾
> 身為 Flutter 開發者，  
> 我點擊 Error Summary 中的某個錯誤分組卡片，  
> 我希望下方列表自動過濾為該組的所有請求，  
> 好讓我直接查看該類錯誤的具體請求而不用手動調 FilterChip。

### US-3：無錯誤時不添亂
> 身為 Flutter 開發者，  
> 當 buffer 中不存在任何錯誤請求時，  
> Error Summary 橫幅應完全不顯示，  
> 不佔空間、不添噪音。

---

## 驗收條件

| # | 條件 | 驗證方式 |
|---|------|---------|
| AC-1 | Error Summary 橫幅出現在 `_SearchBar` 下方、`_FilterChips` 上方 | 視覺確認 + widget test |
| AC-2 | 按 `(statusCode, errorType)` 分組：同 statusCode + 同 errorType 歸為一組；statusCode 為 null 時以 errorType 為唯一 key | unit test |
| AC-3 | 每組顯示：分類標籤（如 `502 Bad Gateway`、`Timeout`）、出現次數（`× N`）、最早與最近發生時間 | 視覺確認 + widget test |
| AC-4 | 點擊某組卡片 → 下方列表過濾為該組的請求（套用對應的 statusCode/errorType 過濾條件） | widget test |
| AC-5 | 無錯誤請求時橫幅完全不渲染（`entries.where(isError).isEmpty` → 不佔空間） | widget test |
| AC-6 | 清除 buffer（`clearNetwork()`）後橫幅消失 | widget test |
| AC-7 | `isReplay == true` 的重送請求若是錯誤，一樣被計入聚合 | unit test |
| AC-8 | 橫幅區域可展開/收起（默認展開），收起後只顯示一行「N errors」摘要 | widget test |
| AC-9 | 聚合邏輯為**純函式**（`aggregateNetworkErrors()`），可獨立 unit test | unit test |
| AC-10 | 不新增任何 pub 依賴 | pubspec.yaml 對比 |

---

## 設計摘要

### 資料結構

```
聚合 key：(int? statusCode, DioExceptionType? errorType)
聚合結果：NetworkErrorGroup {
  statusCode: int?
  errorType: DioExceptionType?
  count: int
  firstSeen: DateTime
  lastSeen: DateTime
  label: String          // 人類可讀標籤（如 "502 Bad Gateway"、"Connection Timeout"）
}
```

- **不複製資料**：聚合函式從 `NetworkInspector.entries` snapshot 做 groupBy，產出 `List<NetworkErrorGroup>`。不額外存資料、不引入第二份真相。
- **錯誤判定**：複用 `NetworkStatusGroup.matches()` 已有的邏輯——`clientError`（4xx）、`serverError`（5xx）、`failed`（transport error, statusCode == null）。

### 聚合規則

1. 遍歷 `entries`，取所有 `isError` 的 entry（`error != null || (statusCode != null && statusCode >= 400)`）
2. 以 `(statusCode, errorType)` 為 key 做 `groupBy`
3. 每組算 `count`、`firstSeen`（最早 timestamp）、`lastSeen`（最近 timestamp）
4. 結果按 `count` 降序排列（最頻繁的排最前）

### UI 位置

```
NetworkTab Column:
  ├── _SearchBar             ← 既有
  ├── _ErrorSummaryBanner    ← 🆕 新增（條件渲染：有 error 時才出現）
  ├── _FilterChips           ← 既有
  ├── Divider                ← 既有
  └── Expanded(ListView)     ← 既有
```

### UI 樣式

- **橫幅容器**：水平可滾動的 `SizedBox(height: ~72)` + `ListView(horizontal)`
- **每組卡片**：小型 `Card`，內含分類 icon + 標籤 + `× N` 計數 + 時間跨度
- **顏色**：沿用 `InspectorTheme.statusColor()` 的既有色彩映射
- **展開/收起**：默認展開；用 `ExpansionTile` 或自製 toggle，收起後只顯示一行文字「⚠ N errors (M types)」

### 點擊互動

卡片被點擊時：
1. 把該組的 `statusCode` 和/或 `errorType` 轉換為對應的 `NetworkStatusGroup` + 額外條件
2. 套用到 `_NetworkTabState` 的 `_statusGroups`（已有的 FilterChip state）
3. 下方列表自動過濾為該組的請求

---

## 範圍邊界

### 在範圍內

- 網路請求（`NetworkEntry`）的錯誤聚合
- `NetworkTab` 內的 UI 橫幅
- 聚合純函式 + 對應 unit test
- widget test 驗證渲染與互動

### 明確排除

| 排除項 | 理由 |
|--------|------|
| Log 錯誤（`LogLevel.error`）的聚合 | 保持 scope 最小。Log 錯誤有不同結構（message-based），未來可獨立實作 |
| Console tab 的 error summary | 同上，跨 tab 功能未來再議 |
| 聚合結果的匯出/分享 | 留給 #3 一鍵診斷報告統一處理 |
| 即時通知/Badge | 已有 `NetworkNotifier` + `AlertThrottler`，不在此功能重複 |
| 歷史趨勢圖/時間線圖表 | 過度工程。數字 + 首末時間已足夠判斷「持續 vs 偶發」 |
| 自定義分組 key | `(statusCode, errorType)` 是最自然的分類，不需要使用者配置 |

---

## 破壞性分析

| 面向 | 風險 | 緩解 |
|------|------|------|
| 既有 `NetworkTab` UI | 插入新元件可能影響佈局 | 條件渲染 + 純擴充式改動，無 error 時 zero impact |
| `NetworkFilter` / `applyNetworkFilter()` | 點擊卡片需操作 filter state | 透過已有的 `_toggle()` 機制操作，不改 `NetworkFilter` 介面 |
| 效能 | 500 筆 entries 的 groupBy 計算 | O(N) 遍歷，N ≤ 500（buffer 容量），每次 `build` 最多花 ~1ms，完全可接受 |
| Public API | 無新增 public API | 聚合函式放在 `src/utils/`，不從 barrel file 匯出 |

---

## 核心判斷

✅ **值得做**。

理由：這是純粹的「展示層優化」——資料全在、分類邏輯全在（`NetworkStatusGroup.matches()`、`InspectorTheme.statusColor()`），差的只是一個 `groupBy + count`。成本低、視覺衝擊大、排查價值明確。

---

## 相關文件

- Brainstorm 原始描述：[2026-07-12-features-brainstorm.md#7](../brainstorm/2026-07-12-features-brainstorm.md)
- 可複用的 filter 模式：[network_utils.dart](../../lib/src/utils/network_utils.dart)
- 可複用的 UI 元件：[detail_section.dart](../../lib/src/ui/widgets/detail_section.dart)
- 既有 tab 佈局參考：[network_tab.dart](../../lib/src/ui/dashboard/tabs/network_tab.dart)
