# 實作計畫：Dashboard 錯誤計數 Badge（§P6）

> Spec（唯一需求真實來源）：`docs/features/2026-08-07-dashboard-error-badge.md`
> 本文件只寫 **How**。需求爭議一律回 spec，不在此重新討論。

---

## 一、資料結構與資料流

### 1.1 關鍵實查結論：唯一寫入路徑是 `RingBuffer`，不是 inspector

Spec 採用路線 (C)（單一 revision notifier），但「notifier 掛哪一層」是本次最關鍵的設計判斷。
實查四個 inspector 後，事實如下：

| inspector | 寫入方式 | 通知鉤子 |
|---|---|---|
| `LogInspector.add` | `_buffer.add(entry)` | 無 |
| `NavigatorInspector.add` | `_buffer.add(entry)` | 無 |
| `DatabaseInspector.add` | `_buffer.add(entry)` | 無 |
| `NetworkInspector.add` | `_buffer.replace(...)` 或 `_buffer.add(...)` | `onAdd`（**已被 `NetworkNotifier` 佔用**） |

四者的共同點：**每一次資料變動都必然穿過 `RingBuffer` 的 `add` / `replace` / `clear` 三個方法**。
且全 `lib/` 只有這四個 `RingBuffer` 實例（已驗證，`grep RingBuffer lib/` 僅命中四個 inspector 的欄位宣告），
沒有任何其他消費端會被誤觸發。

### 1.2 方案比較

| 方案 | 做法 | 判定 |
|---|---|---|
| **(甲) registry 持有 notifier，四個 inspector 回呼** | `InspectorRegistry` 建 `ValueNotifier`，四個 inspector 各加一個 `VoidCallback? onChanged` 欄位，registry 建構時接線 | ❌ |
| **(乙) `FlutterInspector` 持有 notifier，在 8 個公開方法遞增** | `log()` / `logNetwork()` / `database()` / navigator observer + 四個 `clearXxx()` 各加一行 | ❌ |
| **(丙) `RingBuffer` 持有 notifier，registry 注入同一個實例** | `RingBuffer` 建構式收一個 `VoidCallback? onMutate`，在 `add` / `replace` / `clear` 尾端呼叫。`InspectorRegistry` 建立**一個** `ValueNotifier<int>`，把同一個遞增回呼交給四個 inspector 轉傳給各自的 buffer | ✅ **採用** |

**採用 (丙) 的理由：**

1. **它是唯一「消滅特殊情況」的位置。** spec §核心設計決策第 3 點要求「把通知收斂到資料寫入的唯一路徑，
   新增任何寫入端都自動正確，不需要接線」。`RingBuffer` **就是**那個唯一路徑。
   (甲) 與 (乙) 都只是把接線從 4 條變成 4 條——(甲) 要在四個 inspector 各補一個 `onChanged` 欄位與呼叫點，
   (乙) 要在 8 個方法各補一行。兩者都是「靠人記得」的設計，日後新增 `NetworkInspector.remove()`、
   或任何直接動 buffer 的方法時必然會漏。(丙) 漏不掉，因為繞過 `RingBuffer` 就等於沒有資料。

2. **(丙) 的 diff 最小。** `RingBuffer` 加 1 個 optional 欄位 + 3 行呼叫；
   四個 inspector 各改 1 行建構式；registry 加 1 個 notifier + 1 個私有遞增方法。
   (甲) 要動的行數是它的兩倍以上，而且新增了「inspector 有 onChanged 欄位」這個永久的概念負擔。

3. **`replace` 也被涵蓋，這是 (甲)/(乙) 會漏的真實 bug。**
   `NetworkInspector.add(entry, replaces: pending)` 是 pending → completed 的轉換路徑。
   **失敗的請求正是走這條路徑產生的**（pending 時 `statusCode == null` 故 `isFailed == false`，
   completed 時才帶 4xx/5xx 或 `error`）。若 notifier 只掛在 inspector 的 `add` 進入點，
   語意上仍會通知，但 (丙) 在 `RingBuffer` 層天然涵蓋 `replace`，語意更精確：
   **「buffer 內容變了」才通知，而不是「有人呼叫了 add」**。

4. **零公開 API 破壞。** `RingBuffer` 的新參數是 optional named（`RingBuffer(capacity, {this.onMutate})`），
   既有 `RingBuffer<int>(3)` 呼叫全數不變 → `test/core/ring_buffer_test.dart` 13 項測試零改動通過。

**確認不與 `NetworkInspector.onAdd` 衝突：**
`onAdd` 是 `NetworkInspector` 上的 public 欄位，由 `_initNetworkNotifier` 指派；
`onMutate` 是 `RingBuffer` 上的建構式參數，由 `InspectorRegistry` 在建構時注入。
**兩者是不同物件的不同欄位，永不互相覆寫**，也不存在初始化順序問題
（`onMutate` 在 buffer 建構時就定案，`onAdd` 之後才由非同步的 `_initNetworkNotifier` 指派）。
`NetworkInspector.add` 的尾端 `onAdd?.call(...)` 一行完全不動。

### 1.3 資料流

```
LogInspector.add ─┐
NavigatorInsp.add ─┤
DatabaseInsp.add  ─┼─→ RingBuffer.add / replace / clear ─→ onMutate?.call()
NetworkInsp.add   ─┘                                            │
                                                                ▼
                                     InspectorRegistry._revision (ValueNotifier<int>)
                                                  revision.value++
                                                                │
                                                    （僅 dashboard 開啟時有訂閱者）
                                                                ▼
                                        _DashboardTabBar (StatefulWidget)
                                          addListener → setState → 重算 count
                                                                │
                                                                ▼
                                    Badge(isLabelVisible: count > 0) 包住 Tab 的 child
```

### 1.4 count 計算

兩個 count 在 `_DashboardTabBar.build` 內即時重算（O(n)、n ≤ 500，且只在 dashboard 開啟時發生）：

```dart
// Network：必須沿用 NetworkEntry.isFailed，嚴禁重新實作失敗判定（spec 驗收條件 5）
final networkErrorCount =
    inspector.networkEntries.where((e) => e.isFailed).length;

// Console：僅計 log 的 error + warning，刻意不含 timeline 裡的 network（spec 驗收條件 6）
final consoleErrorCount =
    inspector.logInspector.entriesAtLevel(LogLevel.error).length +
    inspector.logInspector.entriesAtLevel(LogLevel.warning).length;
```

`FlutterInspector` 已公開 `networkEntries` 與 `logInspector` 兩個 getter，**不需新增任何 public API**。

### 1.5 revision notifier 的公開範圍

Spec 明列「不對外公開為 public API」。作法：
- `InspectorRegistry` 的欄位命名為 `revision`，型別 `ValueListenable<int>`（對外唯讀），
  內部另存 `ValueNotifier<int>` 私有欄位。
- `InspectorRegistry` 本身位於 `lib/src/`，且 `FlutterInspector.registry` getter 已標 `@visibleForTesting`。
  因此 `revision` 天然不在 package 的公開 API 表面上——**不需要在 `FlutterInspector` 上新增任何 getter**。
- UI 端經由既有的 `@visibleForTesting` 的 `inspector.registry.revision` 取用。
  這是 package 內部程式碼存取 package 內部型別，符合 spec 的「僅內部使用」約束。

---

## 二、Material 3 `Badge` 可用性驗證（spec 風險項）

**結論：可用，M2 主題下無問題，採用 `Badge` widget，不需自繪替代方案。**

實查 `flutter/lib/src/material/badge.dart`（本機 SDK 3.41.9）：

1. **`Badge` 原始碼裡沒有任何 `useMaterial3` 分支。** 只存在 `_BadgeDefaultsM3`，
   無論 `useMaterial3` 為 true/false 都走同一份 defaults。
2. `_BadgeDefaultsM3` 只依賴三個東西：`colorScheme.error`、`colorScheme.onError`、
   `textTheme.labelSmall`。這三者在 M2 的 `ThemeData` 中**同樣存在且有預設值**
   （`ColorScheme` 與 `TextTheme` 並非 M3 專屬）。
3. `isLabelVisible: false` 時 `build` 直接 `return child ?? const SizedBox()`——
   **不產生 `Stack`、不產生任何額外可見 widget**，這正好是驗收條件 2（count 為 0 時外觀與現況完全一致）
   的免費實作，不需要自己寫 `if (count > 0)` 條件分支。

> 註：專案 `.claude/rules/flutter-styles.md` 標示 Flutter 3.35，實機為 3.41.9。
> `Badge` 的上述行為在兩版本間一致（無 `useMaterial3` 分支的設計自 3.16 導入 M3 defaults 起即如此），
> 不構成版本風險。

**Tab 計數安全性：** `Badge` 包在 `Tab` 的 **child** 上，即
`Tab(child: Badge(...child: Text('Console')))`。`Tab` widget 本身數量不變（4 或 5），
`find.byType(Tab)` 的 `findsNWidgets(4)` / `findsNWidgets(5)` 維持通過。

> ⚠️ 實作注意：現況是 `const Tab(text: 'Console')`。改用 `child:` 後，
> `Tab` 的 `text` 與 `child` 是互斥的（`Tab` 建構式 assert 兩者不可同時給）。
> 帶 badge 的兩個 tab 改用 `child:`，`Navigator` / `Database` / 自訂 tab **維持原樣不動**
> （spec 驗收條件 4：不顯示 badge）。
> `find.text('Console')` 仍會命中（`Text('Console')` 仍在樹中），既有斷言安全。

---

## 三、檔案異動清單

### 修改

| 檔案 | 異動要點 |
|---|---|
| `lib/src/core/ring_buffer.dart` | 建構式加 optional named `this.onMutate`：`RingBuffer(this.capacity, {this.onMutate})`。新增欄位 `final VoidCallback? onMutate;`（需 `import 'package:flutter/foundation.dart';` 取得 `VoidCallback`）。在 `add` 尾端、`replace` 成功回傳前、`clear` 尾端各加 `onMutate?.call();`。**`replace` 回傳 `false` 的路徑不呼叫**（buffer 沒變就不該通知）。文件註解說明此鉤子的用途與「這是資料變動的唯一路徑」的邊界。 |
| `lib/src/inspectors/log_inspector.dart` | 建構式加 `VoidCallback? onMutate`，轉傳給 `RingBuffer(bufferSize, onMutate: onMutate)`。 |
| `lib/src/inspectors/network_inspector.dart` | 同上（`bufferCapacity`）。**`onAdd` 欄位與 `add` 尾端的 `onAdd?.call` 一行不動。** |
| `lib/src/inspectors/navigator_inspector.dart` | 同上。 |
| `lib/src/inspectors/database_inspector.dart` | 同上。 |
| `lib/src/core/inspector_registry.dart` | 新增私有 `final ValueNotifier<int> _revision = ValueNotifier(0);`；公開唯讀 `ValueListenable<int> get revision => _revision;`；私有方法 `void _bump() => _revision.value++;`。建構式改為 body 形式（因為 `_bump` 需在四個 inspector 建構前可用——用 tear-off `_bump` 即可，Dart 允許在初始化列表引用 instance method tear-off？**不允許**，故建構式改成一般 body：先宣告四個 `late final` inspector 欄位，在 body 內 `log = LogInspector(bufferSize: bufferSize, onMutate: _bump);` …）。詳見任務 3 的實作註記。 |
| `lib/src/ui/dashboard/dashboard_modal.dart` | `_DashboardTabBar` 由 `StatelessWidget` 改為 `StatefulWidget`，新增 `inspector` 欄位；`initState` 中 `widget.inspector.registry.revision.addListener(_onRevisionChanged)`，`dispose` 中 `removeListener`；`_onRevisionChanged` 為 `setState(() {})`。`build` 內重算兩個 count，Console / Network 兩個 `Tab` 改用 `child: Badge(...)`。`DashboardModal` **維持 `StatelessWidget`**（見下方 §四.2）。新增 `_TabLabel`（或直接內嵌）獨立 widget 承載 badge。 |

### 新增

| 檔案 | 用途 |
|---|---|
| `test/ui/dashboard_error_badge_test.dart` | 驗收條件 8–13 的 widget test（6 個案例）。 |
| `test/core/inspector_registry_revision_test.dart` | 驗收條件 14–15 的 unit test。 |

### 不動

- `test/core/ring_buffer_test.dart`（13 項，optional 參數保證零改動通過）
- `test/ui/dashboard_modal_test.dart`（4 項，驗收條件 11 要求維持通過）
- `test/inspectors/network_inspector_test.dart`（10 項，含 2 項 `onAdd`）
- `lib/src/core/flutter_inspector.dart`（**完全不改**——`clearXxx()` 走 `_registry.X.clear()` → `RingBuffer.clear` → 自動通知；`_initNetworkNotifier` 不受影響）
- 四個 tab 的 `_refresh()` 手動更新行為

---

## 四、記憶體洩漏：訂閱責任歸屬

Spec 風險項明列此點。責任分配如下：

### 4.1 訂閱方：`_DashboardTabBar`（唯一）

- **只有 `_DashboardTabBar` 訂閱**，因為只有它需要 badge。
- `initState` → `addListener(_onRevisionChanged)`
- `dispose` → `removeListener(_onRevisionChanged)`（**必須在 `super.dispose()` 之前**，
  符合 `.claude/rules/flutter-styles.md` §7.4 資源管理紀律）
- 監聽的 callback 用**具名方法**而非 inline closure，否則 `removeListener` 因物件不等而移除失敗
  ——這是本次最容易寫錯、且靜默失敗的一點，實作時必須用 `_onRevisionChanged` 具名 tear-off。

### 4.2 被訂閱方：`InspectorRegistry._revision`（永不 dispose）

- `FlutterInspector` 是 app 全域長生命週期物件，其 `_registry` 與 `_revision` 隨行程存活。
- **刻意不呼叫 `_revision.dispose()`**：`FlutterInspector` 沒有 dispose 生命週期
  （`detach()` 只卸載 overlay 與 lifecycle observer，物件本身仍可繼續使用並重新 `attach`）。
  dispose 一個之後還會被 `addListener` 的 notifier 會直接拋錯。
  需在程式碼註解明示：**「此 notifier 與 inspector 同生命週期，故意不 dispose；
  洩漏防護由訂閱端（`_DashboardTabBar.dispose`）的 `removeListener` 負責」**。
- 洩漏方向確認：`ValueNotifier` 持有 listener closure → closure 持有 `_DashboardTabBarState`。
  只要 `removeListener` 有執行，強引用即斷開，dashboard 關閉後無殘留。

### 4.3 為何 `DashboardModal` 維持 `StatelessWidget`

`DashboardModal` 本身不讀 revision，只把 `inspector` 往下傳（它早已這麼做）。
把它改成 Stateful 只是為了「持有一個它不用的訂閱」，屬無謂改動，且會擴大既有測試的風險面。
**訂閱下沉到真正需要它的 `_DashboardTabBar`**，是最小且最正確的位置。

---

## 五、任務拆分

複雜度標註：`快/便宜`（1–2 檔、機械性）／`標準`（多檔整合）／`最強推論`（設計判斷、跨層）

---

### T1 — `RingBuffer` 加 `onMutate` 鉤子（TDD）

- **目標**：讓 `RingBuffer` 在 `add` / `replace`(成功) / `clear` 後呼叫可選回呼。
- **寫入 scope**：`lib/src/core/ring_buffer.dart`、`test/core/ring_buffer_test.dart`（**僅追加**新 group，不動既有 13 項）
- **複雜度**：`快/便宜`
- **步驟**：
  1. 先在 `test/core/ring_buffer_test.dart` 追加 group `'RingBuffer onMutate'`，4 個案例：
     `add 觸發`、`clear 觸發`、`replace 成功時觸發`、`replace 失敗時不觸發`。跑測試確認紅燈。
  2. 實作：建構式簽章 `RingBuffer(this.capacity, {this.onMutate})`，
     欄位 `final VoidCallback? onMutate;`，三處呼叫點。綠燈。
- **驗收**：新 4 案例通過；既有 13 案例零改動全通過。
- **依賴**：無（起點）

---

### T2 — 四個 inspector 轉傳 `onMutate`（TDD）

- **目標**：四個 inspector 建構式接受 `VoidCallback? onMutate` 並轉傳給各自 buffer。
- **寫入 scope**：`lib/src/inspectors/log_inspector.dart`、`network_inspector.dart`、
  `navigator_inspector.dart`、`database_inspector.dart`
- **複雜度**：`快/便宜`（機械性，四個檔案同一個改法）
- **步驟**：
  1. 在 `test/inspectors/network_inspector_test.dart` 追加 1 案例：
     `'onMutate and onAdd both fire independently'`——同時設 `onAdd` 與傳入 `onMutate`，
     `add` 一筆後兩者皆收到通知。此即 spec 驗收條件 15 的 inspector 層版本。
  2. 四個檔案各改建構式一行。
- **驗收**：新案例通過；`network_inspector_test.dart` 既有 10 項（含 2 項 `onAdd`）全通過；
  四個 inspector 既有測試全通過。
- **依賴**：**必須在 T1 之後**（依賴 `RingBuffer` 的新簽章）

---

### T3 — `InspectorRegistry` 持有 revision notifier（TDD）

- **目標**：registry 建立單一 `ValueNotifier<int>`，四個 inspector 的任何變動都令其遞增。
- **寫入 scope**：`lib/src/core/inspector_registry.dart`、
  **新增** `test/core/inspector_registry_revision_test.dart`
- **複雜度**：`最強推論`（跨層接線 + 建構式初始化順序的 Dart 限制）
- **實作註記（關鍵）**：
  Dart **不允許**在建構式初始化列表（`:` 之後）引用 `this` 的 instance method tear-off。
  現況四個 inspector 是在初始化列表中建立的，必須改寫。兩種寫法擇一，**推薦後者**：
  - (a) 四個欄位改 `late final`，建構式改為 body 形式。
  - (b) **推薦**：`_revision` 宣告為 `final ValueNotifier<int> _revision = ValueNotifier(0);`
    （欄位初始化器，在初始化列表前完成），初始化列表中傳入 closure
    `onMutate: () => _revision.value++`——但 closure 捕獲 `this` 同樣不被允許。
    **故實際採 (a)**：四個欄位 `late final`，建構式 body 內建立四個 inspector 並傳 `onMutate: _bump`。

  最終形式（signature 層級）：
  ```dart
  class InspectorRegistry {
    InspectorRegistry({int bufferSize = 500}) {
      log = LogInspector(bufferSize: bufferSize, onMutate: _bump);
      network = NetworkInspector(bufferCapacity: bufferSize, onMutate: _bump);
      navigator = NavigatorInspector(bufferCapacity: bufferSize, onMutate: _bump);
      database = DatabaseInspector(bufferCapacity: bufferSize, onMutate: _bump);
    }

    late final LogInspector log;
    late final NetworkInspector network;
    late final NavigatorInspector navigator;
    late final DatabaseInspector database;

    final ValueNotifier<int> _revision = ValueNotifier<int>(0);

    /// Bumped on every mutation of any of the four buffers. Read-only to callers.
    ValueListenable<int> get revision => _revision;

    void _bump() => _revision.value++;
  }
  ```
  註解需寫明：此 notifier 與 inspector 同生命週期，故意不 dispose（見 §四.2）。
- **驗收**：對應 spec 驗收條件 **14**、**15**。
- **依賴**：**必須在 T2 之後**

---

### T4 — `_DashboardTabBar` 改 Stateful 並訂閱 revision

- **目標**：TabBar 訂閱 revision、正確解除訂閱，且不改變現有渲染結果。
- **寫入 scope**：`lib/src/ui/dashboard/dashboard_modal.dart`
- **複雜度**：`標準`
- **步驟**：
  1. `_DashboardTabBar` → `StatefulWidget`，新增 `final FlutterInspector inspector;`。
  2. `DashboardModal.build` 傳入 `inspector: inspector`。
  3. `initState` / `dispose` 接線（具名 `_onRevisionChanged`，`removeListener` 在 `super.dispose()` 前）。
  4. **此步驟先不加 badge**——tabs 內容維持原樣。
- **驗收**：`test/ui/dashboard_modal_test.dart` 4 項全通過（`Tab` 數量與文字皆未變）。
  這是刻意的中繼檢查點：先證明「改 Stateful + 訂閱」本身零破壞，再疊 badge。
- **依賴**：**必須在 T3 之後**（依賴 `registry.revision`）

---

### T5 — Badge 渲染（TDD）

- **目標**：Console / Network 兩個 tab 依 count 顯示 badge。
- **寫入 scope**：`lib/src/ui/dashboard/dashboard_modal.dart`、
  **新增** `test/ui/dashboard_error_badge_test.dart`
- **複雜度**：`標準`
- **步驟**：
  1. 先寫 `test/ui/dashboard_error_badge_test.dart` 的 6 個案例（見 §六），紅燈。
  2. `_DashboardTabBarState.build` 內計算兩個 count（公式見 §1.4）。
  3. Console / Network 的 `Tab` 改為：
     ```dart
     Tab(
       child: Badge(
         isLabelVisible: consoleErrorCount > 0,
         label: Text('$consoleErrorCount'),
         child: const Text('Console'),
       ),
     )
     ```
     `Navigator` / `Database` / 自訂 tab 完全不動（維持 `const Tab(text: ...)`）。
  4. 依 `.claude/rules/flutter-styles.md` §7.1，若 badge 包裝出現重複，
     提取為獨立類別 `_BadgeTabLabel extends StatelessWidget`（**不可用 helper method**）。
     兩處重複即達提取門檻，建議直接提取。
  5. 在 `_DashboardTabBar` 的 class 註解寫明 spec 的「兩套更新模型並存」邊界：
     badge 即時、tab 內列表維持手動 refresh，這是刻意取捨，勿據此把整個 dashboard 改成 reactive。
- **驗收**：對應 spec 驗收條件 **1、2、3、4、8、9、10、11、12、13**。
- **依賴**：**必須在 T4 之後**

---

### T6 — 全套驗證

- **目標**：確認零破壞。
- **寫入 scope**：無（唯讀）
- **複雜度**：`快/便宜`
- **步驟**：
  1. `rtk flutter analyze`（須零 issue）
  2. `dart format --set-exit-if-changed lib/ test/`
  3. `rtk flutter test`
     - ⚠️ **`test/ui/magical_tap_test.dart` 有既知的 10 分鐘 timeout**，全套執行前先確認是否要排除。
  4. 逐項對照 spec 驗收條件 1–15 打勾。
- **依賴**：**必須在 T5 之後**

---

### 並行性總結

**全部 6 個任務為嚴格序列鏈：T1 → T2 → T3 → T4 → T5 → T6。**

不存在可並行的分支。原因：這是一條由下而上的單一垂直切片
（`RingBuffer` → inspector → registry → widget → 測試），每一層的簽章都是下一層的前提。
硬拆並行只會製造 merge 衝突與 stub 成本，不划算。

唯一的「內部並行」機會在 **T2**：四個 inspector 檔案彼此獨立，
可用單次多檔編輯一併完成，但它們同屬一個任務、無需分派給不同 session。

**執行方式建議**：
- **subagent-driven（推薦）**：任務鏈短（6 步）、序列、單一垂直切片，
  由單一 implementer 一路做完最省協調成本。T4 是天然的中繼驗證點。
- **parallel session**：**不建議**。無獨立分支可切，並行只會增加同檔衝突。

---

## 六、測試計畫

### 6.1 `test/core/ring_buffer_test.dart`（追加 group，T1）

| 案例名稱 | 內容 |
|---|---|
| `'onMutate fires on add'` | 傳入計數 closure，`add` 兩次 → 計數為 2 |
| `'onMutate fires on clear'` | `add` 後 `clear` → 計數含 clear 那次 |
| `'onMutate fires on successful replace'` | `replace` 命中 → 計數 +1 |
| `'onMutate does not fire when replace misses'` | `replace` 未命中（回傳 false）→ 計數不變 |

### 6.2 `test/inspectors/network_inspector_test.dart`（追加 1 案例，T2）

| 案例名稱 | 對應驗收條件 |
|---|---|
| `'onMutate and onAdd both fire independently'` | **15**（inspector 層）——同時設 `onAdd` 與 `onMutate`，`add` 一筆後兩者皆被呼叫，證明 badge 機制未搶佔 `onAdd` |

### 6.3 `test/core/inspector_registry_revision_test.dart`（新檔，T3）

group `'InspectorRegistry revision'`：

| 案例名稱 | 對應驗收條件 |
|---|---|
| `'revision starts at 0'` | — |
| `'revision bumps on log add'` | 14 |
| `'revision bumps on network add'` | 14 |
| `'revision bumps on navigator add'` | 14 |
| `'revision bumps on database add'` | 14 |
| `'revision bumps on each of the four clears'` | 14（一個案例涵蓋四種 clear，逐次斷言遞增） |
| `'revision bumps on network replace'` | 14 延伸（pending → completed 路徑，(丙) 方案的關鍵優勢） |
| `'badge notification does not steal NetworkInspector.onAdd'` | **15**（registry 層）——在 registry 的 network inspector 上設 `onAdd`，`add` 一筆後 `onAdd` 與 `revision` 兩者皆生效 |

測資依 `.claude/rules/flutter-styles.md` §8.2，若需共用 entry 樣本則放同檔的 `_Data` 類別；
本檔測資極簡（單筆 `NetworkEntry(method: 'GET', url: '/1')` 之類），可直接內嵌。

### 6.4 `test/ui/dashboard_error_badge_test.dart`（新檔，T5）

group `'DashboardModal error badges'`：

| 案例名稱 | 對應驗收條件 | 要點 |
|---|---|---|
| `'Network tab shows 2 when two entries failed'` | **8** | 注入 2 筆 `isFailed`（如 `statusCode: 500`）+ 若干成功 → `find.text('2')` 命中；且 `find.byType(Tab)` 仍為 4 |
| `'Network tab shows no badge when all requests succeeded'` | **9** | 全 `statusCode: 200` → 無 badge。斷言用 `find.byType(Badge)` 搭配 `isLabelVisible` 的效果：改以「找不到數字文字」+ `Badge` 不渲染 label 來驗證 |
| `'Console tab shows 2 for one error and one warning'` | **10** | 1 error + 1 warning + 3 info → 顯示 `2`（證明 info 不計入） |
| `'empty inspector renders no badges on either tab'` | **11** | `FlutterInspector()` 空實例 → 兩個 tab 皆無 badge |
| `'badge appears without any refresh when a failed request arrives'` | **12** ⭐ | **核心案例**：先 `pumpWidget` 渲染完成（此時無 badge）→ 直接 `inspector.logNetwork(NetworkEntry(..., statusCode: 500))` → `await tester.pump()` → `find.text('1')` 命中。**全程不觸發任何 refresh 按鈕**。這是路線 (C) 相對 (A)/(B) 的唯一差異證明 |
| `'badge disappears after the buffer is cleared'` | **13** | 有 badge 狀態 → `inspector.clearNetwork()` → `pump()` → badge 消失 |

**驗收條件 11 的後半**（既有 4 項斷言維持通過）由 T4/T6 直接執行
`test/ui/dashboard_modal_test.dart` 驗證，**不重複實作**。

**Badge 存在性斷言技巧**：`Badge` 在 `isLabelVisible: false` 時仍是樹中的一個 `Badge` widget
（它 build 出 `child`），所以 `find.byType(Badge)` **不能**用來判斷「有沒有 badge」。
正確斷言方式是找 badge 的數字文字（`find.text('2')`），
或用 `tester.widget<Badge>(...).isLabelVisible` 直接讀旗標。測試中採前者為主、後者為輔。

---

## 七、風險與回退

| # | 風險 | 機率 | 徵兆 | 對策／回退 |
|---|---|---|---|---|
| R1 | **T3 建構式初始化順序**：`_bump` 是 instance method，不能在初始化列表引用 | 高（已預見） | 編譯錯誤 `Can't access 'this' in a field initializer` | 已在 T3 給出解法（四個欄位改 `late final` + 建構式 body）。若 `late final` 造成其他問題，退回方案：`_revision` 改為 `static`? **不可**（會跨實例污染）；改用 `_bump` 包成獨立的頂層閉包持有 registry 參考亦可，但 `late final` 是最笨最清楚的做法 |
| R2 | **`removeListener` 靜默失敗** | 中 | 無編譯錯誤、無測試失敗，但 dashboard 反覆開關後累積 listener | 強制使用**具名方法 tear-off**（`_onRevisionChanged`），禁止 inline closure。可在 T5 追加一個測試：pump dashboard → pumpWidget 換成空白 widget → 觸發 `inspector.log(...)` → 確認不拋 `setState called after dispose` |
| R3 | **`Tab` 的 `text` 與 `child` 互斥** | 中 | assert 失敗 | 已在 §二標註。改用 `child:` 時必須移除 `text:` |
| R4 | **既有 `dashboard_modal_test.dart` 的 `Tab` 計數失敗** | 低 | `findsNWidgets(4)` 失敗 | T4 已設為中繼驗證點——先只改 Stateful 不加 badge 並跑該測試，把「改結構」與「加 badge」兩個風險源分開。若 T5 後才失敗，即可斷定是 badge 包裝方式錯誤（增生了 `Tab`），改回包 child |
| R5 | **通知風暴掉幀** | 低 | 高頻 log 時 dashboard 卡頓 | Spec 明示「現階段不預先優化」。若實測有問題，最小介入是在 `_onRevisionChanged` 加一個 frame 級去抖（`SchedulerBinding.instance.addPostFrameCallback` 合併），**不改資料層** |
| R6 | **`ring_buffer_test.dart` 意外需要改動** | 極低 | 既有 13 項紅燈 | optional named 參數保證不會發生。若真發生，代表簽章寫成了 positional required——立即改回 optional named |

**最可能出錯的一步：T3**（R1 已預見且已給解法）。
**破壞面最大的一步：T5**（動到既有測試覆蓋的 widget 樹）——用 T4 的中繼驗證點隔離風險。

**整體回退成本**：本次改動全為加法（optional 參數、新欄位、新測試檔），
唯一的結構改動是 `_DashboardTabBar` Stateless → Stateful 與兩個 `Tab` 的 `text:` → `child:`。
任一步失敗都可單獨 `git revert` 該 commit 而不影響前序任務，故建議 **T1–T5 各自獨立 commit**。
