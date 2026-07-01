# 實作計畫：Navigator Tab 當前路由堆疊可視化（Active Stack）

- **日期**：2026-07-01
- **階段**：STAGE 0b — 實作計畫（只寫 How）
- **對應規格**：`docs/features/2026-07-01-navigator-active-stack.md`（source of truth）
- **性質**：既有 Navigator tab 的視圖增補。核心工作是新增一個**純函式重播器**（把事件序列推導成當前堆疊），再把 tab 加上頂部切換、掛上垂直卡片子視圖。事件模型與公開 API 不動。

---

## 核心設計

### 1. 資料流：從事件序列推導當前堆疊

規格 §5 已誠實界定：`NavigatorEntry` 是事件記錄、非堆疊快照，當前堆疊必須由事件序列**推導**。本計畫把推導封裝成一個**純函式 class**，與 Flutter widget tree 完全解耦，讓它能被單元測試逐一覆蓋。

#### 1.1 關鍵事實：資料方向必須先反轉（實作階段簡化：無需額外拷貝）

- `NavigatorInspector.entries`（`navigator_inspector.dart:13`）回傳 `RingBuffer.items`，順序為 **newest first（最新在前）**。
- `FlutterInspector.navigatorEntries`（`flutter_inspector.dart:154`）直接轉發，同樣 newest first。
- 重播堆疊語意必須依**發生時序（oldest first）**逐一 apply。**實作簡化**：不建立 `entries.reversed.toList()` 這份額外拷貝，改用 `for (var i = entries.length - 1; i >= 0; i--)` 直接倒著走 index，效果等價但省一次 `O(n)` 拷貝（見 commit `5b942a0`）。

> 這是整個演算法最容易出錯的一點：若直接對 newest-first 順序（不反轉、不倒走）重播，push/pop 順序會完全顛倒。無論是「先建反轉拷貝再正向走」或「直接倒著走 index」，語意都是依時序（oldest first）逐一 apply，兩者等價；本專案採後者以避免多餘配置。

#### 1.2 核心資料結構：不新增 model，直接複用 `NavigatorEntry`

當前堆疊表示為 `List<NavigatorEntry>`，**由頂（index 0 = 堆疊頂 = 當前畫面）到底（末元素 = 根路由）排序**。

- **不新增 model class**：堆疊每一層要顯示的正是 `displayName` + `routeName`，`NavigatorEntry` 既有欄位已足夠。新增輕量 model 只會多一份轉換與一份要維護的相等性，違反 YAGNI。
- **堆疊層直接就是 push/replace 當時記錄的那個 `NavigatorEntry` 實例**：卡片渲染時讀它的 `displayName` getter 與 `routeName`，零額外映射。
- 對外只暴露一個純函式，不持久化、不寫入第二份真相（對齊 `console-merged-timeline` 的「衍生視圖只在渲染讀取當下計算」品味守則）。

#### 1.3 重播演算法規則（best-effort，明確且可預測）

新增 `NavigatorStackResolver`（純 Dart，不 import flutter/material）：

```
List<NavigatorEntry> resolve(List<NavigatorEntry> entries)
  // 輸入：navigatorEntries（newest-first，如同 FlutterInspector 對外形狀）
  // 輸出：當前堆疊，top-first（index 0 = 堆疊頂）
```

內部演算法（以「底→頂」的可變工作堆疊 `stack` 進行，最後反轉成 top-first 輸出）：

1. **倒著走 index**：`for (var i = entries.length - 1; i >= 0; i--)`，從 `entries`（newest-first）的尾端往頭端走，即依時序（oldest → newest）逐一取得 `entry`——不建立額外的反轉拷貝（見 §1.1 實作簡化）。
2. 逐一 apply 每個 `entry`，工作堆疊語意為 `stack.last == 堆疊頂`：

| action | 重播規則 | fallback（規則不適用時） |
|---|---|---|
| `push` | `stack.add(entry)` — 入堆疊頂 | 無 fallback，push 永遠成立 |
| `pop` | `if (stack.isNotEmpty) stack.removeLast()` — 移除堆疊頂 | 空堆疊時 no-op（不製造負深度，對應 US-4「pop 到底」） |
| `replace` | `if (stack.isNotEmpty) stack[last] = entry` 否則 `stack.add(entry)` — **直接替換堆疊頂**，深度不變 | 空堆疊時退化為 push（等同 replaceRoot 的合理呈現） |
| `remove` | 從**頂往底**掃描，移除**第一個** `_matches(candidate, entry)` 的層；找不到符合項則 **no-op** | 找不到符合層：no-op（不亂砍，對應 US-4「不誤傷上層」） |

3. **輸出**：`return stack.reversed.toList();`（底→頂 轉成 頂→底 = top-first）。

**`replace` 的明確規則**：規格 §5 指出 `didReplace` 只記 `newRoute`、無 `oldRoute`，無法精確定位被換的層。本計畫採「**直接替換當前堆疊頂**」——這是可預測、不誤導的最佳努力：多數 replace 就是換頂部路由（如 `pushReplacement`），深度維持不變符合 US-4「replace 不多疊一層」。

**`remove` 的比對規則 `_matches`**：以 `routeName` + `widgetType` 兩者都相等視為同一路由。

```
bool _matches(NavigatorEntry a, NavigatorEntry b) =>
    a.routeName == b.routeName && a.widgetType == b.widgetType;
```

- 用 top-first 掃描並移除**第一個**符合層：貼合「remove 通常移除較上層」的直覺，且對重複路由（同名多層）採「先移上層」的可預測選擇。
- **找不到符合層 → no-op**：對應 US-4「remove 非頂部路由不誤傷上層」——寧可少移一層也不亂砍。不拋錯（規格 §5：不誤導、不假精確）。

**nested Navigator / 歧義**：本 resolver 只重播單一線性事件流（規格 §3 Out-of-Scope 明確不承諾 nested 多樹）。上述規則在多 Navigator 事件混流時會給出「單線最佳努力堆疊」，不崩潰、不拋錯，符合 §5 best-effort 門檻。

#### 1.4 inspector 自身路由（US-3）

`flutter_inspector_dashboard` 在事件記錄層級（`_isInspectorRoute`）就已排除，從不進入 `navigatorEntries`。Resolver 只讀 `navigatorEntries`，天然不含它。**Resolver 不需、也不應**重新加任何 inspector 路由過濾（加了反而是第二份真相）。此點以測試確認（見任務 T3）。

### 2. UI 改動：頂部切換 + 垂直卡片

#### 2.1 版面選型：`ChoiceChip`（實作階段由 `SegmentedButton` 改版，見規格 §6 決策 5）

原計畫選定 `SegmentedButton<StackViewMode>`，理由是 Material 3 內建的單選語意、避免 `TabBar`/`CupertinoSlidingSegmentedControl` 的過度工程。**實作階段改為 `ChoiceChip`**（包在私有 `_Tab` StatelessWidget 內，見 commit `c3c2d7b`、`68f0cc7`、`dae52d8`），原因：

- **相容性**：`SegmentedButton` 在專案實際執行環境下出現相容性問題（見 commit `68f0cc7 remove compatibility SegmentedButton hack`），改用更輕量、相容性更好的 `ChoiceChip` 組合排除該問題。
- **狀態管理不變**：切換狀態仍是 `StackViewMode` enum 欄位存在 `_NavigatorTabState`，`setState` 切換即可，`ChoiceChip.selected` + `onSelected` 與原本 `SegmentedButton.selected`/`onSelectionChanged` 語意等價，零新 controller、零 dispose 負擔。
- **視覺**：兩個 `_Tab(label: ..., selected: ..., onSelected: ...)` 各自包一個 `ChoiceChip`，維持「同一資料源兩視圖互斥切換」的單選語意，只是元件從 `SegmentedButton` 換成 `ChoiceChip` 組合。

`enum StackViewMode { activeStack, eventHistory }` 維持放在 `navigator_tab.dart` 檔內頂層（不對外導出）。

#### 2.2 `NavigatorTab` 結構（實作後現況）

```
Column
├─ Row（統一工具列，同一列並存：）
│   ├─ _Tab('Active Stack')   （ChoiceChip 包裝，切 activeStack）
│   ├─ _Tab('Event History')  （ChoiceChip 包裝，切 eventHistory）
│   ├─ Spacer()
│   ├─ IconButton(refresh)
│   └─ IconButton(delete)
└─ Expanded
   └─ 三元運算依 _mode 切換
      ├─ activeStack  → _buildActiveStack（私有方法：垂直卡片列表）
      └─ eventHistory → 既有 ListView.builder（原樣搬移，邏輯零變更）
```

- 原計畫設想「Row（refresh/delete）」與「切換元件」是 `Column` 底下兩個獨立子項；**實作階段收斂為單一統一 Row**（commit `dae52d8 extract _Tab widget and unify toolbar row`）：切換 chip 靠左，`Spacer()` 把 refresh/delete 按鈕推到最右，兩個模式共用同一列工具列，兩者恆常可見。
- 既有「事件歷史」的 `ListView.builder` **整段搬進 `eventHistory` 分支，內容一字不改**——保 US-5。
- refresh / delete 按鈕操作的是 `navigatorEntries` 與 `clearNavigator()`，對兩個視圖都適用（clear 後兩視圖同步清空，因為堆疊是 `navigatorEntries` 的衍生）。

#### 2.3 `_buildActiveStack`（垂直卡片子視圖，實作為 `_NavigatorTabState` 私有方法，非獨立 widget 檔）

- 在 build 當下呼叫 `NavigatorStackResolver().resolve(widget.inspector.navigatorEntries)`，得到 top-first 堆疊。
- 空堆疊 → 顯示佔位文字 **`'Empty stack history'`**（英文，見 commit `517b25f`、`a04ed8e`；原計畫的中文「當前堆疊為空」僅為示意文字，未被規格 §6 拍板，實作採此英文字串），不崩潰。
- 非空 → `ListView.builder` 逐層渲染 `Card`：
  - 標題：`entry.displayName`
  - 副標：`entry.routeName ?? '(no route name)'`（displayName + routeName 並陳，對應規格 §6 卡片欄位集）
  - **不顯示 `arguments`**（規格 §6 已定，維持卡片簡潔）。
- 頂層（index 0）已加「當前」視覺標記（此為原計畫核准的 nice-to-have，已定案）：leading `Icon(Icons.visibility, color: Colors.blue)` + trailing 圓角徽章 `Text('Current', ...)`；index != 0 時 `leading`/`trailing` 皆為 `null`。

---

## 檔案異動清單

### 新增

| 路徑 | 內容 |
|---|---|
| `lib/src/inspectors/navigator_stack_resolver.dart` | `NavigatorStackResolver` 純函式重播器（不 import flutter/material） |
| `lib/src/ui/dashboard/tabs/navigator/active_stack_view.dart` | `_ActiveStackView` 垂直卡片子視圖（或內嵌於 `navigator_tab.dart`，見任務 T5 判斷） |
| `test/inspectors/navigator_stack_resolver_test.dart` | resolver 純函式單元測試（重播規則全覆蓋） |
| `test/ui/tabs/navigator_active_stack_test.dart` | 當前堆疊子視圖 widget 測試 |

### 修改

| 路徑 | 改動 |
|---|---|
| `lib/src/ui/dashboard/tabs/navigator_tab.dart` | 加 `StackViewMode` enum、`_mode` 狀態、兩分支切換；新增私有 `_Tab` StatelessWidget（包 `ChoiceChip`，取代原計畫的 `SegmentedButton`，見 §2.1）；`_buildActiveStack` 私有方法渲染垂直卡片（未獨立成 `active_stack_view.dart`）；既有事件歷史 `ListView.builder` 原樣搬入 `eventHistory` 分支 |
| `test/ui/tabs/navigator_tab_test.dart` | **只增不改**：既有 case 全保留（US-5）；新增「ChoiceChip 切換存在且可切換」的 case |

> 實作結果（T5 設計判斷已定案）：`_ActiveStackView` 選擇**內嵌** `navigator_tab.dart` 作為私有方法 `_buildActiveStack`，未新增 `active_stack_view.dart` 獨立檔；對應測試在獨立的 `test/ui/tabs/navigator_active_stack_test.dart`（而非併入 `navigator_tab_test.dart`）。

---

## 任務拆解（TDD 風格）

每個任務先寫測試（紅）→ 實作（綠）。複雜度分級：**機械性**（照樣板套）／**整合**（串既有元件）／**設計判斷**（需權衡）。

### T1 — resolver 骨架與 push/pop 重播【設計判斷】

- **描述**：新增 `NavigatorStackResolver`，實作 `resolve()` 的時序化（`.reversed`）＋ push/pop 規則。先只支援 push/pop。
- **寫入 scope**：`lib/src/inspectors/navigator_stack_resolver.dart`、`test/inspectors/navigator_stack_resolver_test.dart`
- **測試案例概要**：
  - 空輸入 → 空堆疊。
  - 單 push → 單層堆疊，頂=該路由。
  - push A, push B（記得 newest-first 輸入）→ 堆疊 top-first = [B, A]。
  - push A, push B, pop B → [A]。
  - push A, pop A, pop（多 pop）→ 空堆疊，不負深度（US-4 pop 到底）。
- **依賴**：無（地基任務）。

### T2 — replace 重播規則【設計判斷】

- **描述**：加入 `replace` 分支（替換堆疊頂；空堆疊退化為 push）。
- **寫入 scope**：`navigator_stack_resolver.dart`、`navigator_stack_resolver_test.dart`
- **測試案例概要**：
  - push A, replace B → [B]（深度不變、頂身分改變，US-4 replace 語意）。
  - push A, push B, replace C → [C, A]（只換頂）。
  - replace A（空堆疊起手）→ [A]（退化為 push 的 fallback）。
- **依賴**：T1（同檔續寫）。

### T3 — remove 重播規則與 fallback【設計判斷】

- **描述**：加入 `_matches` 與 `remove` 分支（top-first 掃描移第一個符合層；找不到 no-op）。順帶驗證 inspector 路由天然不入堆疊（US-3）。
- **寫入 scope**：`navigator_stack_resolver.dart`、`navigator_stack_resolver_test.dart`
- **測試案例概要**：
  - push A, push B, push C, remove B → [C, A]（移非頂部層、上層 C 不受傷，US-4）。
  - remove 一個不存在於堆疊的路由 → 堆疊不變（no-op fallback）。
  - 同名重複路由 remove → 移最上層那個（可預測選擇）。
  - resolver 輸入不含 `flutter_inspector_dashboard`（因記錄層級已排除）→ 堆疊不含它（US-3 確認）。
- **依賴**：T1、T2（同檔續寫）。

### T4 — 頂部切換骨架（切換機制，不含卡片內容）【整合】

- **描述**：`navigator_tab.dart` 加 `StackViewMode` enum、`_mode` 狀態、切換元件，兩分支先用佔位；既有事件歷史 `ListView.builder` 原樣搬入 `eventHistory` 分支。**實作結果**：切換元件為私有 `_Tab` widget（包 `ChoiceChip`），標籤為英文「Active Stack」/「Event History」，取代計畫原定的 `SegmentedButton` + 中文標籤（見規格 §6 決策 5）。
- **寫入 scope**：`lib/src/ui/dashboard/tabs/navigator_tab.dart`、`test/ui/tabs/navigator_tab_test.dart`
- **測試案例概要**：
  - **既有 case 全數保留且通過**（US-5：`PUSH /home` 顯示、delete 清空）——預設 `_mode` 須落在能看到事件歷史的狀態，或測試明確切到 eventHistory。
  - 新增：兩個 `ChoiceChip` 存在，含「Active Stack」「Event History」兩選項。
  - 新增：切到「Active Stack」→ 事件歷史列表消失、堆疊視圖區塊出現（此時可為空佔位）。
- **依賴**：無（可與 T1–T3 並行，不同檔）。

### T5 — 垂直卡片子視圖 `_ActiveStackView`【整合】

- **描述**：接上 `NavigatorStackResolver`，渲染 top-first 卡片（displayName + routeName，不含 arguments）；空堆疊佔位。決定內嵌或獨立檔。
- **寫入 scope**：`lib/src/ui/dashboard/tabs/navigator_tab.dart`（＋可選 `.../navigator/active_stack_view.dart`）、`test/ui/tabs/navigator_active_stack_test.dart`
- **測試案例概要**：
  - 餵一組事件（push A, push B）→ 切到當前堆疊 → 見兩張卡片，順序 top-first（B 在上、A 在下）。
  - 卡片顯示 `displayName` 與 `routeName` 並陳；**不出現 `arguments` 內容**。
  - 空 `navigatorEntries` → 顯示空佔位、不崩潰。
  - clear（delete 按鈕）後切當前堆疊 → 空佔位（驗證衍生同步）。
- **依賴**：T1–T3（需 resolver）、T4（需頂部切換骨架）。

### T6 — 迴歸驗證與收尾【機械性】

- **描述**：跑全套 `test/models/navigator_entry_test.dart`、`test/observers/navigator_observer_test.dart`、`test/ui/tabs/navigator_tab_test.dart` 確認未破壞；`dart analyze` 無新增 lint。
- **寫入 scope**：無源碼寫入（純驗證）；如有 lint 才回補對應檔。
- **測試案例概要**：既有三支測試檔全綠、analyze 乾淨。
- **依賴**：T1–T5。

**任務總數：6**

---

## 不可破壞項目（Never break userspace，對應 US-5）

以下為**不可變更**的既有 API 與既有測試，任務執行中若需觸碰即為紅線：

### 不可變更的公開 API

- `FlutterInspector.navigatorEntries`（getter，讀事件列表，newest-first 語意）。
- `FlutterInspector.clearNavigator()`（清空語意）。
- `FlutterInspector.navigatorInspector` / `NavigatorInspector` 對外形狀。
- `NavigatorEntry` 全部公開表面：欄位（`timestamp`/`action`/`routeName`/`widgetType`/`arguments`）、`displayName` getter 語意、`copyWith`、`==`/`hashCode`、`TimestampedEntry` 實作。
- `NavigatorAction` enum 值集（push/pop/replace/remove）。
- `FlutterInspectorNavigatorObserver` 的攔截行為與 `_isInspectorRoute` 排除邏輯（不改動事件記錄層）。

### 不可失效 / 不可放寬的既有測試

- `test/models/navigator_entry_test.dart`（事件模型契約）。
- `test/observers/navigator_observer_test.dart`（觀察者攔截契約，含 inspector 路由排除、不鏡射 console log）。
- `test/ui/tabs/navigator_tab_test.dart` 的**既有 case**（`PUSH /home` 顯示、delete 清空）——本計畫只允許在此檔**新增** case，既有 case 一字不改、不放寬斷言。

### 設計層紅線

- Resolver **不寫入**任何 buffer、不持久化堆疊——當前堆疊永遠是渲染當下的衍生計算（規格 §1、§3）。
- Resolver **不重新引入** inspector 路由過濾（記錄層已負責），避免第二份真相。
- **不重構** `NavigatorEntry` 為堆疊快照（規格 §3 Out-of-Scope）。

---

## 驗證方式

1. **單元測試（resolver 為主）**：`flutter test test/inspectors/navigator_stack_resolver_test.dart` — push/pop/replace/remove 四規則與各 fallback 全覆蓋，純函式無 widget tree 依賴，快速可重複。
2. **Widget 測試**：`flutter test test/ui/tabs/navigator_tab_test.dart test/ui/tabs/navigator_active_stack_test.dart` — ChoiceChip 切換、卡片 top-first 排序、欄位並陳、空堆疊佔位、clear 同步。
3. **迴歸**：`flutter test test/models/navigator_entry_test.dart test/observers/navigator_observer_test.dart` — 確認 US-5 既有契約全綠。
4. **靜態檢查**：`dart analyze` 無新增警告；resolver 檔案確認未 import `package:flutter/material.dart`（保純函式可測性）。
5. **驗收對照**：逐條核對規格 §2 的 US-1～US-5 驗收條件（尤其 US-4 的三個邊界：pop 到底、replace 深度不變、remove 非頂部不誤傷）。

---

## 執行方式建議（供 STAGE 2 選擇）

依任務相依與寫入 scope，兩種執行路徑：

### 選項 A：subagent-driven（序列 + 局部並行）

- **並行群 1**：T1→T2→T3（resolver 三任務同檔、必須序列）與 T4（`navigator_tab.dart` 骨架、不同檔）**可並行**——resolver 檔與 tab 檔寫入 scope 不重疊。
- **收斂**：T5 需同時依賴 resolver（T1–T3）與頂部切換骨架（T4），為匯流點。
- **收尾**：T6 迴歸。
- 適合：單一 session 內以 subagent 分派 resolver 與 UI 骨架兩條線，主 agent 於 T5 收斂。

### 選項 B：parallel session（兩條獨立線）

- **Session 1（資料線）**：T1→T2→T3→（resolver 對應測試）。純 Dart，可獨立跑到綠。
- **Session 2（UI 線）**：T4（頂部切換骨架，先用假堆疊資料或空佔位）。
- **合流 session**：T5 接線 + T6 迴歸。
- 適合：資料演算法與 UI 版面由不同人／不同 model 並行推進；風險是 T5 合流前 UI 線只能用 stub，需在合流時補齊真實 resolver 呼叫。

**建議**：優先選項 A。resolver 是三任務同檔序列、UI 骨架單檔，並行收益有限但收斂點單純（T5），主 agent 一次收斂即可，協調成本最低。
