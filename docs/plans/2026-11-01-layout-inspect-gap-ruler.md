# 實作計畫：雙元件間距標尺與像素測距 (Widget Gap / Distance Ruler)

> 規格：[`docs/features/2026-11-01-layout-inspect-gap-ruler.md`](../features/2026-11-01-layout-inspect-gap-ruler.md)

## 動工前必查結論

1. **統一雙目標資料結構（以好品味消除不對稱特殊情況）**
   - 既有 `_LayoutInspectLayerState` 已具備完整的 `_chain`（`List<LayoutLevel>`）與 `_index`，並支援 `_onParent`、`_onChild` 與邊界防護。
   - 進入測距模式時，不新增獨立的「第二組鏈與索引」，而是：
     - 將基準 A 鎖定為快照：`LayoutLevel? _lockedA = _chain[_index];`。
     - 使用者後續點選畫面時，**完全復用既有探測邏輯**直接更新 `_chain` 與 `_index`。當前選取的即為對照 B！
     - **好品味價值**：對照 B 天然繼承父鏈瀏覽能力（Parent/Child 按鈕直接作用於 B），點選 `Card` 或 `Button` 內部的文字時，使用者可直接按 ↑ 導航至父級 `Card` 或 `Button` 量測間距，完全消滅了「B 只能是 leaf node」的重大缺陷。
     - 退出測距時僅需設 `_lockedA = null`，保留當前 B 的選取，操作心智模型無縫連續。
2. **1D 區間投影距離算法與閉區間包含判定**
   - 1D Gap 投影距離算法：
     ```dart
     double compute1DGap(double aStart, double aEnd, double bStart, double bEnd) {
       return math.max(0.0, math.max(aStart, bStart) - math.min(aEnd, bEnd));
     }
     ```
   - 閉區間包含判定（防守 Flutter `Rect.contains(Offset)` 右底邊半開區間陷阱）：
     ```dart
     bool containsRect(Rect outer, Rect inner) =>
         outer.left <= inner.left &&
         outer.top <= inner.top &&
         outer.right >= inner.right &&
         outer.bottom >= inner.bottom;
     ```
   - 窮盡幾何關係模型（`sealed class GapRelation`）：
     - `Separated(gapX, gapY)`：完全相離（純水平、純垂直或對角分離）。
     - `Contained(outerIsA, insets: RulerInsets)`：一者完全包含另一者（含邊緣貼齊 padding=0）。
     - `Overlapping(intersection)`：局部重疊但非完全包含，標註交集 Rect 與尺寸。
     - `Adjacent(axis)`：邊緣剛好貼齊（gap == 0.0 但非重疊）。
3. **標尺幾何資料結構化（純 Dart 可測性）**
   - 拒絕在 `GapRulerPainter.paint()` 內做幾何運算。
   - 在 `gap_ruler_geometry.dart` 提煉 `RulerDisplayModel` 與 `RulerSegment`：
     ```dart
     class RulerSegment {
       const RulerSegment({
         required this.start,
         required this.end,
         required this.label,
         this.isDashed = false,
         this.badgeOffset,
       });
       final Offset start;
       final Offset end;
       final String label;
       final bool isDashed;
       final Offset? badgeOffset;
     }

     class RulerDisplayModel {
       const RulerDisplayModel({
         required this.rectA,
         required this.rectB,
         required this.relation,
         required this.segments,
       });
       final Rect rectA;
       final Rect rectB;
       final GapRelation relation;
       final List<RulerSegment> segments;
     }
     ```
   - `buildRulerDisplayModel(Rect a, Rect b)` 負責產生所有端點、虛線投影、文字標籤與徽章避讓坐標，100% 透過純 Dart 單元測試檢驗。
   - `GapRulerPainter` 僅單純根據 `RulerDisplayModel` 繪製線條與文字。
4. **資訊卡與複製分享合約**
   - 資訊卡 `_LayoutInfoCard` 在 `_lockedA != null` 時：
     - 工具列顯示高亮之「退出測距」按鈕（圖示 `Icons.straighten` 變為 Active 色彩）。
     - 顯示副標題提示：`Measuring against: ${_lockedA.widgetName ?? _lockedA.renderName}`。
     - 顯示簡潔間距摘要：如 `Gap: 16.0 px (horizontal)` 或 `Insets: T:8 R:12 B:8 L:12`。
   - 複製與分享：擴充 `formatLayoutChain`（或新增 `formatMeasurement`），在測距模式下輸出：
     ```text
     === Measurement (Gap Ruler) ===
     Reference A: Text (RenderParagraph) [size: 80.0x20.0, offset: (16.0, 40.0)]
     Target B: ElevatedButton (RenderFlex) [size: 120.0x48.0, offset: (16.0, 68.0)]
     Relation: Separated
     Vertical Gap: 8.0 px
     Horizontal Gap: 0.0 px
     ```
5. **繪製層防禦與 320dp 螢幕防護**
   - 標尺 `CustomPaint` 外層強制包覆 `IgnorePointer`，杜絕手勢攔截。
   - `_LayoutInfoCard` 內之動作按鈕使用 `Wrap`，並將內距縮減，確保在 320dp 狹窄螢幕下零 overflow。

## 檔案異動清單

| 檔案 | 異動 |
|:---|:---|
| `lib/src/ui/layout_inspect/gap_ruler_geometry.dart`（新增） | `compute1DGap`、`containsRect`、`GapRelation`（sealed）、`RulerSegment`、`RulerDisplayModel`、`buildRulerDisplayModel` 純幾何運算核心 |
| `lib/src/ui/layout_inspect/gap_ruler_painter.dart`（新增） | `GapRulerPainter` 純 Canvas 標尺繪製元件（消費 `RulerDisplayModel`） |
| `lib/src/utils/layout_formatters.dart` | 擴充 `formatMeasurement` 支援雙元件測距純文字輸出（供 Copy/Share 使用） |
| `lib/src/ui/layout_inspect/layout_inspect_overlay.dart` | 資訊卡新增測距按鈕、管理 `_lockedA` 狀態、Stack 疊加 `IgnorePointer(child: CustomPaint(painter: GapRulerPainter))` |
| `test/ui/layout_inspect/gap_ruler_geometry_test.dart`（新增） | 幾何間距、閉區間包含、對角投影與線段生成純 Dart 單元測試 |
| `test/ui/layout_inspect/gap_ruler_painter_test.dart`（新增） | 標尺 Canvas 繪製 widget 測試 |
| `test/ui/layout_inspect/gap_ruler_overlay_test.dart`（新增） | 測距模式進入/退出、對照 B 父鏈切換、Copy 測距數據整合測試 |

## 任務拆分

### 任務 1 `[標準]`：幾何運算核心、標尺資料模型與文字格式化 (`gap_ruler_geometry.dart` & `layout_formatters.dart`)
- **檔案**：
  - `lib/src/ui/layout_inspect/gap_ruler_geometry.dart`
  - `lib/src/utils/layout_formatters.dart`
  - `test/ui/layout_inspect/gap_ruler_geometry_test.dart`
- **實作內容**：
  1. `gap_ruler_geometry.dart`：
     - `compute1DGap` 與 `containsRect`。
     - `sealed class GapRelation`：`SeparatedRelation`、`ContainedRelation`、`OverlappingRelation`、`AdjacentRelation`。
     - `RulerSegment` 與 `RulerDisplayModel`。
     - `buildRulerDisplayModel(Rect a, Rect b)`：
       - 純水平分離（Y 軸重疊）：在重疊中心計算水平標尺線與端點垂線。
       - 純垂直分離（X 軸重疊）：在重疊中心計算垂直標尺線與端點水平線。
       - 對角分離：分別計算 X 軸與 Y 軸投影線段（虛線）與間距段（實線標尺）。
       - 完全包含：計算 Top/Bottom/Left/Right 四條 Inset 指引線段。
       - 局部相交：生成交集 Rect 標註線段與交集尺寸。
  2. `layout_formatters.dart`：
     - 新增 `formatMeasurement(LayoutLevel a, LayoutLevel b, GapRelation relation)`。
- **測試重點**：
  - 閉區間貼齊測試：`containsRect` 在四邊 padding 均為 0 時仍回傳 true。
  - 對稱性測試：`buildRulerDisplayModel(A, B)` 與 `buildRulerDisplayModel(B, A)` 產出之數值與間距大小恆等。
  - 覆蓋四種幾何關係的分支測試。
  - 格式化文字輸出正確性測試。

### 任務 2 `[標準]`：標尺繪製器、資訊卡整合與測距互動 (`gap_ruler_painter.dart` & `layout_inspect_overlay.dart`)
- **檔案**：
  - `lib/src/ui/layout_inspect/gap_ruler_painter.dart`
  - `lib/src/ui/layout_inspect/layout_inspect_overlay.dart`
  - `test/ui/layout_inspect/gap_ruler_painter_test.dart`
  - `test/ui/layout_inspect/gap_ruler_overlay_test.dart`
- **實作內容**：
  1. `gap_ruler_painter.dart`：
     - 接收 `RulerDisplayModel`。
     - 繪製 A（藍色）與 B（橘色）邊框。
     - 繪製實線標尺、端點與虛線投影。
     - 以 `TextPainter` 繪製半透明膠囊背景徽章與文字。
  2. `layout_inspect_overlay.dart`：
     - 在 `_LayoutInspectLayerState` 引入 `LayoutLevel? _lockedA`。
     - 點擊「測距」按鈕：切換 `_lockedA = _chain.isNotEmpty ? _chain[_index] : null`。
     - 點選畫面更新 `_chain`（作為 B）：若 `_lockedA != null`，Stack 頂部透過 `Positioned.fill` + `IgnorePointer` 渲染 `CustomPaint(painter: GapRulerPainter(...))`。
     - 資訊卡連動：顯示 B 的詳細資訊、`_lockedA` 參考元件名、間距摘要。
     - Parent/Child 導航：直接調用既有 `_onParent` / `_onChild`，對照 B 沿層級移動，標尺即時重繪。
     - 複製與分享：若處於測距模式，一併附加 `formatMeasurement`。
     - 退出測距：按鈕重設 `_lockedA = null`，標尺隱藏，保留當前 B 的選取。
- **測試重點**：
  - Painter 測試：確認在各種幾何模型下 `paint` 正常運作，無例外拋出。
  - 互動測試：
    - 點選元件 A → 點擊「測距」→ 點選元件 B → 同時出現藍框、橘框與標尺。
    - 在 B 上點擊 Parent ↑ → B 移動至外層容器，標尺即時重新計算並更新。
    - 點擊複製 → 剪貼簿收到包含兩元件名稱與間距數據的字串。
    - 點擊退出測距 → 藍框與標尺消失，B 維持選取狀態。
    - 關閉 Layout Inspector → 攔截層完全清理。

## 驗證流程

```bash
flutter test test/ui/layout_inspect/
flutter test
flutter analyze lib/ test/
```
