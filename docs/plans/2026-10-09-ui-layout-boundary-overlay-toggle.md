# 實作計畫：視覺化排版邊界切換 (UI Layout Boundary Overlay Toggle)

## 實作方向與 Trade-off 分析
1. **方案 A：自訂 Overlay 繪製邊界**
   - *優點*: 可客製化邊框樣式與顏色。
   - *缺點*: 需透過 RenderTree 遍歷與手動計算 Global Position 繪製自訂邊框，代碼量巨大且容易發生座標偏移、效能不佳、維護成本極高。
2. **方案 B：直接操作 Flutter 內建 `debugPaintSizeEnabled`（選定方案）**
   - *優點*: 零新模型、零自訂繪圖邏輯。完全復用 Flutter 官方引擎自帶的排版輔助線機制。切換時調用 `WidgetsBinding.instance.reassembleApplication()` 即刻全域重繪。
   - *缺點*: 依賴 Flutter Framework 除錯旗標，在 Release 模式下無法運作。但本套件本就定位為開發/測試除錯工具，且我們以 `!kReleaseMode` 作為守衛，在 Release 模式下乾淨隱藏。

**最終選擇**: 採用方案 B。遵循 Linus 模式「好品味」原則——不重新發明輪子，直接操作既有原生旗標。

## 資料結構與架構設計
- **核心資料**: Flutter 原生 `debugPaintSizeEnabled`（全域布林值，位於 `package:flutter/rendering.dart`）。
- **元件結構**:
  - `_LayoutBoundaryToggleAction`: 一個私有的 `StatefulWidget`，位於 `lib/src/ui/dashboard/dashboard_modal.dart`。
  - 根據 `debugPaintSizeEnabled` 顯示對應的 `Icon`（開：`Icons.grid_on` 搭配 primary 色彩高亮；關：`Icons.grid_off_outlined`）。
  - 點擊時反轉 `debugPaintSizeEnabled` 並呼叫 `WidgetsBinding.instance.reassembleApplication()`。
- **守衛條件**:
  - `if (!kReleaseMode)` 條件式加入 `DashboardModal` 的 `AppBar.actions`。

## 檔案異動清單
1. `lib/src/ui/dashboard/dashboard_modal.dart`:
   - 引入 `package:flutter/foundation.dart` 與 `package:flutter/rendering.dart`。
   - 在 `DashboardModal.build` 的 `AppBar.actions` 列表加入 `if (!kReleaseMode) const _LayoutBoundaryToggleAction()`。
   - 新增 `_LayoutBoundaryToggleAction` 獨立類別元件。
2. `test/ui/dashboard/layout_boundary_toggle_test.dart` (新增):
   - 測試 `_LayoutBoundaryToggleAction` 在未開啟時點擊能啟用 `debugPaintSizeEnabled`。
   - 測試再次點擊能停用 `debugPaintSizeEnabled`。
   - 測試 Tooltip 與 Icon 狀態隨旗標即時更新。
   - 確保 `tearDown` 重置 `debugPaintSizeEnabled = false` 不污染環境。

## 任務拆分
1. **任務 1：實作 Dashboard Modal 的排版邊界切換按鈕**
   - 檔案: `lib/src/ui/dashboard/dashboard_modal.dart`
   - 動作:
     - 匯入 `package:flutter/foundation.dart` 與 `package:flutter/rendering.dart`。
     - 在 `DashboardModal` 的 `AppBar.actions` 中加入 `if (!kReleaseMode) const _LayoutBoundaryToggleAction()`。
     - 宣告獨立的 `_LayoutBoundaryToggleAction` `StatefulWidget`，處理點擊切換、`debugPaintSizeEnabled` 操作、`WidgetsBinding.instance.reassembleApplication()` 刷新，以及高亮 Icon 與 Tooltip 提示。
2. **任務 2：撰寫 Widget 與功能單元測試**
   - 檔案: `test/ui/dashboard/layout_boundary_toggle_test.dart`
   - 動作:
     - 建立測試驗證 `_LayoutBoundaryToggleAction` 的渲染。
     - 模擬點擊並驗證 `debugPaintSizeEnabled` 狀態切換。
     - 驗證點擊前後 Tooltip 與 Icon 的狀態變化。
     - 驗證 tearDown 清理。
