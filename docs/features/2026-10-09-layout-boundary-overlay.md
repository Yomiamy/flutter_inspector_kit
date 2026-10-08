# 規格：§P28 視覺化排版邊界切換 (Layout Boundary Overlay)

## 📖 使用者故事 (User Story)
作為 QA 或開發者，我希望能在裝置端直接打開排版邊界（Debug Paint），以便在發現跑版時能用截圖精準指出是哪個 Widget 的尺寸溢出，而不用重新接線掛載 DevTools。

## ✅ 驗收條件 (Acceptance Criteria)
1. **控制入口**：在 Dashboard（例如 AppBar 或獨立設定區）新增一個排版邊界切換開關。
2. **狀態綁定**：切換時，直接操作原生 `rendering` 函式庫的全域變數（如 `debugPaintSizeEnabled` 與 `debugPaintBaselinesEnabled`）。
3. **即時重繪**：切換狀態後，必須強制觸發全域重繪（例如呼叫 `RendererBinding.instance.reassembleApplication()`），讓排版邊界立刻在畫面上顯現。
4. **零污染**：這只是純視覺的輔助工具，絕不將開啟或關閉的動作寫入任何 Log 或干擾既有的 Timeline 紀錄。

## 🚫 範圍邊界 (Out of Scope / Edge Cases)
1. **編譯模式防禦**：`debugPaintSizeEnabled` 在 Release 模式下不存在或無作用。必須用 `kDebugMode` 或 `kProfileMode` 進行防禦，在 Release 模式下直接隱藏此開關，徹底消滅無效操作與潛在的編譯錯誤。
2. **狀態不落地**：不將開關的狀態進行本地持久化儲存（不用 SharedPreferences）。重啟後預設重置即可，拒絕引入任何狀態維護的複雜度。
3. **不重新造輪子**：嚴禁手寫任何 `CustomPaint` 或 `Overlay` 來自行繪製框線，全盤交由 Flutter 既有的底層旗標處理，這才叫做實用主義。
