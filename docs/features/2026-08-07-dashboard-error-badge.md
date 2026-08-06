# Dashboard 錯誤計數 Badge（§P6）

> 來源：`docs/brainstorm/2026-08-05-features-brainstorm.md` §P6（Tier 3，effort low，排查價值 ⭐⭐⭐）

## 問題

Dashboard 的 TabBar 只有 4 個純文字標籤（`Console` / `Network` / `Navigator` /
`Database`），沒有任何數量提示。使用者開啟 dashboard 後，得逐 tab 點進去、
掃視列表，才知道「這次操作到底有沒有炸東西」。

實際排查情境更糟：真正想知道的是「**有沒有**錯誤」這個是非題，
但目前的互動成本是「切 4 個 tab + 每個 tab 捲動掃視」。
資訊已經全在 buffer 裡，只是沒有被摘要到最上層。

## 使用者故事

> 作為在真機上排查問題的開發者，我想在 dashboard 一打開時，
> 就從 tab 標籤上直接看到「Network 有 3 筆失敗、Console 有 5 筆錯誤」，
> 不必逐 tab 點進去確認，能立刻決定先看哪一個 tab。

## 核心設計決策

### 背景：brainstorm 的原始構想不成立

§P6 寫「用 `ValueListenableBuilder` 監聽 buffer 變化，局部重建」。
實查後確認**這個基礎設施不存在**：

| 檢查項 | 現況 |
|---|---|
| `lib/` 內的 `ValueNotifier` / `ChangeNotifier` / `Listenable` | **零個**（全檔搜尋無命中） |
| `RingBuffer` | 純資料容器，`add` / `clear` 不發任何通知 |
| `InspectorRegistry` | 只是四個 inspector 的持有者，無通知機制 |
| 四個 tab 的資料更新方式 | 一律 `void _refresh() => setState(() {})`，綁在手動 refresh 按鈕上 |

所以「監聽 buffer」在本專案是一項**架構新增**，不是「沿用既有機制」。
effort 從 low 被低估的部分就在這裡。

### 三條路線與取捨

| 路線 | 做法 | 判定 |
|---|---|---|
| **(A) 開啟時快照** | badge 在 `DashboardModal.build` 算一次，之後不變 | ❌ 否決 |
| **(B) 上抬 refresh** | `DashboardModal` 改 StatefulWidget，各 tab refresh 一併通知上層重算 | ❌ 否決 |
| **(C) revision notifier** | registry/inspector 層加 `ValueNotifier<int>`，`add` 時遞增，badge 監聽 | ✅ **採用** |

### 採用 (C)：引入單一 revision notifier

**理由：**

1. **只有 (C) 讓 badge 的語意是誠實的。** badge 是一個「常駐在畫面最上層的數字」，
   使用者對它的預期就是「現在的值」。(A) 與 (B) 都會產生「badge 顯示 0，
   但 Network tab 裡躺著 3 筆紅色失敗」的狀態——這是**主動誤導**，
   比沒有 badge 更糟。加一個會說謊的指示器，不如不加。

2. **這不是想像出來的問題。** dashboard 是**長駐開著**的：使用者開著 dashboard、
   切到 app 操作、再切回來看結果，是本工具最主要的使用流程。
   在這個流程裡，資料一定會在 dashboard 生命週期內變動。(A) 的快照
   從第二秒起就是錯的。

3. **(C) 是唯一「消滅特殊情況」的設計。** (B) 需要在 4 個 tab 各接一條
   回呼線，往後每新增一個 tab、每新增一個會改動 buffer 的入口
   （clear all、bookmark、replay…）都要記得補接。這是典型的
   「靠人記得」的設計，必然會漏。(C) 把通知收斂到資料寫入的**唯一路徑**，
   新增任何寫入端都自動正確，不需要接線。

**被否決路線的致命問題：**

- **(A) 開啟時快照的致命問題**：資訊不一致且無法自我修正。使用者按了 tab 內的
   refresh、按了 clear all，或只是切出去操作再切回來——badge 全部維持舊值。
   此時 badge 不只是「不夠即時」，而是**與同畫面上的列表互相矛盾**。
   一個和旁邊列表打架的數字，會直接摧毀使用者對整個 dashboard 的信任。
   零架構改動買到的是負值。

- **(B) 上抬 refresh 的致命問題**：它把「資料變了」錯誤地綁定到
   「使用者按了按鈕」。實查確認除了 4 個 refresh 按鈕外，
   `ConsoleTab` 有 clear-all（一次清四個 buffer）、`NetworkTab` 有 clear-all，
   而 app 執行期的網路請求、log 寫入**根本不經過任何 UI 事件**。
   (B) 能覆蓋的只有「使用者剛好按了 refresh」這一種情況，
   其餘全部漏掉——付出 4 條接線的成本，只買到 (A) 的品質。
   這是三者中 CP 值最差的一條。

### (C) 的實作邊界（避免它膨脹成大改）

採用 (C) 不代表要把整個 package 重寫成 reactive。**明確限縮：**

- 只新增**一個** revision counter，代表「任一 buffer 被寫入或清除過」，
  **不做**細分到 per-inspector 的多個 notifier。badge 收到通知後重算四個
  count 的成本是 O(n)、n ≤ 500，且僅在 dashboard 開啟時發生，
  完全不需要為此做精細化拆分。
- **不改動**現有四個 tab 的手動 refresh 行為。兩套模型並存是刻意的：
  tab 內列表維持手動 refresh（避免捲動位置在使用者閱讀時被抽掉，
  這是既有的正確設計），只有 badge 走即時更新。
  兩者職責不同——列表要**穩定**，摘要要**即時**。

### 已知的實作陷阱（必須在 STAGE 0b 處理）

實查發現兩個 brainstorm 未提及、會直接影響設計的事實：

1. **`NetworkInspector.onAdd` 是單一插槽，且已被佔用。**
   `network_inspector.dart:18` 宣告 `NetworkAddListener? onAdd`，
   `flutter_inspector.dart:242` 在 `showNetworkNotification` 為 true 時
   將它指派給 `NetworkNotifier`。若 badge 直接複用 `onAdd`，
   **會覆蓋掉網路通知功能**（或反之被覆蓋），視初始化順序而定。
   revision counter 不可掛在 `onAdd` 上，必須是獨立的通知點。

2. **另外三個 inspector 完全沒有通知鉤子。**
   `LogInspector.add` / `NavigatorInspector` / `DatabaseInspector`
   都是直接 `_buffer.add(entry)`，沒有任何 callback。

## 驗收條件

### Badge 顯示規則

1. Badge 依附在 `Console` 與 `Network` 兩個 tab 的標籤上。
2. 對應 count 為 `0` 時，**該 tab 不顯示 badge**（標籤外觀與現況完全一致）。
3. count `> 0` 時顯示該數字。
4. `Navigator` / `Database` / 自訂 tab **不顯示 badge**（見範圍邊界）。

### Count 語意（可測試的定義）

5. **Network tab 的 count** = `inspector.networkEntries.where((e) => e.isFailed).length`。
   **必須沿用 `NetworkEntry.isFailed`**（`network_entry.dart:109`，
   定義為 `(statusCode ?? 0) >= 400 || error != null || errorType != null`）。
   **嚴禁**在 badge 端重新實作失敗判定——該判定已由 PR #101 收斂為單一來源，
   目前有四個消費端統一走它，新增第五個分歧實作會使收斂前功盡棄。

6. **Console tab 的 count** = **僅計算 `LogEntry` 中 level 為 `error` 或 `warning` 的筆數**，
   即 `logInspector.entriesAtLevel(LogLevel.error).length +
   logInspector.entriesAtLevel(LogLevel.warning).length`。

   **此定義需要明文釐清，因為 Console tab 實際上是混合時間軸**
   （`mergedTimeline` 合併 log / network / nav / db 四種來源，預設全選）。
   刻意**不**把 timeline 裡的失敗 network 計入 Console badge，理由：
   - 失敗的 network 已由 Network badge 表達。兩邊都算會**重複計數**，
     使用者看到 `Console 3 / Network 3` 會誤以為總共有 6 個問題。
   - 兩個 badge 各自對應一個明確的、不重疊的資料來源，語意才可預測。

7. Badge 的 count 在 dashboard 開啟期間，於任一 buffer 新增或清除後**自動更新**，
   不需使用者按 refresh。

### 可測試斷言

8. Widget test：注入 2 筆 `isFailed` 的 network entry → Network tab 顯示 `2`。
9. Widget test：全部 network entry 皆成功 → Network tab 無 badge。
10. Widget test：注入 1 筆 `error` + 1 筆 `warning` + 3 筆 `info` log
    → Console tab 顯示 `2`。
11. Widget test：無任何資料（`FlutterInspector()` 空實例）→ 兩個 tab 皆無 badge，
    且既有的 `dashboard_modal_test.dart` 四項斷言全數維持通過。
12. Widget test：dashboard 已渲染後再寫入一筆失敗請求 → 不觸發任何 refresh 操作，
    pump 後 badge 由 `0`（無 badge）變為 `1`。此為 (C) 相對於 (A)/(B) 的核心差異，
    必須有對應測試。
13. Widget test：清除 buffer 後 badge 消失。
14. Unit test：revision counter 在四種 `add` 與四種 `clear` 後皆遞增。
15. Unit test：badge 的通知機制**不影響** `NetworkInspector.onAdd`——
    同時設定 `onAdd` 與 badge 監聽，兩者都要收到通知
    （對應上述陷阱 1，防止網路通知功能被靜默破壞）。

## 範圍邊界

**做：**

- 在資料層新增單一 revision notifier，於四個 buffer 的寫入/清除路徑遞增
- `DashboardModal` / `_DashboardTabBar` 接上該 notifier，重算並渲染 badge
- Console / Network 兩個 tab 的 badge

**不做（out of scope）：**

- **不加** Navigator / Database / 自訂 tab 的 badge。前兩者沒有「錯誤」語意
  （導航事件與 DB 操作本身無成敗），自訂 tab 的內容由 host 提供、
  package 無從得知其錯誤定義。
- **不改**四個 tab 內部列表的手動 refresh 行為（刻意保留，見上文）。
- **不做** badge 點擊行為（例如點 badge 自動套用錯誤篩選）。Network tab
  已有 `_ErrorSummaryBanner` 提供分組篩選，職責不重複。
- **不改** `NetworkEntry.isFailed` 的定義，也不新增任何替代的失敗判定。
- **不把** revision notifier 對外公開為 public API（見風險分析）。
- **不做** badge 的上限截斷（如 `99+`）。buffer 上限預設 500，
  現階段直接顯示實際數字；真有寬度問題再說。
- **不**引入任何新的第三方相依（狀態管理套件一律不加，
  符合專案「本 package 無跨畫面共享狀態」的既定方針）。

## 風險與破壞性分析

### 公開 API

本 package 已發布至 pub.dev **v2.0.0**，公開 API 破壞不可接受。

| 項目 | 影響 |
|---|---|
| `FlutterInspector` 建構式參數 | **不變**（badge 無需設定項，恆常啟用） |
| `FlutterInspector` 既有 getter | **不變** |
| `DashboardModal` 建構式 | **不變**（`inspector` / `initialIndex` / `key` 維持） |
| `NetworkInspector.onAdd` | **不變**，且須有測試證明未被 badge 機制搶佔 |
| revision notifier | **不對外公開**，僅內部使用，避免成為需長期維護的 API 承諾 |

結論：**無公開 API 破壞**，屬 minor 版本可涵蓋的加法變更。

### 既有測試

- `test/ui/dashboard_modal_test.dart` 有 4 項斷言，其中兩項為
  `expect(find.byType(Tab), findsNWidgets(4))` 與 `findsNWidgets(5)`。
  若 badge 的實作方式改變 `Tab` widget 的數量或結構，這兩項會失敗。
  **驗收條件 11 明列此測試須維持通過**——badge 應包裹 `Tab` 的內容，
  而非替換或增生 `Tab` 本身。
- `test/inspectors/network_inspector_test.dart` 有 2 項 `onAdd` 相關測試
  （`:49`、`:111`），對應上述陷阱 1，必須維持通過。
- 四個 tab 的既有測試不受影響（tab 內部行為不變）。

### 其他風險

| 風險 | 說明 |
|---|---|
| **通知風暴** | 高頻 log 寫入會高頻觸發 badge 重算（O(n)、n ≤ 500）。僅在 dashboard 開啟時有訂閱者，關閉時無成本。若實測有掉幀，STAGE 0b 需評估節流；現階段不預先優化。 |
| **Material 3 依賴** | 本 package 未自行設定 `useMaterial3`，主題由 host app 決定。`Badge` 在 M2 主題下的外觀需確認可接受，或改用自繪的輕量標記。STAGE 0b 需驗證。 |
| **兩套更新模型並存** | badge 即時、列表手動，是刻意取捨（摘要要即時、列表要穩定）。風險是後續開發者誤以為整個 dashboard 已 reactive 而做出不一致的擴充——需在程式碼註解明示此邊界。 |
| **記憶體洩漏** | dashboard 關閉時若未解除訂閱，`FlutterInspector` 為 app 全域長生命週期物件，會持有已 dispose 的 widget。必須有對應的 dispose 處理。 |
