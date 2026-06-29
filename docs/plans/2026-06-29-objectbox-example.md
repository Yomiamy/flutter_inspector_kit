# ObjectBox Example Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 example app 新增一份 ObjectBox 的 `DatabaseBrowserSource` reference implementation,示範**非 SQL 資料源**如何接入 Flutter Inspector 的 Database 瀏覽功能。

**Architecture:** ObjectBox 是強型別 NoSQL object store,沒有動態 schema(`box.getAll()` 回傳強型別物件,無執行期欄位反射)。因此 source 用一張 **entity 註冊表(adapter map)**,把每個 entity type 對應到一組「欄位定義 + 計數函式 + 物件攤平函式」。所有改動都在 `example/` 內,套件介面零變更。

**Tech Stack:** Flutter、ObjectBox(`objectbox` ^5.3.1 + `objectbox_flutter_libs`)、`build_runner` 程式碼生成、`path_provider`。

---

## 驗證模型說明(重要)

這是 **example 示範程式碼**,不是單元測試的目標。`example/` 既有慣例只有一個預設
`widget_test.dart`,沒有 source-level 的測試框架。因此本計畫的「驗證」採用兩道防線:

1. **`flutter analyze` 乾淨**(每個改 Dart 的步驟後執行)。
2. **`build_runner` 成功生成 + app 可編譯**(ObjectBox 階段的關鍵驗證)。

最終人工驗證:在行動裝置/桌面 run app → 點 `Seed ObjectBox Demo` → 開 Inspector
Dashboard 的 Database tab → 看到 `Note`、`Tag` 兩張表與資料。

> ⚠️ **生成檔限制**:`objectbox.g.dart` 與 `objectbox-model.json` 只能由
> `build_runner` 產生,**不可手寫**(手寫的 model uid/hash 幾乎一定編不過)。
> 計畫已把這一步獨立為「需要人工執行 build_runner」的任務。

---

## File Structure

| 檔案 | 責任 | 動作 |
|------|------|------|
| `example/pubspec.yaml` | 宣告 objectbox / path_provider 依賴 | Modify |
| `example/lib/objectbox_entities.dart` | `@Entity` 定義:`Note`(id/title/body)、`Tag`(id/label) | Create |
| `example/lib/objectbox_browser_source.dart` | `DatabaseBrowserSource` 的 ObjectBox 實作 + `_EntityAdapter` helper | Create |
| `example/lib/objectbox.g.dart` | build_runner 生成的 binding | Generate(commit) |
| `example/objectbox-model.json` | build_runner 生成的 model metadata | Generate(commit) |
| `example/lib/main.dart` | 加 Seed ObjectBox Demo 按鈕 + 註冊 source + web 防呆 | Modify |

---

## Chunk 1: Entity 定義與依賴

### Task 1: 新增 ObjectBox 依賴

**Files:**
- Modify: `example/pubspec.yaml`

- [ ] **Step 1: 加入依賴**

在 `dependencies:` 區塊(現有 `sqflite: ^2.4.0` 之後)加入:

```yaml
  objectbox: ^5.3.1
  objectbox_flutter_libs: any
  path_provider: ^2.1.0
```

在 `dev_dependencies:` 區塊(現有 `flutter_lints` 之後)加入:

```yaml
  build_runner: ^2.4.11
  objectbox_generator: any
```

- [ ] **Step 2: 取得依賴**

Run: `cd example && flutter pub get`
Expected: 成功解析,無版本衝突。若 objectbox 版本約束報錯,放寬為 `objectbox: any` 並記錄實際解析到的版本。

- [ ] **Step 3: Commit**

```bash
git add example/pubspec.yaml example/pubspec.lock
git commit -m "chore(example): add objectbox and path_provider dependencies"
```

---

### Task 2: 定義 Note 與 Tag entities

**Files:**
- Create: `example/lib/objectbox_entities.dart`

- [ ] **Step 1: 寫 entity 定義**

```dart
import 'package:objectbox/objectbox.dart';

/// A demo entity, intentionally shaped like the sqflite `users` table so you
/// can see the same kind of data rendered from a non-SQL source.
@Entity()
class Note {
  Note({this.id = 0, required this.title, this.body});

  @Id()
  int id;

  String title;

  String? body;
}

/// A second entity, so `ObjectBoxBrowserSource.listTables()` has more than one
/// "table" to enumerate — mirroring the two-table sqflite demo.
@Entity()
class Tag {
  Tag({this.id = 0, required this.label});

  @Id()
  int id;

  String label;
}
```

- [ ] **Step 2: 分析(此時會因缺少 objectbox.g.dart 而有 import 警告,屬預期)**

Run: `cd example && flutter analyze lib/objectbox_entities.dart`
Expected: 僅 objectbox 相關 import 解析正常;此檔本身不 import 生成檔,應無錯誤。

- [ ] **Step 3: Commit**

```bash
git add example/lib/objectbox_entities.dart
git commit -m "feat(example): define Note and Tag ObjectBox entities"
```

---

## Chunk 2: 生成 binding(需人工執行 build_runner)

### Task 3: 生成 objectbox.g.dart 與 objectbox-model.json

**Files:**
- Generate: `example/lib/objectbox.g.dart`
- Generate: `example/objectbox-model.json`

> 這一步需要本機已安裝 ObjectBox 的 native 產生環境。Claude 無法產生正確的
> 生成檔內容,必須由人執行下列指令。

- [ ] **Step 1: 執行 build_runner**

Run: `cd example && dart run build_runner build --delete-conflicting-outputs`
Expected:
- 終端輸出 `Succeeded after ...`。
- `example/lib/objectbox.g.dart` 出現,內含 `getObjectBoxModel()`、`openStore()`、`Note_`、`Tag_`。
- `example/objectbox-model.json` 出現。

若失敗:
- 缺 native lib → 依 https://docs.objectbox.io/getting-started 安裝(macOS 通常需 `bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-dart/main/install.sh)`)。
- 報 entity 錯 → 回頭檢查 Task 2 的 `@Id()` 欄位是否為非 nullable `int`。

- [ ] **Step 2: 確認生成檔內容合理**

Run: `cd example && grep -c "openStore\|getObjectBoxModel" lib/objectbox.g.dart`
Expected: ≥ 2(兩個 helper 都生成)。

- [ ] **Step 3: Commit 生成檔**

```bash
git add example/lib/objectbox.g.dart example/objectbox-model.json
git commit -m "chore(example): generate ObjectBox bindings for Note/Tag"
```

---

## Chunk 3: Source 實作與接線

### Task 4: 實作 ObjectBoxBrowserSource

**Files:**
- Create: `example/lib/objectbox_browser_source.dart`

- [ ] **Step 1: 寫 source 實作**

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:objectbox/objectbox.dart';

import 'objectbox.g.dart';
import 'objectbox_entities.dart';

/// A reference implementation of [DatabaseBrowserSource] for ObjectBox.
///
/// You can copy this code directly into your app to browse ObjectBox data.
///
/// Why this looks different from the sqflite source: a relational DB exposes a
/// dynamic schema (`SELECT *` returns column names for free). ObjectBox is a
/// strongly-typed object store with NO runtime schema reflection — so YOU
/// describe the schema, by registering one [_EntityAdapter] per entity type.
class ObjectBoxBrowserSource implements DatabaseBrowserSource {
  ObjectBoxBrowserSource(this._store, {this.name = 'ObjectBox database'});

  final Store _store;

  @override
  final String name;

  /// The "schema you write yourself": each entity type maps to its columns,
  /// a row count, and a function that flattens an object into a row.
  late final Map<String, _EntityAdapter> _adapters = {
    'Note': _EntityAdapter(
      columns: const ['id', 'title', 'body'],
      count: () => _store.box<Note>().count(),
      fetch: (limit, offset) => _store
          .box<Note>()
          .getAll()
          .skip(offset)
          .take(limit)
          .map((n) => [n.id, n.title, n.body])
          .toList(),
    ),
    'Tag': _EntityAdapter(
      columns: const ['id', 'label'],
      count: () => _store.box<Tag>().count(),
      fetch: (limit, offset) => _store
          .box<Tag>()
          .getAll()
          .skip(offset)
          .take(limit)
          .map((t) => [t.id, t.label])
          .toList(),
    ),
  };

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    return _adapters.entries
        .map((e) => DatabaseTableInfo(name: e.key, rowCount: e.value.count()))
        .toList();
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final adapter = _adapters[tableName];
    if (adapter == null) {
      // Unknown table — return an empty page rather than throwing, so the UI
      // degrades gracefully.
      return const DatabaseTablePage(columns: [], rows: [], totalRows: 0);
    }
    // NOTE: For production / large tables, replace getAll().skip().take() with
    // box.query().build()..offset = offset..limit = limit; then .find().
    // getAll() loads everything into memory — fine for this demo's tiny data.
    return DatabaseTablePage(
      columns: adapter.columns,
      rows: adapter.fetch(limit, offset),
      totalRows: adapter.count(),
    );
  }
}

/// Binds one entity type to the way it should appear as a browsable table.
class _EntityAdapter {
  _EntityAdapter({
    required this.columns,
    required this.count,
    required this.fetch,
  });

  final List<String> columns;
  final int Function() count;
  final List<List<Object?>> Function(int limit, int offset) fetch;
}
```

- [ ] **Step 2: 分析**

Run: `cd example && flutter analyze lib/objectbox_browser_source.dart`
Expected: No issues found.(前提:Task 3 的生成檔已存在。)

- [ ] **Step 3: Commit**

```bash
git add example/lib/objectbox_browser_source.dart
git commit -m "feat(example): add ObjectBoxBrowserSource reference implementation"
```

---

### Task 5: main.dart 接線(Seed 按鈕 + 註冊 + web 防呆)

**Files:**
- Modify: `example/lib/main.dart`

- [ ] **Step 1: 加 import**

在現有 import 區塊(`import 'sqflite_browser_source.dart';` 之後)加入:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'objectbox.g.dart';
import 'objectbox_browser_source.dart';
import 'objectbox_entities.dart';
```

- [ ] **Step 2: 加 state 旗標**

在 `_MyHomePageState` 內,現有 `bool _sqliteRegistered = false;` 旁邊加入:

```dart
  bool _objectboxRegistered = false;
  Store? _objectboxStore;
```

- [ ] **Step 3: 加 _seedObjectBox 方法**

在 `_seedSqlite()` 方法之後加入(緊鄰,維持兩個 seed 方法相鄰):

```dart
  Future<void> _seedObjectBox() async {
    // ObjectBox relies on native libraries and does NOT support web.
    // Fail loudly-but-gracefully instead of crashing the app.
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ObjectBox is not supported on web. '
              'Run this demo on a mobile or desktop target.',
            ),
          ),
        );
      }
      return;
    }
    if (_objectboxRegistered) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final store = openStore(directory: '${dir.path}/objectbox-demo');
      _objectboxStore = store;

      final noteBox = store.box<Note>();
      if (noteBox.isEmpty()) {
        noteBox.putMany([
          Note(title: 'Welcome', body: 'This row comes from ObjectBox.'),
          Note(title: 'No SQL here', body: null),
          Note(title: 'Strongly typed', body: 'Mapped by hand in the source.'),
        ]);
      }

      final tagBox = store.box<Tag>();
      if (tagBox.isEmpty()) {
        tagBox.putMany([Tag(label: 'demo'), Tag(label: 'objectbox')]);
      }

      inspector.registerDatabaseSource(
        ObjectBoxBrowserSource(store, name: 'objectbox-demo'),
      );
      _objectboxRegistered = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ObjectBox demo seeded and registered!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ObjectBox seeding failed: $e')));
      }
    }
  }
```

- [ ] **Step 4: 加按鈕**

在 build() 的 Column children 中,`Seed SQLite Demo` 的 `ElevatedButton` 與其後
`SizedBox(height: 20)` 之後,插入:

```dart
            ElevatedButton(
              onPressed: _seedObjectBox,
              child: const Text('Seed ObjectBox Demo'),
            ),
            const SizedBox(height: 20),
```

- [ ] **Step 5: 加 dispose 釋放 store**

在 `_MyHomePageState` 找 `dispose()`;若不存在則新增。確保關閉 store:

```dart
  @override
  void dispose() {
    _objectboxStore?.close();
    super.dispose();
  }
```

> 若已有 `dispose()`,只加 `_objectboxStore?.close();` 一行(在 `super.dispose()` 前)。

- [ ] **Step 6: 分析**

Run: `cd example && flutter analyze`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add example/lib/main.dart
git commit -m "feat(example): wire ObjectBox seed button and source registration"
```

---

## Chunk 4: 整合驗證

### Task 6: 全量分析 + 編譯驗證

- [ ] **Step 1: 全專案分析**

Run: `cd example && flutter analyze`
Expected: No issues found.

- [ ] **Step 2: 編譯驗證(擇一可用平台,非 web)**

Run: `cd example && flutter build apk --debug`(或 `flutter build macos --debug`)
Expected: 編譯成功。確認 ObjectBox native libs 正確連結。

- [ ] **Step 3: 人工煙霧測試**

1. `cd example && flutter run`(行動裝置/桌面,非 web)。
2. 點 `Seed ObjectBox Demo` → 應見 SnackBar「seeded and registered」。
3. 觸發 Inspector(magical tap / FAB)開 Dashboard → Database tab。
4. 應見來源 `objectbox-demo`,展開有 `Note`(3 列)、`Tag`(2 列)兩張表。
5. 點 cell 可複製值。

- [ ] **Step 4: README 補一句(可選)**

**Files:** Modify `example/README.md`
若 README 列出 demo 功能,補一行說明 ObjectBox demo 示範非 SQL 資料源接入。

- [ ] **Step 5: Final commit(若有 README 改動)**

```bash
git add example/README.md
git commit -m "docs(example): mention ObjectBox non-SQL source demo"
```

---

## 向後相容性檢查清單

- [ ] `lib/` 套件程式碼零改動(`git diff --stat main -- lib/` 應為空)。
- [ ] `DatabaseBrowserSource` 介面未變。
- [ ] sqflite demo 仍正常運作(seed 按鈕、Database tab)。
