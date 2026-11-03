# 雙元件間距標尺與像素測距 (Widget Gap / Distance Ruler)

> 來源：[`docs/brainstorm/2026-11-04-features-brainstorm.md`](../brainstorm/2026-11-04-features-brainstorm.md) §P36。

## What & Why

在 UI 開發與 QA 實機走查時，最耗時的反覆確認之一是元件相對間距與 Padding 是否符合設計稿（例如按鈕與文字之間差了多少 px、卡片內部邊距是否為 16px、相鄰兩卡片的外距是否一致）。

既有的 Layout Inspect（§P31）僅支援點選單一元件檢視其本身的 `size`、`constraints` 與 `offset`，無法直接對比兩個元件的相對幾何關係。QA 仍須以肉眼比對、手動心算坐標差，甚至截圖進繪圖軟體量測。

本功能在 Layout Inspect 基礎上，提供**雙元件間距標尺與像素測距 (Gap Ruler)**：
1. 使用者在選取元件 A 後，可一鍵開啟「測距模式」將其鎖定為基準 A（藍框）。
2. 點選畫面上的第二個元件作為對照 B（橘框）。
3. 畫布自動透過具備交換律對稱的 **1D 區間投影距離算法** 計算兩元件間距，並以 `CustomPainter` 即時繪製虛線投影引導線、端點標尺線與 px 數值標籤。
4. 當兩元件存在包含關係或邊界重疊時，自動切換為 **四周 Inset 邊距分析模式**，直觀標註四方向的 padding 像素值。
5. 探測退出即丟棄狀態，零 buffer、零時間軸負擔，全 build mode（含 release）皆可運作。

## 使用者故事 (User Stories)

- 身為 QA，我在實機上想確認「標題文字」與「副標題文字」之間的垂直間距是否精確為 8px，我希望點選標題後點擊「測距」，再點選副標題，畫面上便直接畫出 8px 的垂直標尺線。
- 身為開發者，我想確認自訂按鈕內部的 Icon 與文字是否符合 12px 內邊距，當我點選按鈕與內部文字時，標尺自動顯示四周 Inset (Top/Bottom/Left/Right) 的 padding 數值。
- 身為測試人員，我希望測距操作無論「先點 A 後點 B」或「先點 B 後點 A」，計算出的幾何間距完全一致，不因點選順序而產生正負號或跨距誤差。

## 驗收條件 (Acceptance Criteria)

1. **進入與切換測距模式**
   - 既有 `_LayoutInfoCard`（資訊卡）新增「測距」按鈕（圖示 `Icons.straighten`，tooltip `Measure distance`）。
   - 點擊後將當前選取的元件鎖定為基準 A（以藍色外框標記），卡片提示進入測距模式（「Tap another widget to measure gap」），並提供退出測距按鈕。
   - 處於測距模式時，點擊第二個元件作為對照 B（以橘色外框標記）。
2. **幾何間距計算核心 (Gap Ruler Geometry)**
   - 採 1D 區間投影距離算法：
     `compute1DGap(double aStart, double aEnd, double bStart, double bEnd) => math.max(0.0, math.max(aStart, bStart) - math.min(aEnd, bEnd))`
   - 算法具備嚴格交換律對稱性：`computeGap(A, B) == computeGap(B, A)`。
   - 支援外距 (External Gap)：當 X 軸或 Y 軸兩區間不重疊時，計算其最近邊緣的垂直/水平距離。
   - 支援內距 / 包含 (Inset Padding)：當元件 B 完全或部分落在元件 A 範圍內（或反之）時，計算四周相對邊緣的 padding 差值（Top, Bottom, Left, Right）。
3. **Canvas 標尺繪製 (GapRulerPainter)**
   - 繪製基準 A（藍框）與對照 B（橘框）的外邊界框線。
   - 繪製軸向間距線、虛線投影輔助線（Dash line）與端點垂線。
   - 在標尺中心繪製圓角標籤徽章，清楚顯示如 `16 px` 或 `8.5 px` 的格式化數值；若間距小於標籤寬度，標籤自動外浮或保持高對比度可讀性。
4. **重新選取與退出**
   - 在已選取 A 與 B 狀態下，點擊第三個元件可替換對照 B，即時重繪標尺。
   - 資訊卡提供「清除標尺 / 退出測距」動作，復原為單元件選取狀態。
   - 關閉 Layout Inspector（點擊 Close）時一併銷毀所有測距狀態。
5. **資料快照與零副作用**
   - 測距僅讀取當前探測取得之 `LayoutLevel` 快照，不持有 `RenderObject` 引用。
   - 零 buffer 配置、不寫入 DB、不污染 Inspector 事件時間軸。
6. **測試覆蓋**
   - 純幾何算法單元測試：覆蓋完全相離（水平、垂直、對角）、部分重疊、邊緣相切、完全包含、交換順序恆等性。
   - Inset Padding 算法單元測試：父子容器四邊 padding 計算精確度。
   - Widget 測試：驗證點擊「測距」進入模式、點擊第二個元件呈現雙框與標尺、更換對照 B、清除標尺與關閉 Inspector 之完整交互路徑。

## 範圍邊界 (Scope & Boundaries)

- **Included（包含）**
  - 1D 區間投影距離與 Inset 計算純 Dart 函數與資料結構。
  - `GapRulerPainter` Canvas 標尺繪製元件。
  - `_LayoutInspectLayer` 與 `_LayoutInfoCard` 的測距狀態管理與 UI 整合。
  - 完整單元測試與 Widget 測試。
- **Excluded（排除）**
  - 3 個以上元件的多點鏈式標尺（保留雙元件核心）。
  - 旋轉多邊形非軸對齊之任意角距離（以軸對齊 global bounding Rect 為準）。
  - 標尺數據寫入歷史時間軸或持久化儲存。
