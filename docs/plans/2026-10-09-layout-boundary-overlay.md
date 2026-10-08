# 實作計畫：§P28 視覺化排版邊界切換 (Layout Boundary Overlay)

## 資料結構/全域影響 (Data Structures / Global Impact)
- **無狀態落地**：純記憶體切換，不使用 `SharedPreferences`，每次重啟自動重置。符合實用主義，拒絕不必要的複雜度。
- **無侵入性**：純視覺輔助功能，不寫入任何 log，不污染現有的監控數據或時間軸。
- **全域影響**：只依賴 Flutter 原生的 `debugPaintSizeEnabled` 旗標（來自 `package:flutter/rendering.dart`），不自己造輪子（不手寫 Overlay/CustomPaint）。
- **編譯模式防護**：受 `kDebugMode || kProfileMode` 保護，確保 Release 模式完全不存在此邏輯，絕不破壞用戶空間。

## 檔案異動清單 (Files to Change)
1. `lib/src/ui/dashboard/dashboard_modal.dart`
   - 在 `DashboardModal` 的 `AppBar.actions` 區塊中加入切換按鈕。
   - 新增 `_LayoutBoundaryToggleButton` (私有 StatefulWidget) 來管理當前狀態。

## 任務拆分 (Tasks)
1. **實作切換元件 `_LayoutBoundaryToggleButton`**
   - 讀取原生 `debugPaintSizeEnabled` 決定初始 Icon 狀態。
   - 點擊時切換 `debugPaintSizeEnabled` 的布林值。
   - 呼叫 `RendererBinding.instance.reassembleApplication()` 強制全域重繪，讓排版邊界立即生效。
2. **整合至 Dashboard**
   - 將該元件加入 `DashboardModal` 的 `AppBar` 右側 actions 列表（建議放在原有的分享匯出按鈕旁邊）。
   - 使用 `if (kDebugMode || kProfileMode)` 條件式包裝按鈕，確保它在 Release 模式下被徹底剔除。
