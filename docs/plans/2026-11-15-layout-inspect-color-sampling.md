# 實作計畫：Inspect layout 結算點取色（Settled-Point Color Sampling）

> **給執行 agent**：依 `subagent-driven-development`（建議）或 `executing-plans` 逐任務執行；步驟以 `- [ ]` 追蹤。執行者必須同時讀本計畫與規格。本計畫的程式碼與測試已在 scratchpad 原型上逐字跑過（§8），照抄即可，不要自行「改良」。

- **日期**：2026-11-15（plan-verifier 初審 REVISE 後第 1 次修正；複審 READY 後再採納 3 條次要意見。對照見 §11）
- **規格**：[`docs/features/2026-11-15-layout-inspect-color-sampling.md`](../features/2026-11-15-layout-inspect-color-sampling.md)（已經使用者確認）
- **Effort**：Medium ｜ **總任務數：6**（STAGE 2 起手執行 `wf-state.sh set <檔> total_tasks=6`）

**Goal**：Layout inspect 每次結算出一個點（點擊，或拖曳放開／系統取消），就讀取該點在畫面上實際顯示的像素色，在資訊卡顯示色塊與 `color: #RRGGBB`，並寫進複製／分享文字。結果不含 inspector 自己畫的任何東西；讀不到真實顯示色時靜默不顯示。

**Architecture**：取色只掛在兩個結算入口（`_onTapUp`、`_onPanEnd`）。`layout_probe.dart` 新增 `sampleColorAt(anchor, globalPosition)`：讓所有 `LayoutProbeShield` 子樹在下一幀不繪製，於該幀的 post-frame callback 對 root `TransformLayer`（`RenderView.layer`）擷取結算點所在的 1×1 實體像素，再以 `toByteData` 讀回。`_LayoutInspectLayerState` 只多兩個狀態：`Color? _color` 與世代計數 `int _sampleId`。`LayoutLevel`、`probeLayoutAt`、`formatLayoutChain` 一行都不改。

**Tech Stack**：SDK 內建 `OffsetLayer.toImageSync`、`ui.Image.toByteData`、`SchedulerBinding.addPostFrameCallback`、`PipelineOwner.rootNode`、`ContainerLayer.applyTransform`、`PlatformViewLayer`／`TextureLayer`。沒有新依賴。

**實際使用的 SDK：Flutter 3.47.1**（PATH 上的 `flutter`，與 touch-loupe 計畫的實查相同；`.fvm/version` 未生效）。用到的 API 都早於 `pubspec.yaml` 的 Dart `^3.10.1` 下限。

---

## 0. 擷取方式 (A)／(B) 取捨（規格 Q1）

主對話已定案採 **(A)**。使用者可在 0b 暫停點改選 (B)，以下是取捨與改選的影響。

| | (A) root layer＋shield 停繪一幀（採用） | (B) 命中路徑最外層 route `RepaintBoundary` |
|:--|:--|:--|
| 保真度 | 取到的就是合成上屏的那一幀：所有 route、modal barrier、host 自己的 overlay entry、祖先 `Opacity`／`ColorFiltered` 全部算進去 | 漏掉 boundary 以外的東西。在 dialog 遮罩上會**靜默取到錯色** |
| 排除 inspector | 結構上成立：凡是包在 `LayoutProbeShield` 裡的子樹（選取層、資訊卡、放大鏡、kit FAB）在擷取幀都不繪製 | 天然不含 overlay entry |
| 代價 | 每次結算 kit UI 消失一幀（可見閃爍），多一幀 | 無閃爍。但 `RenderRepaintBoundary.toImage` 沒有 `bounds` 參數，若不讀 protected `layer` 就得擷取整頁（1080×2400 約 10 MB） |
| 受保護成員 | 在 `_RenderLayoutProbeShield` 的 instance member 內讀 `RenderView.layer`，analyzer 無診斷（§8-6） | 同樣需要讀 boundary 的 `layer` 才能縮到 1×1 |

**若改選 (B)，會變的任務：**
- **Task 1**：刪掉 S2（閃爍評估），改成記錄「dialog 遮罩上的色碼與實際不符」作為已知限制。
- **Task 3**：重寫。移除 `_hidden`、`paint` 覆寫、`_shields` 註冊與 `_setHidden`；`sampleColorAt` 改為以 shielded hit test（需把 `probeLayoutAt` 的 `_probing` 段抽成共用 helper）找出命中路徑上最外層的 `RenderRepaintBoundary`，以 `globalToLocal` 換算後對它的 layer 呼叫 `toImageSync(bounds)`，不必等幀。測試刪掉 `hides every shield for exactly the capture frame`，新增一支記錄 modal barrier 不計入的限制測試。
- **Task 6**：README 把「閃一幀」改成「dialog 遮罩與頁面以上的效果不計入」。
- **Task 2、4、5 不變**：`sampleColorAt` 的簽章與「失敗回傳 `null`」的契約相同，overlay 接線與整合測試照用。

**(A) 內部已否決的變體：**
- **把 inspector 從 widget tree 移除再擷取**：drag-aim 測試在單次 `pump()` 後就查藍框 `DecoratedBox` 與卡片全部文字（`layout_inspect_drag_aim_test.dart:93-109`、`:124-129`），移除會讓 AC8 失效（規格 Q1 已點出）。
- **零閃爍：在 post-frame 內手動 `flushPaint()` 擷取後再還原**：等於在 `drawFrame` 之外跑 paint phase，碰到 compositing bits 未更新的節點會觸發 debug assert，且依賴 pipeline 內部時序。為了省一幀而綁死框架內部行為，不值得。

---

## Global Constraints

- 純 Dart。`pubspec.yaml` 的 `dependencies` 不變；`lib/flutter_inspector_kit.dart` 匯出清單不變（`layout_inspect/` 與 `layout_formatters.dart` 都不在匯出清單 `:1-15`）。
- 不碰 `InspectorRegistry`、`RingBuffer`、`revision`、`mergedTimeline`，不寫 log，不呼叫 `debugPrint`（AC10）。
- `LayoutLevel`、`probeLayoutAt`（`layout_probe.dart:4-47`、`:70-145`）與 `formatLayoutChain`（`layout_formatters.dart:26-47`）零 diff。
- 以下既有測試**一行都不改**：`test/ui/layout_inspect/` 下的 `layout_inspect_overlay_test.dart`、`layout_inspect_drag_aim_test.dart`、`gap_ruler_overlay_test.dart`、`gap_ruler_painter_test.dart`、`gap_ruler_geometry_test.dart`、`layout_probe_test.dart`。`test/utils/layout_formatters_test.dart` **只在檔尾新增一個 test**，既有 test case 不動（diff 只能有 `+` 行）。
- 空狀態提示 `Tap a widget to inspect`（`layout_inspect_overlay.dart:440`）原文不變。
- debug／profile／release 皆可用：不用 `kDebugMode`、`assert` 才生效的 API，也不用 `debugLayer`（release 恆為 `null`）。
- 取色失敗一律靜默：不顯示色碼列、不跳 SnackBar／dialog、不產生未捕獲例外（AC7）。
- 程式風格依 `.claude/rules/flutter-styles.md`：lib 內禁用 `!`、加尾逗號、不寫 `_buildX()`、禁 `.then()`。測試沿用既有 `overlayKey.currentState!` 寫法（`layout_inspect_drag_aim_test.dart:322`，pump 後可證非 null）。
- `dart format` **只格式化本次碰到的檔案**（指令見各任務），不要跑 `make format`。
- `flutter analyze lib/ test/` 只能有既有的 7 個 info。全套測試基準：**981**（0b 實測，CLAUDE.md 的 950 已過時），本計畫新增 24 個，完成後應為 **1005**。
- 指令一律加 `rtk`（`flutter`／`dart` 不在 hook 自動改寫名單內）。

---

## 1. 開放問題定案（規格 §6 Q2–Q9）

| # | 定案 | 理由與證據 |
|:--|:--|:--|
| Q2 座標與取整 | 以 root `TransformLayer.transform` 把 global 邏輯座標換成實體座標，取 `floor` 後的 **1×1 實體像素**（`toImageSync(Rect.fromLTWH(floor(x), floor(y), 1, 1))`，`pixelRatio` 用預設 1）。不做平均，抗鋸齒混色照實回報。 | root layer 的 transform 已含 DPR（規格引 SDK `view.dart:269-270`），所以 `bounds` 是實體像素單位。用 layer 自己的 transform 而不是自己乘 DPR，test binding 與實機都一致。像素區間取半開 `[i, i+1)`，和 `Rect.contains` 同語意。DPR 2.625 下 x = 39.9 → 104.74：`floor` 取左側像素，`round` 會取到右側；改成 `round` 時 `reads the physical pixel…` 測試變紅（§8-4）。 |
| Q3 Web／release | **所有平台走同一條路徑，不加 `kIsWeb` 開關。** 是否需要退路由 Task 1 S5 在真實瀏覽器確認。 | 0b 以 `flutter test --platform chrome`（CanvasKit）跑本計畫的 3 個測試檔：28/28 通過（§8-5）。`--wasm`（skwasm）下取色本身可用（同一個 test 內連取兩次，讀回 `[51,102,153,255]` 與 `[170,0,170,255]`），但同一檔案從第二個 `testWidgets` 起讀不到，屬測試環境問題，不列入基準。release：`RenderView.layer`、`toImageSync`、`toByteData` 都不是 debug-only。 |
| Q4 競態 | `_probeAt` 每次執行（點擊、拖曳成立、拖曳移動、放開）都 `_sampleId++` 並在同一個 `setState` 內清掉 `_color`；結算時記下當下的 id，非同步完成後只在 `mounted && id == _sampleId` 時寫入。 | 「新的點」的唯一入口就是 `_probeAt`（`layout_inspect_overlay.dart:114-133`），把失效放在這裡就沒有特殊情況：拖曳成立會自然清色並作廢進行中的取色。拿掉 id 檢查時 `a drag started before the sample finishes drops it` 變紅；拿掉 `mounted` 時 `closing before the sample finishes…` 變紅（§8-4）。`listEquals(chain)` 不夠用的理由見規格 R3。 |
| Q5 色碼放哪 | `_LayoutInspectLayerState` 的獨立狀態 `Color? _color`，經參數傳給 `_LayoutInfoCard`。 | `LayoutLevel.==` 被標尺用來判斷同一元件（`layout_probe.dart:34-46`；`layout_inspect_overlay.dart:161`、`:215`）。色碼是點的屬性，放進去會讓自我量測防護失效。 |
| Q6 平台視圖／透明 | 兩道判定，任一命中就回傳 `null`：① **掃描擷取幀的 layer tree**，有任何 `PlatformViewLayer` 或 `TextureLayer` 的矩形（換算到實體座標後）包含該點；② 讀回像素 **alpha ≠ 255**（含 0 < alpha < 255）。輸出一律不含 alpha。`TextureBox` 一律視為失敗，不另做可擷取性確認。 | 規格傾向「命中路徑含平台視圖 render box」，**改用 layer tree**，因為 hit test 只看最上層命中者：半透明 Flutter 元件疊在 WebView／地圖上時，路徑裡沒有平台視圖，擷取卻會把它合成在 Scaffold 底色上，得到不透明的錯色。0b 實測：拿掉 layer 檢查後 `returns null for a widget drawn over a texture` 變紅，證明這個情境確實會回報錯色（§8-4）。layer tree 就是被擷取的那一幀，不受 hit test 行為（例如 `PlatformViewHitTestBehavior.transparent`）影響；Android 的 `AndroidView` 畫的是 `TextureLayer`，Hybrid Composition／iOS／Web 畫的是 `PlatformViewLayer`，兩型就涵蓋。alpha < 255 代表露出的是 Flutter 場景以外的東西（平台視圖洞或視窗底色），顏色無從得知。`TextureBox` 走 fail-safe：`example/` 沒有 texture demo，無從實測，寧可不顯示。「不誤判」方向由 `does not block points outside a texture` 鎖住：texture 經 `RepaintBoundary` 的 offset layer 與 `Padding` 的層內位移上屏，取它外面的兩個點必須拿到背景色，`.contains` 改成 `true`、略過 `applyTransform` 或 DPR 重複乘都會變紅（§8-4）。 |
| Q7 測試策略 | 用真實取色，**不加注入參數**。兩個 helper 都是 `pump()`（擷取幀）後反覆 `runAsync(10ms)` + `pump()`：單元的 `_sample` 等到 `done`，整合的 `_settleSample` 等到出現色碼列，上限都是 50 輪（0.5 秒）。失敗以自然情境觸發：`Texture`、半透明像素、擷取幀前 shield 被移除。競態以「取色未完成時開始新的點」觸發。 | 0b 實測 VM 上通常一輪就有結果，但三個 `flutter test` 同時跑時，單輪 10ms 的版本有 2 次 `reads the app pixel under kit UI…` 失敗（isolate 內第一次擷取較慢），所以改成輪詢（§8-7）。「沒有色碼列」的斷言因此都是在讀回有充分時間完成之後才檢查，比固定一輪更嚴格。既有測試只 `pump()` 不 `runAsync`，取色永遠不會完成，卡片文字不變，AC8 自然成立；測試結束時留著未完成的讀回也不會報錯（全套 981 個既有測試照過，§8-3）。`on Object catch` 那一行沒有自然觸發方式，為它加一個只給測試用的注入點不划算（YAGNI）。 |
| Q8 匯出位置 | 全文最後，以 `\n\ncolor: #RRGGBB` 追加，只出現一次；標尺模式也只有一行（代表當前點）。 | 色碼不屬於 chain 中任何一層，放最後就不必拆 `formatLayoutChain` 的輸出。無色碼時 `colorLine` 是空字串，輸出與現行逐字相同。 |
| Q9 拖曳中 | **(A)**：拖曳成立就不顯示色碼列，放開後顯示新點的色碼。 | 走 Q4 的 `_probeAt` 清色就自然成立，零額外程式碼。 |

**卡片色碼列位置（AC3）**：放在 `offset` 列之後、`names may be obfuscated` 之前。既有各列的相對順序不變。

---

## 2. 資料結構與流程

```
_LayoutInspectLayerState
  _chain / _index / _lockedA / _aim ...   （既有，不變）
  Color? _color        結算點的顯示色；null = 尚未取得或取色失敗
  int _sampleId        每個新點 +1；過期的非同步結果靠它丟棄

layout_probe.dart（檔案私有）
  bool _hidden                          true 時所有 shield 的 paint 直接 return
  Set<_RenderLayoutProbeShield> _shields  attach／detach 時登記，用來 markNeedsPaint
```

結算時序（點擊與放開相同）：

```
_onTapUp / _onPanEnd
  └─ _settleAt(p)
       ├─ _probeAt(p)            同步：_sampleId++、_chain = hit、_color = null
       └─ _sampleAt(p)           若 _chain 為空則不取色
            └─ sampleColorAt(anchor, p)
                 ├─ 從 anchor 往上找到所屬 _RenderLayoutProbeShield（找不到 → null）
                 ├─ 先註冊 post-frame callback，再 _setHidden(true)：所有 shield markNeedsPaint
                 ├─ 下一幀：shield 不繪製 → 合成上屏（使用者看到 kit UI 消失一幀）
                 ├─ post-frame callback（layer tree 仍是無 kit UI 的那一幀）：
                 │    shield._capturePixel(p)
                 │      owner.rootNode → RenderView.layer（root TransformLayer）
                 │      p' = transform × p；掃 layer tree 找 PlatformViewLayer／TextureLayer
                 │      root.toImageSync(1×1 @ floor(p'))
                 │    finally _setHidden(false) → 再下一幀 kit UI 回來
                 └─ await image.toByteData()：alpha ≠ 255 → null；finally image.dispose()
            └─ mounted && id == _sampleId && color != null → setState(_color = color)
```

為什麼不會錯：
- **同一幀內連續兩次結算**：兩個 post-frame callback 在同一幀依序執行，第一個 `_setHidden(false)` 只是 `markNeedsPaint`，layer tree 要到下一幀才重繪，所以第二個擷取看到的仍是無 kit UI 的那一幀。
- **擷取幀前 inspector 被關閉**：shield detach 時 `owner` 變 `null`，`_capturePixel` 回傳 `null`；`finally` 照樣把其餘 shield（kit FAB）恢復繪製。
- **`_hidden` 卡住**：只會發生在之後永遠沒有下一幀的情況（App 被終止）。測試結束時 test binding 會再 pump 一幀拆樹，post-frame 照樣執行。先註冊負責恢復的 callback、再設 `_hidden = true`，所以即使 `_setHidden(true)` 中途拋例外，恢復也已排定。

---

## 3. 實作層級的方案取捨

1. **平台視圖偵測：layer tree 掃描（採用）vs 命中路徑 render 型別（規格傾向，不採用）**
   - 命中路徑看不到被半透明 Flutter UI 蓋住的平台視圖，會回報錯色，違反 AC7 的硬性要求（§1 Q6 有實測）。
   - layer tree 掃描約 15 行遞迴，只認兩種 layer 型別；它看的正是被擷取的那一幀，和擷取結果天然一致。
   - 已知限制：忽略 clip layer，平台視圖在該點被裁掉時仍會擋下取色。方向是 fail-safe（少顯示，不錯顯示），程式碼留 `shortcut:` 註解。
2. **擷取 API：`toImageSync`（採用）vs `toImage`（退路）**
   - `toImageSync` 在 post-frame callback 內同步拿到 image，非同步只剩一次 `toByteData`，測試的讀回只要一輪 `runAsync`。
   - 若 Task 1 實機上 `toImageSync` 失敗，改用 `root.toImage(bounds)`（完整程式碼在 Task 1 S1 退路，已在原型跑過）：`OffsetLayer.toImage` 在第一個 `await` 之前就同步組好 scene，所以仍然擷取到無 kit UI 的那一幀。
3. **測試失敗注入：自然情境（採用）vs `show()` 新增注入參數（規格 Q7 傾向，不採用）**
   - `Texture`、半透明像素、擷取前移除 shield，已涵蓋 AC7 的所有可觀察分支；競態用「讀回未完成時開始新的點」就能穩定重現。多一個內部參數只為了測一行 `catch`，不划算。
4. **`_probeAt` 的空結果分支：合併（採用）**
   - `probeLayoutAt` 所有空結果都回傳 `const []`（`layout_probe.dart:85`、`:103`、`:113`），`hit.isEmpty` 分支（`layout_inspect_overlay.dart:118-126`）與一般分支寫入的值完全相同，是多餘的特殊情況。合併後 `_color = null` 只要加一處。
5. **匯出文字：在既有兩個 `return` 後面接 `colorLine`（採用）vs 改寫成 `StringBuffer`**
   - 前者 diff 最小（+2 行、改 2 行），也不碰 `_lockedA!` 的既有寫法。

---

## 4. 檔案異動清單

| 檔案 | 動作 | 預估行數 | 說明 |
|:---|:---:|:---:|:---|
| `lib/src/utils/layout_formatters.dart` | 修改 | +6 | `formatColor(Color)` |
| `test/utils/layout_formatters_test.dart` | 修改（只新增） | +6 | 1 個 test |
| `lib/src/ui/layout_inspect/layout_probe.dart` | 修改 | 約 +120 | shield 註冊／停繪／擷取、`_coversExternalSurface`、`_setHidden`、`sampleColorAt` |
| `test/ui/layout_inspect/color_sampling_test.dart` | 新增 | 約 285 | `sampleColorAt` 單元測試 10 個 |
| `lib/src/ui/layout_inspect/layout_inspect_overlay.dart` | 修改 | 約 +60／−10 | 結算取色、競態、卡片色碼列 `_ColorRow`、匯出行 |
| `test/ui/layout_inspect/layout_inspect_color_test.dart` | 新增 | 約 335 | overlay 整合測試 13 個 |
| `README.md` | 修改 | +1 段 | Inspect layout 段落（`:133-141`） |
| `README.zh-TW.md` | 修改 | +1 段 | 同一段落的中文版（`:133-141`）。規格 AC13 未列；兩份 README 該段逐段對應（`02cda02` 兩邊一起改），若使用者不同意就略過 |
| `docs/architecture/overview.md` | 修改 | 改 1 行 | `:71` `LayoutInspectOverlay` 描述 |
| `docs/architecture/file-reference.md` | 修改 | 改 3 列 | `:72`（formatters）、`:98`（overlay）、`:99`（probe） |

---

## 5. 任務總表

| # | 標題 | 性質（分級用） | 寫入檔案 | 相依／並行 | 派發 |
|:--:|:--|:--|:--|:--|:--|
| 1 | Spike：實機與瀏覽器驗證 (A) | 實測 gate | repo 零寫入（暫存 worktree，用完移除） | 無；Task 2–6 開工前 | 主進程＋使用者 |
| 2 | `formatColor` 與單元測試 | 機械性 | `layout_formatters.dart`、`layout_formatters_test.dart` | Task 1 通過後 | **微任務**（每檔 ≤ 20 行、無公共 API）：主進程原地 |
| 3 | `sampleColorAt`：停繪、擷取、外部表面與 alpha 判定 | 設計判斷 | `layout_probe.dart`、`color_sampling_test.dart`（新） | Task 2 通過後（不並行：Task 2 的 Red 狀態會讓 Task 3 的 `flutter analyze lib/ test/` 出現錯誤） | subagent（強） |
| 4 | Overlay 接線：結算取色、競態、卡片列、匯出行 | 整合 | `layout_inspect_overlay.dart`、`layout_inspect_color_test.dart`（新） | Task 2 + Task 3 | subagent（標準） |
| 5 | 全套驗證與 AC12 實機手測 | 驗證 | 無 | Task 4 | 主進程＋使用者 |
| 6 | 文件同步 | 機械性 | `README.md`、`README.zh-TW.md`、`overview.md`、`file-reference.md` | 內容只依 Task 1 結論，寫入路徑與 2–5 不重疊，Task 1 後即可撰寫；排在最後執行 | **微任務**（每檔 ≤ 20 行、純文件）：主進程原地 |

---

## 6. 任務細節

### Task 1 `[實測 gate／主進程＋使用者]`：Spike — 實機與瀏覽器驗證 (A)

**目標**：0b 已在 `flutter_tester`（VM）與 Chrome CanvasKit 的測試環境證實 (A) 正確（§8）。剩下只有實機與真實瀏覽器才能回答的問題：原生 Impeller 管線、閃爍是否可接受、平台視圖、release、真實瀏覽器。

**寫入路徑**：repo 零寫入。在暫存 worktree 套用 Task 2–4 的 lib 程式碼（測試檔不需要），驗完即移除。不建分支、不 commit。

- [ ] **Step 1：建立暫存 worktree 並套用程式碼**

```bash
git worktree add --detach .worktrees/spike-color-sampling HEAD
```

在 `.worktrees/spike-color-sampling/` 內依序套用：Task 2 Step 3、Task 3 Step 3–6、Task 4 Step 3 的 lib 改動。`example/pubspec.yaml` 以 `path: ../` 依賴套件，所以 example 會直接吃到 worktree 的 lib。

- [ ] **Step 2：逐項驗證**（以 `cd .worktrees/spike-color-sampling/example && flutter run -d <device>` 執行；實機優先，一時沒有手機可先用 iOS Simulator／Android emulator 驗管線，但 S1–S4 至少要在一台實機上過）

`example/lib/main.dart:384-412` 有兩個現成色塊：`Box 1`（`Colors.blue` = `#2196F3`，正好等於 inspector 藍）與 `Box 2`（`Colors.red` = `#F44336`）。點的時候避開白色文字。

| # | 驗什麼 | 操作 | 成功判準 | 失敗時的退路 |
|:--|:--|:--|:--|:--|
| S1 | 原生擷取正確（Q1、AC5） | 進 Inspect layout，點 Box 1 實心處；點 Box 2 實心處；點 Box 2 左緣內 1 dp 處 | 依序顯示 `color: #2196F3`、`color: #F44336`、`color: #F44336`（不是 `#2196F3`） | 無色碼列或色值錯誤：套用下方「S1 退路程式碼」（改用 `toImage`），重驗一次。仍失敗，或色值有系統性偏移（例如 iOS 廣色域），就停止並回 0b |
| S2 | 閃爍可否接受（Q1） | 連點數次，觀察 kit UI（藍框、卡片、FAB）消失一幀 | 使用者判定可接受 | 使用者改選 (B)：依 §0 改寫 Task 3 與 Task 6 |
| S3 | 平台視圖（Q6、AC7） | 開 WebView demo（`example/lib/demos/webview_demo.dart`）與 InAppWebView demo：(a) 點網頁內容；(b) 在 WebView 還在畫面上時點 AppBar 的空白處（`webview_demo.dart:52` 的 `AppBar(title: Text('WebView Demo'))`，捲動網頁之前點，避免 M3 scrolled-under 底色變化） | (a) 卡片照常顯示 chain，**沒有**色碼列，無錯誤訊息；(b) **有**色碼列，值等於該 AppBar 的背景色（`ColorScheme.fromSeed(seedColor: Colors.deepPurple)` 的 `surface`，可在 DevTools Widget inspector 查 `AppBar` 的實際背景色比對），App 不 crash，`flutter run` console 與 kit Console tab 都沒有錯誤 log | 出現色碼：在 Flutter DevTools 或 `debugDumpLayerTree()` 查該平台視圖對應的 layer 型別，加進 `_coversExternalSurface` 的 `switch`。若找不到可辨識的 layer，再加一道命中路徑判定（`PlatformViewRenderBox`／`RenderAndroidView`／`RenderDarwinPlatformView`）作為補充。(b) 沒有色碼列：layer 掃描誤判（例如座標換算錯），以 `debugDumpLayerTree()` 比對 WebView layer 的 rect 與點擊的實體座標後修正；有 crash 或錯誤 log 則停止回 0b |
| S4 | release（AC9） | `flutter run -d <device> --release`，重做 S1 | 結果同 S1 | 停止並回 0b |
| S5 | Web（Q3） | `flutter run -d chrome` 與 `flutter run -d chrome --wasm`，各重做 S1 | 兩者結果同 S1 | 在 `sampleColorAt` 第一行加 `if (kIsWeb) return null;`，附 `// shortcut: color sampling is off on web; enable once <原因> is fixed.`（需 `import 'package:flutter/foundation.dart';`），Task 6 README 加一句「Web 不顯示色碼」。只有 `--wasm` 失敗也一樣整個 Web 關掉，不另做 renderer 偵測 |
| S6 | 拖曳與標尺（AC6） | 拖曳讓準星停在 Box 2 再放開；鎖定 Box 1 為 A 後點 Box 2 左緣內側 | 都顯示 `color: #F44336` | 視為 S1 失敗處理 |

**S1 退路程式碼**（只在 S1 失敗時套用；已在原型上以 Task 3、4 的 23 個新測試跑過，全綠，測試 helper 不必改）。改兩處，其餘與 Task 3 相同：

1. `_capturePixel` 改回傳 `Future<ui.Image>?`，最後的 `toImageSync` 換成 `toImage`：

```dart
  Future<ui.Image>? _capturePixel(Offset globalPosition) {
    final view = owner?.rootNode;
    if (view is! RenderView) return null;
    final root = view.layer;
    if (root is! TransformLayer) return null;
    final transform = root.transform;
    if (transform == null) return null;
    final p = MatrixUtils.transformPoint(transform, globalPosition);
    if (_coversExternalSurface(root, Matrix4.identity(), p)) return null;
    // toImage builds the scene before its first await, so it still captures
    // the frame painted without kit UI.
    return root.toImage(
      Rect.fromLTWH(p.dx.floorToDouble(), p.dy.floorToDouble(), 1, 1),
    );
  }
```

2. `sampleColorAt` 從 `final captured = …` 起改成下面這樣：`captured.complete(...)` 收的是 future，它的 rejection 只會在 `await captured.future` 浮現，所以這個 `await` 必須在 `try` 裡；`image` 改成可為 null 的區域變數，`finally` 用 `image?.dispose()`。

```dart
  final captured = Completer<ui.Image?>();
  SchedulerBinding.instance.addPostFrameCallback((_) {
    try {
      // A rejected capture surfaces at `await captured.future` below.
      captured.complete(shield._capturePixel(globalPosition));
    } on Object catch (_) {
      // A failed capture only hides the color row (spec AC7).
      captured.complete(null);
    } finally {
      _setHidden(false);
    }
  });
  // Hide only once the callback that unhides is registered.
  _setHidden(true);
  ui.Image? image;
  try {
    image = await captured.future;
    if (image == null) return null;
    final bytes = await image.toByteData();
    // Not fully opaque: what shows through is outside the Flutter scene.
    if (bytes == null || bytes.getUint8(3) != 255) return null;
    return Color.fromARGB(
      255,
      bytes.getUint8(0),
      bytes.getUint8(1),
      bytes.getUint8(2),
    );
  } on Object catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}
```

0b 另以「`_capturePixel` 回傳 `Future.error(StateError('injected'))`」驗證過這個退路：`reads the app pixel…` 得到 `null`，log 中沒有任何 `injected` 未捕獲錯誤（AC7、AC10）。

- [ ] **Step 3：保存 spike 的 lib diff，再清理**

先把 spike 實際驗過的 `lib/` 改動存到 session scratchpad（以下 `$SCRATCHPAD` 代表 system prompt 給的 scratchpad 絕對路徑），Task 5 要拿它比對；之後才移除 worktree。

```bash
# --output 由 git 直接寫檔、不經 stdout，避開 RTK hook 壓縮（.claude/rules/rtk-rules.md：diff 逐字比對須取原文）
git -C .worktrees/spike-color-sampling diff --output="$SCRATCHPAD/spike-lib.diff" -- lib/
test -s "$SCRATCHPAD/spike-lib.diff"   # 不可為空
git worktree remove --force .worktrees/spike-color-sampling
git status --short   # 只能看到本計畫與規格兩個未追蹤檔
```

- [ ] **Step 4：把結論回寫到本計畫 §8-9**（每項 S1–S6 的結果、裝置型號、是否套用了退路）。有套用退路就同步修改 Task 3 的程式碼區塊，讓後續任務照抄的就是驗證過的版本。

**驗收**：S1–S6 全部通過，或已依退路調整並重驗通過；worktree 已移除。

---

### Task 2 `[機械性／微任務：主進程原地]`：`formatColor` 與單元測試

**寫入路徑**：`test/utils/layout_formatters_test.dart`（+6）、`lib/src/utils/layout_formatters.dart`（+6）

- [ ] **Step 1：在測試檔最後一個 test 之後、外層 `group` 的 `});` 之前加入**

```dart

    test('formatColor writes #RRGGBB in upper case without alpha', () {
      expect(formatColor(const Color(0xFFAA00AA)), '#AA00AA');
      expect(formatColor(const Color(0xFF00AA55)), '#00AA55');
      expect(formatColor(const Color(0x80336699)), '#336699');
    });
```

三個斷言分別驗證大寫 A–F、前導零補齊、丟棄 alpha。`Color` 已由既有的 `package:flutter/rendering.dart` 匯入。

- [ ] **Step 2：確認 Red**

```bash
rtk flutter test test/utils/layout_formatters_test.dart
```

預期：編譯失敗，`formatColor` 未定義。

- [ ] **Step 3：在 `formatOffset`（`layout_formatters.dart:20-22`）之後插入**

```dart

/// Formats [color] as `#RRGGBB` in upper case, dropping alpha.
String formatColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
```

- [ ] **Step 4：確認 Green 與既有測試不變**

```bash
rtk flutter test test/utils/layout_formatters_test.dart
git diff --numstat test/utils/layout_formatters_test.dart   # 第二欄（刪除行數）必須為 0；numstat 一行即完整、不受 RTK 壓縮影響
```

**驗收**：該檔全部通過；測試檔 diff 只有新增行。

---

### Task 3 `[設計判斷]`：`sampleColorAt` — 停繪、擷取、外部表面與 alpha 判定

**寫入路徑**：`test/ui/layout_inspect/color_sampling_test.dart`（新增）、`lib/src/ui/layout_inspect/layout_probe.dart`（修改）

- [ ] **Step 1：新增測試檔 `test/ui/layout_inspect/color_sampling_test.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_probe.dart';
import 'package:flutter_inspector_kit/src/ui/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static const Key anchor = ValueKey('anchor');
  static const Rect block = Rect.fromLTWH(100, 100, 100, 100);
  static const Color background = Color(0xFF00AA55);
  static const Color blockColor = Color(0xFFAA00AA);
}

/// App content at the bottom, a [LayoutProbeShield] holding the sampling
/// anchor on top, optionally painting [cover] over the block.
Future<void> _pumpScene(
  WidgetTester tester, {
  Widget app = const ColoredBox(color: _Data.background),
  Color? cover,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(child: app),
          Positioned.fill(
            child: LayoutProbeShield(
              child: Stack(
                children: [
                  const Positioned.fill(child: SizedBox(key: _Data.anchor)),
                  if (cover != null)
                    Positioned.fromRect(
                      rect: _Data.block,
                      child: ColoredBox(color: cover),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _blockOn(Color background, Color block) => Stack(
  children: [
    Positioned.fill(child: ColoredBox(color: background)),
    Positioned.fromRect(
      rect: _Data.block,
      child: ColoredBox(color: block),
    ),
  ],
);

/// Starts a sample, runs the capture frame, then lets the engine finish the
/// pixel read-back. `testWidgets` runs on fake time, so the read-back only
/// completes inside `runAsync`; the `pump` after it delivers the result. The
/// first capture in an isolate, or a loaded machine, can need several rounds.
Future<Color?> _sample(WidgetTester tester, Offset point) async {
  Color? color;
  var done = false;
  Future<void> run() async {
    color = await sampleColorAt(
      tester.renderObject(find.byKey(_Data.anchor)),
      point,
    );
    done = true;
  }

  unawaited(run());
  await tester.pump();
  for (var i = 0; i < 50 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done, isTrue, reason: 'sample did not complete');
  return color;
}

void main() {
  group('sampleColorAt', () {
    testWidgets('reads the app pixel under kit UI painted inside a shield', (
      tester,
    ) async {
      await _pumpScene(
        tester,
        app: _blockOn(_Data.background, _Data.blockColor),
        cover: ThemeColor.color2196F3,
      );

      expect(await _sample(tester, _Data.block.center), _Data.blockColor);
    });

    testWidgets('reports an app color equal to the kit blue as is', (
      tester,
    ) async {
      await _pumpScene(
        tester,
        app: _blockOn(_Data.background, ThemeColor.color2196F3),
      );

      expect(await _sample(tester, _Data.block.center), ThemeColor.color2196F3);
    });

    testWidgets('reads the physical pixel that contains the point at a '
        'fractional devicePixelRatio', (tester) async {
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetDevicePixelRatio);
      // At 2.625, logical x = 40 is physical x = 105 exactly; 39.9 maps to
      // 104.74, inside the left pixel. Rounding would pick the right one.
      await _pumpScene(
        tester,
        app: const Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 40, child: ColoredBox(color: _Data.blockColor)),
            Expanded(child: ColoredBox(color: _Data.background)),
          ],
        ),
      );

      expect(await _sample(tester, const Offset(39.9, 20)), _Data.blockColor);
    });

    testWidgets('returns null over a texture', (tester) async {
      await _pumpScene(
        tester,
        app: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: _Data.background)),
            Positioned.fromRect(
              rect: _Data.block,
              child: const Texture(textureId: 1),
            ),
          ],
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('returns null for a widget drawn over a texture', (
      tester,
    ) async {
      // The hit lands on the translucent box, not the texture below it.
      await _pumpScene(
        tester,
        app: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: _Data.background)),
            Positioned.fromRect(
              rect: _Data.block,
              child: const Texture(textureId: 1),
            ),
            Positioned.fromRect(
              rect: _Data.block.deflate(30),
              child: const ColoredBox(color: Color(0x80AA00AA)),
            ),
          ],
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('does not block points outside a texture', (tester) async {
      // Layers: root TransformLayer (DPR 3) > RepaintBoundary OffsetLayer at
      // (50, 50) > the texture's own OffsetLayer at (50, 50) > TextureLayer
      // (0, 0, 100, 100). The walk must add both offsets and the DPR.
      await _pumpScene(
        tester,
        app: const Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: _Data.background)),
            Positioned(
              left: 50,
              top: 50,
              width: 150,
              height: 150,
              child: RepaintBoundary(
                child: Padding(
                  padding: EdgeInsets.only(left: 50, top: 50),
                  child: Texture(textureId: 1),
                ),
              ),
            ),
          ],
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
      // The texture spans physical 300..600. Dropping the offsets moves it to
      // 0..300 (150..450 if only the outer one is lost), which catches
      // 75 * 3 = 225; applying the DPR twice moves it to 900..1800, which
      // catches 350 * 3 = 1050. Nothing paints over the background there.
      expect(await _sample(tester, const Offset(75, 75)), _Data.background);
      expect(await _sample(tester, const Offset(350, 350)), _Data.background);
    });

    testWidgets('returns null when the pixel is not fully opaque', (
      tester,
    ) async {
      await _pumpScene(tester, app: const ColoredBox(color: Color(0x80AA00AA)));

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('hides every shield for exactly the capture frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: _Data.background)),
              Positioned(
                left: 0,
                top: 0,
                width: 50,
                height: 50,
                child: LayoutProbeShield(
                  child: ColoredBox(color: ThemeColor.color2196F3),
                ),
              ),
              Positioned.fill(
                child: LayoutProbeShield(child: SizedBox(key: _Data.anchor)),
              ),
            ],
          ),
        ),
      );
      final other = tester.renderObject(find.byType(LayoutProbeShield).first);
      expect(other, isNot(paintsNothing));

      unawaited(
        sampleColorAt(
          tester.renderObject(find.byKey(_Data.anchor)),
          const Offset(25, 25),
        ),
      );
      expect(other, paintsNothing);

      await tester.pump();
      expect(other, isNot(paintsNothing));
    });

    testWidgets('returns null when the anchor is outside any shield', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ColoredBox(
          color: _Data.background,
          child: SizedBox.expand(key: _Data.anchor),
        ),
      );

      expect(await _sample(tester, _Data.block.center), isNull);
    });

    testWidgets('returns null without throwing when the shield is removed '
        'before the capture frame', (tester) async {
      await _pumpScene(tester);
      Color? color = _Data.blockColor;
      var done = false;
      Future<void> run() async {
        color = await sampleColorAt(
          tester.renderObject(find.byKey(_Data.anchor)),
          _Data.block.center,
        );
        done = true;
      }

      unawaited(run());
      await tester.pumpWidget(const SizedBox.shrink());

      expect(done, isTrue);
      expect(color, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
```

測試與規格的對應：

| 測試 | 規格 |
|:--|:--|
| `reads the app pixel under kit UI painted inside a shield` | AC6（結構性排除） |
| `reports an app color equal to the kit blue as is` | AC5（不得以色值過濾） |
| `reads the physical pixel … fractional devicePixelRatio` | AC5（DPR ≠ 1）、Q2 |
| `returns null over a texture`、`… widget drawn over a texture` | AC7、Q6 ① |
| `does not block points outside a texture` | Q6 ① 的反向：畫面上有平台視圖時，其餘位置仍能取色；鎖住 layer 掃描的座標累積（offset layer、層內位移、root DPR） |
| `returns null when the pixel is not fully opaque` | AC7、Q6 ② |
| `hides every shield for exactly the capture frame` | AC6（kit FAB 等其他 shield 也停繪）、閃爍只有一幀 |
| `returns null when the anchor is outside any shield` | 呼叫端必須在 shield 內，否則自己的 UI 會入鏡 |
| `returns null without throwing when the shield is removed …` | AC7（無未捕獲例外） |

- [ ] **Step 2：確認 Red**

```bash
rtk flutter test test/ui/layout_inspect/color_sampling_test.dart
```

預期：編譯失敗，`sampleColorAt` 未定義。

- [ ] **Step 3：替換 `layout_probe.dart` 的 import（`:1-2`）**

```dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
```

- [ ] **Step 4：在 `bool _probing = false;`（`:49`）之後加兩行，並更新 `LayoutProbeShield` 的 dartdoc（`:51-52`）**

```dart
bool _probing = false;
bool _hidden = false;
final Set<_RenderLayoutProbeShield> _shields = {};

/// Wraps a subtree so that it is invisible to [probeLayoutAt] hit tests and
/// to [sampleColorAt] captures, while behaving identically to its child
/// otherwise.
```

- [ ] **Step 5：把 `_RenderLayoutProbeShield`（`:62-68`）整個換成**

```dart
class _RenderLayoutProbeShield extends RenderProxyBox {
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shields.add(this);
  }

  @override
  void detach() {
    _shields.remove(this);
    super.detach();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_probing) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_hidden) return;
    super.paint(context, offset);
  }

  // Reads RenderView.layer, which is @protected: legal only inside a
  // RenderObject member.
  ui.Image? _capturePixel(Offset globalPosition) {
    final view = owner?.rootNode;
    if (view is! RenderView) return null;
    final root = view.layer;
    if (root is! TransformLayer) return null;
    final transform = root.transform;
    if (transform == null) return null;
    final p = MatrixUtils.transformPoint(transform, globalPosition);
    if (_coversExternalSurface(root, Matrix4.identity(), p)) return null;
    return root.toImageSync(
      Rect.fromLTWH(p.dx.floorToDouble(), p.dy.floorToDouble(), 1, 1),
    );
  }
}
```

- [ ] **Step 6：在上面的 class 之後、`probeLayoutAt` 的 dartdoc（`/// Hit-tests the [RenderView]…`）之前插入**

```dart

// Platform views and textures are composited outside the Flutter scene, so a
// capture cannot see what they show on screen.
// shortcut: clips and z-order are ignored, so a platform view clipped away
// at the point, or covered there by opaque UI, still hides the color; refine
// with clip intersection and paint order if that shows up in practice.
bool _coversExternalSurface(Layer layer, Matrix4 transform, Offset point) {
  final rect = switch (layer) {
    PlatformViewLayer(:final rect) || TextureLayer(:final rect) => rect,
    _ => null,
  };
  if (rect != null) {
    return MatrixUtils.transformRect(transform, rect).contains(point);
  }
  if (layer is! ContainerLayer) return false;
  for (var child = layer.firstChild; child != null; child = child.nextSibling) {
    final childTransform = transform.clone();
    layer.applyTransform(child, childTransform);
    if (_coversExternalSurface(child, childTransform, point)) return true;
  }
  return false;
}

// shortcut: kit tooltips are drawn through OverlayPortal, outside any shield,
// so one still showing after a long press (~1.5s) can end up in the sample;
// wrap the tooltip overlay in a shield if that shows up in practice.
void _setHidden(bool value) {
  _hidden = value;
  for (final shield in _shields) {
    shield.markNeedsPaint();
  }
}

/// Reads the on-screen color of the physical pixel under [globalPosition].
///
/// [anchor] must sit inside a [LayoutProbeShield]. Every shield subtree is
/// left unpainted for one frame, so the result never contains kit UI.
/// Completes with `null`, never with an error, when the displayed color
/// cannot be known: a platform view or texture covers the point, the pixel is
/// not fully opaque, or the capture fails.
Future<Color?> sampleColorAt(RenderObject anchor, Offset globalPosition) async {
  RenderObject? node = anchor;
  while (node != null && node is! _RenderLayoutProbeShield) {
    node = node.parent;
  }
  if (node is! _RenderLayoutProbeShield) return null;
  final shield = node;

  final captured = Completer<ui.Image?>();
  SchedulerBinding.instance.addPostFrameCallback((_) {
    try {
      captured.complete(shield._capturePixel(globalPosition));
    } on Object catch (_) {
      // A failed capture only hides the color row (spec AC7).
      captured.complete(null);
    } finally {
      _setHidden(false);
    }
  });
  // Hide only once the callback that unhides is registered.
  _setHidden(true);
  final image = await captured.future;
  if (image == null) return null;
  try {
    final bytes = await image.toByteData();
    // Not fully opaque: what shows through is outside the Flutter scene.
    if (bytes == null || bytes.getUint8(3) != 255) return null;
    return Color.fromARGB(
      255,
      bytes.getUint8(0),
      bytes.getUint8(1),
      bytes.getUint8(2),
    );
  } on Object catch (_) {
    return null;
  } finally {
    image.dispose();
  }
}
```

說明：
- `on Object catch` 兩處是刻意的：規格 AC7 要求取色失敗不能變成未捕獲例外（否則會經 `uncaught_error_handler.dart:54-56` 進時間軸，違反 AC10），也不能記 log。前例：`_onShare`（`layout_inspect_overlay.dart:194`）、Dio interceptor §P39。
- 不需要 `shield.attached` 檢查：shield detach 後 `owner` 為 `null`，`_capturePixel` 第一行就回傳 `null`（0b 實測拿掉該檢查也全綠，所以刪掉）。
- `toByteData()` 預設 `rawRgba`（premultiplied）。alpha 已限定為 255，premultiplied 與 straight 的 RGB 相同。

- [ ] **Step 7：確認 Green，且探測與既有 overlay 行為不變**

```bash
rtk flutter test test/ui/layout_inspect/
rtk dart format --output=none --set-exit-if-changed lib/src/ui/layout_inspect/layout_probe.dart test/ui/layout_inspect/color_sampling_test.dart
rtk flutter analyze lib/ test/
```

預期：`color_sampling_test.dart` 10 個全過；`layout_probe_test.dart` 等既有測試全過（AC8）；format 0 changed；analyze 仍為 7 個既有 info（**不得**出現 `invalid_use_of_protected_member`）。

---

### Task 4 `[整合]`：Overlay 接線 — 結算取色、競態、卡片列、匯出行

**寫入路徑**：`test/ui/layout_inspect/layout_inspect_color_test.dart`（新增）、`lib/src/ui/layout_inspect/layout_inspect_overlay.dart`（修改）

**前置**：Task 2（`formatColor`）與 Task 3（`sampleColorAt`）已完成。

- [ ] **Step 1：新增測試檔 `test/ui/layout_inspect/layout_inspect_color_test.dart`**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_inspect_overlay.dart';
import 'package:flutter_inspector_kit/src/ui/widgets/inspector_fab.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static const Rect rectA = Rect.fromLTWH(24, 60, 120, 40);
  static const Rect rectB = Rect.fromLTWH(300, 60, 60, 60);
  static const Color colorA = Color(0xFF336699);
  static const Color colorB = Color(0xFFAA00AA);
  static const String rowA = 'color: #336699';
  static const String rowB = 'color: #AA00AA';
}

Widget _blocks() => Stack(
  children: [
    Positioned.fromRect(
      rect: _Data.rectA,
      child: const ColoredBox(color: _Data.colorA),
    ),
    Positioned.fromRect(
      rect: _Data.rectB,
      child: const ColoredBox(color: _Data.colorB),
    ),
  ],
);

/// Pumps [body] in a Scaffold, optionally under a kit FAB, then opens the
/// inspector above it (the FAB entry goes first, as in a real host).
Future<void> _pumpInspect(
  WidgetTester tester,
  Widget body, {
  bool withFab = false,
}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  final overlay = Overlay.of(
    tester.element(find.byType(Scaffold)),
    rootOverlay: true,
  );
  if (withFab) {
    final fab = OverlayEntry(builder: (_) => InspectorFab(onTap: () {}));
    overlay.insert(fab);
    addTearDown(fab.remove);
  }
  LayoutInspectOverlay.show(overlay);
  await tester.pump();
}

/// Runs the capture frame and lets the engine finish the pixel read-back,
/// which only completes inside `runAsync` under the test's fake time. Stops
/// once a color row shows, else after 0.5s, so "no row" is asserted only
/// after a read-back has had ample time to land.
Future<void> _settleSample(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 50 && _colorRow.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Finder get _colorRow => find.textContaining('color: #');

void main() {
  group('LayoutInspectOverlay color sampling', () {
    String? clipboardText;

    setUp(() {
      clipboardText = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = call.arguments as Map<Object?, Object?>;
              clipboardText = args['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('a tap shows the pixel color, also inside the 2px frame', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());

      await tester.tapAt(_Data.rectB.center);
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
      expect(find.text('size: 60.0 × 60.0'), findsOneWidget);

      // 1px from the left edge: the blue frame is painted right there.
      await tester.tapAt(Offset(_Data.rectA.left + 1, _Data.rectA.center.dy));
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);
      expect(_colorRow, findsOneWidget);
    });

    testWidgets('the color row fits a 320dp screen', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpInspect(tester, _blocks());

      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('parent, ruler and copy keep the color of the point', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);

      await tester.tap(find.byTooltip('Parent'));
      await _settleSample(tester);
      expect(find.textContaining('2 / '), findsOneWidget);
      expect(find.text(_Data.rowA), findsOneWidget);

      await tester.tap(find.byTooltip('Measure distance'));
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);

      await tester.tap(find.byTooltip('Copy layout chain'));
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);
    });

    testWidgets('dragging hides the color; release samples the last aim '
        'point', (tester) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);
      expect(find.text(_Data.rowA), findsOneWidget);

      final gesture = await tester.startGesture(_Data.rectA.center);
      await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
      await tester.pump();
      expect(_colorRow, findsNothing);

      await gesture.moveTo(_Data.rectB.center);
      await _settleSample(tester);
      expect(_colorRow, findsNothing);

      await gesture.up();
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('a drag started before the sample finishes drops it', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      // Capture frame only: the read-back for A is still pending.
      await tester.pump();

      final gesture = await tester.startGesture(_Data.rectA.center);
      await gesture.moveTo(_Data.rectB.center);
      await _settleSample(tester);
      expect(_colorRow, findsNothing);

      await gesture.up();
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('two quick taps show only the second color', (tester) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await tester.pump();
      await tester.tapAt(_Data.rectB.center);
      await tester.pump();
      expect(_colorRow, findsNothing);

      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
      expect(_colorRow, findsOneWidget);
    });

    testWidgets('ruler frames are not sampled', (tester) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await tester.pump();
      await tester.tap(find.byTooltip('Measure distance'));
      await tester.pump();

      // The orange 2px stroke of B is centered on its edge.
      await tester.tapAt(Offset(_Data.rectB.left + 0.5, _Data.rectB.center.dy));
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('the kit FAB is not sampled', (tester) async {
      await _pumpInspect(
        tester,
        const Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 200,
              child: ColoredBox(color: _Data.colorB),
            ),
          ],
        ),
        withFab: true,
      );

      await tester.tapAt(tester.getCenter(find.byType(InspectorFab)));
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('a release over the info card samples the app below it', (
      tester,
    ) async {
      await _pumpInspect(
        tester,
        const SizedBox.expand(child: ColoredBox(color: _Data.colorB)),
      );
      final gesture = await tester.startGesture(const Offset(400, 100));
      await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
      await tester.pump();

      await gesture.moveTo(
        tester.getCenter(find.byTooltip('Copy layout chain')),
      );
      await tester.pump();
      await gesture.up();
      await _settleSample(tester);
      expect(find.text(_Data.rowB), findsOneWidget);
    });

    testWidgets('samples the global point when the overlay is offset', (
      tester,
    ) async {
      const targetRect = Rect.fromLTWH(100, 150, 80, 50);
      final overlayKey = GlobalKey<OverlayState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fromRect(
                  rect: targetRect,
                  child: const ColoredBox(color: Color(0xFF00AA55)),
                ),
                Positioned(
                  left: 40,
                  top: 80,
                  width: 500,
                  height: 400,
                  child: Overlay(key: overlayKey),
                ),
              ],
            ),
          ),
        ),
      );
      LayoutInspectOverlay.show(overlayKey.currentState!);
      await tester.pump();

      await tester.tapAt(targetRect.center);
      await _settleSample(tester);
      expect(find.text('color: #00AA55'), findsOneWidget);
    });

    testWidgets('copy writes one color line at the end, also with the ruler', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await _settleSample(tester);
      await tester.tap(find.byTooltip('Copy layout chain'));
      await tester.pump();
      expect(clipboardText, endsWith('\n\n${_Data.rowA}'));
      expect('color: #'.allMatches(clipboardText ?? '').length, 1);

      await tester.tap(find.byTooltip('Measure distance'));
      await tester.pump();
      await tester.tapAt(_Data.rectB.center);
      await _settleSample(tester);
      await tester.tap(find.byTooltip('Copy layout chain'));
      await tester.pump();
      expect(clipboardText, contains('=== Measurement (Gap Ruler) ==='));
      expect(clipboardText, endsWith('\n\n${_Data.rowB}'));
      expect('color: #'.allMatches(clipboardText ?? '').length, 1);
    });

    testWidgets('a failed sample hides the row and leaves the rest intact', (
      tester,
    ) async {
      await _pumpInspect(
        tester,
        const Center(
          child: SizedBox(width: 80, height: 80, child: Texture(textureId: 1)),
        ),
      );

      await tester.tapAt(tester.getCenter(find.byType(Texture)));
      await _settleSample(tester);
      expect(_colorRow, findsNothing);
      expect(find.text('size: 80.0 × 80.0'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Copy layout chain'));
      await tester.pump();
      expect(clipboardText, contains('#0 Texture (TextureBox)'));
      expect(clipboardText, isNot(contains('color:')));
    });

    testWidgets('closing before the sample finishes throws nothing', (
      tester,
    ) async {
      await _pumpInspect(tester, _blocks());
      await tester.tapAt(_Data.rectA.center);
      await tester.pump();

      await tester.tap(find.byTooltip('Close layout inspector'));
      await _settleSample(tester);
      expect(find.byTooltip('Close layout inspector'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
```

Fixture 說明（AC5 末段）：區塊色是 `#336699`、`#AA00AA`、`#00AA55`，都不是 inspector 的 `#2196F3`／`#FF9800`／`#F44336`。標尺的 B 框是以 `drawRect` 畫 2px stroke，**中心在邊上**（`gap_ruler_painter.dart:24-28`），所以內側只有 1 logical px，測試點在 `left + 0.5`；`left + 1` 會落在 stroke 之外而測不出東西（0b 實測）。

測試與規格的對應：

| 測試 | 規格 |
|:--|:--|
| `a tap shows the pixel color, also inside the 2px frame` | AC3、AC5（內部與邊緣）、AC6 |
| `the color row fits a 320dp screen` | AC3（既有 320dp 測試不跑讀回，這支補上「有色碼列時」的窄螢幕） |
| `parent, ruler and copy keep the color of the point` | AC1 |
| `dragging hides the color; release samples the last aim point` | AC1、AC2、Q9 |
| `a drag started before the sample finishes drops it` | AC2（過期結果丟棄） |
| `two quick taps show only the second color` | AC2（規格指定案例，且中間不閃舊色） |
| `ruler frames are not sampled` | AC6（標尺 B 框內緣不是 `#FF9800`） |
| `the kit FAB is not sampled` | AC6（kit FAB） |
| `a release over the info card samples the app below it` | AC6（不靠位置假設） |
| `samples the global point when the overlay is offset` | AC5（巢狀 Overlay 位移） |
| `copy writes one color line at the end, also with the ruler` | AC4、Q8 |
| `a failed sample hides the row and leaves the rest intact` | AC7、AC4（無色碼時不含 `color:` 行） |
| `closing before the sample finishes throws nothing` | AC7、R7 |

- [ ] **Step 2：確認 Red**

```bash
rtk flutter test test/ui/layout_inspect/layout_inspect_color_test.dart
```

預期：11 個失敗、2 個通過（`a failed sample…` 與 `closing before…` 只斷言「沒有出現」，在未接線時本來就成立）。

- [ ] **Step 3：修改 `layout_inspect_overlay.dart`**（共 8 處，全部在同一檔）

(a) 狀態欄位：在 `Offset _stackOffset = Offset.zero;`（`:72`）之後加

```dart
  Color? _color;
  int _sampleId = 0;
```

(b) `_onTapUp`（`:85`）：`_probeAt(details.globalPosition);` → `_settleAt(details.globalPosition);`

(c) `_onPanEnd`（`:104`）：`if (aim != null) _probeAt(aim);` → `if (aim != null) _settleAt(aim);`

(d) 把 `_probeAt`（`:114-133`）整個換成下面三個方法（合併多餘的空結果分支，理由見 §3-4）：

```dart
  void _probeAt(Offset globalPosition) {
    final anchor = context.findRenderObject();
    if (anchor == null) return;
    final hit = probeLayoutAt(anchor, globalPosition);
    _copiedTimer?.cancel();
    // A new point: drop the old color and orphan any in-flight sample.
    _sampleId++;
    setState(() {
      _chain = hit;
      _index = 0;
      _copied = false;
      _color = null;
    });
  }

  void _settleAt(Offset globalPosition) {
    _probeAt(globalPosition);
    unawaited(_sampleAt(globalPosition));
  }

  Future<void> _sampleAt(Offset globalPosition) async {
    final anchor = context.findRenderObject();
    if (anchor == null || _chain.isEmpty) return;
    final id = _sampleId;
    final color = await sampleColorAt(anchor, globalPosition);
    if (!mounted || id != _sampleId || color == null) return;
    setState(() => _color = color);
  }
```

`_aimAt`（`:109-112`）不動：拖曳中仍只呼叫 `_probeAt`，所以只清色、不取色。`unawaited` 來自既有的 `import 'dart:async';`。

(e) `_buildExportText`（`:156-174`）：開頭加兩行，兩個 `return` 接上 `$colorLine`，其餘不動

```dart
  String _buildExportText() {
    final color = _color;
    final colorLine = color == null ? '' : '\n\ncolor: ${formatColor(color)}';
    final chainText = formatLayoutChain(
      ...（原樣）
      return '$chainText\n\n$measurementText$colorLine';
    }
    return '$chainText$colorLine';
  }
```

(f) `build` 內建立 `_LayoutInfoCard` 處（`:262-263`），在 `mayBeObfuscated: widget.mayBeObfuscated,` 之後加 `color: _color,`

(g) `_LayoutInfoCard` 建構式（`:379-380`）在 `required this.mayBeObfuscated,` 之後加 `required this.color,`；欄位（`:394-395`）在 `final bool mayBeObfuscated;` 之後加 `final Color? color;`

(h) 卡片內 `offset` 那個 `Text`（`:567-570`）之後、`if (mayBeObfuscated)` 之前加一行

```dart
                        if (color case final sampled?) _ColorRow(sampled),
```

並在檔尾（`_LayoutInfoCard` class 之後）新增

```dart

class _ColorRow extends StatelessWidget {
  const _ColorRow(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox.square(
          dimension: ThemeSize.space12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: ThemeColor.color9E9E9E),
            ),
          ),
        ),
        const SizedBox(width: ThemeSize.space4),
        Text(
          'color: ${formatColor(color)}',
          style: ThemeTextStyle.monospaceStyle,
        ),
      ],
    );
  }
}
```

色塊加灰色細框，否則白色或與卡片同色的取樣在卡片上看不見。`if (color case final sampled?)` 是因為 `color` 是公開 final 欄位，不能做型別提升；用 pattern 而不是 `!`。

- [ ] **Step 4：確認 Green 與零破壞**

```bash
rtk flutter test test/ui/layout_inspect/
rtk flutter test
rtk dart format --output=none --set-exit-if-changed lib/src/ui/layout_inspect lib/src/utils/layout_formatters.dart test/ui/layout_inspect test/utils/layout_formatters_test.dart
rtk flutter analyze lib/ test/
git diff --exit-code pubspec.yaml lib/flutter_inspector_kit.dart
git diff --exit-code -- test/ui/layout_inspect/layout_inspect_overlay_test.dart test/ui/layout_inspect/layout_inspect_drag_aim_test.dart test/ui/layout_inspect/gap_ruler_overlay_test.dart test/ui/layout_inspect/gap_ruler_painter_test.dart test/ui/layout_inspect/gap_ruler_geometry_test.dart test/ui/layout_inspect/layout_probe_test.dart
```

預期：
- `test/ui/layout_inspect/` 全過（既有 49 個加新增 23 個，共 72 個）。
- 全套 `flutter test` **1005** 個全過（981 + 24）。
- format 0 changed；analyze 只有既有 7 個 info。
- 兩個 `git diff --exit-code` 都以 exit code 0 結束：`pubspec.yaml` 與匯出檔零 diff（AC10）；六個既有測試檔零 diff（AC8）。任一非 0 即不通過。

---

### Task 5 `[驗證／主進程＋使用者]`：全套驗證與 AC12 實機手測

**寫入路徑**：無。

- [ ] **Step 1：在功能分支上重跑 Task 4 Step 4 的全部指令**，結果需與預期一致。
- [ ] **Step 2：AC12 實機手測**（`cd example && flutter run -d <實機>`，至少一台）：
  1. 點 Box 1／Box 2 實心處，色碼為 `#2196F3`／`#F44336`。
  2. 拖曳讓準星停在 Box 2 再放開，色碼為 `#F44336`。
  3. 標尺模式：鎖定 Box 1，點 Box 2，卡片同時有間距摘要與 `color: #F44336`。
  4. 按複製，貼到任一文字欄位，最後一行是 `color: #F44336`。
  5. 開 WebView demo：點網頁內容，沒有色碼列、沒有錯誤訊息；再點 AppBar 空白處（捲動網頁之前），有色碼列且值等於 AppBar 背景色，App 不 crash、無錯誤 log（判準同 Task 1 S3 (b)）。

  **沿用條件**：Task 1 沒有套用任何退路，且下面的比對 **exit code 為 0** 時，可直接沿用 Task 1 的實機結果作為 AC12 證據，只需補做第 4 項（複製後貼上）；否則五項全部重做。

  ```bash
  # --output 寫檔再以 cmp 的 exit code 判定，不看輸出，避開 RTK hook 壓縮造成假通過
  git diff main --output="$SCRATCHPAD/branch-lib.diff" -- lib/ && cmp "$SCRATCHPAD/spike-lib.diff" "$SCRATCHPAD/branch-lib.diff"
  ```

  兩份 diff 都以 `main` 為基準，內容相同時連 `index` 行的 blob hash 都相同。`spike-lib.diff` 不存在（例如 scratchpad 已被清空）或 `main` 在 spike 之後有新 commit 時，條件不成立，一律重做。
- [ ] **Step 3：把結果（裝置型號、OS、五項結果）回寫到本計畫 §8-9**。

**驗收**：五項全部符合；若 Task 1 有套用任何退路，這裡驗的必須是套用後的版本。

---

### Task 6 `[機械性／微任務：主進程原地]`：文件同步（最後執行）

**寫入路徑**：`README.md`、`README.zh-TW.md`、`docs/architecture/overview.md`、`docs/architecture/file-reference.md`。CHANGELOG 不在本次（`test/version_test.dart:77` 要求頂端標題等於 pubspec 版號，沿用 2026-11-01 裁決）。

> 若 Task 1 的 S5 套用了 Web 退路，README 兩份都要在新段落末尾加上「不支援 Web」那句（下方以【Web 退路】標示）。若 S2 改選 (B)，依 §0 改寫「閃一幀」那句。

- [ ] **Step 1：`README.md`**：在 Gap Ruler 段落（`:139`，以 `…Tap the ruler button again to exit measurement mode.` 結尾）之後、`It needs no setup…`（`:141`）之前插入一段：

```markdown
Each time you tap or release, the card also shows the color actually displayed at that point — a swatch and `color: #RRGGBB` — and copying or sharing adds the same line. It is read from the screen pixel, not from the widget's declared color, and never includes the inspector's own outline, ruler, card, magnifier or FAB: they are hidden for the one frame in which the pixel is read, so the overlay flickers briefly. Over a platform view or texture (WebView, maps, video) or where the pixel is not fully opaque, the color row is left out. One exception to the exclusion: a card button's tooltip, if still showing from a long press, can end up in the sample.
```

【Web 退路】句尾追加：` Color sampling is not available on web.`

- [ ] **Step 2：`README.zh-TW.md`**：在對應的 Gap Ruler 段落（`:139`）之後、下一段（`:141`）之前插入：

```markdown
每次點擊或放開時，卡片也會顯示該點在畫面上實際呈現的顏色——一個色塊加上 `color: #RRGGBB`——複製或分享時也會附上同一行。顏色取自螢幕像素，而非 widget 宣告的顏色，且不會包含 inspector 自己的外框、尺規、卡片、放大鏡或 FAB：讀取像素的那一幀會先把它們隱藏，所以畫面會短暫閃一下。點在平台視圖或 texture（WebView、地圖、影片）上，或該像素並非完全不透明時，不會顯示色碼列。唯一的例外：若長按卡片按鈕後 tooltip 仍顯示中，取色可能會取到 tooltip。
```

【Web 退路】句尾追加：`Web 不支援取色。`

- [ ] **Step 3：`docs/architecture/overview.md:71`**：在 `LayoutInspectOverlay` 該行句尾（`…雙單位資訊。`之後）追加：

```markdown
點擊或放開（結算）時以 `sampleColorAt` 取該點的實際顯示色：讓所有 `LayoutProbeShield` 子樹停繪一幀，在 post-frame 對 root `TransformLayer`（`RenderView.layer`）以 `toImageSync` 擷取 1×1 實體像素並 `toByteData` 讀回；擷取幀的 layer tree 在該點有 `PlatformViewLayer`／`TextureLayer`，或像素非完全不透明時不顯示。色碼是點的屬性，存在 overlay state 而非 `LayoutLevel`，以世代計數丟棄過期結果，資訊卡與複製／分享文字各多一行 `color: #RRGGBB`。
```

- [ ] **Step 4：`docs/architecture/file-reference.md`**：
  - `:72`（`layout_formatters.dart`）：符號欄在 `formatMeasurement` 之後加上 ``<br>`formatColor` ``，說明欄的「格式化為純文字」前加上「、取色結果（`#RRGGBB`）」。
  - `:98`（`layout_inspect_overlay.dart`）：說明欄在「支援雙點鎖定間距標尺（Gap Ruler）。」之後加「點擊或放開時取該點實際顯示色，資訊卡顯示色塊與 `color: #RRGGBB` 並寫入複製／分享文字。」
  - `:99`（`layout_probe.dart`）：符號欄在 `probeLayoutAt()` 之後加上 ``<br>`sampleColorAt()` ``，說明欄句尾加「；`sampleColorAt` 讓所有 shield 停繪一幀後擷取 root layer 的 1×1 實體像素，遇平台視圖、texture 或非不透明像素回傳 `null`。」

- [ ] **Step 5：驗證**

```bash
rtk flutter test test/version_test.dart test/public_api_readme_example_test.dart
git diff --stat
```

預期：兩個測試通過；`git diff --stat` 只列出本計畫 §4 的檔案。

---

## 7. 執行方式

| 方式 | 評估 |
|:--|:--|
| **Subagent-driven，序列為主（建議）** | 批次 0：Task 1（主進程＋使用者，需要實機）。批次 A：Task 2（主進程原地，微任務）。批次 A'：Task 3（subagent，設計判斷；Task 2 通過後才開始，不並行，否則 Task 3 的 analyze 會撞上 Task 2 的 Red 狀態）。批次 B：Task 4（subagent，整合；需 Task 2、3 通過驗收）。批次 C：Task 5（主進程＋使用者）。批次 D：Task 6（主進程原地，微任務）。每個 subagent 任務各自經 verifier 驗收。 |
| Parallel session | 不建議。程式任務是嚴格的鏈（Task 2 → 3 → 4），唯一能並行的是 Task 6 的文件撰寫，另開 session 不划算。 |
| 主進程全程原地 | 可行（程式碼已在原型逐字驗證，總計約 120 行 lib），但會繞過「實作與驗收分離」，不建議。 |

---

## 8. 0b 預驗證紀錄

做法：把 repo 的 `lib/`、`test/`、`pubspec.*`、`analysis_options.yaml`（及 README、CHANGELOG 供 `version_test` 使用）複製到 scratchpad，套用本計畫的程式碼，SDK 為 Flutter 3.47.1。repo 本身沒有改動，複本驗證完已刪除。

1. **全套**：基準 981 個（repo 原狀實跑）。套用本計畫後 **1005** 個全過（修正後重跑；修正前為 1004）；`flutter analyze lib/ test/` 恰為既有 7 個 info；Task 4 Step 4 的 `dart format` 指令（涵蓋 14 個檔）0 changed。
2. **AC8 零破壞**：`test/ui/layout_inspect/` 既有 49 個測試與 `layout_formatters_test.dart` 既有 4 個測試在未修改下全過，包括 drag-aim 單次 `pump()` 後查藍框與卡片文字的斷言。
3. **R7 未完成的讀回**：既有測試只 `pump()`，每次結算都留下未完成的 `toByteData`，全套照過，測試結束時沒有 pending 錯誤。
4. **紅燈實證（mutation，以最終程式碼與輪詢 helper 全部重跑；正確實作下 23/23 綠）**：以腳本逐項套用變異，跑 Task 3、4 的兩個新測試檔，以 `[E]` 標記計數（`flutter test` 結尾的 Failing tests 清單會截斷，不能用來計數）。每項都有測試變紅：

| 變異 | 紅燈數 | 變紅的測試 |
|:--|:--:|:--|
| 拿掉 shield `paint` 的 `if (_hidden) return;` | 6 | 單元：`reads the app pixel under kit UI…`、`hides every shield…`；整合：`a tap shows…`（藍框邊緣）、`ruler frames…`、`the kit FAB…`、`a release over the info card…` |
| `finally` 不呼叫 `_setHidden(false)` | 1 | `hides every shield for exactly the capture frame` |
| 拿掉 `_shields.add(this)` | 8 | 單元 8 支（不註冊就沒有 shield 被重繪，停繪與恢復都不會發生） |
| `floor` 改 `round` | 1 | `reads the physical pixel … fractional devicePixelRatio` |
| 拿掉 `_coversExternalSurface` 檢查 | 4 | `returns null over a texture`、`… widget drawn over a texture`（證明命中路徑判定不夠）、`does not block points outside a texture`、整合 `a failed sample…` |
| `.contains(point)` 改成 `return true` | 1 | **只有** `does not block points outside a texture`；單獨保留 `(75, 75)` 那條斷言也會紅。修正前的 23 個測試在這個變異下全綠，plan-verifier F1 屬實 |
| 只在 `TransformLayer` 套 `applyTransform`（丟掉 OffsetLayer 位移、保留 DPR） | 4 | `does not block points outside a texture`，以及 `returns null over a texture`、`… widget drawn over a texture`、整合 `a failed sample…`。實測 texture 自帶一層 OffsetLayer（layer 路徑：root `TransformLayer` → RepaintBoundary 的 `OffsetLayer(50, 50)` → texture 自己的 `OffsetLayer(50, 50)` → `TextureLayer(0, 0, 100, 100)`），所以此變異下 rect 是實體 0..300，不是審查推估的 150..450。單獨保留 `(75, 75)`（實體 225）那條斷言即變紅，不依賴 `block.center` 的半開區間邊界 |
| 起始 transform 傳 root 的 `transform` 而非 `Matrix4.identity()`（DPR 重複乘） | 4 | `does not block points outside a texture`（單獨保留 `(350, 350)` 那條斷言即變紅），以及修正前就有的 `returns null over a texture`、`… widget drawn over a texture`、整合 `a failed sample…`（texture 被算到 3 倍遠，原本該擋的點不再被擋） |
| 拿掉 `layer.applyTransform(child, childTransform)` | 4 | 同上 4 支 |
| 拿掉 alpha 檢查 | 1 | `returns null when the pixel is not fully opaque` |
| 拿掉 `id != _sampleId` | 1 | `a drag started before the sample finishes drops it` |
| 拿掉 `!mounted` | 1 | `closing before the sample finishes throws nothing` |
| 拿掉 `_probeAt` 內的 `_color = null` | 3 | `dragging hides the color…`、`a tap shows…`、`copy writes one color line…`（輪詢 helper 看到殘留的舊色碼列就停，舊色直接被斷言抓到） |
| `_onPanEnd` 改回 `_probeAt` | 3 | `dragging hides…`、`a drag started…`、`a release over the info card…` |
| `_aimAt` 改成每次移動都取色 | 2 | `dragging hides…`、`a drag started…` |
| 標尺分支的 `return` 拿掉 `$colorLine` | 1 | `copy writes one color line at the end…` |
| `shield.attached` 檢查（初版有） | 0 | detach 後 `owner` 為 `null`，`_capturePixel` 已回傳 `null`，此檢查多餘，已從計畫刪除 |

   `_setHidden(true)` 與 callback 註冊的順序調換（plan-verifier 次要 2）不改變任何可觀察行為（隱藏仍在下一幀之前完成），全套照過，沒有對應的紅燈測試。
   Task 4 Red 實測：以 repo 原本的 overlay 跑整合測試為 `+2 -11`。
5. **Web**：`flutter test --platform chrome`（CanvasKit）跑本計畫 3 個測試檔：28/28 通過（修正後重跑）。`--platform chrome --wasm`（skwasm）：同一個 test 內連續兩次取色皆正確（`[51,102,153,255]`、`[170,0,170,255]`），但同一檔案從第二個 `testWidgets` 起讀不到（延長到 10×100ms 仍然如此），判定為 skwasm 測試環境跨 test 的問題，不影響功能，不列入基準，由 Task 1 S5 以真實瀏覽器確認。
6. **受保護成員**：在 `_RenderLayoutProbeShield` 的 instance member 內讀 `owner?.rootNode` 的 `.layer`，Flutter 3.47.1 analyzer 無任何診斷（與規格 Q1 的實測一致）。
7. **測試讀回節奏與 flake**：VM 上通常 `pump → runAsync(10ms) → pump` 一輪就有結果。但三個 `flutter test` 行程同時跑兩個新測試檔時（同時有工具編譯負載），單輪版本出現 2 次 `reads the app pixel under kit UI…` 失敗。改成輪詢 helper（上限 50 輪）後：
   - 單一 `flutter test --concurrency=8`、8 份新測試副本（92 個測試）連跑 3 次，全綠。
   - 全套 1005 個全綠，`layout_inspect/` 72 個全綠（目錄耗時約 2 秒增為約 4 秒，多出來的是「斷言沒有色碼列」那幾處要等滿 0.5 秒）。
   - 同一 project 目錄同時開多個 `flutter test` 行程，會互搶 `build/native_assets`（`OS Error: No such file or directory`、`Failed to code sign binary`），那是工具層的衝突，不是測試失敗；壓力測試請改用單一行程加 `--concurrency`。
8. **S1 退路（`toImage`）**：把 Task 1「S1 退路程式碼」套進原型，Task 3、4 的 23 個新測試全過（輪詢 helper 版本重跑）；再把 `_capturePixel` 改成回傳 `Future.error(StateError('injected'))`，`reads the app pixel…` 得到 `null`，輸出中沒有 `injected` 未捕獲錯誤。
9. **Task 1／Task 5 實機結果**：
   - **Task 1（2026-11-15）**：S1–S6 全部通過，使用者實機手測回報「皆可接受」；S2 閃爍判定可接受，維持 (A)。執行指令指向 iPhone 實機（`flutter devices` 的 `YiandayH`，debug 與 `--release`）與 Chrome（`-d chrome` 與 `--wasm`）；使用者未另報型號與 OS 版本。
   - **未套用任何退路**：Task 3 程式碼區塊維持原樣（`toImageSync`，Web 不加 `kIsWeb` 關閉）。
   - **spike 產物**：使用者要求以分支形式執行，spike 程式碼 commit 於本地分支 `spike/202611/251-layout-inspect-color-sampling`（`61fe345`，不合併）；spike worktree 已移除。Task 5 沿用比對的基準 diff 由 `git diff 6513be0 61fe345 --output=… -- lib/` 產生，存於 `$SCRATCHPAD/spike-lib.diff`（327 行）；scratchpad 被清空時可由同一指令重建。
   - **Task 5（2026-11-16）**：Step 1 重跑 Task 4 Step 4 全部指令，結果與預期一致：`layout_inspect/` 72 個全過、全套 1005 個全過、format 14 檔 0 changed、analyze 恰為既有 7 個 info、`pubspec.yaml`／匯出檔／六個既有測試檔對 `main` 零 diff、`layout_formatters_test.dart` numstat 為 `6 0`。Step 2 沿用條件成立：`git diff main -- lib/` 與 `git diff 6513be0 61fe345 -- lib/` 兩份 diff（各 327 行）`cmp` exit 0，`main` 仍為 `c2e1b6e`，故第 1、2、3、5 項沿用 Task 1 實機結果；第 4 項（標尺模式鎖定 Box 1、點 Box 2 後複製貼上，最後一行為 `color: #F44336`）由使用者實機補測，回報通過，未另報型號與 OS 版本。

---

## 9. 規格覆蓋對照

| 規格 AC | 對應 |
|:--|:--|
| AC1 只在結算時取色一次 | 結構：只有 `_onTapUp`／`_onPanEnd` 走 `_settleAt`。測試：`parent, ruler and copy keep…`、`dragging hides the color…` |
| AC2 色碼對應最後一次結算 | 結構：`_probeAt` 內 `_sampleId++` 與清色。測試：`two quick taps…`、`a drag started before the sample finishes…`、`dragging hides…` |
| AC3 資訊卡呈現 | Task 4 (h)；測試：`a tap shows…`（`find.text` 精確比對，含 A–F）、`the color row fits a 320dp screen`；既有 320dp 測試不改 |
| AC4 複製與分享 | Task 4 (e)；複製與分享共用 `_buildExportText`（`:179`、`:191`）。測試：`copy writes one color line…`、`a failed sample…`（無色碼時不含 `color:`）；`formatLayoutChain` 零 diff |
| AC5 色碼正確性 | 單元：`reports an app color equal to the kit blue…`、`fractional devicePixelRatio`；整合：`a tap shows…`（邊緣）、`samples the global point when the overlay is offset`；Task 1 S1 |
| AC6 排除 inspector | 結構：shield 停繪。單元：`reads the app pixel under kit UI…`、`hides every shield…`；整合：藍框邊緣、`ruler frames…`、`the kit FAB…`、`a release over the info card…` |
| AC7 失敗與不支援 | 單元：texture、widget over texture、非不透明、shield 外、擷取前移除；整合：`a failed sample…`、`closing before…`；反向（不因畫面上有平台視圖就全面失效）：`does not block points outside a texture`、Task 1 S3 (b)；Task 1 S3 (a) |
| AC8 既有行為零改變 | Global Constraints；Task 4 Step 4 的 `git diff --exit-code -- <6 個既有測試檔>`；§8-2 |
| AC9 平台與 build mode | 不用 debug-only API；Task 1 S4（release）、S5（Web） |
| AC10 零副作用 | 不 import registry／buffer、不 log；Task 4 Step 4 的 `git diff --exit-code` |
| AC11 測試與分析 | Task 4 Step 4、Task 5 Step 1 |
| AC12 實機手測 | Task 5 Step 2 |
| AC13 文件同步 | Task 6 |

---

## 10. 風險與退路

| 風險 | 可能性 | 退路 |
|:--|:--|:--|
| 原生 Impeller 上 `toImageSync` 失敗或色值偏移（含 iOS 廣色域） | 中 | 見 Task 1 S1 退路程式碼（§6 Task 1「S1 退路程式碼」起）：`toImage` 的 future 交給 `captured.complete`，在 `try` 內 `await`，不在 post-frame callback 內 await；仍失敗則停止回 0b |
| 使用者不接受一幀閃爍 | 中 | 改選 (B)，影響範圍見 §0 |
| 某平台的平台視圖不是 `PlatformViewLayer`／`TextureLayer` | 低 | Task 1 S3：把該 layer 型別加進 `switch`；找不到就補命中路徑判定 |
| Web（CanvasKit 或 skwasm）在真實瀏覽器失敗 | 低（CanvasKit 測試環境已過） | Task 1 S5：`if (kIsWeb) return null;` 加 `shortcut:` 註解，README 註明 |
| 未來 analyzer 收緊 `@protected` 規則 | 低 | 在 `_capturePixel` 讀 `view.layer` 那行加 `// ignore: invalid_use_of_protected_member`（repo 測試已有同類 ignore 先例） |
| layer 掃描的座標換算錯，畫面上有影片／地圖／WebView 時色碼列全面消失 | 低 | `does not block points outside a texture` 鎖住三種換算錯誤（§8-4）；Task 1 S3 (b) 在真 WebView 旁取色 |
| 長按卡片按鈕後 tooltip 經 `OverlayPortal` 繪製、不在 shield 內，殘留期間（約 1.5 秒）取色可能取到 tooltip | 低 | 不修，`_setHidden` 上的 `shortcut:` 註解與 README 註明；有人回報再把 tooltip overlay 包進 shield |
| `_hidden` 全域旗標卡住 | 極低 | 只在之後永遠沒有下一幀時發生；`finally` 保證每次擷取後恢復，包括 shield 已移除的情況（單元測試覆蓋） |
| skwasm 測試環境跨 test 讀不到 | 已知 | 不列入基準（專案無 CI，基準是 VM 上的 `flutter test`）；功能面由 Task 1 S5 確認 |

---

## 11. 本次修正對照（plan-verifier 初審 REVISE #1）

| 審查項 | 處置 | 位置 |
|:--|:--|:--|
| F1-1 layer 掃描「不誤判」方向無可證偽測試 | 採納。新增單元測試 `does not block points outside a texture`（texture 經 `RepaintBoundary` offset layer 加 `Padding` 層內位移上屏，取外側兩點須得背景色）。三個變異（`contains` 改 `true`、DPR 重複乘、略過 `applyTransform`）皆已在原型實跑變紅 | Task 3 Step 1 測試與對應表；§1 Q6；§8-4 |
| F1-2 實機 gate 沒驗「畫面上有平台視圖、點在別處」 | 採納。S3 加 (b) 點 WebView demo 的 AppBar；Task 5 Step 2 第 5 項同步 | Task 1 S3；Task 5 Step 2 |
| F1-3 測試數同步 | 採納。新增 23 → 24，全套 1004 → 1005，`layout_inspect/` 71 → 72，單元 9 → 10，Chrome 27 → 28，全部重跑確認 | Global Constraints、§1 Q3、§4、Task 3 Step 7、Task 4 Step 4、§8 |
| 次要 1 tooltip 經 `OverlayPortal` 不在 shield 內 | 採納（不修程式，只註明）。`_setHidden` 上加 `shortcut:` 註解，兩份 README 段落加一句 | Task 3 Step 6；Task 6 Step 1–2；§10 |
| 次要 2 `_setHidden(true)` 移到 callback 註冊之後 | 採納 | Task 3 Step 6；§2 |
| 次要 3 S1 退路寫出完整程式碼 | 採納。`_capturePixel` 回傳 `Future<ui.Image>?`，`await captured.future` 移進 `try`；已在原型跑過 23 個新測試，並注入 rejection 驗證無未捕獲錯誤 | Task 1「S1 退路程式碼」；§3-2；§8-8 |
| 次要 4 Task 2 排在 Task 3 之前、不並行 | 採納 | §5、§7 |
| 次要 5 AC8 檢查改 `git diff --exit-code` | 採納 | Task 4 Step 4；§9 AC8 |
| 次要 6 `shortcut:` 註解補 z-order | 採納 | Task 3 Step 6 |
| 次要 7 Task 5 可沿用 Task 1 實機結果 | 採納，附沿用條件（無退路且 `lib/` 逐字相同；仍補做複製貼上） | Task 5 Step 2 |
| 附註：「DPR 重複乘一次則 23 個測試照樣全綠」 | 實測與此不符：以「起始 transform 傳 root `transform`」實作該變異時，修正前就有 3 支測試變紅（§8-4）。「`contains` 改 `true`」的確全綠，F1 的結論成立，新測試同時涵蓋兩者 | §8-4 |

### 複審 READY 後追加採納（3 條次要意見）

| 意見 | 處置 | 位置 |
|:--|:--|:--|
| 1. 外側點 `(30, 30)` 改 `(75, 75)` | 採納。`(75, 75)` 在 RepaintBoundary 區內、Padding 區（透明）上，正確實作取到的是 `_Data.background`（原型實跑通過）。原型實測：正確實作 23/23 綠；「丟 OffsetLayer 位移、保留 DPR」、`contains → true`、「DPR 重複乘」三個變異都紅，且各自單獨保留對應那條斷言時也紅。實測的 layer 結構與審查推估不同（texture 自帶 OffsetLayer），註解已照實測改寫 | Task 3 Step 1 新測試；§8-4 |
| 2. Task 5 沿用條件可執行化 | 採納。Task 1 Step 3 移除 worktree 前先存 `$SCRATCHPAD/spike-lib.diff`；Task 5 以 `git diff main -- lib/ \| diff -u "$SCRATCHPAD/spike-lib.diff" -` 比對，無輸出才沿用 | Task 1 Step 3；Task 5 Step 2 |
| 3. §10 第一列措辭 | 採納。改指向 Task 1「S1 退路程式碼」，並註明不在 post-frame callback 內 await | §10 |
| 追加（原型重跑時發現） | 單輪 10ms 的測試 helper 在多行程負載下出現 2 次 flake。兩個 helper 改為輪詢（上限 50 輪），測試數不變 | Task 3 Step 1 `_sample`；Task 4 Step 1 `_settleSample`；§1 Q7；§8-7 |

