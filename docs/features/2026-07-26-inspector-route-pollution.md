# 功能規格：修復 Inspector 自身頁面污染 NavigatorTab

- **日期**：2026-07-26
- **狀態**：STAGE 0a — 待確認
- **來源**：`docs/brainstorm/2026-07-26-features-brainstorm.md` §D6
- **類型**：**既有缺陷修復（bug fix）**，非新功能
- **實測驗證**：2026-07-26 probe test 實跑確認，非推論

---

## 1. 問題陳述（What & Why）

### 一句話本質

打開 inspector dashboard 後在裡面點開的每一個 detail view，都被誤記進**使用者 app 的** Navigator 軌跡，導致 NavigatorTab 顯示的不是「我的 app 的導航」，而是「我的 app 的導航 + inspector 自己的導航」混在一起。

### 現況行為 vs 期望行為

| | 現況（bug） | 期望 |
|---|---|---|
| 使用者 app 自身的 push/pop/replace/remove | 記錄進 `navigatorInspector.entries` ✅ | 維持不變 ✅ |
| Dashboard 本體（`showGeneralDialog`） | 已被排除 ✅ | 維持排除 ✅ |
| Dashboard 內的 detail view / bottom sheet | **被誤記進 entries** ❌ | **一律不記錄** |

### 實測證據

在掛載 `FlutterInspectorNavigatorObserver` 的 app 中開啟 dashboard、點開一筆 network entry 後，`inspector.navigatorInspector.entries` 的實際內容：

```text
ENTRIES: [NavigatorAction.push/NetworkDetailView, NavigatorAction.push/SizedBox]
```

`NetworkDetailView` 是 inspector 自己的 UI，卻出現在使用者 app 的導航軌跡中。

### 根因鏈（三段，逐檔核對）

1. **Dashboard 掛在被觀察的 Navigator 上**
   `lib/src/ui/dashboard/dashboard_modal.dart:30` 的 `showGeneralDialog` 未指定 `useRootNavigator`，Flutter 預設為 `true` → dashboard 掛在**宿主 app 的 root Navigator**，正是掛載 `FlutterInspectorNavigatorObserver` 的那一個。

2. **Detail view 繼承同一個 Navigator**
   Dashboard 子樹內的 `Navigator.of(context).push(...)` / `showModalBottomSheet(...)`，其 `context` 來自 dashboard 子樹 → 解析到同一個 root Navigator → 同樣被觀察。

3. **過濾器認不出它們**
   `lib/src/observers/navigator_observer.dart:17-18` 的過濾條件是：

   ```dart
   bool _isInspectorRoute(Route<dynamic> route) =>
       route.settings.name == 'flutter_inspector_dashboard';
   ```

   而這些 detail view 的 route **完全沒帶 `RouteSettings.name`**（`name == null`）→ 條件不成立 → 過濾器一律放行，四個覆寫（`didPush` / `didPop` / `didReplace` / `didRemove`）的 early return 全部失效。

### 完整污染來源清單（2026-07-26 實查 grep，共 7 處）

> ⚠️ brainstorm 文件記錄 4 處，為過時快照。以下為當下實查結果，其中 `export_report_sheet.dart` 是文件**完全未列到**的污染點。

| # | 檔案 | 行 | 呼叫形式 | 推送的頁面 | 現有 route name |
|---|------|---|---------|-----------|----------------|
| 1 | `lib/src/ui/dashboard/dashboard_modal.dart` | 30 | `showGeneralDialog` | `DashboardModal` 本體 | ✅ `'flutter_inspector_dashboard'` |
| 2 | `lib/src/ui/dashboard/tabs/console_tab.dart` | 172 | `Navigator.of(context).push` + `MaterialPageRoute` | `LogDetailView` | ❌ 無 |
| 3 | `lib/src/ui/dashboard/tabs/console_tab.dart` | 196 | `Navigator.of(context).push` + `MaterialPageRoute` | `NetworkDetailView` | ❌ 無 |
| 4 | `lib/src/ui/dashboard/tabs/network_tab.dart` | 268 | `Navigator.of(context).push` + `MaterialPageRoute` | `NetworkDetailView` | ❌ 無 |
| 5 | `lib/src/ui/dashboard/tabs/database_tab.dart` | 181 | `Navigator.push(context, ...)` + `MaterialPageRoute` | `TableRowsView` | ❌ 無 |
| 6 | `lib/src/ui/dashboard/tabs/database/table_rows_view.dart` | 118 | `showModalBottomSheet` | `_CellDetailsBottomSheet` | ❌ 無 |
| 7 | `lib/src/ui/dashboard/export_report_sheet.dart` | 19 | `showModalBottomSheet` | `ExportReportSheet` | ❌ 無 |

**形狀分類（影響方案設計，勿假設可套同一個入口）**：

- **A 類（4 處：#2 #3 #4 #5）**：`MaterialPageRoute` + `builder`，形狀一致。
- **B 類（2 處：#6 #7）**：`showModalBottomSheet`，**不建構 `MaterialPageRoute`**，需透過其 `routeSettings:` 參數帶入名稱。bottom sheet 同樣是 route，一樣觸發 `didPush` / `didPop`。
- **C 類（1 處：#1）**：`showGeneralDialog`，已有名稱，但字串常值目前散落三份（見下），需一併收斂。

**字串常值現況（實查）**：`'flutter_inspector_dashboard'` 目前硬編在三個地方——

- `lib/src/ui/dashboard/dashboard_modal.dart:32`（產生端）
- `lib/src/observers/navigator_observer.dart:18`（判斷端）
- `test/observers/navigator_observer_test.dart:109`（測試端）

沒有共用常數。若不收斂，前綴定義會出現多份，同樣的漏接問題會在常數層再犯一次。

### 為何值得修（Why）

污染量與使用者的**排查強度成正比**。越是深入追查（反覆開關 detail view、逐筆點進 network entry、瀏覽資料表），NavigatorTab 就被灌進越多雜訊——**正好在最需要乾淨導航軌跡的時候最髒**。

這違背診斷工具的基本原則：**不干擾被觀測對象**（觀測者效應）。一個會把自己寫進使用者資料的 inspector，其 NavigatorTab 的資料可信度是不可靠的——使用者無法分辨某一筆記錄是自己 app 的行為，還是 inspector 自己的行為。

此缺陷同時波及下游：`NavigatorStackResolver` 從 `entries` 推導的 Active Stack 視圖會混入 inspector 的路由層，`docs/features/2026-07-01-navigator-active-stack.md` 的 US-3（「inspector 自身路由不出現在堆疊視圖」）在 detail view 情境下**實際未達成**。

---

## 2. 使用者故事

### US-1：排查中的開發者看到乾淨的導航軌跡

> 身為使用 inspector 追查導航問題的開發者，我在 dashboard 內點開 detail view 檢視細節時，**不希望我的檢視動作本身被記錄成我 app 的導航事件**。我要看的是「我的 app 走過哪些頁面」，不是「我剛才在 inspector 裡點過哪些卡片」。

**痛點情境**：追一個「某頁面被重複 push 兩次」的 bug。開啟 dashboard → 進 NavigatorTab → 發現需要對照 network 請求 → 切到 NetworkTab 點開三筆請求細節 → 回 NavigatorTab。此時軌跡多了 3 筆 `NetworkDetailView`，與正在追查的真實 push 事件混在一起，必須靠肉眼分辨哪些是雜訊。

### US-2：使用診斷報告的開發者拿到可信的資料

> 身為要把診斷報告貼進 issue 或給同事看的開發者，我希望匯出的導航軌跡是我 app 的真實行為，不含 inspector 自己的 UI 導航。

**痛點情境**：`ExportReportSheet` 本身就是污染點 #7 ——**開啟匯出面板這個動作，會把 `ExportReportSheet` 這筆 push 寫進即將被匯出的資料裡**。使用者拿到的報告在最後一筆記著一個他從未在 app 裡訪問過的頁面。

### US-3：package 使用者（維護者視角）不必記得補 route name

> 身為 flutter_inspector_kit 的維護者，我希望未來新增任何 detail view 時，**不必記得**手動補上 route name 才不會污染使用者資料。正確性應由結構保證，而非由人的記憶保證。

**痛點情境**：本次污染清單從 brainstorm 記錄的 4 處長成實查的 7 處，正是「靠記憶維護」的失敗實證——`export_report_sheet.dart` 加入時沒人記得它是 route。

---

## 3. 驗收條件

### AC-1：Dashboard 內的所有 route 都不進入 entries

- [ ] 開啟 dashboard 後，於 dashboard 內開啟**上述清單第 2～7 處的任一頁面**（`LogDetailView`、`NetworkDetailView`（兩個入口皆須驗）、`TableRowsView`、`_CellDetailsBottomSheet`、`ExportReportSheet`），`inspector.navigatorInspector.entries` **不新增任何一筆**。
- [ ] 上述頁面的**關閉（pop）**動作同樣不新增 entry（`didPop` 亦被排除）。
- [ ] Dashboard 本體（`showGeneralDialog`）維持不被記錄（既有行為不回歸）。
- [ ] 針對實測證據的回歸驗證：重跑該情境，`entries` 中**不再出現** `NetworkDetailView`。

### AC-2：使用者 app 自身的導航仍完整記錄（不可誤殺）

- [ ] 使用者 app 的 `push` / `pop` / `replace` / `remove` 事件仍如常記錄進 `entries`，含 `routeName`、`widgetType`、`arguments`。
- [ ] **無名稱的**使用者 route（`RouteSettings.name == null`，例如 app 自己 `MaterialPageRoute(builder: ...)` 未設 name）**仍被記錄**——過濾條件不得退化成「無名稱就丟棄」。此為誤殺風險最高的一條。
- [ ] 名稱**碰巧**與 inspector 前綴無關的使用者 route（例如 `/flutter`、`/inspector`、`/home`）不受影響。

### AC-3：正確性由單一來源保證（消滅特殊情況）

- [ ] Dashboard 內部所有 route 的名稱皆來自**同一份常數定義**，不存在「某處自行硬編 name 字串」的旁路。名稱的**傳遞方式**依 route 形狀而異：page route 走 `pushInspectorRoute` helper、bottom sheet 經 `showModalBottomSheet` 的 `routeSettings:`、dashboard dialog 用共用常數——三者共用同一份常數與前綴，這才是「單一來源」的實質內容（非單一函式，見 §6）。
- [ ] `_isInspectorRoute` 的判斷只依賴**一個**來源定義的名稱規則。
- [ ] `'flutter_inspector_dashboard'` 這類字串常值收斂為**單一共用常數**，產生端與判斷端引用同一份定義。
- [ ] 誤用（未依規則命名）在 **debug build 會當場失敗**（例如 `assert`），而非靜默漏過成為新的污染點。

### AC-4：既有測試與行為不回歸

- [ ] `test/observers/navigator_observer_test.dart` 既有 8 個測試全數通過，其中 `'ignores inspector dashboard route'` 與 4 個 `did*` 記錄測試（皆使用 `/home`、`/new`、`/removed` 等使用者路由名）行為不變。
- [ ] `test/inspectors/navigator_stack_resolver_test.dart`、`test/ui/tabs/navigator_tab_test.dart`、`test/ui/tabs/navigator_active_stack_test.dart` 不因本次修復而失效或需被放寬。
- [ ] `test/ui/export_report_sheet_test.dart`、`test/ui/tabs/console_tab_test.dart` 等碰到 dashboard 內部推送的測試不需修改斷言即可通過（若需修改，須為斷言本身反映舊 bug 行為的情況，並在計畫中明列）。

### AC-5：新增污染點會被擋下（防回歸）

- [ ] 存在一個測試涵蓋「dashboard 內開啟 detail view 不污染 entries」的端到端路徑，使未來新增未走收斂入口的 detail view 時測試會失敗。

---

## 4. 範圍邊界（Scope）

### In-Scope

- 收斂 dashboard 內部 route 推送的命名來源（7 處污染點全數納管）。
- 收斂 `'flutter_inspector_dashboard'` 字串常值為單一共用常數。
- 調整 `_isInspectorRoute` 的判斷規則，使其只認收斂後的單一來源。
- `showModalBottomSheet`（B 類，2 處）以 `routeSettings:` 帶入名稱——形狀與 A 類不同，需個別處理。
- 新增防回歸測試（AC-5）。

### Out-of-Scope（明確排除，不做）

- **不改 `useRootNavigator`**：不把 dashboard 改掛到獨立 Navigator。那是改變 dashboard 的掛載拓撲，風險遠大於本次修復範圍（會影響全螢幕行為、返回鍵、系統手勢），且**不需要**——名稱過濾已足以解決問題。此為刻意的最小 diff 選擇。
- **不改 NavigatorTab UI**：本次是資料層修復，不動任何呈現。
- **不動 `NavigatorStackResolver`**：Active Stack 是 `entries` 的衍生視圖，資料源乾淨後它自然乾淨，不需為此修改推導邏輯。
- **不改 `NavigatorEntry` 模型**：欄位、`displayName`、`copyWith`、相等性一律不動。
- **不新增「顯示/隱藏 inspector 路由」的使用者開關**：inspector 的路由對使用者**永遠**無意義，做成可切換是為不存在的需求增加狀態（YAGNI）。
- **不清理歷史已污染的 entries**：既有 buffer 中的髒資料不做回溯清除；使用者以 `clearNavigator()` 處理即可。
- **不處理宿主 app 自行推送 inspector widget 的情況**：若使用者把 `NetworkDetailView` 當作自己 app 的一個頁面推送（極不可能），該記錄仍會保留——這是正確行為，因為那確實是使用者 app 的導航。
- **不改 `FlutterInspector` 的公開 API 形狀**：`navigatorEntries`、`navigatorObserver`、`clearNavigator()` 語意不變。

---

## 5. 破壞性分析（Never break userspace）

本 package 已發布至 pub.dev，任何變更須逐項評估對既有使用者的影響。

### 5.1 公開 API 曝光面

| 符號 | 是否於 `lib/flutter_inspector_kit.dart` export | 使用者可達路徑 | 結論 |
|---|---|---|---|
| `FlutterInspectorNavigatorObserver` | ❌ **未直接 export** | ✅ 可達：`FlutterInspector.navigatorObserver` getter（`flutter_inspector.dart:126`）回傳此型別，而 `FlutterInspector` 有 export | **型別公開可達，但成員未直接曝光** |
| `_isInspectorRoute` | — | ❌ 私有方法 | 可自由修改 |
| `didPush` / `didPop` / `didReplace` / `didRemove` | — | ✅ 公開覆寫（`NavigatorObserver` 契約） | **簽章不得變更** |
| `DashboardModal.show` | ❌ 未 export（`ui/dashboard/` 不在 export 清單） | ❌ | 可自由修改 |
| 各 detail view（`NetworkDetailView` 等） | ❌ 未 export | ❌ | 可自由修改 |
| `'flutter_inspector_dashboard'` 字串 | — | ⚠️ 使用者可能已在自家程式中硬編此字串做過濾 | 見 5.2 |

**判斷**：使用者能持有 `FlutterInspectorNavigatorObserver` 實例並掛到 `navigatorObservers`（這正是套件的標準用法），但**無法**呼叫或覆寫其內部過濾邏輯。修改 `_isInspectorRoute` 的實作**不構成 API 破壞**。

### 5.2 行為相容性風險

| 風險項 | 評估 | 緩解 |
|---|---|---|
| **誤殺使用者 route** | 🔴 **最高風險**。若新規則寫成「無名稱 → 排除」或前綴比對過寬（例如 `contains` 而非 `startsWith`），會吞掉使用者的合法導航記錄——這是比原 bug 更嚴重的破壞（資料遺失 vs 資料多餘）。 | AC-2 三條驗收條件專門守此；前綴須具足夠辨識度以避免碰撞。 |
| **既有 route name 字串變更** | 🟡 中。若 `'flutter_inspector_dashboard'` 的**值**被改動，任何在自家程式中硬編此字串做過濾的使用者會失效。 | **常數的值必須保持 `'flutter_inspector_dashboard'` 不變**，只做「收斂到常數」而非「改名」。新增的 detail view 名稱是全新字串，不影響既有使用者。 |
| **新增 route name 造成使用者側行為改變** | 🟢 低。detail view 原本 `name == null`，改為帶名稱後，理論上使用者若掛了自己的 `NavigatorObserver`，會從「收到 name=null 的事件」變成「收到帶 inspector 前綴的事件」。 | 事件本身數量不變，只是多了可辨識的名稱——對使用者而言是**淨改善**（原本無從分辨，現在可自行過濾）。 |
| **`entries` 數量減少** | 🟢 低，且**這正是修復目的**。使用者若有測試斷言 dashboard detail view 出現在 entries 中，該斷言本身是在驗證 bug。 | CHANGELOG 明列為 bug fix。 |
| **`showGeneralDialog` / `showModalBottomSheet` 行為改變** | 🟢 無。僅新增 `routeSettings`，不改 `useRootNavigator`、`isScrollControlled` 等既有參數。 | — |

### 5.3 既有測試影響評估（實查）

碰觸 navigator observer 或 dashboard 內部推送的測試共 12 個檔案：

| 測試檔 | 影響評估 |
|---|---|
| `test/observers/navigator_observer_test.dart` | 🟡 **直接相關**。含 `'ignores inspector dashboard route'`（硬編 `'flutter_inspector_dashboard'`，第 109 行）與 4 個使用具名使用者路由（`/home` 等）的記錄測試。前者應改為引用共用常數；後者行為不得變。**另需補一則「無名稱使用者 route 仍被記錄」的測試守 AC-2。** |
| `test/ui/export_report_sheet_test.dart` | 🟡 可能受影響（#7 是污染點，其 `show` 會加 `routeSettings`）。 |
| `test/ui/tabs/console_tab_test.dart` | 🟡 可能受影響（#2 #3 為污染點）。 |
| `test/ui/tabs/navigator_tab_test.dart`、`navigator_active_stack_test.dart` | 🟢 應不受影響（讀取端，資料源乾淨後行為更正確）。 |
| `test/inspectors/navigator_stack_resolver_test.dart`、`navigator_inspector_test.dart`、`models/navigator_entry_test.dart` | 🟢 不受影響（不經過 observer 過濾）。 |
| `test/core/*`、`test/utils/diagnostic_report_test.dart` | 🟢 應不受影響。 |

> 出口要求：修復完成後上述測試須**全數通過且不放寬斷言**；任何需要修改的斷言，須在實作計畫中逐條說明「該斷言原本在驗證舊 bug」。

### 5.4 CHANGELOG 定位

本次為 **bug fix**（修正 inspector 自身 UI 導航污染使用者 Navigator 記錄）。無公開 API 變更、無使用者遷移動作。

---

## 6. 設計判斷：為何採方案 B

> 本節複述 `docs/brainstorm/2026-07-26-features-brainstorm.md` §D6 已定案的結論，非重新提案。

### 方案 A（已否決）— 逐處補 `RouteSettings(name: ...)`

為 7 處污染點各自補上帶前綴的 `RouteSettings(name: ...)`，`_isInspectorRoute` 改用 `startsWith` 前綴比對。

**否決理由：治標。** 把正確性寄託在人的記憶上——新增任何 detail view 都必須記得補 name，漏一個就再破一次。本次污染清單從 brainstorm 記錄的 4 處長成實查的 7 處（`export_report_sheet.dart` 是新增的、無人察覺的污染點），**已經是這個方案失敗的實證**。

### 方案 B（採用）— 收斂為單一推送入口

Dashboard 內部推送統一走一個 helper（如 `pushInspectorRoute`），由它統一掛上帶前綴的 route name；`_isInspectorRoute` 只認這一個來源。

**採用理由**：符合專案的 Linus 式判準——**消滅特殊情況優先於增加判斷**。4+ 個散落的命名判斷點收斂成 1 個，正確性由結構保證而非人的記憶保證。新增 detail view 時，若走 helper 就自動正確；若不走 helper，AC-3 要求的 `assert` 會在 debug build 當場失敗，而非靜默成為下一個污染點。

### 已知的形狀落差（不可忽略）

方案 B 的「統一入口」在實作上**不是單一函式**：

- **A 類（4 處）** 建構 `MaterialPageRoute`，可由單一 helper 完整覆蓋。
- **B 類（2 處）** `showModalBottomSheet` 不建構 `MaterialPageRoute`，需經其 `routeSettings:` 參數帶入。**不可假設能套同一個 helper。**
- **C 類（1 處）** `showGeneralDialog` 已有名稱，只需將字串常值收進共用常數。

三類共用**同一份名稱規則與前綴常數**（這是「單一來源」的實質內容），但入口形式可有兩種。這是形狀差異的必然結果，不是設計妥協——強行把 bottom sheet 塞進 page route helper 才是為統一而統一。

### 實作備忘（brainstorm 提供，供 STAGE 0b 參考）

- Helper 內建議加 `assert(name.startsWith(prefix))`，讓誤用在 debug build 當場炸出來。
- `dashboard_modal.dart` 現有的 `'flutter_inspector_dashboard'` 字串常值一併收進共用常數（**值不變**，見 §5.2）。
- 專案既有常數慣例為 file 層級 `const String kXxx`（見 `lib/src/utils/redaction.dart:6`、`lib/src/models/network_entry.dart:14`、`lib/src/webview/webview_bridge_js.dart:5`）；`lib/src/` 下**無**集中式 constants 檔，常數放置位置由 STAGE 0b 依既有慣例決定（候選：`lib/src/ui/dashboard/` 下的新檔，或既有的 `lib/src/utils/`）。

---

## 7. 規格出口條件

- [ ] 問題陳述與實測證據已確認（7 處污染點清單為實查結果，取代 brainstorm 的 4 處快照）。
- [ ] AC-1～AC-5 已確認為可測試、可驗收。
- [ ] 範圍邊界已確認：不改 `useRootNavigator`、不改 NavigatorTab UI、不動 `NavigatorStackResolver`、不改 `NavigatorEntry`、不新增使用者開關。
- [ ] 破壞性分析已確認：`FlutterInspectorNavigatorObserver` 未直接 export（僅經 `navigatorObserver` getter 可達），修改 `_isInspectorRoute` 不構成 API 破壞；`'flutter_inspector_dashboard'` 的**值**保持不變。
- [ ] AC-2「無名稱使用者 route 仍被記錄」已確認為最高風險項並列入驗收。
- [ ] 方案 B 的三類形狀落差（page route / bottom sheet / general dialog）已確認為已知事實，不視為方案缺陷。

進入 STAGE 0b（實作計畫），細化：共用常數與前綴的具體定義與放置位置、helper 的簽章與 `assert` 條件、bottom sheet 的 `routeSettings` 接線方式、`_isInspectorRoute` 的新判斷規則、7 處污染點的逐檔異動清單，以及對應的 TDD 任務拆解。
