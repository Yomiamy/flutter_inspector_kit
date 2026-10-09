# RenderFlex 錯誤視覺化解析 (RenderFlex Error Context)

## What & Why
在 Flutter 開發與測試過程中，最常見且令人困擾的版面配置異常莫過於「A RenderFlex overflowed by X pixels」錯誤。當 UI 元件（如 `Row` 或 `Column`）的內容超出約束邊界時，Flutter 框架會拋出錯誤，並在 Console 輸出長篇日誌堆疊。
目前 Inspector 的 ConsoleTab 與 LogDetailView 僅能將其視為普通的 `LogLevel.error` 純文字日誌，使用者必須在一長串文字中人眼尋找超出幾像素（pixels）以及是在哪個方向（如 bottom 或 right）超出，排查繁瑣且無法一眼掌握視覺脈絡。

本功能在不破壞既有資料模型與日誌管線的前提下，於 `UncaughtErrorHandler` 攔截到 Flutter 錯誤時，針對 RenderFlex 溢出訊息進行輕量正則提取，將結構化資訊（例如 `overflowPixels` 與 `overflowDirection`）附加到既有的 `LogEntry.data` 中。同時在 ConsoleTab 的列表列 (`_LogEntryRow`) 與 LogDetailView 中，為 RenderFlex 溢出日誌提供專屬的視覺標籤 (Badge) 與高亮指示，大幅降低 QA 與開發者的問題辨識成本。

## 使用者故事 (User Stories)
- 身為一位測試工程師 (QA)，當我在 App 內觸發排版溢出（如鍵盤彈起擠壓或長文字撐開）時，我希望在 Console 列表能一眼看到專屬的「Overflow」標籤以及溢出像素與方向（例如 `Overflow: 24.0px bottom`），以便截圖或快速確認問題。
- 身為一位 Flutter 開發者，當我點進溢出錯誤的 LogDetailView 時，我希望在結構化資料或專屬資訊區塊中清楚看到解析後的溢出細節，而不需要在一大段錯誤字串中手動尋找關鍵數字。
- 身為一位套件維護者，我希望解析邏輯具備完全的容錯回退能力（Fallback），即使 Flutter 未來微調錯誤文字格式或解析失敗，也絕對不拋出例外，維持原始純文字日誌正常輸出，確保對現有日誌系統零破壞。

## 驗收條件 (Acceptance Criteria)
1. **錯誤訊息輕量解析 (UncaughtErrorHandler)**:
   - 當 `UncaughtErrorHandler` 捕獲 Flutter 錯誤且訊息包含 `RenderFlex overflowed by <N> pixels on the <direction>` 時，提取溢出像素值（如 `double` 或字串）與方向（如 `bottom`, `right`, `left`, `top` 等）。
   - 將提取結果附加至 `LogEntry.data`（例如 `isRenderFlexOverflow: true`, `overflowPixels: 24.0`, `overflowDirection: 'bottom'`）。
   - 解析需置於安全保護下，若正規表示式未命中或格式不符，靜默忽略並不中斷正常日誌記錄流程。
2. **列表視覺化標籤 (ConsoleTab)**:
   - 在 `_LogEntryRow` 中，當 `entry.data` 包含 RenderFlex 溢出特徵時，顯示醒目的溢出標籤 Badge（例如紅色/橘色背景的緊湊標籤，顯示 `RenderFlex 24px bottom` 或類似字樣）。
3. **詳細視圖結構化呈現 (LogDetailView)**:
   - 在 `LogDetailView` 中，除 `JsonTreeViewer` 自動展示 `data` 外，可在 General 區塊或專屬標籤直觀呈現溢出摘要。
4. **測試覆蓋**:
   - 單元測試：驗證 `UncaughtErrorHandler` 能正確解析典型的 RenderFlex 錯誤字串並寫入 `data`；非溢出錯誤則保持原樣。
   - Widget 測試：驗證帶有 RenderFlex 溢出 metadata 的 `LogEntry` 在 `ConsoleTab` 列表中正確渲染溢出標籤。

## 範圍邊界 (Scope & Boundaries)
- **Included (包含)**:
  - `UncaughtErrorHandler` 的正則解析邏輯與 metadata 附加。
  - `_LogEntryRow` 的專屬溢出標籤顯示。
  - 對應的單元與 Widget 測試。
- **Excluded (排除)**:
  - 不建立全新的模型類別或資料庫表格（嚴格復用既有 `LogEntry.data`）。
  - 不介入或覆寫 Flutter 原生 `ErrorWidget` 的繪製外觀（例如斑馬線警告條）。
  - 不自動跳轉至對應 Widget 原始碼位置（保持單純排查輔助）。
