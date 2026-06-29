# ObjectBox 範例接入設計

**日期**:2026-06-29
**主題**:在 example app 新增 ObjectBox 的 `DatabaseBrowserSource` 範例
**狀態**:設計已確認,待實作

---

## 1. 目的與核心洞察

### 目的
示範**非 SQL 資料源**如何接入 `DatabaseBrowserSource`。現有的
`SqfliteBrowserSource` 已示範關聯式資料庫;ObjectBox 補上反面情境:
NoSQL object store、強型別、無動態 schema。

### 核心洞察(本設計的靈魂)
> sqflite source 教的是「動態 schema:`SELECT *` + `keys` 通殺」。
> ObjectBox source 教的是反面:**沒有動態 schema,你得自己當 schema**。

ObjectBox 是強型別 object store,`box.getAll()` 回傳 `List<Person>`,
**沒有**乾淨的執行期 API 把任意物件攤成欄位(已透過官方文件確認:
`getObjectBoxModel` / annotations 都不提供 runtime 屬性反射)。

因此本範例的教學重點是回答:「當資料源不給你動態 schema 時,
`DatabaseBrowserSource` 怎麼接?」答案 ——
**用一張 entity 註冊表,把每個 entity type 對應到一組(欄位定義 + 映射函式)**。
這是非 SQL 資料源的通用心法。

---

## 2. 檔案結構與依賴

```
example/
  pubspec.yaml                     # + objectbox 相關依賴
  lib/
    objectbox_entities.dart        # 新增:Note + Tag 兩個 @Entity 定義
    objectbox_browser_source.dart  # 新增:reference implementation
    objectbox.g.dart               # build_runner 生成(commit 進版控)
    main.dart                      # 改:加 Seed ObjectBox Demo 按鈕 + 註冊 source
  objectbox-model.json             # build_runner 生成(commit 進版控)
```

### 依賴(版本來自 ObjectBox 官方文件確認)
```yaml
dependencies:
  objectbox: ^5.3.1
  objectbox_flutter_libs: any
dev_dependencies:
  build_runner: ^2.4.11
  objectbox_generator: any
```

### 決策:`objectbox.g.dart` 與 `objectbox-model.json` 進版控
**commit 生成檔**。理由:否則任何人 clone 下來都得先裝 ObjectBox CLI、
跑 `build_runner` 才能編譯,違背 example「開箱即看」的目的。
代價是生成檔進版控。

---

## 3. `ObjectBoxBrowserSource` 實作(核心)

### 設計:entity 註冊表(adapter map)

```dart
class ObjectBoxBrowserSource implements DatabaseBrowserSource {
  ObjectBoxBrowserSource(this._store, {this.name = 'ObjectBox database'});
  final Store _store;
  @override final String name;

  // 心法:ObjectBox 沒有動態 schema,所以你自己當 schema。
  // 每個 entity type 註冊一筆:表名 → (欄位定義, 計數, 物件攤成 row)。
  late final Map<String, _EntityAdapter> _adapters = {
    'Note': _EntityAdapter(
      columns: ['id', 'title', 'body'],
      count: () => _store.box<Note>().count(),
      fetch: (limit, offset) => _store.box<Note>().getAll()
          .skip(offset).take(limit)
          .map((n) => [n.id, n.title, n.body]).toList(),
    ),
    'Tag': _EntityAdapter(
      columns: ['id', 'label'],
      count: () => _store.box<Tag>().count(),
      fetch: (limit, offset) => _store.box<Tag>().getAll()
          .skip(offset).take(limit)
          .map((t) => [t.id, t.label]).toList(),
    ),
  };

  @override
  Future<List<DatabaseTableInfo>> listTables() async =>
      _adapters.entries.map((e) =>
          DatabaseTableInfo(name: e.key, rowCount: e.value.count())).toList();

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final adapter = _adapters[tableName]!;
    return DatabaseTablePage(
      columns: adapter.columns,
      rows: adapter.fetch(limit, offset),
      totalRows: adapter.count(),
    );
  }
}
```

### 取捨
1. **分頁**:用 `getAll()` 後在記憶體 `skip(offset).take(limit)`。
   註解標明「production 大表請改用 `box.query().build()` 的 offset/limit」。
   對 demo 的小資料量是對的,且不模糊主軸。
2. **`_EntityAdapter` 是 example 自己的小 helper**,不碰套件介面 ——
   保持 `DatabaseBrowserSource` 零改動(向後相容)。

---

## 4. main.dart 接線 + 平台處理

- 加一顆 `Seed ObjectBox Demo` 按鈕,與現有 `Seed SQLite Demo` 對稱呈現。
- 用 `path_provider` 拿目錄 → `openStore()` → 塞幾筆 Note/Tag →
  `inspector.registerDatabaseSource(ObjectBoxBrowserSource(store))`。
- 沿用 `_sqliteRegistered` 模式,加 `_objectboxRegistered` 旗標防重複註冊。

### Web 平台處理(必須)
ObjectBox 依賴 native libs,**不支援 web**;example 有 web 目錄。
按鈕 handler 用 `kIsWeb` 檢查,在 web 上彈 SnackBar 說明
「ObjectBox 不支援 web,請在行動裝置/桌面執行」,而非讓 app 崩潰。
這同時也是個誠實的教學點。

---

## 向後相容性

- **零套件介面變更**:`DatabaseBrowserSource` / `DatabaseTableInfo` /
  `DatabaseTablePage` 完全不動。
- 所有新增都在 `example/` 內,不影響套件本身或既有 sqflite 範例。
