# 視覺化排版邊界切換 (UI Layout Boundary Overlay Toggle)

## What & Why
QA 與開發者在實機或模擬器測試時，常遇到 UI 跑版、文字被截斷、元件重疊或尺寸異常等視覺問題。然而在未接線的情況下，測試者很難精確指出是哪一層 Widget 的尺寸或排版約束 (Constraints) 出現偏差，通常只能截圖回報，開發者再額外連接電腦開啟 Flutter DevTools 的 Debug Paint 來排查，溝通與重現成本高昂。

Flutter 原生在 `package:flutter/rendering.dart` 內建了 `debugPaintSizeEnabled` 等除錯旗標，能在畫面上繪製所有 RenderBox 的邊界、邊距與對齊輔助線。本功能在 Inspector 的 Dashboard AppBar 中提供一個快速切換按鈕，讓 QA 與開發者無需電腦與 DevTools，即可在實機上直接開啟／關閉排版輔助線，並即時強制重繪畫面。

## 使用者故事 (User Stories)
- 身為一位測試工程師 (QA)，我希望在 Inspector Dashboard 的 AppBar 上能直接點擊按鈕開啟「排版邊界 (Layout Boundaries)」，讓 App 畫面立即繪出每個元件的邊界線與 Padding，使我截圖回報 UI bug 時能提供精確的排查證據。
- 身為一位開發者，我希望開關排版邊界時能夠即時反映在畫面上（呼叫 `RendererBinding.instance.reassembleApplication()`），且關閉時邊界能乾淨消失，不需要重新編譯或重啟 App。
- 身為一位專案架構師，我希望這項功能在 Release 模式 (`kReleaseMode`) 下自動隱藏或停用，不發明冗餘的自訂繪製抽象，完全復用 Flutter 原生能力，確保對生產環境零副作用。

## 驗收條件 (Acceptance Criteria)
1. **Dashboard AppBar Action**:
   - 在 `DashboardModal` 的 `AppBar.actions` 中，新增排版邊界切換按鈕（如 `IconButton`，具有適當的 Tooltip 如 "Toggle layout boundaries"）。
   - 按鈕圖示依據當前 `debugPaintSizeEnabled` 狀態變化（例如未開啟顯示 `Icons.grid_off_outlined` 或 `Icons.layers_outlined`，開啟時顯示 `Icons.grid_on` 或 `Icons.layers`，並具備色彩或狀態高亮）。
2. **切換邏輯與即時重繪**:
   - 點擊按鈕時反轉 `debugPaintSizeEnabled` 的布林值。
   - 切換後調用 `RendererBinding.instance.reassembleApplication()`，確保當前 Flutter 畫面的所有 RenderObject 立即重新繪製輔助線。
3. **模式安全防護**:
   - 在 Release 模式下 (`kReleaseMode`)，不渲染該切換按鈕，避免無效操作與潛在的未定義行為。
4. **測試覆蓋**:
   - 驗證按鈕點擊後 `debugPaintSizeEnabled` 狀態確實切換。
   - 驗證點擊後有正確通知或觸發應用程式重繪。
   - 驗證在模擬環境下的 Widget 渲染與點擊交互。

## 範圍邊界 (Scope & Boundaries)
- **Included (包含)**:
  - `DashboardModal` 頂部工具列的操作按鈕與狀態指示。
  - `debugPaintSizeEnabled` 的切換與 `reassembleApplication()` 重繪調用。
  - Release 模式環境檢查。
  - 對應的單元與 Widget 測試。
- **Excluded (排除)**:
  - 自行實作客製化的 Canvas 邊界繪圖邏輯（嚴格復用 Flutter 既有能力，避免過度工程）。
  - 將開關狀態持久化至本地儲存（除錯開關以當次 session 記憶體為準）。
  - 記錄到 Timeline 或日誌流（純視覺操作，不產生日誌噪音）。
