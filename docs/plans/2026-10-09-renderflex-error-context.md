# 實作計畫：RenderFlex 錯誤視覺化解析 (RenderFlex Error Context)

## 實作方向與 Trade-off 分析
1. **方案 A：自訂專屬錯誤類別 (RenderFlexErrorLogEntry)**
   - *優點*: 型別明確。
   - *缺點*: 破壞既有 `LogEntry` 與資料庫/日誌管線，增加不必要的類別繼承與特殊情況判斷，嚴重違反 Linus「好品味」原則與向後兼容性。
2. **方案 B：於攔截時輕量字串解析，注入既有 `LogEntry.data`（選定方案）**
   - *優點*: 零新模型、零 schema 變更。在 `UncaughtErrorHandler` 中以正規表示式安全解析溢出像素與方向，寫入 `LogEntry.data`。UI 透過讀取 `data` 鍵值渲染專屬視覺標籤，解析失敗時靜默退回原始文字日誌，完全不影響生產環境。
   - *缺點*: 依賴 Flutter 錯誤訊息字串格式。但 Flutter 對此經典錯誤訊息長年保持高度一致，且正則匹配失敗時無損降級，風險極低。

**最終選擇**: 採用方案 B。

## 資料結構與架構設計
- **核心資料**: 
  - 沿用 `LogEntry.data` (`Map<String, dynamic>`)。
  - 溢出欄位定義：
    - `isRenderFlexOverflow`: `bool` (`true`)
    - `overflowPixels`: `double` (例如 `24.0`)
    - `overflowDirection`: `String` (例如 `'bottom'`, `'right'`)
- **解析邏輯**:
  - 正則表達式：`r'A RenderFlex overflowed by (\d+(?:\.\d+)?) pixels on the (\w+)'` (不區分大小寫)。
  - 解析置於 `try-catch` 或條件防禦中，提取失敗時不附加欄位。
- **UI 呈現**:
  - `_LogEntryRow` (`lib/src/ui/dashboard/tabs/console_tab.dart`):
    - 若 `entry.data` 包含 `overflowPixels` 與 `overflowDirection`，在訊息上方或標題 Row 渲染專屬溢出標籤 Chip/Badge（例如 `Overflow: 24px bottom`）。
  - `LogDetailView` (`lib/src/ui/dashboard/tabs/console/log_detail_view.dart`):
    - 在 General 區塊增列 `DetailKeyValueRow.text('Overflow Context', ...)`。

## 檔案異動清單
1. `lib/src/core/uncaught_error_handler.dart`:
   - 增加私有或通用輔助解析函式 `_extractRenderFlexOverflow(String message)`。
   - 在 `_logFlutterError` 中，將解析結果合併至 `data`。
2. `lib/src/ui/dashboard/tabs/console_tab.dart`:
   - 於 `_LogEntryRow` 檢查 RenderFlex 溢出 metadata，並渲染專屬醒目標籤。
3. `lib/src/ui/dashboard/tabs/console/log_detail_view.dart`:
   - 於 General 區塊提供 RenderFlex 溢出上下文之文字展示。
4. `test/core/uncaught_error_handler_renderflex_test.dart` (新增):
   - 驗證 `UncaughtErrorHandler` 截獲 RenderFlex 溢出錯誤時正確解析 pixels 與 direction。
   - 驗證一般錯誤不會誤判。
5. `test/ui/dashboard/renderflex_badge_test.dart` (新增):
   - 驗證包含溢出資料的 `LogEntry` 能在 `ConsoleTab` 正確渲染標籤。

## 任務拆分
1. **任務 1：於 `UncaughtErrorHandler` 增加 RenderFlex 錯誤字串解析**
   - 檔案: `lib/src/core/uncaught_error_handler.dart`
   - 動作:
     - 實作溢出訊息正則匹配與解析。
     - 將解析出的 `isRenderFlexOverflow`、`overflowPixels`、`overflowDirection` 注入 `data`。
2. **任務 2：於 ConsoleTab 及 LogDetailView 呈現溢出標籤與資訊**
   - 檔案: `lib/src/ui/dashboard/tabs/console_tab.dart`, `lib/src/ui/dashboard/tabs/console/log_detail_view.dart`
   - 動作:
     - 在 `_LogEntryRow` 渲染溢出標籤 Badge。
     - 在 `LogDetailView` 的 General 區塊展示溢出資訊。
3. **任務 3：撰寫單元測試與 Widget 測試**
   - 檔案: `test/core/uncaught_error_handler_renderflex_test.dart`, `test/ui/dashboard/renderflex_badge_test.dart`
   - 動作:
     - 測試解析成功與失敗各情境。
     - 測試 UI 標籤渲染與非溢出日誌的乾淨共存。
