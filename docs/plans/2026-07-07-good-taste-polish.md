# 實作計畫：階段三 消滅邊界情況 (Good Taste Polish)

## 目標
依照 architecture report 的階段三指示，整理 UI 中散落的硬編碼 const 邊距、字體、顏色等樣式，統一移至 `InspectorTheme`。同時確認代碼中不存在危險的 `.firstWhere` 呼叫。

## 任務拆分

### Task 1: 確認 firstWhere 情況
* **內容**：全域搜尋 `lib/src/` 內的 `firstWhere`。
* **狀態**：✅ 已完成。搜尋結果顯示 `lib/src/` 中沒有使用 `firstWhere`。

### Task 2: 建立 InspectorTheme 基礎類別
* **內容**：建立 `lib/src/ui/theme/inspector_theme.dart`。
* **定義**：
  * **Spacing**: `spacingXs`, `spacingSm`, `spacingMd`, `spacingLg` 
  * **Padding**: 對應 spacing 的 `paddingXs` 等。
  * **Colors**: `textMuted`, `errorColor`, `warningColor`, `infoColor`, `successColor`。
  * **TextStyles**: `monospaceStyle`, `boldStyle`, `mutedStyle`。

### Task 3: 替換現有 UI 元件中的硬編碼 (一)
* **內容**：修改 `DatabaseTab`, `TableRowsView`。
* **修改**：將 `const EdgeInsets.all(...)`, `Colors.grey`, `TextStyle(fontWeight: FontWeight.bold)` 替換為 `InspectorTheme` 的對應靜態變數。

### Task 4: 替換現有 UI 元件中的硬編碼 (二)
* **內容**：修改 `ConsoleTab`, `NetworkTab`, `NavigatorTab` 及對應的 Detail View。
* **修改**：替換相關 padding、SizedBox、Colors。同時將 NetworkDetailView 裡的 status color function 收斂至 Theme 或單獨函數，消除 `Colors.red` 等硬編碼。

### Task 5: 替換 Widget 中的硬編碼 (三)
* **內容**：修改 `lib/src/ui/widgets/` 下的元件（`error_card.dart`, `detail_section.dart`, `key_value_table.dart`）。
* **修改**：套用 `InspectorTheme` 樣式。
