# 實作計畫：點選元件查看尺寸與 constraints (Tap-to-Inspect Layout Info)

> 規格：[`docs/features/2026-10-17-tap-to-inspect-layout.md`](../features/2026-10-17-tap-to-inspect-layout.md)

## 動工前必查結論（brainstorm §P31「⚠️ 動工前必查」）

1. **hit test 入口 API（已對本機 Flutter SDK git tag 實查）**
   - `GestureBinding.hitTestInView(result, position, viewId)`：**3.13.0 才出現**，低於套件下限 `flutter >= 3.10.0` 不可用。
   - `RendererBinding.renderViews`：約 3.16 才出現；`RendererBinding.renderView` 在新版已 deprecated。兩者都無法橫跨 3.10 → 3.47。
   - `RenderView.hitTest(HitTestResult result, {required Offset position})`：3.10.0 與 3.47.1 簽章一致。
   - `WidgetsBinding.rootElement`：3.10.0 起存在。
   - **決定**：不碰任何 binding 層 hit test API。從攔截層自己的 `RenderObject` 沿 `parent` 往上找到所屬 `RenderView`，直接呼叫 `RenderView.hitTest`。這同時天然支援 multi-view（只探測攔截層所在的 view），不需 `viewId`。
   - `RenderObject.parent` 型別在 3.10 為 `AbstractNode?`、新版為 `RenderObject?`；走訪時以 `Object?` 變數 + `is` 判斷，兩版都可編譯。
2. **overlay 管理（已 grep）**
   - `lib/` 內唯一的 `OverlayEntry` 擁有者是 `InspectorOverlayManager`，職責是「FAB 的常駐生命週期」，註明僅支援單一 FAB 實體。
   - **決定**：選取模式是短暫工具層，生命週期與 FAB 無關，**不擴充** `InspectorOverlayManager`；改由選取模式自己的 `show()` 管一個 entry。另外，`InspectorFab.build` 頂層回傳 `Positioned`（`ParentDataWidget<StackParentData>`），必須維持為 Overlay `_Theatre` 的直接子節點；因此探測屏蔽 `LayoutProbeShield` 包在 `InspectorFab` 的 `Positioned.child` 外層（包裹 `GestureDetector`），不改 `InspectorOverlayManager`。

## 實作方向與 Trade-off

**問題核心**：hit test 會被最上層的東西吃掉——攔截層自己、FAB 都在 app 上方。Overlay 的 `_RenderTheater` 命中第一個子層就停，事後過濾 `HitTestResult.path` 沒用，app 根本不會出現在路徑上。

- **方案 A：探測時暫時 `IgnorePointer`** — 需要 rebuild 才生效，而探測是同步的，做不到。❌
- **方案 B：事後過濾 path** — 如上，下層根本沒被 hit test。❌
- **方案 C（選定）：探測屏蔽 `LayoutProbeShield`** — 一個 `RenderProxyBox`，平常行為與一般 proxy 完全相同；只有在全域同步旗標 `_probing == true` 的那一瞬間 `hitTest` 回傳 `false`。探測流程：`_probing = true` → `RenderView.hitTest` → `_probing = false`（`try/finally`）。全程同步、單執行緒，不會洩漏到真實手勢。攔截層與 FAB 都包上屏蔽，一個機制消滅「點到自己」這整類特殊情況。

## 資料結構

```dart
/// 一層 RenderBox 的快照。點擊當下讀取，之後 UI 只讀它，不持有 render object。
@immutable
class LayoutLevel {
  const LayoutLevel({
    required this.widgetName,   // 找不到 element 時為 null
    required this.renderName,   // renderObject.runtimeType.toString()
    required this.size,
    required this.constraints,
    required this.rect,         // 螢幕座標（global），供框線與文字使用
  });
  final String? widgetName;
  final String renderName;
  final Size size;
  final BoxConstraints constraints;
  final Rect rect;
}
```

- 父鏈 = `List<LayoutLevel>`，index 0 為命中目標，往後依序為 `RenderBox` 祖先，止於 `RenderView`（不含）。
- 無新 model 進 `lib/src/models/`、無 buffer、無 notifier 進 registry。UI 狀態只有「目前的 chain」與「目前 index」兩個欄位，存在選取模式的 `State` 內，關閉即丟。

## 核心演算法

### `probeLayoutAt(RenderObject anchor, Offset globalPosition) → List<LayoutLevel>`

1. 從 `anchor` 沿 `parent` 找 `RenderView`；找不到 → 回傳空 list。
2. `_probing = true; try { view.hitTest(result, position: globalPosition); } finally { _probing = false; }`
3. 在 `result.path` 中取第一個 `target is RenderBox && target.hasSize` 的項目為目標；沒有 → 回傳空 list。
4. 從目標沿 `parent` 往上收集所有 `RenderBox && hasSize`（略過 sliver 等非 `RenderBox`），止於 `RenderView`。
5. 名稱反查：把 chain 的 render object 放進 `Set`，從 `WidgetsBinding.instance.rootElement` 做**一次**深度優先走訪；遇到 `element is RenderObjectElement && set.contains(element.renderObject)` 就記下 `element.widget.runtimeType.toString()`。不分 build mode、不讀 `debugCreator`。
6. 每層 `rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size)`（正確處理 `Transform`／縮放）。

> 一次點擊 = 一次 hit test + 一次樹走訪，成本可接受；不做快取。

### `formatLayoutChain(List<LayoutLevel> chain, {required bool mayBeObfuscated}) → String`

純函式，放 `lib/src/utils/layout_formatters.dart`（對齊既有 `log_formatters.dart`／`network_formatters.dart`）：

```text
Layout inspect — 3 levels (target first)
Note: names may be obfuscated
#0 RichText (RenderParagraph)
   size: 120.0 × 20.0
   constraints: 0.0 ≤ w ≤ 360.0, 0.0 ≤ h ≤ ∞
   offset: (16.0, 200.0)
#1 Padding (RenderPadding)
   ...
```

- `Note:` 行僅在 `mayBeObfuscated` 為 true 時輸出；呼叫端預設傳 `!kDebugMode`（支援注入以供測試）。
- 數值一律 `toStringAsFixed(1)`，`double.infinity` 顯示 `∞`。`widgetName == null` 時只印 render 名。
- 資訊卡與文字輸出共用同一組單層格式化 helper（`formatSize`、`formatConstraints`、`formatOffset`），避免兩份格式。

## UI 結構（`lib/src/ui/layout_inspect/layout_inspect_overlay.dart`）

```text
LayoutInspectOverlay.show(OverlayState overlay, {bool? mayBeObfuscated})   // static，已開啟時 no-op
  └─ OverlayEntry
      └─ LayoutProbeShield
          └─ _LayoutInspectLayer (StatefulWidget: chain, index)
              Stack
              ├─ Positioned.fill  GestureDetector(opaque, onTapUp → probe)
              ├─ Positioned.fromRect(rect: level.rect, child: IgnorePointer(child: DecoratedBox border))
              └─ Align(card 位置：依初始命中目標 chain.first.rect.center.dy 在下半螢幕 → 頂部，否則底部；切換父鏈時固定不跳動)
                  └─ _LayoutInfoCard（無選取時顯示 "Tap a widget to inspect" + 關閉鈕）
```

- 探測的 `anchor` 用攔截層自己的 `context.findRenderObject()`。
- `_LayoutInfoCard` 顯示內容：widget 型別名、render object 型別名、`formatSize(level.size)`、`formatConstraints(level.constraints)`、`formatOffset(level.rect.topLeft)`、層級位置 `index + 1 / length`，以及當 `mayBeObfuscated`（預設 `!kDebugMode`）為 true 時標註 `names may be obfuscated`。
- `_LayoutInfoCard` 按鈕：parent ↑、child ↓（到頂／到底停用）、copy、share、close。
- copy：`Clipboard.setData` + 卡片內短暫顯示 `Copied` 狀態文字（overlay 不一定在 `Scaffold` 底下，故不用 `ScaffoldMessenger`；以 `State` 內 bool + `Timer` 2 秒復原，`dispose` 時取消）。
- share：`shareText(formatLayoutChain(...))`。
- close 與生命週期清理：`show()` 直接以 `if (_entry != null) return;` 防重入（涵蓋同幀連呼）；按 close 呼叫 `entry.remove()` 並將靜態 `_entry` 清回 `null`；同時在 `_LayoutInspectLayerState.dispose()` 中若 `_entry == widget.entry` 亦同步將靜態 `_entry` 清回 `null`，確保測試拆樹或宿主 `Overlay` 重建卸載時不會殘留死參考。
- 卡片包 `Material` + `SafeArea`，自帶 `Theme`／`Directionality` 來源仰賴 overlay 所在的 `MaterialApp`（與 FAB 相同前提）。

## 檔案異動清單

| 檔案 | 異動 |
|:---|:---|
| `lib/src/ui/layout_inspect/layout_probe.dart`（新增） | `LayoutLevel`、`probeLayoutAt`、`LayoutProbeShield`（widget + `RenderProxyBox`）、`_probing` 旗標 |
| `lib/src/utils/layout_formatters.dart`（新增） | `formatSize`、`formatConstraints`、`formatOffset`、`formatLayoutChain` |
| `lib/src/ui/layout_inspect/layout_inspect_overlay.dart`（新增） | `LayoutInspectOverlay.show`、`_LayoutInspectLayer`、`_LayoutInfoCard` |
| `lib/src/ui/dashboard/dashboard_modal.dart` | `AppBar.actions` 新增 `_LayoutInspectAction`（`Icons.ads_click`，tooltip `Inspect layout`，**不加 `kDebugMode`**）：先取 `Overlay.maybeOf(context, rootOverlay: true)`，`pop()` dashboard，再 `LayoutInspectOverlay.show(overlay)` |
| `lib/src/ui/widgets/inspector_fab.dart` | `Positioned.child` 外層包上 `LayoutProbeShield`，維持 `Positioned` 為 `_Theatre` 直接子節點 |
| `test/utils/layout_formatters_test.dart`（新增） | formatter 單元測試 |
| `test/ui/layout_inspect/layout_probe_test.dart`（新增） | 探測邏輯 widget 測試 |
| `test/ui/layout_inspect/layout_inspect_overlay_test.dart`（新增） | 選取模式整合 widget 測試 |

> 不改 CHANGELOG：與本批次前幾項 PR（#205／#207／#209）一致，版本說明於發版流程統一彙整。不新增 `FlutterInspector` 公開 API、不改 barrel export。

## 任務拆分

### 任務 1 `[標準]`：探測核心 + formatter（純邏輯，無 UI 入口）

- 檔案：`layout_probe.dart`、`layout_formatters.dart` 及其兩份測試。
- 測試要點：
  - formatter：多層輸出、`∞`、`widgetName == null`、`mayBeObfuscated` 開關、`formatOffset`。
  - probe：`Center > SizedBox(100×40) > ColoredBox` 點中心 → chain[0] 為 `RenderBox`、size 為 100×40、constraints 為 tight 100×40；chain 依序往上且不含 `RenderView`；名稱反查得到對應 widget 名。
  - probe：在目標上方疊一層 `LayoutProbeShield(child: 全螢幕 GestureDetector(opaque))`，探測仍命中下層目標；一般 `tester.tap` 時該 GestureDetector 照常收到點擊（屏蔽平常透明無副作用）。
  - probe：點擊位置無任何 `RenderBox`（或 anchor 不在 `RenderView` 底下）→ 空 list。
  - probe：例外安全——`_probing` 在 hit test 拋錯時仍會被 `finally` 復原（以子類 render object 於 `hitTest` 拋錯驗證）。

### 任務 2 `[標準]`：選取模式 UI + dashboard 入口 + FAB 屏蔽

- 檔案：`layout_inspect_overlay.dart`、`dashboard_modal.dart`、`inspector_fab.dart` 及整合測試。
- 測試要點：
  - dashboard 出現 `Inspect layout` 按鈕（不受 `kDebugMode` 影響的斷言：按鈕存在即可）。
  - 點按鈕 → dashboard 關閉、顯示 `Tap a widget to inspect`。
  - 點擊已知元件 → 卡片顯示其 widget/render 名稱、size、constraints、offset、`1 / N`（以及 `mayBeObfuscated: true` 時顯示 `names may be obfuscated`）。
  - parent ↑ → 顯示 `2 / N` 且內容改變，卡片位置維持依 `chain.first` 不跳動；到頂時 ↑ 停用、到底時 ↓ 停用。
  - copy → 剪貼簿（mock `SystemChannels.platform`）收到 `formatLayoutChain` 結果，卡片顯示 `Copied`。
  - close → 攔截層移除，app 元件可再被正常點擊。
  - 重複呼叫 `show` 不會疊兩層；Overlay 拆樹卸載後再次呼叫 `show` 可正常重新掛載。
  - FAB 已 attach 時，點 FAB 所在位置 → 命中的是 FAB 底下的 app 元件。

## 驗證

```bash
flutter test test/utils/layout_formatters_test.dart test/ui/layout_inspect/
flutter test
flutter analyze lib/ test/
```

手動驗收（可選）：example app 既有 RenderFlex 溢出示範頁，以 release build 點選溢出元件並沿父鏈找到卡住它的父層。
