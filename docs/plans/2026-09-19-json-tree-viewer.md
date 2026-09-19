# P17 實作計畫 · 原生折疊式 JSON 樹狀檢視器（JsonTreeViewer）

> **規格來源**：`docs/features/2026-09-19-json-tree-viewer.md`
> **階段**：STAGE 0b 實作計畫（How）· 2026-09-19
> **新增檔案**：1 個 lib + 2 個 test；**修改檔案**：2 個 detail view

---

## 0. 核心判斷

✅ **值得做**。痛點是實查過的真實問題（`key_value_table.dart:15` 的
`toString()` 把巢狀壓成單行 blob；`prettyJson()` 吐三百行扁平縮排）。

**關鍵洞察（資料結構先行）**：這功能的本質是
**「把遞迴的 JSON 樹壓成一維的可見節點清單」**。一旦扁平化節點的形狀對了，
折疊、搜尋過濾、`ListView.builder`、路徑複製**全部退化成同一個 list 的重建**，
沒有任何特殊情況。反之若用遞迴 widget 樹，折疊/搜尋/效能會各自長出分支。

**Ponytail 階梯結果**：
- 第 2 階（codebase 已有）：`DetailSection` / `ThemePadding` / `ThemeSize` /
  `ThemeTextStyle.monospaceStyle` 全部重用，不新增主題 token。
- 第 3 階（stdlib）：decode 用 `dart:convert` 的 `jsonDecode`，
  不自寫 parser。
- 第 5 階（禁新增相依）：規格驗收條件 9 已鎖死，無討論空間。
- 最終落在第 7 階：**一個檔案、一個 public widget、一個 private 節點 class**。

**砍掉的東西**（明確不做，避免實作時長回來）：
- ❌ 不做 `JsonNode` 的 public export（純 UI 內部結構，`json_tree_viewer.dart`
  的 library-private）。
- ❌ 不做 `JsonTreeController` / 不做 interface / 不做 factory。
  只有一個實作的抽象＝噪音。
- ❌ 不做 `expandDepth` 之外的任何 config 參數。

---

## 1. 資料結構（最關鍵的一節）

### 1.1 扁平節點 `_JsonNode`

整棵樹在 `initState`（或資料變更時）**一次性展開成完整的扁平清單**，
之後折疊/搜尋只是在這份清單上做**篩選**，不重建樹。

```dart
/// A single row in the flattened tree. Immutable — expansion state lives
/// outside, in the widget's Set<String> of expanded node ids.
class _JsonNode {
  const _JsonNode({
    required this.id,
    required this.parentId,
    required this.path,
    required this.label,
    required this.depth,
    required this.kind,
    required this.valueText,
    required this.childCount,
  });

  /// Structural identity: the chain of sibling ordinals, e.g. `0.3.1`.
  /// Derived from traversal order, never from key content, so it cannot
  /// collide no matter what characters a map key contains.
  final String id;

  /// Id of the owning container; '' for children of the root.
  final String parentId;

  /// Human-readable path for display and copy, e.g. `data.users[0].id`.
  /// Root node's path is ''. Two nodes may share a path when a map key
  /// itself contains '.', which is harmless — this field never keys state.
  final String path;

  /// The display key: `id` for a map entry, `[0]` for a list element,
  /// '' for the root.
  final String label;

  /// Indent level. Root = 0.
  final int depth;

  final _JsonKind kind; // map / list / leaf

  /// Rendered value: `toString()` for leaves (R5), a summary such as
  /// `{3}` / `[12]` for containers.
  final String valueText;

  /// Number of direct children; 0 for leaves.
  final int childCount;
}

enum _JsonKind { map, list, leaf }
```

**為什麼 expansion state 不放在節點上**：節點若可變，搜尋過濾就得複製一份或
就地改寫，產生「第二份真相」。改成 `Set<String> _expanded`（存 **id**）後，
折疊狀態與節點清單完全正交，R3 的「還原 / 重置」也只是對這個 Set 動手。

**為什麼 id 與 path 必須分離（避免 key 撞名）**：`path` 一個欄位無法同時
承擔「給人看的可讀字串」與「狀態的唯一 key」兩種相反需求。
`{'a.b': {'c': 1}}` 與 `{'a': {'b': {'c': 1}}}` 的 path 同為 `a.b.c`，
若 path 兼任 `_expanded` 的 key，展開其中一個會連帶展開另一個——
這是行為錯誤，不是顯示瑕疵。
拆成 `id`（走訪序號鏈，與 key 內容無關 ⇒ 結構上不可能撞）與
`path`（純顯示/複製）後，特殊情況自然消失，**不需要任何跳脫邏輯**：
複製出來的仍是 `a.b.c`，正是使用者要貼進程式碼的字串，
跳脫成 `a\.b.c` 反而不能直接用。

**誰擁有**：`_JsonTreeViewerState` 擁有 `List<_JsonNode> _all`（不可變，
資料變更才重建）與 `Set<String> _expanded`（可變，存 id）。

### 1.2 扁平化演算法（`_flatten`）

深度優先前序走訪，遞迴改成**顯式堆疊**以支援 R4 的深度上限與循環偵測。

- 輸入：`Object? root`（`Map` / `List` / primitive / 任意物件）
- 輸出：`List<_JsonNode>`，前序排列 ⇒ **父節點必定排在其所有子孫之前**，
  這個性質讓「可見節點計算」變成一次線性掃描。

**id 的產生**：每個容器對自己的直接子節點依走訪順序編號 0,1,2…，
子節點 `id = parentId.isEmpty ? '$i' : '$parentId.$i'`。
序號來自走訪順序而非 key 內容，故
`{'a.b': …}` 得到 `0`、`{'a': {'b': …}}` 得到 `0.0`，**結構上不可能相撞**。

**R4 防禦（不得省略）**：
- **深度上限 `_kMaxDepth = 32`**。超過上限的容器不再展開，
  直接產生一個 `leaf` 節點，`valueText` 為 `'… (max depth reached)'`。
- **循環偵測**：走訪路徑上維護 `List<Object>` 的祖先堆疊，
  以 `identical()` 比對（不是 `==`，自訂物件可能覆寫 `==` 導致誤判）。
  命中即產生 leaf，`valueText` 為 `'… (circular reference)'`。
  離開節點時必須 pop，否則同一個共享子物件（DAG，非循環）會被誤報。

**R5（非 JSON 型別）**：`kind` 判定只認 `Map` 與 `List`（用
`is Map` / `is List`，不是 `is Map<String, dynamic>`——`LogEntry.data`
的巢狀值實際型別常是 `Map<dynamic, dynamic>`，寫死泛型會漏判）。
其餘一律 `leaf`，`valueText = value.toString()`（`null` → `'null'`，
`String` 直接顯示不加引號，與現況 `KeyValueTable` 一致，無退化）。

### 1.3 可見節點計算（`_visibleNodes`）

```dart
List<_JsonNode> _visibleNodes()
```

單次線性掃描 `_all`，兩層篩選：

1. **折疊篩選**：節點可見 ⟺ `parentId == ''`（根層）或
   `parentId ∈ _expanded`。
   因為前序排列，父折疊時其子孫的 `parentId` 不在 `_expanded`，
   自然一路隱下去，不需要額外的「skip subtree」邏輯。
   *（前提：折疊一個節點時不從 `_expanded` 移除其子孫——子孫留著也不可見，
   展開時還能還原使用者原本的展開狀態，是「免費」的好行為。）*
2. **搜尋篩選**（`_query` 非空時）：先算出命中集合
   `hits = { n | n.label.contains(q) || n.valueText.contains(q) }`（
   大小寫不敏感），再把每個 hit 的祖先鏈（沿 `parentId` 往上，
   用一個 `Map<String, _JsonNode>`（id → node）索引查父）
   加入 `keep`。可見集合 = `keep ∩ 折疊篩選結果`，
   但搜尋期間**祖先鏈強制視為展開**（驗收條件 4：祖先鏈必須可見）。

複雜度：O(N) 每次重建，N = 節點總數。展開/折疊/輸入搜尋各觸發一次
`setState` → 一次 O(N)。**不是 O(N²)**（驗收條件 5）。

### 1.4 路徑組成

- map 子節點：`parent.isEmpty ? key : '$parent.$key'`
- list 子節點：`'$parent[$index]'`（根為 list 時 → `[0]`，可接受）

**`path` 只負責顯示與複製，不參與任何狀態識別**（狀態一律用 `id`，見 §1.1）。
因此 map key 含 `.` 造成的 path 撞名**不影響行為**：`{'a.b': {'c': 1}}` 與
`{'a': {'b': {'c': 1}}}` 顯示同為 `a.b.c`，但 id 分別是 `0` 與 `0.0`，
展開互不干擾。
**不加跳脫邏輯**——`a\.b.c` 無法直接貼進程式碼，反而破壞複製的用途。

**A2 必須涵蓋的測資**：`{'a.b': {'c': 1}, 'a': {'b': {'c': 2}}}`
混在同一份資料，斷言展開前者不影響後者的折疊狀態。

---

## 2. API 定案（三個開放題）

### 2.1 R1 — 建構式與 decode 責任

**定案：元件只接受已解析資料；decode 責任在呼叫端；fallback 分支落在
`NetworkDetailView`。**

```dart
class JsonTreeViewer extends StatefulWidget {
  /// [data] is already-decoded JSON-like data (Map / List / primitive).
  const JsonTreeViewer(this.data, {this.emptyLabel, super.key});

  final Object? data;

  /// Shown when [data] is null or an empty container. Null → renders
  /// nothing special (a single `null` leaf).
  final String? emptyLabel;
}
```

**理由**：
- 兩側輸入形狀不同（Network 是字串、Log 是 `Map<String, dynamic>?`）。
  若元件吃字串，Log 側就得先 `jsonEncode` 再讓元件 decode——**純浪費，
  且對 `DateTime` 這類非 JSON 型別會直接炸掉**，違反 R5。
  所以元件吃已解析資料是唯一正確方向。
- decode 失敗的 fallback**必須回到純文字**，而純文字的樣式
  （`SelectableText` + `monospaceStyle` + 容器裝飾）是 `_bodySection` 既有的
  東西。把 fallback 放在元件內，元件就得知道「純文字長怎樣」，
  責任錯置；放在呼叫端則是**一個 `if`**。最短 diff 勝出。
- **不提供 `JsonTreeViewer.fromJsonString()` 命名建構式**——它只會是
  `try { jsonDecode } catch { ??? }`，而 `???`（fallback widget）無法在
  元件內決定。只有一個呼叫點，不值得為它造 API。

Network 側呼叫端（`_bodySection` 內）：

```dart
final decoded = isJson ? _tryDecode(body) : null;   // null ⇒ 走純文字
// _tryDecode: try { return jsonDecode(body); } on FormatException { return null; }
```

**注意**：`jsonDecode('null')` 合法且回傳 `null`，與失敗同值。
但 body 為字面 `'null'` 時純文字呈現也是 `null`，**兩條路輸出相同**，
不需要區分——這正是「消滅特殊情況」。

### 2.2 R2 — 是否加「切回純文字」開關

**定案：不做。**

理由：
1. 規格驗收條件 10 已保證 `prettyJson()` 與分享/複製全文路徑不變，
   「拿到完整原文」的需求**已有既有出口**（share menu 的 Copy as text）。
   加開關是解決一個已被解決的問題。
2. `LogDetailView` 的 `_isConcise` 不是對等前例——它切換的是
   **兩種都無法從別處取得的內容**（normalize 前後的 stack trace），
   而這裡的純文字隨時可從 share menu 取得。一致性論點站不住。
3. 開關會在兩個 detail view 各長出一份狀態（`NetworkDetailView` 目前是
   `StatelessWidget`，為了開關得升級成 `StatefulWidget`，且有
   Request/Response 兩個 body 要各自記狀態）。成本與收益不成比例。

若日後有實證回報「需要選取任意片段」，再另立 feature。

### 2.3 R3 — 搜尋清除後的折疊狀態

**定案：還原搜尋前狀態。**

理由：使用者搜尋前的展開佈局是他自己一路點出來的「工作現場」，
清除搜尋就抹掉它是資料遺失級的體驗退化。而還原的實作成本**趨近於零**——
搜尋期間**根本不修改 `_expanded`**，祖先鏈的強制可見是
`_visibleNodes()` 的計算結果，不是狀態變更。清除搜尋 ⇒ `_query = ''`
⇒ 計算自然回到原本的 `_expanded`。

**「重置為預設 2 層」反而要多寫程式碼**（得存一份初始 Set 再覆蓋回去）。
懶惰與正確在此同向。

必寫測試：`test/ui/widgets/json_tree_viewer_test.dart` 的
`'清除搜尋後還原搜尋前的折疊狀態'`。

### 2.4 預設展開深度

建構 `_expanded` 初值 = `{ n.id | n.depth < 2 && n.kind != leaf }`，
即第 0、1 層容器展開，第 2 層（含）以下折疊（驗收條件 2）。
深度常數 `_kDefaultExpandDepth = 2`，**不開放成參數**（沒有第二個呼叫點
需要不同值 ⇒ config for a value that never changes，禁止）。

---

## 3. 檔案異動清單

| # | 檔案 | 動作 | 具體位置 |
|:--|:--|:--|:--|
| F1 | `lib/src/ui/widgets/json_tree_viewer.dart` | **新增** | 全新檔；含 `JsonTreeViewer`（public）、`_JsonNode`、`_JsonKind`、`_JsonNodeRow`、`_flatten`（library-private） |
| F2 | `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | 修改 | `_bodySection`（:171–190）改為 decode + 分支；新增 `dart:convert` import |
| F3 | `lib/src/ui/dashboard/tabs/console/log_detail_view.dart` | 修改 | `_dataSection`（:139 附近）`KeyValueTable` → `JsonTreeViewer`；import 換掉 `key_value_table.dart` |
| F4 | `test/ui/widgets/json_tree_viewer_test.dart` | **新增** | 元件本體全部測試 |
| F5 | `test/ui/tabs/network_detail_view_test.dart` | 修改（追加） | 追加 decode 失敗 fallback / 非 JSON 路徑測試 |
| F6 | `test/ui/tabs/log_detail_view_test.dart` | 修改（追加） | 追加巢狀 data 渲染 / `(no data)` 空狀態測試 |

**不動**：`network_formatters.dart`（`prettyJson` 原封不動）、
`key_value_table.dart`（Network 的 headers/query 仍用它，**禁止刪除**）、
`theme/`（無新增 token 需求）、`pubspec.yaml`。

---

## 4. 元件內部結構（Widget 拆分）

依專案規則，新增 widget **一律獨立類別，禁止 `_buildXxx()`**：

- `JsonTreeViewer`（`StatefulWidget`，public）
  - `_JsonTreeViewerState`：持有 `_all` / `_expanded` / `_query` /
    `_searchController`；`build()` 回傳
    `Column[搜尋框, ListView.builder]`。
  - `didUpdateWidget`：`widget.data` 變更時重建 `_all` 與 `_expanded`。
  - `dispose`：`_searchController.dispose()`（資源管理規則）。
- `_JsonNodeRow`（`StatelessWidget`）：單列渲染。
  參數：`_JsonNode node`（positional，核心資料）+
  `{required bool isExpanded, required VoidCallback? onToggle,
  required String query}`（named，配置 ≥3 且含 bool）。
  - 內容：縮排 `SizedBox(width: depth * ThemeSize.space12)` →
    展開箭頭（`kind != leaf` 才給，`Icons.chevron_right` /
    `expand_more`，`ThemeSize.size16`）→ `label:` → `valueText`。
  - **文字一律主題預設前景色**（驗收條件 6），
    樣式用 `ThemeTextStyle.monospaceStyle`。
  - **搜尋高亮**：用 `Text.rich` + `TextSpan` 對 `query` 命中片段套
    `backgroundColor: Theme.of(context).colorScheme.primaryContainer`。
    這是唯一的著色例外。
  - **複製**：整列包 `InkWell`，`onLongPress` → `Clipboard.setData`
    寫入 `'${node.path}: ${node.valueText}'`（驗收條件 3）。
    root 節點 path 為空時只寫 `valueText`。
    複製後 `ScaffoldMessenger` 顯示 SnackBar
    （呼叫在 `await` 前先取出 messenger，遵守 async-gap 規則）。
  - `onTap` → `onToggle`（leaf 為 `null` ⇒ 無展開 affordance，
    驗收條件 1）。

**巢狀深度自查**：`_JsonNodeRow.build` = `InkWell > Padding > Row > [子項]`
＝ 4 層，踩線但未超。若實作時超出，把高亮的 `Text.rich` 抽成
`_HighlightedText` 獨立類別。

**`_flatten` 長度自查**：顯式堆疊版本約 40 行，在 ≤50 行限制內。
若超出，把「單一 value → `_JsonKind` + `valueText`」抽成
`_describe(Object? value)` 頂層函式。

---

## 5. 任務拆分

每個任務 2–5 分鐘。**並行判斷以「寫入路徑是否重疊」為準**。

### 批次 A：元件核心（序列，同一檔案 F1 + F4）

| # | 任務 | 做什麼 | 驗收條件 | 測試要求 | 並行 |
|:--|:--|:--|:--|:--|:--|
| A1 | 建立 `_JsonNode` / `_JsonKind` | 在 F1 定義 §1.1 的不可變資料結構（含 `id` / `parentId` / `path` 三者分離），無邏輯 | 檔案編譯通過；`flutter analyze` 零新增 info | 無（純資料結構，trivial） | ❌ 批次內序列 |
| A2 | 寫 `_flatten` 的測試（TDD 先行） | 在 F4 建立 `_Data` 類別與 `group('_flatten')`；涵蓋 map/list/巢狀/primitive 根，**以及 §1.4 的 key 含 `.` 撞名測資** | 測試存在且**紅燈** | — | ❌ |
| A3 | 實作 `_flatten` 基本走訪 | 顯式堆疊前序走訪，產出扁平清單 + 正確 id/parentId/path/depth | A2 全綠（含撞名案例：path 相同但 id 不同） | A2 | ❌ |
| A4 | **R4 深度上限測試 + 實作** | 測資：巢狀 40 層的 Map；斷言節點數有界且出現 `max depth reached` leaf | 不 stack overflow、不無限展開 | unit（透過 widget 渲染斷言，或把 `_flatten` 設為 `@visibleForTesting` 頂層函式） | ❌ |
| A5 | **R4 循環引用測試 + 實作** | 測資：`final m = <String, dynamic>{}; m['self'] = m;`。斷言出現 `circular reference` 且終止 | 不 hang、不 OOM | unit | ❌ |
| A6 | **R5 非 JSON 型別測試 + 實作** | 測資含 `DateTime`、自訂 `class Foo { toString() => 'FOO' }`、`null`、`int`、`bool` | 皆為 leaf、`valueText == value.toString()`、`null` → `'null'` | unit | ❌ |
| A7 | 實作 `JsonTreeViewer` 骨架 + 預設 2 層 | `StatefulWidget`、`initState` 建 `_all`/`_expanded`、`ListView.builder` 渲染 `_JsonNodeRow` | 驗收條件 2、5 | widget：斷言第 3 層節點初始不可見 | ❌ |
| A8 | 實作 `_JsonNodeRow` 展開/折疊 | `onTap` toggle `_expanded`；leaf 無箭頭 | 驗收條件 1 | widget：點展開後子節點出現，再點消失 | ❌ |
| A9 | 實作搜尋框 + 過濾 + 祖先鏈保留 | `TextField` → `_query`；`_visibleNodes` 的兩層篩選 | 驗收條件 4 | widget：搜尋後只剩命中 + 祖先鏈 | ❌ |
| A10 | **R3 清除搜尋還原狀態測試** | 展開某深層節點 → 搜尋 → 清除 → 斷言該節點仍展開 | §2.3 定案 | widget | ❌ |
| A11 | 實作搜尋高亮 | `Text.rich` 命中片段套 `primaryContainer` 底色 | 驗收條件 4、6（唯一著色例外） | widget：斷言 `RichText` 含多個 span | ❌ |
| A12 | 實作長按複製路徑與值 | `InkWell.onLongPress` → Clipboard + SnackBar | 驗收條件 3 | widget：mock `SystemChannels.platform`，斷言 `data.users[0].id: 1` 格式（比照 `network_detail_view_test.dart` 既有 clipboard mock 寫法） | ❌ |
| A13 | 空狀態 `emptyLabel` | `data == null` 或空容器 → 顯示 `emptyLabel`（比照 `KeyValueTable` 的 muted italic 樣式） | 驗收條件 8 | widget | ❌ |

### 批次 B：兩側接線（**B1 與 B2 可並行**，寫入路徑不重疊）

| # | 任務 | 做什麼 | 驗收條件 | 測試要求 | 並行 |
|:--|:--|:--|:--|:--|:--|
| B1 | Network 接線（F2 + F5） | `_bodySection` 加 `_tryDecode`；decode 成功 → `JsonTreeViewer(decoded)`，否則維持既有 `SelectableText(prettyJson/body)` 路徑逐字不變 | 驗收條件 7、10；**R1 fallback** | 追加 3 個 widget test：(a) `isJson==true` 且合法 → 樹出現；(b) `isJson==true` 但 body 為 `'{"a":'` 截斷 → 不拋例外且 `SelectableText` 仍在；(c) `isJson==false` → 純文字路徑不變 | ✅ 與 B2 並行 |
| B2 | Log 接線（F3 + F6） | `_dataSection` 改 `JsonTreeViewer(widget.entry.data, emptyLabel: '(no data)')`；移除 `key_value_table` import | 驗收條件 8 | 追加 2 個 widget test：(a) 巢狀 `{'a': {'b': 1}}` 可展開；(b) `data == null` → `(no data)` | ✅ 與 B1 並行 |

### 批次 C：驗證（序列，最後）

| # | 任務 | 做什麼 | 驗收條件 |
|:--|:--|:--|:--|
| C1 | `flutter test` 全綠 | 含既有 606 tests + 新增 | 零失敗 |
| C2 | `flutter analyze lib/ test/` | 比對基準 | **不超過 7 個既有 info** |
| C3 | `make format` | `dart format .` | 無未格式化檔 |

**總任務數：18**（A 13 + B 2 + C 3）。
**可並行者：B1 / B2 兩項**（其餘因共用 F1/F4 或有前後依賴而序列）。

---

## 6. 測試策略

| 類型 | 位置 | 覆蓋 |
|:--|:--|:--|
| **unit**（`_flatten`） | `test/ui/widgets/json_tree_viewer_test.dart` 的 `group('_flatten')` | R4 深度上限、R4 循環引用、R5 非 JSON 型別、path 組成正確性、**key 含 `.` 時 path 撞名但 id 唯一** |
| **widget**（`JsonTreeViewer`） | 同檔 `group('JsonTreeViewer')` | 預設 2 層、展開/折疊、搜尋過濾+祖先鏈、**R3 清除搜尋還原**、高亮、長按複製、空狀態、**撞名節點的展開互不干擾** |
| **widget**（接線） | `network_detail_view_test.dart` / `log_detail_view_test.dart` 追加 | **R1 decode 失敗 fallback**、非 JSON 路徑不變、Log 巢狀渲染、`(no data)` |

**測資分離**：所有 JSON 測資放同檔 `class _Data`（專案規則 §8.2），
例如 `_Data.nested`、`_Data.deep40`、`_Data.cyclic()`（循環需工廠方法，
不能用 `const`）、`_Data.mixedTypes`。

**`_flatten` 如何被 unit test 觸及**：把它設為 `json_tree_viewer.dart` 的
**頂層函式 + `@visibleForTesting`**，回傳 `List<_JsonNode>`。
`_JsonNode` 雖 private，測試可透過 `library-private` 無法跨檔存取——
故 **`_JsonNode` 改為 `JsonNode`（public 但不從 package 的
`flutter_inspector_kit.dart` barrel 匯出）**，測試以
`package:flutter_inspector_kit/src/ui/widgets/json_tree_viewer.dart`
直接 import（既有測試已是這種 `src/` 直接 import 風格）。
**這不違反「禁止未經要求的抽象」**——沒有多出任何型別，只是可見性調整。

**大型 payload 效能（驗收條件 5）不寫效能測試**——
`ListView.builder` 本身即 lazy build，寫一個「幾毫秒內完成」的測試在 CI
缺席的環境下只會變成 flaky。改以**結構性斷言**代替：
一個 1000 節點的 payload，斷言 `find.byType(_JsonNodeRow)` 的數量
**遠小於 1000**（證明只建構可視範圍）。

---

## 7. 風險與回滾

### 7.1 零破壞的保證

| 既有行為 | 是否受影響 | 憑據 |
|:--|:--|:--|
| `prettyJson()` | ❌ 不動 | F2 僅在 decode 成功時繞過它；失敗仍呼叫 |
| `buildNetworkPlainText` / `buildCurl` / share menu | ❌ 不動 | 未修改 `network_formatters.dart` / `share_text.dart` |
| `KeyValueTable` | ❌ 不刪 | Network 的 Query Params / Request Headers / Response Headers 三處仍用 |
| `RingBuffer` / `mergedTimeline` / `InspectorRegistry` | ❌ 不動 | 本功能純 UI 呈現層 |
| 條件匯出（`_io.dart` / `_web.dart`） | ❌ 不動 | 無觸及 |

### 7.2 既有測試的碰撞面（已實查）

- `test/ui/tabs/network_detail_view_test.dart`：**實查確認**僅斷言
  `find.text('Request Body')` / `'Response Body'` 等**區塊標題**，
  未對 body 內容文字做斷言。改渲染方式**不破壞**這些測試。
  但 `:558` 與 `:609` 有針對 `SelectableText` 的 predicate 斷言——
  那兩處分別是 General 的 `'-'` 與 Exception 的 stack trace，
  **不在 body section**，不受影響。
- `test/ui/tabs/log_detail_view_test.dart`：`:47` 有
  `expect(find.textContaining('exceptionType'), findsOneWidget)`。
  `JsonTreeViewer` 渲染扁平 data 時 `exceptionType` 仍會出現
  （第 1 層，預設展開），**但可能因 `Text.rich` 而變成 `RichText`**，
  `findsOneWidget` 的計數也可能改變。
  ⚠ **B2 必須實際跑這個測試**，若紅燈，**調整測試斷言而非改行為**
  （渲染方式改變是本功能的目的，測試跟進是正當的）。
- `test/ui/tabs/console_tab_test.dart`（22K）：若其中有從 Console 點進
  detail view 並斷言 data 內容的案例，同上處理。**B2 執行時需一併跑。**

### 7.3 回滾方案

三個修改點彼此獨立、且都是「一個分支 / 一行替換」：
- 回滾 Network：`_bodySection` 還原為 `final rendered = isJson ? prettyJson(body) : body;`
- 回滾 Log：`_dataSection` 還原為 `KeyValueTable(...)`
- `json_tree_viewer.dart` 為純新增檔，刪除即可，無任何反向依賴。

⇒ **可單側回滾**（例如只回滾 Log 側而保留 Network 側），
因為兩者無耦合。

### 7.4 主要風險點

| 風險 | 緩解 |
|:--|:--|
| `_flatten` 對極大 payload 一次性全展開（1000 節點都建 `_JsonNode`） | 節點物件很輕（6 個欄位、無 widget）；`ListView.builder` 才是渲染瓶頸的關鍵，已解。若日後遇到十萬節點再談懶展開——**現在不做**（臆測需求） |
| `Text.rich` 高亮使既有 `find.text(...)` 斷言失效 | 只在 `_query` 非空時走 `Text.rich`；**`_query` 為空時用純 `Text`**，既有斷言行為不變。這是一行 if，值得 |
| `analyze` 新增 info（尤其 `dynamic` 與 `!`） | `_flatten` 的走訪值型別用 `Object?` 而非 `dynamic`；不使用 `!`；所有 map iteration 用 `MapEntry<Object?, Object?>` |

---

## 8. 執行方式選項

| 方式 | 適用 | 說明 |
|:--|:--|:--|
| **A. subagent-driven（建議）** | 本計畫 | 批次 A 交給單一 implementer 序列跑完（同檔案，並行只會衝突）；批次 B 的 B1/B2 派給兩個 subagent 並行（F2+F5 與 F3+F6 完全不重疊）；批次 C 由主對話收斂驗證 |
| **B. parallel session** | 不建議 | 批次 A 佔 13/18 任務且無法並行，開多 session 的協調成本高於收益 |
| **C. 單一 session 序列** | 可接受的保守選項 | 全部 18 任務由一個 session 跑完，B1/B2 的並行收益（約 1 個任務時間）放棄 |

**建議採 A**，並行點僅 B1/B2 一處，收益有限但零風險。
