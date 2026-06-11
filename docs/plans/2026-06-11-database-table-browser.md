# 實作計畫：Database Table Browser（SQL administrator 式表格瀏覽）

- **日期**：2026-06-11
- **功能規格**：`docs/features/2026-06-11-database-table-browser.md`
- **狀態**：STAGE 0b — 待確認
- **已確認決策**：D1 直接取代（舊流水帳移除、舊測試改寫保覆蓋率）｜D2 core 介面 + example SQLite adapter｜D3 200 列 + Load more｜D4 ObjectBox 僅文件級範例｜D5 不做 SQL console

---

## 1. 設計總覽

核心策略：**資料結構先行——介面 + 純函式（分組、欄位聯集、排序比較器）全部 TDD 做扎實，UI 疊在上面**。`DatabaseBrowserSource` 是唯一抽象，operation log 與真實 DB 走同一條路徑，UI 不出現「預設來源 vs 真實來源」的資料分支（唯一例外：clear 按鈕可見性）。

### 資料結構決策

- **介面 `Future`-based**：真實 DB 本來就非同步，operation log 同步資料包成 Future——消除兩種分支，UI 一律 `FutureBuilder`。
- **排序不進介面**：在已載入頁面上記憶體內排序（純函式，100% 可單測），介面保持最小。
- **OperationLogSource 欄位聯集以「時間順序首次出現」決定欄序**：新 entry 進來不會打亂既有欄位順序（buffer 是 newest-first，聯集計算須反轉為 oldest-first 再掃描）。
- **中繼欄 `#time` / `#op` / `#rows` 永遠在前三欄**，`#` 前綴與使用者 data key 區隔。
- **`DatabaseEntry` 零改動、`inspector.database(...)` API 零改動**（Never break userspace）。

### 新增依賴

- **core `pubspec.yaml`：零新增**（驗收條件）。
- **example `pubspec.yaml`：新增 `sqflite: ^2.4.0`**（僅 example，唯一 owner = T8a）。

### 既有程式碼影響面

- `DatabaseTab(inspector:)` 建構子簽名不變 → `dashboard_modal.dart` **零改動**。
- 舊 `test/ui/tabs/database_tab_test.dart` 覆蓋的行為（顯示 entry、clear 清空）改寫為：顯示 table 清單、clear 清空 operation log 來源——**覆蓋率不退化，是改寫不是刪除**。
- `test/inspectors/database_inspector_test.dart` 不動（行為未變，最終驗證鏈確認不退化）。

## 2. 檔案異動清單

| 檔案 | 動作 | 任務 | 共享檔 owner |
|------|------|------|------|
| `lib/src/models/database_browser_source.dart` | **新增**：`DatabaseBrowserSource` / `DatabaseTableInfo` / `DatabaseTablePage` | T1 | — |
| `lib/flutter_inspector_kit.dart` | 改：export 上述三型別 | T1 | **唯一 owner = T1** |
| `test/models/database_browser_source_test.dart` | **新增** | T1 | — |
| `lib/src/utils/table_sort.dart` | **新增**：`compareCells` / `sortRows` / `cellPreview` 純函式 | T3 | — |
| `test/utils/table_sort_test.dart` | **新增** | T3 | — |
| `lib/src/sources/operation_log_source.dart` | **新增**：`OperationLogSource`（包 `DatabaseInspector`） | T2 | — |
| `test/sources/operation_log_source_test.dart` | **新增** | T2 | — |
| `lib/src/core/flutter_inspector_impl.dart` | 改：`databaseSources` 建構參數 + `registerDatabaseSource()` + getter | T4 | — |
| `test/core/flutter_inspector_impl_test.dart` | 改：追加註冊 API 測試 group | T4 | — |
| `lib/src/ui/dashboard/tabs/database/table_rows_view.dart` | **新增**：Row grid 全頁 | T5a, T5b | T5a→T5b 序列 |
| `test/ui/tabs/table_rows_view_test.dart` | **新增** | T5a, T5b | T5a→T5b 序列 |
| `lib/src/ui/dashboard/tabs/database_tab.dart` | **重寫**：流水帳 → table 清單頁（D1 直接取代） | T6 | — |
| `test/ui/tabs/database_tab_test.dart` | **改寫**（非刪除）：對應新 UI、保留 clear 覆蓋 | T6 | — |
| `example/pubspec.yaml` | 改：加 `sqflite` | T8a | **唯一 owner = T8a** |
| `example/lib/sqflite_browser_source.dart` | **新增**：SQLite adapter 參考實作 | T8a | — |
| `example/lib/main.dart` | 改：seed 按鈕 + 註冊 source 示範 | T8b | **唯一 owner = T8b** |
| `README.md` | 改：Database 段落改寫 + SQLite/ObjectBox adapter 範例（D4） | T9 | **唯一 owner = T9** |
| `CHANGELOG.md` | 改：頂部新增 `## Unreleased` 段落（0.1.0 剛發布） | T10 | **唯一 owner = T10** |

## 3. 任務拆分

> 複雜度分級對齊 implementer model 策略：🟢 機械性=快/便宜｜🟡 整合=標準｜🔴 設計判斷/跨層=最強。
> 每任務 2–5 分鐘。**TDD：先寫測試（紅）→ 實作（綠）**。

### T1 — 介面與 models（TDD）🟢 機械性
- **目標**：建立 `DatabaseBrowserSource` 抽象與兩個 model，並 export 為公開 API。
- **寫入**：`lib/src/models/database_browser_source.dart`、`test/models/database_browser_source_test.dart`、`lib/flutter_inspector_kit.dart`（T1 為此共享檔唯一 owner）
- **內容**（直接採用規格 §4.1 的程式碼形狀）：
  - `abstract class DatabaseBrowserSource { String get name; Future<List<DatabaseTableInfo>> listTables(); Future<DatabaseTablePage> fetchRows(String tableName, {int limit = 200, int offset = 0}); }`
  - `DatabaseTableInfo`（`name` + `rowCount?`，`@immutable`、`==`/`hashCode`/`toString` 比照 `DatabaseEntry` 慣例）
  - `DatabaseTablePage`（`columns` / `rows` / `totalRows?`）
  - export 檔加一行 `export 'src/models/database_browser_source.dart';`（依字母序插入）
- **測試先行**：model 建構/相等性；以匿名 fake 實作介面驗證 `limit`/`offset` 預設值（`limit == 200`、`offset == 0`）；測試從 `package:flutter_inspector_kit/flutter_inspector_kit.dart` import 以同時驗證 export。
- **驗證**：`flutter test test/models/database_browser_source_test.dart`

### T2 — `OperationLogSource`（TDD）🟡 整合
- **目標**：把 `DatabaseInspector` 的 entries 重組為虛擬表格的預設來源。
- **寫入**：`lib/src/sources/operation_log_source.dart`、`test/sources/operation_log_source_test.dart`
- **內容**：
  - `class OperationLogSource implements DatabaseBrowserSource`，建構子收 `DatabaseInspector`；`name => 'Operation log'`。
  - `listTables()`：依 `tableName` 分組，table 依名稱字母排序，`rowCount` = 該組 entry 數。
  - `fetchRows()`：columns = `['#time', '#op', '#rows']` + 該組 data key 聯集（**以 oldest-first 掃描的首次出現順序**，buffer 為 newest-first 須反轉計算）；rows 一筆 entry 一列（newest-first，與 buffer 一致），缺 key 補 null；`#time` = `timestamp.toIso8601String()`、`#op` = `operation.name`、`#rows` = `affectedRows`；以 `limit`/`offset` 切頁，`totalRows` = 組內 entry 總數。
  - 不存在的 tableName → 回傳空 page（columns 僅三中繼欄、rows 空、totalRows 0），不丟例外。
- **測試先行**（規格驗收逐條轉測試）：分組正確、字母排序、rowCount、中繼欄永遠存在、key 聯集順序穩定、缺值補 null、分頁（limit/offset/totalRows）、空 buffer 回空清單。
- **驗證**：`flutter test test/sources/operation_log_source_test.dart`

### T3 — 排序比較器與 cell 純函式（TDD）🟢 機械性
- **目標**：row grid 的記憶體內排序與儲存格顯示邏輯，純函式、零 Flutter 依賴。
- **寫入**：`lib/src/utils/table_sort.dart`、`test/utils/table_sort_test.dart`
- **內容**：
  - `int compareCells(Object? a, Object? b)`：null 永遠排最後（不論升降冪由呼叫端處理——比較器中 null 視為最大）；兩者皆 `num` 按數值；其餘 `toString()` 字串比較。
  - `List<List<Object?>> sortRows(List<List<Object?>> rows, int columnIndex, bool ascending)`：回傳新 list 不改原資料；降冪時 null 仍排最後（即先比 null、再反轉非 null 部分的比較結果）。
  - `String cellPreview(Object? value, {int maxLength = 100})`：null → `'NULL'`；超長截斷 + `…`。
- **測試先行**：數字欄按數值（`9 < 10`）、字串欄、混合型別、null 排最後（升冪與降冪皆然）、不可變性、截斷邊界（99/100/101 字元）。
- **驗證**：`flutter test test/utils/table_sort_test.dart`
- **依賴**：無（函式收純 `List<Object?>`，不 import T1 型別）→ 可與 T1 並行。

### T4 — `FlutterInspector` 註冊 API（TDD）🟡 整合
- **目標**：來源註冊機制，`OperationLogSource` 永遠第一位。
- **寫入**：`lib/src/core/flutter_inspector_impl.dart`、`test/core/flutter_inspector_impl_test.dart`（追加 group，不動既有測試）
- **內容**：
  - 建構子新增可選參數 `List<DatabaseBrowserSource>? databaseSources`。
  - 內部建立 `OperationLogSource(_registry.database)` 作為預設來源。
  - `void registerDatabaseSource(DatabaseBrowserSource source)`：執行期動態註冊。
  - `List<DatabaseBrowserSource> get databaseSources`：回傳 unmodifiable list，`[operationLog, ...建構時注入, ...動態註冊]`。
  - 既有參數、getter、行為全部不動。
- **測試先行**：預設只有一個來源且 `name == 'Operation log'`；建構注入排第二；`registerDatabaseSource` 追加；回傳 list 不可變；`inspector.database(...)` 記錄後預設來源 `listTables()` 看得到（端到端黏合）。
- **驗證**：`flutter test test/core/flutter_inspector_impl_test.dart`
- **依賴**：T1、T2。

### T5a — Row grid 頁骨架（TDD）🔴 設計判斷
- **目標**：`TableRowsView` 全頁——載入、表格呈現、雙向捲動、NULL 呈現、狀態列、錯誤卡片。
- **寫入**：`lib/src/ui/dashboard/tabs/database/table_rows_view.dart`、`test/ui/tabs/table_rows_view_test.dart`
- **內容**：
  - `TableRowsView({required DatabaseBrowserSource source, required String tableName})`，StatefulWidget；`initState` 觸發 `fetchRows(limit: 200, offset: 0)`。
  - AppBar：返回 + `users (12 rows)`（rowCount 不可得時只顯示名稱）+ refresh（重置 offset 重新載入）。
  - `DataTable` 外包橫向 + 縱向 `SingleChildScrollView`（沿用 `network_detail_view` 的 `MaterialPageRoute` push 慣例由呼叫端負責）。
  - 儲存格：`cellPreview()`（T3）；null 值以灰色斜體 `NULL` Text 呈現（非一般文字）。
  - **守衛**：`columns` 為空或 rows 為空 → 顯示置中 `'No rows'` 文字，**不建 DataTable**（`DataTable` 空 columns 會 assert 崩潰）。
  - 底部狀態列：`Showing X of Y`（`totalRows` null 時顯示 `Showing X`）。
  - 錯誤處理：`fetchRows` 拋例外 → 錯誤訊息卡片（`Card` + error icon + `e.toString()`）+ Retry 按鈕，UI 不崩潰。
  - 排序、cell 詳情、Load more 留給 T5b（同檔序列）。
- **測試先行**：欄名標頭呈現、一列一筆、NULL 灰色斜體（`find.byWidgetPredicate` 驗 style）、空 table 顯示 `'No rows'`、狀態列文字、來源丟例外顯示錯誤卡片不崩潰、refresh 重新呼叫來源。測試用 in-memory fake `DatabaseBrowserSource`（可注入延遲/例外）。**FutureBuilder/async 載入記得 `await tester.pumpAndSettle()`**。
- **驗證**：`flutter test test/ui/tabs/table_rows_view_test.dart`
- **依賴**：T1、T3。

### T5b — Row grid 互動：排序 + cell 詳情 + Load more（TDD）🟡 整合
- **目標**：補齊 row grid 三個互動。
- **寫入**：`lib/src/ui/dashboard/tabs/database/table_rows_view.dart`、`test/ui/tabs/table_rows_view_test.dart`（接 T5a，同檔**序列**）
- **內容**：
  - 排序：`DataColumn.onSort` + `DataTable.sortColumnIndex`/`sortAscending`（內建方向箭頭），呼叫 T3 `sortRows`；再點同欄切換升/降冪；Load more 後重套當前排序。
  - cell 詳情：`onTap` 開 `showModalBottomSheet`，顯示完整值（`SelectableText`）+ Copy 按鈕 → `Clipboard.setData` + SnackBar `'Copied'` 回饋（沿用 network sharing 慣例）。
  - Load more：`totalRows != null && rows.length < totalRows`，或 `totalRows == null` 且上一頁回滿 200 筆時，狀態列旁顯示 `Load more` 按鈕；點擊 `fetchRows(offset: 已載入數)` 追加。
- **測試先行**：點欄名後列序改變、再點反向、數字欄數值排序且 null 最後；點 cell 出現完整值與 Copy、複製後 SnackBar；fake source 餵 450 筆 → 首頁 200 筆 + `Showing 200 of 450` + Load more 後 400 筆。
- **驗證**：`flutter test test/ui/tabs/table_rows_view_test.dart`
- **依賴**：T5a（同檔）。

### T6 — Database tab 重寫為 table 清單頁 + 舊測試改寫（TDD）🔴 設計判斷
- **目標**：D1 直接取代——流水帳移除，Database tab 變為 source 切換 + table 清單；舊測試**改寫**保覆蓋。
- **寫入**：`lib/src/ui/dashboard/tabs/database_tab.dart`（重寫）、`test/ui/tabs/database_tab_test.dart`（改寫）
- **內容**：
  - 建構子維持 `DatabaseTab({required this.inspector})` → `dashboard_modal.dart` 零改動。
  - 頂列：來源選擇（`inspector.databaseSources.length > 1` 才顯示 `DropdownButton`，否則只顯示來源名稱 Text）+ refresh + clear。
  - clear 僅當選中來源 `is OperationLogSource` 時顯示（內部 import，`OperationLogSource` 不公開 export）；動作 = `inspector.clearDatabase()` + 重載。
  - 清單：`FutureBuilder` on `listTables()`；`ListTile`（table 名 + `12 rows` / `n/a` + `Icons.chevron_right`，沿用 network_tab 慣例）；點擊 `Navigator.push(MaterialPageRoute(builder: (_) => TableRowsView(source: ..., tableName: ...)))`。
  - 空狀態：operation log 來源顯示 `'No database activity'`，其他來源顯示 `'No tables in this source'`。
  - `listTables()` 拋例外 → 同 T5a 風格錯誤卡片。
- **測試改寫**（覆蓋率不退化是硬要求）：
  - 舊「displays database entries」→ 新「`inspector.database(...)` 記錄後顯示分組 table 清單與 row 數」。
  - 舊「supports clearing」→ 新「點 clear 後清單清空、顯示空狀態」（保留 `Icons.delete` tap 路徑覆蓋）。
  - 新增：空狀態文字、多來源顯示下拉且切換後清單更新、單來源不顯示下拉、非 op-log 來源 clear 不可見、rowCount null 顯示 `n/a`、點 table 推入 `TableRowsView`。
- **驗證**：`flutter test test/ui/tabs/database_tab_test.dart` 與 `flutter test test/ui/dashboard_modal_test.dart`（確認 modal 不受影響）
- **依賴**：T4（`databaseSources`）、T5a（push 目標）。

### T8a — Example SQLite adapter 參考實作 🟡 整合
- **目標**：可複製貼上等級的 `DatabaseBrowserSource` SQLite 實作。
- **寫入**：`example/pubspec.yaml`（唯一 owner，加 `sqflite: ^2.4.0`）、`example/lib/sqflite_browser_source.dart`
- **內容**（規格 §4.3）：
  - `class SqfliteBrowserSource implements DatabaseBrowserSource`，建構子收 `Database` + `name`。
  - `listTables()`：`SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name`，每表 `SELECT COUNT(*)` 取 rowCount。
  - `fetchRows()`：`SELECT * FROM "<table>" LIMIT ? OFFSET ?`（table 名以雙引號包裹），columns 取自第一筆 result 的 keys（空結果 → 空 columns，T5a 已有守衛）；`totalRows` 用 COUNT(*)。
  - 檔頭註解標明「參考實作，可直接複製到你的 app」。
- **驗證**：`(cd example && flutter pub get && flutter analyze)`（adapter 無法在 host 單測 sqflite plugin，靠 analyze + T8b 手動煙測）
- **依賴**：T4（API 定型）。寫入路徑全在 `example/`，可與 T6 並行。

### T8b — Example app 接線示範 🟢 機械性
- **目標**：main.dart 示範開 DB、seed、註冊 source。
- **寫入**：`example/lib/main.dart`
- **內容**：
  - 新增 `'Seed SQLite demo'` 按鈕：開啟/建立 demo db（`users` 表 + 數筆含 null 的種子資料，重複點擊冪等）、`inspector.registerDatabaseSource(SqfliteBrowserSource(db, name: 'demo.db'))`（以 bool 守衛避免重複註冊）、SnackBar 回饋。
  - **DB 操作只在按鈕 tap 後發生**——啟動路徑零 plugin 呼叫，`example/test/widget_test.dart` 維持綠燈。
- **驗證**：`(cd example && flutter analyze && flutter test)`
- **依賴**：T8a。

### T9 — README 更新（含 ObjectBox 文件級範例，D4）🟢 機械性
- **目標**：文件對齊新功能。
- **寫入**：`README.md`（唯一 owner）
- **內容**：
  - 「Track database operations」段落後新增「Browse database tables」段：兩層瀏覽說明、`databaseSources:` 建構注入與 `registerDatabaseSource()` 範例。
  - SQLite adapter：貼 `SqfliteBrowserSource` 完整程式碼（與 T8a 同步）。
  - ObjectBox adapter：**文件級範例**——逐 entity 註冊（`box` + `toMap()`），`listTables()` 列已註冊 entity、`box.count()`、`fetchRows` 用 `query().build().find(offset:, limit:)` 逐筆 `toMap()`；明確標注「ObjectBox 無 SQL table，Entity/Box 即 table」。
- **驗證**：人工檢視 + 範例程式碼與 T1/T4 簽名一致。
- **依賴**：T4、T8a（API 與 adapter 形狀定案）。

### T10 — CHANGELOG 更新 🟢 機械性
- **目標**：記錄變更（0.1.0 剛發布 → 新增 `## Unreleased` 段落於頂部，**不動 0.1.0 段落**）。
- **寫入**：`CHANGELOG.md`（唯一 owner）
- **內容**：
  - Added：Database table browser（兩層瀏覽、排序、cell 詳情、200 列 + Load more）；公開 `DatabaseBrowserSource` / `DatabaseTableInfo` / `DatabaseTablePage`；`FlutterInspector` 的 `databaseSources` 參數與 `registerDatabaseSource()`。
  - Changed：Database tab 由操作流水帳改為 table browser（流水帳視圖移除；`inspector.database(...)` 記錄 API 不變）。
- **驗證**：人工檢視。
- **依賴**：T4（API 名稱定案）。

### T11 — 最終驗證鏈 🟢 機械性
- **目標**：全套品質關卡。
- **寫入**：無（只跑指令；若有 format/analyze 修正則就地修）
- **指令**（依序）：
  1. `dart format .`（含 example）
  2. `flutter analyze`（須零 issue，含 example）
  3. `flutter test $(find test -name '*_test.dart' ! -name 'magical_tap_test.dart')`
     — **鐵則：永遠排除 `test/ui/magical_tap_test.dart`**（該檔有 10 分鐘既有 timeout，不在本次變更面）。
  4. `(cd example && flutter analyze && flutter test)`
- **驗證**：全綠，既有測試（`database_inspector_test.dart` 等）零退化。
- **依賴**：全部任務。

## 4. 執行順序與並行批次

> 並行規則：寫入路徑不重疊才可並行；共享檔已指定唯一 owner（`lib/flutter_inspector_kit.dart` → T1、`example/pubspec.yaml` → T8a、`example/lib/main.dart` → T8b、`README.md` → T9、`CHANGELOG.md` → T10）。

```
批次 1（並行）: T1（models+export）        ‖ T3（排序純函式）
                      ↓
批次 2（並行）: T2（OperationLogSource）   ‖ T5a（row grid 骨架，依賴 T1+T3）
                      ↓
批次 3（並行）: T4（註冊 API，依賴 T1+T2） ‖ T5b（grid 互動，接 T5a 同檔）
                      ↓
批次 4（並行）: T6（database_tab 重寫）    ‖ T8a（example adapter）
                      ↓
批次 5（並行）: T8b（example 接線）        ‖ T9（README） ‖ T10（CHANGELOG）
                      ↓
批次 6（序列）: T11（最終驗證鏈）
```

- 同檔序列鏈：T5a → T5b（`table_rows_view.dart` + 其測試）。
- T4 與 T5b 寫入完全不重疊（core/impl vs ui/database）→ 可並行。
- T6 與 T8a 寫入完全不重疊（lib/test vs example）→ 可並行。

## 5. 範圍邊界（重申，照規格 §6 + 已確認決策）

- **不做**資料編輯/寫入（純唯讀）。
- **不做** SQL query console（D5）。
- **不做** schema 檢視（索引、外鍵、型別宣告）。
- **不發布** companion packages（介面設計保留未來空間）。
- **不支援** sqflite/objectbox 以外 DB 的官方 adapter。
- **不做**跨欄位搜尋/篩選（後續迭代）。
- **不做**資料持久化（operation log 維持 RingBuffer 記憶體內）。
- **ObjectBox 不進 example**（D4：僅 README 文件級範例）。
- **舊流水帳視圖直接移除**（D1），但其測試覆蓋的行為（記錄顯示、clear）必須在新 UI 測試中等價重建。
- core `pubspec.yaml` 零新依賴；`DatabaseEntry` 可見性不變（不 export）。

## 6. 執行方式選項

| 方式 | 說明 | 適用 |
|------|------|------|
| **(A) Subagent-driven**（建議） | 同一 session 內按批次派發 implementer subagent，批次內並行、批次間序列；複雜度分級對應 model 強度（🟢 快/便宜、🟡 標準、🔴 最強） | 預設選擇——依賴鏈清楚、共享檔 owner 已定，調度成本最低 |
| (B) Parallel session | 批次 1–3（核心邏輯鏈）與 T8a/T9（example/docs）拆兩個 session 並行 | 想壓縮 wall-clock 時間時；注意 T9 依賴 T4 API 定案，需等核心 session 過批次 3 |

請確認計畫與執行方式後進入實作階段。
