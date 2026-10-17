# 點選元件查看尺寸與 constraints (Tap-to-Inspect Layout Info)

> 來源：[`docs/brainstorm/2026-10-14-features-brainstorm.md`](../brainstorm/2026-10-14-features-brainstorm.md) §P31（含 2026-10-16 使用者三項裁決）。

## What & Why

QA 在實機發現 UI 被壓扁、溢出或尺寸不對時，§P28 排版邊界只能畫出框線（且僅 debug build），回報時仍說不出精確數字：這個元件實際多大？父層給了什麼上下限？是哪一層的 constraints 把它卡住？QA 裝置通常沒有開發機連線，無法開 DevTools。

本功能讓使用者在 dashboard 按一顆按鈕進入「選取模式」，點畫面上任一元件，即可看到它的實際 `size`、`constraints`、螢幕位置與 widget 型別名，並可沿父鏈逐層往上查看，最後一鍵複製／分享成純文字附進 bug 單。**release build 同樣可用**。

## 使用者故事 (User Stories)

- 身為 QA，我在 release 版實機看到某個按鈕被壓扁，希望點它就能看到「size 48×20、constraints 上限高度 20」，並往上找到把高度卡在 20 的那一層父元件。
- 身為 QA，我希望把查到的整條父鏈尺寸資訊一鍵複製或分享，貼進 bug 單，取代「截圖 + 口頭描述」。
- 身為開發者，我希望這個工具不開時完全不存在、不寫入任何 buffer、不出現在時間軸，對 app 零副作用。

## 驗收條件 (Acceptance Criteria)

1. **進入選取模式**
   - `DashboardModal` 的 `AppBar.actions` 新增一顆按鈕（tooltip `Inspect layout`），**所有 build mode 都顯示**（不同於 §P28 的 `kDebugMode` 限制）。
   - 按下後關閉 dashboard，在 app 上蓋一層全螢幕透明攔截層，並顯示提示「Tap a widget to inspect」與關閉鈕。
2. **點選命中**
   - 點擊位置以 Flutter 原生 hit test 取得命中路徑，取路徑上**第一個 `RenderBox`** 作為目標。
   - hit test **不得命中 kit 自身**：選取模式的攔截層／資訊卡、inspector FAB 都必須對探測透明。點到 FAB 所在位置時，命中的是 FAB 底下的 app 元件。
   - 命中路徑上沒有任何 `RenderBox` 時，不顯示資訊卡、維持選取模式。
3. **資訊卡**
   - 顯示目前層級的：widget 型別名、render object 型別名、`size`、`constraints`、螢幕上的左上角位置（global offset）。
   - 在畫面上以框線標出目前層級元件的範圍。
   - 非 debug build 時，卡片標註「names may be obfuscated」（`--obfuscate` 編譯時型別名會被混淆，不嘗試還原）。
4. **父鏈切換**
   - 父鏈 = 目標及其所有 `RenderBox` 祖先（略過非 `RenderBox` 的 render object，如 sliver）。
   - 資訊卡提供「往上一層（parent）」「往下一層（child）」按鈕；到頂／到底時對應按鈕停用。框線與卡片內容隨層級更新。
   - 卡片顯示目前層級位置，如 `2 / 37`。
5. **複製／分享**
   - 複製：把整條父鏈（從目標到最上層）輸出為純文字並 `Clipboard.setData`，顯示 SnackBar 或等效回饋。
   - 分享：同一份文字走既有 `shareText`（`lib/src/utils/share_text.dart` 條件匯出），不新增介面。
6. **重新選取與離開**
   - 資訊卡顯示中，點擊 app 其他位置 → 以新目標重新查詢（停留在選取模式）。
   - 按關閉鈕 → 移除攔截層，回到 app 正常操作。
7. **資料一律快照**
   - 點擊當下即讀取整條父鏈的數值成快照，之後 UI 只讀快照；不持有 render object 參考，畫面變動不即時更新（須重新點選）。
8. **零副作用**
   - 不寫入任何 buffer、不動 `revision`、不進 `mergedTimeline`、不產生 navigator 事件（攔截層是 `OverlayEntry`，不是 route）。
9. **測試覆蓋**
   - 文字 formatter 單元測試。
   - 探測邏輯 widget 測試：已知尺寸／constraints 的元件被正確命中；kit 自身（FAB、攔截層）對探測透明；父鏈順序與內容正確。
   - 選取模式 widget 測試：dashboard 按鈕 → 進入模式 → 點擊顯示資訊卡 → 父鏈切換 → 複製寫入剪貼簿 → 關閉移除攔截層。

## 範圍邊界 (Scope & Boundaries)

- **Included（包含）**
  - Dashboard AppBar 按鈕、選取模式攔截層、資訊卡、框線標示、父鏈切換、純文字 formatter、複製／分享。
  - 讓 inspector FAB 對探測透明所需的最小調整。
  - CHANGELOG 與對應測試。
- **Excluded（排除，沿用 brainstorm「刻意不做」）**
  - 整棵 widget／element tree 瀏覽（AF#8 否決範圍）。
  - 即時更新（畫面變動後須重新點選）。
  - 修改屬性、顏色／padding 等屬性白名單清單（DevTools 範圍，且 release 下 diagnostics 不完整）。
  - 寫入時間軸或任何 buffer。
  - 新增 example 示範頁（以既有 RenderFlex 溢出示範驗收）。
  - 新增 `FlutterInspector` 公開 API（入口只在 dashboard 內）。
