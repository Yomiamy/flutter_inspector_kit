# 實作計畫：網路請求耗時慢查詢標記

## 實作方向與 Trade-off 分析
在實作此功能時，我們考量了以下幾種方向：
1. **直接修改資料模型 (Model) 並新增 `isSlow` getter**:
   - *優點*: 視圖層能直接呼叫 `entry.isSlow`，減少邏輯重複。
   - *缺點*: 閾值屬於 UI 呈現或配置的一環，若把閾值邏輯寫死在資料模型層 (`NetworkEntry`)，可能違反職責分離。
2. **在 Util 或 Config 中定義全域常數，並在 UI 層進行判斷 (選定方案)**:
   - *優點*: 業務邏輯與資料分離。`kSlowRequestThreshold` 定義在 `network_utils.dart` 中，UI 渲染時直接判斷 `duration >= kSlowRequestThreshold`，修改彈性高。
   - *缺點*: 兩個 Tab (`ConsoleTab` 與 `NetworkTab`) 需要各自寫 UI 判斷，但考量到兩個列表元件本來就各自實作，影響範圍可控。
3. **將 Slow 標記獨立抽出成為共用 Widget**:
   - *優點*: 減少 `_EntryTile` (Network) 與 `_NetworkEntryRow` (Console) 的重複代碼。
   - *缺點*: 現階段標籤非常輕量，只是一小段 `Container`。過早抽象可能導致程式碼跳躍與過度設計。

**最終選擇**: 採用方向 2，在 `network_utils.dart` 定義常數，並在 UI 中直接判斷與繪製。保留未來若有更多共用需求再抽出 Widget 的彈性。

## 資料結構與常數定義
- 新增常數 `kSlowRequestThreshold`，型別為 `Duration`，預設為 `Duration(seconds: 2)`。存放於 `lib/src/utils/network_utils.dart`。

## 檔案異動
1. `lib/src/utils/network_utils.dart`: 新增 `kSlowRequestThreshold` 定義。
2. `lib/src/ui/dashboard/tabs/console_tab.dart`: 修改 `_NetworkEntryRow` 的 `trailing`，加入慢查詢的 UI 判斷。
3. `lib/src/ui/dashboard/tabs/network_tab.dart`: 
   - 修改 `_EntryTile` 的 `trailing`，加入慢查詢的 UI 判斷。
   - 修改 `_ErrorSummaryBanner`，在錯誤提示後方加入 `| 🐢 X slow` 的統計文字。

## 任務拆分
1. **定義閾值常數**
   - 檔案: `lib/src/utils/network_utils.dart`
   - 動作: 新增 `const Duration kSlowRequestThreshold = Duration(seconds: 2);` 及其註解。
2. **實作 Network Tab 的慢查詢標籤**
   - 檔案: `lib/src/ui/dashboard/tabs/network_tab.dart`
   - 動作: 找到 `_EntryTile` widget 的 `trailing` 屬性，將原本單一的 `Icon` 改為 `Row`，並在請求耗時大於等於閾值時，顯示帶有 `🐢 SLOW` 的橘色標籤。
3. **實作 Network Tab 摘要列統計**
   - 檔案: `lib/src/ui/dashboard/tabs/network_tab.dart`
   - 動作: 在 `_ErrorSummaryBanner` 的 `TextSpan` 中，動態統計 `entries` 裡慢查詢的數量，並將 `| 🐢 X slow` 渲染出來。
4. **實作 Console Tab 的慢查詢標籤**
   - 檔案: `lib/src/ui/dashboard/tabs/console_tab.dart`
   - 動作: 在頂端引入 `../../../utils/network_utils.dart`。找到 `_NetworkEntryRow` widget 的 `trailing`，加上與 `network_tab.dart` 相同的慢查詢標記 UI。
