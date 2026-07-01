# 功能規格：Navigator Tab 當前路由堆疊可視化（Active Stack）

- **日期**：2026-07-01
- **狀態**：STAGE 0a — 已確認
- **來源**：GitHub issue #24（已關閉的大型多功能 issue）剩餘未實作子項——「Navigator Tab：新增『Active Stack』當前路由堆疊可視化（麵包屑 / 垂直卡片）」
- **類型**：既有 tab 的視圖增補（Navigator tab 在既有「事件歷史列表」之外，新增「當前堆疊」視圖）

---

## 1. 功能概述（What & Why）

### 一句話本質

Navigator Tab 目前只有一份**事件流水帳**（push / pop / replace / remove 依序排列的 `ListTile`）。本功能在同一個 tab 內新增一個**「當前路由堆疊」視圖**，讓開發者一眼看到「此刻畫面對應的路由堆疊長什麼樣」，而不必自己在腦中重播整串事件序列。

### 為什麼要做（Why，已逐檔核對的現況事實）

- `lib/src/ui/dashboard/tabs/navigator_tab.dart`：`NavigatorTab` 只把 `widget.inspector.navigatorEntries`（事件列表）用 `ListView.builder` 攤成 `ListTile`，每列顯示 `ACTION displayName` + `timestamp` + `arguments`。**沒有任何「當前堆疊」的視圖**。
- `lib/src/models/navigator_entry.dart`：`NavigatorEntry` 是**不可變的事件記錄**（欄位：`timestamp` / `action` / `routeName` / `widgetType` / `arguments`，`displayName` 為 getter，優先顯示 `widgetType`）。它記的是「發生了什麼事」，**不是「當前堆疊快照」**。
- `lib/src/observers/navigator_observer.dart`：`FlutterInspectorNavigatorObserver` 攔截 `didPush` / `didPop` / `didReplace` / `didRemove`，把每個事件包成 `NavigatorEntry` 塞進 `_inspector.navigatorInspector`。其中 `didReplace` **只記錄 `newRoute`、不記錄被換掉的 `oldRoute`**；`didRemove` 對任意 route 都記錄，**不區分是否為堆疊頂部**。
- `_isInspectorRoute(route)`（`navigator_observer.dart:17`）已在**事件記錄層級**排除 inspector 自身路由（`route.settings.name == 'flutter_inspector_dashboard'`）：四個 did* 回呼一開頭就 `return`，所以 inspector dashboard 本身從不進入事件流。

現況的痛點：

> 「現在畫面對應的路由堆疊是什麼」這個開發者最常問的問題，Navigator tab **答不出來**。使用者只能滑過整串歷史事件，自己心算 push 幾層、pop 掉哪些、replace 換了誰，才能想像當前堆疊。層數一多（尤其 nested Navigator 情境）就幾乎不可能靠肉眼還原。

### 設計核心（本規格提議、待確認）

> 「當前堆疊」是**一個從事件序列推導出來的衍生視圖（derived view）**，不是新的一份真相。它在渲染當下讀既有的 `navigatorEntries`、重播 push/pop/replace/remove 的堆疊語意、算出「此刻還留在堆疊上的路由」，再以視覺化方式呈現。事件歷史列表與當前堆疊視圖共用同一份 `navigatorEntries` 資料源。

這條設計對齊專案既有品味守則（見 `2026-06-26-console-merged-timeline.md`）：**衍生視圖只在渲染讀取當下計算，不寫入第二份資料、不引入第二份真相**。

**呈現形式的設計判斷（待確認）：**

本規格建議採**垂直卡片（vertical cards）**作為主要呈現形式，理由：

1. **語意貼合**：路由堆疊天然是「後進先出的垂直堆疊」，垂直卡片由上（堆疊頂 = 當前畫面）到下（堆疊底 = 根路由）直接對應心智模型，比水平麵包屑更符合「stack」的空間隱喻。
2. **資訊密度**：每張卡片有空間顯示 `displayName` + `routeName` + `arguments` 摘要，與既有事件列表的 `ListTile` 資訊量對齊；麵包屑受限於單行寬度，深堆疊會被截斷或需水平捲動。
3. **一致性**：與既有 tab（Network / Console）以垂直清單為主的視覺慣例一致。

麵包屑（breadcrumb）列為**次要 / 可選**：若後續希望在狹窄空間快速掃視層級路徑，可作為卡片視圖的補充摘要列。本次以垂直卡片為必做、麵包屑為可選（見 §3 In-Scope 標註）。

---

## 2. 使用者故事與驗收條件

### US-1：開發者一眼看到「此刻的路由堆疊」

> 身為除錯多層 Navigator 的開發者，我希望在 Navigator tab 直接看到「現在畫面對應的路由堆疊」由頂到底的每一層是什麼，而不必滑過整串歷史事件自己心算 push/pop 的淨結果。

**驗收條件：**

- [ ] Navigator tab 新增一個可視化「當前路由堆疊」的區塊 / 子視圖，以**垂直卡片**呈現：由上（堆疊頂 = 當前顯示中的路由）到下（堆疊底 = 根路由）。
- [ ] 每一層卡片顯示 `displayName`（優先 `widgetType`，次之 `routeName`，最後泛用占位）與原始 `routeName`（兩者並陳，方便比對解析結果與原始名稱）。
- [ ] 堆疊視圖與既有事件歷史列表**同處 Navigator tab**，以**頂部切換**呈現：兩個子頁籤（**"Active Stack" / "Event History"**，英文標籤）互斥切換顯示，畫面乾淨不擁擠（實作採 `ChoiceChip` + 私有 `_Tab` widget，非 `SegmentedButton`，見 §6 決策紀錄與 `docs/plans/` 實作計畫）。

### US-2：堆疊視圖即時反映最新狀態，不是歷史流水帳

> 身為開發者，當我 push / pop / replace / remove 之後回到 inspector，我希望堆疊視圖呈現的是「操作後的當前狀態」，而不是要我自己從事件流回推。

**驗收條件：**

- [ ] 堆疊視圖呈現的是**依事件序列重播後的當前堆疊淨結果**，而非事件流水帳：
  - `push` → 該路由出現在堆疊頂。
  - `pop` → 頂部路由自堆疊移除（pop 到只剩根路由時，堆疊視圖對應收斂）。
  - `replace` → 被替換的路由從堆疊上被換成新路由（堆疊深度不變、頂部身分改變）。
  - `remove` → 對應路由自堆疊移除（含移除非頂部路由的情況，見 US-4）。
- [ ] 使用者觸發 refresh（或既有的重新渲染時機）後，堆疊視圖反映的是**最新**的 `navigatorEntries` 重播結果，不存在「畫面已變、堆疊視圖沒跟上」的過時狀態。

### US-3：inspector 自身路由不出現在堆疊視圖

> 身為開發者，我打開 inspector dashboard 這個動作本身不該污染我正在除錯的路由堆疊；我要看的是「我的 app 的堆疊」，不是「inspector 疊在我 app 上」。

**驗收條件：**

- [ ] 堆疊視圖中**不出現** inspector 自身路由（`flutter_inspector_dashboard`）。此排除延續既有 `_isInspectorRoute` 在事件記錄層級的邏輯——由於該路由從不進入 `navigatorEntries`，衍生堆疊天然不含它；本條驗收確認堆疊重播不因任何路徑重新引入它。

### US-4：邊界情況下堆疊仍是可理解的當前狀態

> 身為除錯複雜導覽流程的開發者，我希望遇到 pop 到底、replace、remove 非頂部路由這些情況時，堆疊視圖給的仍是一個「說得通的當前狀態」，而不是崩掉或顯示明顯錯亂的層級。

**驗收條件：**

- [ ] **pop 到底**：連續 pop 至只剩根路由時，堆疊視圖收斂為單層（或明確呈現「僅剩根路由」），不出現負深度、空白崩潰或殘留已 pop 的路由。
- [ ] **replace 的堆疊語意**：`replace` 呈現為「頂部（或對應層）身分被換掉、堆疊深度不變」，而非「多疊一層」。
- [ ] **remove 非頂部路由**：`remove` 一個非頂部的路由時，該層自堆疊視圖消失、其上層維持不變，不會誤把整個上層一起砍掉。
- [ ] 當事件序列不足以無歧義還原精確堆疊時（見 §5 技術限制），堆疊視圖採**明確、可預測的最佳努力（best-effort）規則**呈現，而非拋錯或顯示誤導性的假精確層級（該規則的具體定義與 nested Navigator 的處置屬 STAGE 0b）。**此 best-effort 呈現已確認為驗收合格門檻**——不要求 100% 精確重建，只要求不誤導、行為可預測。

### US-5：不破壞既有事件歷史列表與公開 API（Never break userspace）

> 身為既有套件使用者，我希望新增堆疊視圖後，原本的事件歷史列表與我依賴的 API 完全照舊。

**驗收條件：**

- [ ] 既有**事件歷史列表**（`navigatorEntries` 的流水帳呈現）功能保留可用，觀感與資訊量不因新增堆疊視圖而退化或被移除。
- [ ] 既有公開 API 不變更語意：`FlutterInspector.navigatorEntries`（讀事件列表）、`clearNavigator()`（清空）維持原行為，依賴它們的宿主程式碼不受影響。
- [ ] `NavigatorEntry` 事件模型的**公開 API 不被重構**（欄位、`displayName` 語意、`copyWith`、`==`/`hashCode` 皆不動）。堆疊視圖以既有欄位推導，不要求變更事件模型的對外形狀。
- [ ] 既有測試（`test/models/navigator_entry_test.dart`、`test/observers/navigator_observer_test.dart`、`test/ui/tabs/navigator_tab_test.dart`）不因本功能而失效或需被放寬。

---

## 3. 範圍邊界（Scope）

### In-Scope

- Navigator tab 新增「當前路由堆疊」視圖，以**垂直卡片**由頂到底呈現當前堆疊（**必做**）。
- 堆疊為 `navigatorEntries` 的**渲染當下衍生結果**：重播 push/pop/replace/remove 的堆疊語意算出當前層級，不新增第二份持久化資料源。
- 涵蓋邊界情況的最佳努力呈現：pop 到底、replace 語意、remove 非頂部路由。
- 延續 `_isInspectorRoute` 邏輯，確保 `flutter_inspector_dashboard` 不出現在堆疊視圖。
- 保留既有事件歷史列表與 `navigatorEntries` / `clearNavigator()` 公開 API。
### Out-of-Scope（明確排除）

- **麵包屑（breadcrumb）摘要列**：本次不做，留待後續迭代評估。本次僅交付垂直卡片視圖。
- **重構 `NavigatorEntry` 事件模型的公開 API**：本功能不改事件模型對外形狀（見 US-5）。
- **路由轉場動畫 / 轉場過程的視覺化**：只呈現「當前靜態堆疊」，不做 push/pop 的動畫重演或轉場軌跡視覺化。
- **跨 Isolate / 跨 Engine 的堆疊合併**：只處理當前 observer 所觀測到的單一事件流，不合併多 Isolate 或多 Engine 的堆疊。
- **精確重建任意 nested Navigator 的完整樹**：`NavigatorObserver` 事件流無法可靠區分多個並存 Navigator 的歸屬（見 §5）。本次以單一線性堆疊的最佳努力呈現為準，**不承諾**完整還原 nested Navigator 的多樹結構；此為後續可選迭代。
- **與 GoRouter / Navigator 2.0 宣告式堆疊的深度整合**：本次以既有 `NavigatorObserver` 事件流為唯一資料源，不接入宣告式路由框架的內部 route 表。
- **在堆疊視圖上執行導覽操作**（例如點卡片直接 pop 到該層）：本次為**唯讀可視化**，不提供從 inspector 反向操控 app 導覽的能力。

---

## 4. 向後相容性聲明

本功能定位為「Navigator tab 的視圖增補」，必須維持向後相容：

- **公開 API 保留**：`FlutterInspector.navigatorEntries` 與 `clearNavigator()` 語意不變。
- **事件模型不動**：`NavigatorEntry` 公開形狀（欄位 / `displayName` / `copyWith` / 相等性）不變更，堆疊視圖僅為讀取端的衍生計算。
- **既有視圖保留**：事件歷史列表繼續可用，不被新視圖取代或降級。
- **行為改變受控且為淨增益**：唯一「行為改變」是 Navigator tab 多出一個當前堆疊視圖；既有列表與資料源不動，資訊只增不減。

---

## 5. 技術限制與誠實邊界（規格依據）

本節誠實標註「從 `NavigatorObserver` 事件流重建當前堆疊」的先天限制，避免驗收條件承諾做不到的精確度：

| 現況事實（已逐檔核對） | 對堆疊重建的影響 |
|---|---|
| `NavigatorEntry` 是事件記錄，非堆疊快照（`navigator_entry.dart`） | 當前堆疊必須由事件序列**推導**，無現成快照可讀。 |
| `didReplace` 只記錄 `newRoute`、不記 `oldRoute`（`navigator_observer.dart:78-83`） | replace 事件缺「被換掉的是誰」的顯式資訊，堆疊重播對 replace 目標層的定位屬最佳努力。 |
| `didRemove` 對任意 route 都記錄、不標示是否頂部（`navigator_observer.dart:86-90`） | remove 非頂部路由時，需靠比對重建的堆疊內容來定位被移除層，非事件本身直接給定。 |
| observer 觀測的是事件流，非 route 樹；nested Navigator 的事件會混入同一 `navigatorEntries` | 多個並存 Navigator 的堆疊歸屬無法從事件流可靠切分——這是**不承諾完整還原 nested 多樹**的根本原因（見 §3 Out-of-Scope）。 |
| `_isInspectorRoute` 已在記錄層級排除 inspector 路由（`navigator_observer.dart:17`） | inspector 路由天然不進 `navigatorEntries`，堆疊重播無須、也不應重新引入它。 |

> 誠實結論：本功能能可靠交付的是「單一線性事件流重播出的最佳努力當前堆疊」，對常見的 push/pop/replace/remove 序列能給出正確且有用的堆疊視圖；對 nested Navigator 多樹與 replace/remove 的極端歧義情況，採「明確、可預測、不誤導」的最佳努力規則，而非假裝精確。精確重建 nested 多樹列為 Out-of-Scope。

---

## 6. 決策紀錄（STAGE 0a 已拍板，含實作階段修訂）

1. **版面關係**：頂部切換——「Active Stack」與「Event History」為互斥切換的兩個子頁籤。
2. **麵包屑**：本次不做，僅交付垂直卡片視圖；麵包屑留待後續迭代評估。
3. **best-effort 規則可接受度**：已確認可接受——不要求 100% 精確重建 nested Navigator 或 replace/remove 歧義情況，只要求不誤導、行為可預測。
4. **卡片欄位集**：`displayName` + `routeName` 並陳顯示；不顯示 `arguments` 摘要（維持卡片簡潔）。堆疊頂（index 0）額外加視覺標記：`Icons.visibility` leading icon + 「Current」trailing 徽章，屬 `docs/plans/` §2.3 預先核准的 nice-to-have。
5. **切換元件與標籤語言（實作階段修訂）**：STAGE 0a 原拍板 `SegmentedButton` + 中文標籤（當前堆疊/事件歷史）。實作過程中改為 `ChoiceChip`（包在私有 `_Tab` widget 內）+ 英文標籤（"Active Stack" / "Event History"），理由與細節見 `docs/plans/2026-07-01-navigator-active-stack.md` §2.1。此為已確認的新拍板決定，取代原決策，互斥切換的行為本身不變。

---

## 7. 規格出口條件（已通過）

- US-1 ～ US-5 的驗收條件已確認為可測試、可驗收。
- 呈現形式決策（垂直卡片必做、麵包屑本次不做、頂部切換版面）已確認。
- 範圍邊界（不重構事件模型 API、不做轉場動畫、不跨 Isolate/Engine、不承諾 nested 多樹精確還原、唯讀可視化）已確認。
- §5 技術限制與 best-effort 規則可接受度已確認。

進入 STAGE 0b（實作計畫），細化：當前堆疊的資料表示（衍生計算的形狀）、事件重播演算法（push/pop/replace/remove 的堆疊語意規則、nested/歧義的最佳努力處置）、垂直卡片 UI 與頂部切換版面、與事件列表的切換機制，以及對應的 TDD 任務拆解與逐檔異動清單。
