# 功能規格：Database Table Browser（SQL administrator 式表格瀏覽）

- **日期**：2026-06-11
- **專案**：flutter_inspector_kit（v0.1.0）
- **狀態**：STAGE 0a — 待確認

---

## 1. 背景與目標（Why）

目前 Dashboard 的 Database tab（`lib/src/ui/dashboard/tabs/database_tab.dart`，僅 56 行）是一份「操作流水帳」：每筆 `DatabaseEntry` 以 `ListTile` 顯示 `INSERT on users / Rows affected: 1`。問題：

- 看不到資料本身的樣貌——只知道「發生過什麼操作」，不知道「table 裡現在有什麼」。
- 無分組、無結構：同一 table 的操作散落在時間軸上，無法以 table 為單位檢視。
- 與 Network tab 的成熟度落差大（Network 已有搜尋、篩選、詳情頁、分享）。

**目標**：把 Database tab 改造成 SQL administrator（如 DB Browser for SQLite / phpMyAdmin）式的兩層瀏覽——Table 清單 → Row grid——並建立可插拔的資料來源架構，讓使用者既能零設定看到操作紀錄重組的虛擬表格，也能接上真實的 SQLite / ObjectBox 資料庫。

## 2. 使用者故事

### US-1：Table 清單（零設定）

> 身為開發者，打開 Database tab 時，我要看到「有哪些 table、各有幾筆資料」，而不是一條條操作紀錄。

### US-2：Row grid 瀏覽

> 身為開發者，點進某個 table 後，我要看到像資料庫管理工具一樣的表格：欄名做標頭、一列一筆資料、欄太多時可以橫向捲動、點欄名可以排序。

### US-3：接上真實資料庫

> 身為使用 sqflite 或 ObjectBox 的開發者，我要能用少量程式碼把真實 DB 接進 inspector，直接瀏覽 DB 裡的實際資料，而不只是操作紀錄的重組。

### US-4：不被拖累的使用者

> 身為只用 inspector 看 network/log 的開發者，我不希望因為這個功能被迫安裝 sqflite 或 objectbox。

## 3. UI 規格

### 3.1 第一層：Table 清單頁（Database tab 預設畫面）

```
┌─────────────────────────────────────────────┐
│ Source: [Operation log        ▼]   ⟳  🗑    │  ← 來源切換 + refresh + clear
├─────────────────────────────────────────────┤
│ ▦ users                          12 rows  › │
│ ▦ orders                         48 rows  › │
│ ▦ cart_items                      3 rows  › │
│ ▦ settings                       (n/a)    › │  ← rowCount 不可得時顯示 n/a
├─────────────────────────────────────────────┤
│              (empty state:                   │
│        "No database activity" /              │
│        "No tables in this source")           │
└─────────────────────────────────────────────┘
```

- **Source 下拉**：列出所有已註冊的資料來源；只有一個來源（預設情況）時隱藏下拉、只顯示來源名稱文字。
- **清單項目**：table 名稱 + row 數 + chevron（沿用 `network_tab` 的 `ListTile` + `Icons.chevron_right` 慣例）。
- **🗑（Clear）**：僅對預設來源（operation log）有效——清空 `DatabaseInspector` buffer；真實 DB 來源為唯讀，clear 按鈕隱藏或停用。
- **排序**：table 依名稱字母排序。

### 3.2 第二層：Row grid 頁（push 全頁，沿用 `network_detail_view` 的 `MaterialPageRoute` 先例）

```
┌─────────────────────────────────────────────┐
│ ←  users (12 rows)                       ⟳  │  ← AppBar：返回 + table 名 + refresh
├─────────────────────────────────────────────┤
│ │ id ▲│ name      │ email          │ age │ ◄──── 橫向捲動 ────►
│ ├─────┼───────────┼────────────────┼─────┤
│ │ 1   │ Alice     │ a@example.com  │ 30  │
│ │ 2   │ Bob       │ b@example.com  │ 25  │
│ │ 3   │ Carol     │ NULL           │ 41  │  ← null 以灰色斜體 NULL 呈現
│ │ ... │           │                │     │  ↕ 縱向捲動
├─────────────────────────────────────────────┤
│ Showing 12 of 12                             │  ← 底部列數狀態列
└─────────────────────────────────────────────┘
```

- **表格元件**：Flutter `DataTable`（內建 `sortColumnIndex` / `sortAscending` 支援），外層包橫向 + 縱向 `SingleChildScrollView`。
- **欄位排序**：點欄名切換 升冪 ▲ / 降冪 ▼；排序在已載入的資料上以記憶體內比較完成（數字按數值、其餘按字串、null 排最後）。
- **儲存格**：值以 `toString()` 呈現，過長截斷（單格上限約 100 字元 + ellipsis）；點儲存格以 dialog/bottom sheet 顯示完整值並可複製（複製給 SnackBar 回饋，沿用 US-4 sharing 慣例）。
- **載入上限**：單次最多載入 **200 列**（避免大表卡死 UI）；超過時底部顯示 `Showing 200 of 1,500` 並提供「Load more」。
- **錯誤處理**：來源查詢失敗（DB 已關閉等）顯示錯誤訊息卡片，不崩潰。

## 4. 資料來源架構

### 4.1 核心抽象（放在 package core，零新依賴）

```dart
/// 一個可被 Database tab 瀏覽的資料來源。
abstract class DatabaseBrowserSource {
  /// 顯示在來源下拉中的名稱，如 "Operation log"、"app.db"。
  String get name;

  /// 列出所有 table（名稱 + 可選的 row 數；取不到時為 null）。
  Future<List<DatabaseTableInfo>> listTables();

  /// 讀取某 table 的一頁資料。
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  });
}

class DatabaseTableInfo {
  final String name;
  final int? rowCount;
}

class DatabaseTablePage {
  final List<String> columns;       // 欄名（標頭）
  final List<List<Object?>> rows;   // 一列一筆，與 columns 對齊
  final int? totalRows;             // 取不到時為 null
}
```

- 介面為 `Future`-based：真實 DB 查詢本來就是非同步；預設來源同步資料包成 Future 即可，消除兩種分支。
- 排序不下放到介面（不加 `orderBy` 參數）：在已載入頁面上記憶體內排序，介面保持最小。未來真有需求再擴充。

### 4.2 預設來源：`OperationLogSource`（零設定，永遠存在）

把現有 `DatabaseInspector` 的 `DatabaseEntry` 紀錄重組為虛擬表格：

- **分組**：依 `tableName` 分組 → 每組一個虛擬 table，rowCount = 該組 entry 數。
- **欄位**：固定中繼欄 `#time`、`#op`、`#rows`（timestamp / operation / affectedRows），加上該組所有 entry 的 `data` map key 的聯集（依首次出現順序）。
- **列**：一筆 entry 一列；entry 沒有的 key 填 null。
- 中繼欄以 `#` 前綴與資料欄區隔，避免和使用者的 `data` key 撞名。

### 4.3 真實資料庫接法：介面在 core、adapter 由使用者實作

**調查結論（Dart/Flutter 生態慣例）**：pub 沒有「optional dependency」機制，社群兩種主流作法——

| 作法 | 範例 | 優點 | 缺點 |
|---|---|---|---|
| **(A) 介面放 core + 使用者實作 adapter** | `talker` 的 logger 介面、`alice` 0.x 的 storage 介面 | core 零新依賴；使用者 20–40 行即可接上；維護成本最低 | 使用者要自己寫一小段膠水碼 |
| **(B) Companion packages** | `alice` 1.x（`alice_objectbox`、`alice_dio`…）、`drift_db_viewer` | 使用者只要 `pub add` 即用 | 要維護多個 package 的發版、版本對齊；v0.1.0 階段成本過高 |

**本規格建議：先做 (A)，介面設計上不阻礙未來演進到 (B)**。core 只新增上述抽象；example app（可自由依賴 sqflite/objectbox）內附兩個參考 adapter 實作，README 提供複製貼上等級的範例：

- **SQLite adapter（參考實作，放 example）**：
  - `listTables()` → `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'`，rowCount 用 `SELECT COUNT(*)`。
  - `fetchRows()` → `SELECT * FROM "<table>" LIMIT ? OFFSET ?`，columns 取自查詢結果的 keys。
- **ObjectBox adapter（參考實作，放 example）**：
  - ObjectBox 沒有 SQL table，對應關係為 **Entity/Box → table**。Dart 端無泛用 runtime 反射可把任意 entity 轉成 map，因此 adapter 需由使用者**逐 entity 註冊**：`box` + 該 entity 的 `toMap()` 轉換函式。`listTables()` 列出已註冊的 entity，rowCount 用 `box.count()`；`fetchRows()` 用 `box.query().build().find()` 搭配 offset/limit 後逐筆 `toMap()`。

### 4.4 註冊 API

```dart
final inspector = FlutterInspector(
  databaseSources: [MySqfliteSource(db)],   // 建構時注入（可選）
);
inspector.registerDatabaseSource(source);    // 或執行期動態註冊（DB 開啟較晚的情境）
```

- 預設來源 `OperationLogSource` 永遠在清單第一位，不需註冊。
- 新公開 API export：`DatabaseBrowserSource`、`DatabaseTableInfo`、`DatabaseTablePage`（注意：現有 `DatabaseEntry` 未 export，本次不變動其可見性）。

## 5. 驗收條件

### Table 清單頁
- [ ] 有 database 操作紀錄時，Database tab 顯示依 tableName 分組的 table 清單，每項含 row 數。
- [ ] 無任何來源資料時顯示空狀態文字，不顯示空白畫面。
- [ ] 註冊多個來源時出現來源下拉，切換後清單即時更新；單一來源時不顯示下拉。
- [ ] Clear 只作用於 operation log 來源；真實 DB 來源下 clear 不可用。

### Row grid 頁
- [ ] 點 table 進入 row grid：欄名標頭、一列一筆、可橫向與縱向捲動。
- [ ] 點欄名可排序，再點切換升/降冪，標頭有方向指示；數字欄按數值排序、null 排最後。
- [ ] null 值以可辨識方式呈現（灰色 NULL），不顯示為空字串。
- [ ] 單次載入上限 200 列；超過時顯示 `Showing X of Y` 與 Load more。
- [ ] 點儲存格可看完整值並複製，複製有 SnackBar 回饋。
- [ ] 來源查詢拋例外時顯示錯誤訊息，UI 不崩潰。

### 預設來源（OperationLogSource）
- [ ] data map 的 key 聯集成為欄位，缺值補 null；中繼欄 `#time`/`#op`/`#rows` 永遠存在。
- [ ] 與現有 `inspector.database(...)` 記錄 API 完全相容，呼叫端零改動（Never break userspace）。

### 架構與品質
- [ ] `pubspec.yaml` 不新增任何依賴（sqflite/objectbox 僅出現在 example）。
- [ ] `DatabaseBrowserSource` 等新型別正確 export 於 `lib/flutter_inspector_kit.dart`。
- [ ] example app 含可運作的 SQLite adapter 示範（ObjectBox adapter 至少提供文件級範例，見待決策 D4）。
- [ ] `flutter analyze` 零 issue；新增邏輯（分組、欄位聯集、排序比較器、分頁）有單元測試；UI 有 widget test（沿用 `test/ui/tabs/` 慣例）。
- [ ] 既有 `database_inspector_test.dart` 等測試不退化。

## 6. 範圍邊界（Non-goals）

- **不做資料編輯/寫入**：純唯讀瀏覽，不提供 insert/update/delete UI。
- **不做 SQL query console**：不提供自由輸入 SQL 的介面（見待決策 D5）。
- **不做 schema 檢視**（索引、外鍵、欄位型別宣告）。
- **不發布 companion packages**：本次不建 `flutter_inspector_kit_sqflite` 等獨立 package（介面設計保留未來空間）。
- **不支援 sqflite/objectbox 以外的 DB**（drift、hive、isar 等）——但任何人可透過 `DatabaseBrowserSource` 自行接上。
- **不做跨欄位搜尋/篩選**：第一版不在 row grid 提供關鍵字搜尋（可列為後續迭代）。
- **不做資料持久化**：operation log 來源維持 RingBuffer 記憶體內行為。

## 7. 待使用者決策事項

| # | 事項 | 選項 | 建議 |
|---|---|---|---|
| D1 | **舊版操作流水帳視圖去留**：新設計以 table 分組取代時間軸流水帳，原始的「按時間看所有操作」視圖是否保留？ | (a) 完全移除 (b) 在 tab 內加 view 切換（Tables / Log） | **(b)**——流水帳對 debug「操作順序」仍有價值，且避免破壞既有使用習慣 |
| D2 | **Adapter 策略**：介面 + example 參考實作（本規格建議），或現在就發 companion packages？ | (A) core 介面 + example 示範 (B) companion packages | **(A)**——v0.1.0 階段維護成本考量，介面不阻礙未來轉 (B) |
| D3 | **載入上限數值**：單頁 200 列是否合適？ | 100 / 200 / 500 / 可設定 | **200 + Load more**，第一版不開放設定 |
| D4 | **ObjectBox 示範深度**：example app 是否實際引入 objectbox 依賴跑出可執行示範（需 build_runner codegen，example 變重），或僅 README 文件級範例？ | (a) example 內可執行 (b) 文件級範例 | **(b)**——SQLite 已有可執行示範驗證介面，ObjectBox 留文件範例即可 |
| D5 | **SQL query console**：是否納入本次範圍？ | 納入 / 不納入 | **不納入**——唯讀 console 只對 SQLite 來源有意義（ObjectBox/operation log 無 SQL），且注入風險與範圍膨脹不成比例；列為未來迭代 |

---

## 確認

請確認以上規格（特別是第 7 節五項決策）。確認後進入 STAGE 0b 產出實作計畫。
