# 功能規格：Inspect layout 結算點取色 (Settled-Point Color Sampling)

- **日期**：2026-11-15
- **來源**：gen-grill 需求 brief（2026-11-15 已與使用者逐項確認）。此功能原列於 [`2026-10-31-layout-inspect-touch-loupe.md`](2026-10-31-layout-inspect-touch-loupe.md) §4「不做（使用者已確認）」（:93「取色器」），性質是延後處理，當時沒有否決理由。`docs/brainstorm/2026-11-18-features-brainstorm.md` 沒有對應條目，所以不編 §P 號。
- **Effort**：估計 **Medium**。取色是套件裡沒有的新能力，「排除 inspector 自己畫的東西」與非同步競態都需要設計 ｜ **排查價值**：⭐⭐⭐

> ⚠️ **部分不可行：平台視圖區域無法取得實際顯示色。** Flutter 的畫面擷取（`Scene.toImage` 系列）只包含 Flutter 自己合成的 layer，不含平台視圖（WebView、`HtmlElementView`、原生地圖等）的像素。Web 端已在本機 SDK 實查：toImage 專用的 `PaintVisitor.forToImage` 把 `viewEmbedder` 設成 `null`（`flutter_web_sdk/lib/_engine/engine/layer/layer_visitor.dart:474`），`visitPlatformView` 什麼都不畫（`:730-733`）。原生端的 engine 原始碼不在本機，尚未實查，但一般認為限制相同。因此「色碼 = 畫面上實際顯示的像素色」在平台視圖上做不到。本規格的處置：這類點視同「取色失敗」，**不顯示色碼列，也不能顯示錯誤的顏色**（AC7）。偵測方式交給 STAGE 0b（§6 Q6）。
>
> **其他需求都可行，不衝突既有不變式。** 但「排除 inspector」無法零成本達成，有兩條路線，各有代價：多畫一幀造成可見閃爍，或者在半透明 route／barrier 上保真度不足。這屬於 trade-off，留給 0b 裁決（§6 Q1）。

---

## 1. 背景與問題 (What & Why)

QA 或開發者在實機上看到元件顏色不對，想和設計稿色碼比對。目前只能截圖後用外部工具吸色，有兩個問題：截圖可能因壓縮而色偏，色碼也無法直接附進 bug 回報。Layout inspect 已能回報元件的 size、constraints 與位置，唯獨缺少「這一點在畫面上到底是什麼顏色」。

實查現況：

- `lib/` 全域沒有任何擷取或色碼格式化程式碼：`toImage`、`toByteData`、`toARGB32`、`RepaintBoundary`、`RenderRepaintBoundary`、`toRadixString` 的使用次數都是 0。
- 資訊卡 `_LayoutInfoCard`（`lib/src/ui/layout_inspect/layout_inspect_overlay.dart:372`）的資訊列只有標尺摘要（`:543-557`）、`size`（`:558-561`）、`constraints`（`:562-566`）與 `offset`（`:567-570`）。
- 匯出文字由 `_buildExportText`（`:156-174`）組成，內容是 `formatLayoutChain` 加上標尺模式下的 `formatMeasurement`（`lib/src/utils/layout_formatters.dart:26-47`、`:65-118`）。複製（`_onCopy`，`:176-187`）與分享（`_onShare`，`:189-197`）共用這段文字。
- **結算時機**：點擊走 `_onTapUp`（`:83-86`），拖曳放開或已成立的拖曳被系統取消時走 `_onPanEnd`（`:101-105`），兩者最後都呼叫 `_probeAt`（`:114-133`）。**但 `_probeAt` 不只在結算時執行**：拖曳中每次指標移動都會經 `_aimAt`（`:109-112`，由 `_onPanStart` `:88-91` 與 `_onPanUpdate` `:93-96` 呼叫）重跑一次。所以「結算」只對應 `_onTapUp` 與 `_onPanEnd` 兩個入口，不等於 `_probeAt`。
- inspector 自己在畫面上畫的東西：
  - 藍框：寬 `ThemeSize.space2`（2.0，`theme_size.dart:10`）的 `#2196F3` 邊框，畫在目標 rect **內側**（`:238-253`）。點在元件邊緣 2 logical px 內，看到的就是藍色。
  - 標尺：`GapRulerPainter` 的 A 藍框、B 橘框 `#FF9800`、重疊填色、紅色線段 `#F44336` 與深色徽章（`gap_ruler_painter.dart:17-42`、`:113-115`）。
  - 資訊卡（`:254-271`）與放大鏡（`:274`）。
  - kit 的 FAB 在選取模式中仍然可見。它和選取層一樣包在 `LayoutProbeShield` 內（`inspector_fab.dart:29`、`layout_inspect_overlay.dart:37`），探測會穿透它。

**本功能**：在 Layout inspect 中，每次**結算出一個點**（點擊，或拖曳放開），就取該點在畫面上實際顯示的像素色。資訊卡會顯示一個小色塊與 `color: #RRGGBB`，複製與分享的文字也會寫入同一行。取色結果不能包含 inspector 自己畫的東西。取色失敗時不顯示該列，其他資訊照舊。

## 2. 使用者故事 (User Stories)

- 身為 QA，我覺得某顆按鈕的底色比設計稿深。我點一下按鈕的實心區域，卡片顯示 `color: #1E88E5`，我直接和設計稿的 `#2196F3` 比對，再按複製貼進 bug 單，單子上就有尺寸、constraints 與實際色碼。
- 身為開發者，我想確認一條 1 px 分隔線的顏色。我拖曳讓放大鏡的十字準星對到線上再放開，取到的是線的顏色，不是 inspector 藍框的顏色。
- 身為正在用間距標尺的 QA，我量完 A、B 的間距，卡片上的色碼是我最後點的 B 那一點的顏色，複製出來的文字同時有間距和色碼。
- 身為在 release 版實機回報 bug 的 QA，取色和 Layout inspect 其他功能一樣在 release build 可用。點到 WebView 上時卡片不顯示色碼列，也不會出現錯誤的顏色或錯誤訊息。

## 3. 驗收條件 (Acceptance Criteria)

用語定義：

- **結算點**：點擊時 `_onTapUp` 收到的 `globalPosition`；拖曳放開或被系統取消時，`_onPanEnd` 使用的最後瞄準點（`_aim`，`:102-104`）。
- **色碼**：結算點在畫面上實際顯示的像素色，以 `#RRGGBB` 表示，6 位大寫十六進位，不含 alpha。不讀元件宣告的顏色。

1. **只在結算時取色一次**
   - 只有點擊與拖曳結束（放開或系統取消）會觸發取色。拖曳中（`_onPanStart`／`_onPanUpdate`）不取色、不更新色碼。
   - 切換父鏈層級（Parent／Child）、鎖定或解除標尺 A、複製、分享，都不重新取色，色碼保持不變。色碼是「點」的屬性，不是「元件」的屬性。
   - 驗證：widget test。點 A 區塊後切換 Parent，色碼不變。從 A 區塊拖曳到 B 區塊放開，色碼為 B 的顏色。

2. **色碼永遠對應最後一次結算的點**
   - 新的點開始（新的點擊，或拖曳成立）後，上一個點的色碼不能繼續顯示在新目標的資訊卡上。
   - 取色還沒完成時又結算了新的點：舊結果必須丟棄，不能覆寫新點的色碼，也不能讓卡片短暫顯示舊色。
   - 驗證：widget test 覆蓋「連點兩個不同顏色的區塊，最後只顯示第二個的色碼」。觸發競態的測試手法由 0b 決定（§6 Q4、Q7）。

3. **資訊卡呈現**
   - 有結算結果且取色成功時，卡片資訊區多一列：小色塊（填色等於色碼）加上文字 `color: #RRGGBB`，例如 `color: #AA00AA`。這一列和 `size`／`constraints`／`offset` 放在同一區塊，確切順序由 0b 決定。
   - 色碼一律大寫。驗證時至少用一個含 A–F 的色值（例如既有 fixture 的 `0xFFAA00AA`）。
   - 窄螢幕不溢位：既有 320dp 測試（`layout_inspect_overlay_test.dart:277`）不修改即通過。
   - 驗證：widget test 以 `find.text('color: #...')` 精確比對。

4. **複製與分享的文字**
   - 取色成功後，複製與分享的文字都包含一行 `color: #RRGGBB`，且只出現一次。標尺模式下同樣只有一行，代表當前點，不是 A、B 各一行。
   - 沒有色碼時（取色失敗、尚未完成、平台不支援），匯出文字不含 `color:` 行，其餘內容與現行輸出逐字相同。
   - `formatLayoutChain` 的逐字比對測試（`test/utils/layout_formatters_test.dart:30-77`）不修改即通過。
   - 驗證：widget test mock `Clipboard.setData`（沿用 `layout_inspect_overlay_test.dart:13-23` 的寫法），斷言文字含 `color: #...`。

5. **色碼正確性**
   - 點在已知純色區塊的內部，色碼等於該區塊的顏色。
   - **邊緣**：點在區塊內、距離邊緣小於藍框寬度（2 logical px）的位置，色碼仍是區塊的顏色，不是 `#2196F3`。這是 brief 成功標準 1 的核心案例。
   - **不得以色值過濾來排除 inspector**：App 元件本身就是 `#2196F3` 時，必須如實回報 `#2196F3`。
   - 在 `devicePixelRatio ≠ 1` 的情境下，邏輯座標對應到正確的實體像素。
   - 選取層位於帶位移的巢狀 `Overlay` 時（現有先例：`layout_inspect_drag_aim_test.dart:293`），色碼仍是結算點 global 座標上的顏色。
   - 測試 fixture 的區塊不能使用 inspector 的顏色（`#2196F3`、`#FF9800`、`#F44336`），上面「App 本身就是 `#2196F3`」的案例除外，否則「沒取到藍色」的斷言沒有意義。注意既有 `gap_ruler_overlay_test.dart:50` 的區塊正是 `0xFF2196F3`。

6. **排除 inspector 自身繪製（硬性）**
   - 色碼不能受藍框、標尺（A 框、B 框、重疊填色、線段、徽章）、資訊卡（含本功能新增的色塊）、放大鏡影響。
   - kit 的 FAB 也要排除：點在 FAB 位置時，色碼是 FAB 底下 App 的顏色。這是從硬性排除要求推得的，也和 `probeLayoutAt` 穿透 FAB 的語意一致（`layout_inspect_overlay_test.dart:225`）。
   - 排除必須在結構上成立，不能靠「已知 inspector 不會蓋到結算點」這類位置假設。拖曳可以在資訊卡上方放開，放大鏡也可能殘留到下一幀。
   - 驗證：最低限度是 AC5 的邊緣案例。建議再加「標尺模式下點在 B 框內側邊緣，色碼不是 `#FF9800`」。

7. **取色失敗與不支援**
   - 擷取失敗、拋例外、拿不到像素資料，或平台不支援時：不顯示色碼列，不跳任何錯誤訊息（SnackBar、dialog、卡片錯誤文字都不行），卡片其他資訊與操作不受影響。
   - 無法確定實際顯示色的點（平台視圖區域，見文首 ⚠️）視同失敗，不能顯示錯誤的顏色。
   - 取色失敗**不能產生未捕獲的例外**。套件會用 `PlatformDispatcher.instance.onError` 鏈接收未捕獲錯誤（`lib/src/core/uncaught_error_handler.dart:54-56`），漏接的例外會被寫進 log buffer、進入時間軸，違反 AC10。
   - 驗證：widget test 模擬一次取色失敗，斷言沒有色碼列，`size` 等列照常顯示，`tester.takeException()` 為 `null`。失敗注入方式由 0b 決定。

8. **既有行為零改變**
   - 下列既有測試**不修改**即全綠：`test/ui/layout_inspect/` 下的 `layout_inspect_overlay_test.dart`（4 個 `testWidgets`）、`layout_inspect_drag_aim_test.dart`（12 個）、`gap_ruler_overlay_test.dart`（3 個）、`gap_ruler_painter_test.dart`、`gap_ruler_geometry_test.dart`、`layout_probe_test.dart`，以及 `test/utils/layout_formatters_test.dart`。
   - 特別注意：drag-aim 測試在單次 `pump()` 之後就立刻查找藍框 `DecoratedBox` 並比對卡片全部文字（例如 `layout_inspect_drag_aim_test.dart:93-109`、`:124-129`）。取色機制不能讓這些斷言在該時間點失效。
   - 空狀態提示 `Tap a widget to inspect`（`layout_inspect_overlay.dart:440`）原文不變。
   - 點擊、拖曳瞄準、放大鏡、標尺、父鏈切換的既有行為都不變。

9. **平台與 build mode**
   - debug、profile、release 都可用：不使用僅在 `assert` 內生效或以 `kDebugMode` 控制的 API。注意 `RenderObject.debugLayer` 在 release 恆為 `null`（SDK `rendering/object.dart:3184-3191`）。
   - Web：是否啟用由 0b 實測後決定（§6 Q3）。不啟用時行為等同 AC7，不顯示色碼列。

10. **零副作用**（沿用 §P31／§P37）
    - 取色不寫入任何 buffer、不動 `revision`、不進 `mergedTimeline`、不產生 log 或 navigator 事件。
    - 不新增依賴（`pubspec.yaml` 的 `dependencies` 不變），不新增公開 API（`lib/flutter_inspector_kit.dart` 的匯出清單不變）。

11. **測試與靜態分析**
    - 新增 widget test 覆蓋 AC1–AC7。
    - `flutter test` 全綠。`flutter analyze lib/ test/` 不超出既有 7 個 info。

12. **實機手測**（brief 成功標準 2）
    - 用 `example/` 在至少一台實機手測一次：點純色區塊，與已知色碼比對；拖曳放開取色；標尺模式取色；複製後貼出確認含 `color:` 行；點 WebView demo（`example/lib/demos/webview_demo.dart`）確認不顯示錯誤的色碼。

13. **文件同步**
    - `CHANGELOG.md` 條目延到發版時寫入，因為 `test/version_test.dart:77` 要求頂端標題等於 pubspec 版號（沿用 2026-11-01 裁決）。
    - 同步更新 `README.md` 的 Inspect layout 段落（`:133-139`）、`docs/architecture/overview.md:71` 的 `LayoutInspectOverlay` 描述，以及 `docs/architecture/file-reference.md` 中受影響檔案的列（`layout_inspect_overlay.dart` `:98`、`layout_formatters.dart` `:72`；若改到 `layout_probe.dart` 則含 `:99`）。
    - `docs/architecture/data-flow.md` 沒有 layout inspect 流程，不需更新。

## 4. 範圍邊界 (Scope & Boundaries)

### 包含

- 點擊與拖曳結束時，取結算點的實際顯示像素色。
- 資訊卡的色塊加 `color: #RRGGBB` 列，以及複製、分享文字中的 `color:` 行。
- 一般檢視與標尺模式都適用。標尺模式下取的是當前點。
- 排除 inspector 自身繪製（藍框、標尺、資訊卡、放大鏡、kit FAB）。
- 失敗與不支援時靜默隱藏該列（含平台視圖區域）。
- 對應的 widget test、README 與架構文件同步。

### 不做（使用者已確認）

- 拖曳中即時更新色碼：只在點擊或放開時取一次。
- 取色歷史。
- WCAG 對比度計算。
- 標尺模式下同時顯示 A、B 兩點的色碼。
- 寫入時間軸或 log。
- 色碼格式設定（例如 RGB、HSL、含 alpha、小寫）。

### 不做（沿用或由決策推得）

- **讀取元件宣告的顏色**（例如 `ColoredBox.color`、`BoxDecoration.color`）：已決定取實際顯示像素。
- **取色中的 loading 指示**：取色未完成就是「暫無色碼」，等同 AC7 的不顯示。
- **錯誤訊息或重試按鈕**：brief 明確要求失敗時不提示。
- **空狀態下顯示色碼**：探測結果為空時，`_probeAt` 會清空 `_chain`（`:118-125`），卡片回到空狀態提示。此時不顯示色碼列，以維持 AC8 的提示字串不變。
- **在放大鏡內顯示色碼**：沿用 §P37「放大鏡內不顯示文字」（touch-loupe 規格 :94）。
- **多點平均或區域取樣**：見 §6 Q2。
- **平台視圖內容的真實取色**：技術上不可行（文首 ⚠️），只保證不顯示錯誤的顏色。
- **§P31／§P37 已排除的項目仍排除**：整棵樹瀏覽、修改屬性、同一目標在畫面變動後自動刷新。

## 5. 相依與風險

### 相依

- **擷取 API**（都在 SDK 內，不需新依賴）：
  - `OffsetLayer.toImage(Rect bounds, {pixelRatio})`（SDK `rendering/layer.dart:1546`）與 `toImageSync`（`:1580`）。`bounds` 可以任意指定，所以能只擷取結算點附近極小的範圍。
  - `RenderRepaintBoundary.toImage`（`rendering/proxy_box.dart:3552`）。
  - `dart:ui` 的 `Image.toByteData`。
- **既有探測**：`probeLayoutAt`（`layout_probe.dart:75-145`）與 `LayoutProbeShield`（`:53-68`）繼續作為探測真相。取色是附加在結算點上的資訊，不改變探測結果。
- **不是公開 API 變更**：`LayoutInspectOverlay` 沒有從 `lib/flutter_inspector_kit.dart` 匯出（匯出清單 `:1-15` 不含 `layout_inspect`），調整其內部或 `show()` 參數都不算。

### 風險

- **R1 inspector 和 App 在同一棵 layer tree 上**：選取層是 root `Overlay` 中的一個 `OverlayEntry`（`lib/src/ui/dashboard/dashboard_modal.dart:254-257`），和 App 的 route 共用同一個 theater。`overlay.dart` 沒有為 entry 包 `RepaintBoundary`。因此沒辦法在畫面不變的前提下，直接拿到「扣掉 inspector 的整個畫面」。見 §6 Q1。
- **R2 平台視圖與外部 texture**：見文首 ⚠️。`Texture`（video_player、camera）是否進得了擷取結果尚未實查，0b 應一併確認（§6 Q6）。
- **R3 競態與過期結果**：擷取與讀像素都是非同步。既有 `_onCopy` 用 `listEquals(_chain, currentChain)` 判斷結果是否過期（`:181`），但這招對取色不夠：同一個元件上點兩個不同位置，chain 相等，顏色卻可能不同（漸層、文字、圖片）。見 §6 Q4。
- **R4 `LayoutLevel` 相等性被污染**：`LayoutLevel` 的 `==` 與 `hashCode`（`layout_probe.dart:34-46`）被標尺用來判斷「是不是同一個元件」（`layout_inspect_overlay.dart:161`、`:215`；`gap_ruler_overlay_test.dart:250`「tapping reference widget A again does not self-measure」）。如果把色碼放進 `LayoutLevel`，同一元件點在不同位置就會變成「不相等」，自我量測防護會失效。見 §6 Q5。
- **R5 未捕獲例外污染時間軸**：見 AC7。
- **R6 Web 分支不在預設測試涵蓋範圍**：`flutter test` 跑在 VM 上，`kIsWeb` 恆為 `false`。同 touch-loupe 規格 R5。
- **R7 測試的非同步環境**：`testWidgets` 跑在 FakeAsync 下，`toImage`／`toByteData` 的 future 必須用 `tester.runAsync` 才會完成（本 repo 先例：`test/ui/tabs/network_detail_view_test.dart:795-802`）。好處是既有測試只 `pump()`，取色不會完成，卡片文字不會多出色碼列，AC8 比較容易成立。但 0b 須確認未完成的擷取不會讓測試結束時報 pending 錯誤。
- **R8 擷取成本**：全螢幕擷取會依實體解析度配置整張 RGBA 影像，例如 1080×2400 約 10 MB。`OffsetLayer.toImage` 的 `bounds` 可以縮到結算點附近的 1×1 實體像素。
- **R9 brief 敘述的偏差**：brief 寫「結算路徑 `_probeAt`」，但 `_probeAt` 也是拖曳中的即時探測路徑（§1）。如果把取色掛在 `_probeAt` 上，會直接違反「拖曳中不即時更新」。

## 6. 留給 STAGE 0b 的技術開放問題（附實查事實與傾向）

Q1–Q5 來自需求 brief；Q6–Q9 是撰寫本規格時實查新發現的。以下只列事實與傾向，不在規格中定案。

**Q1. 擷取方式：如何排除 inspector 的 overlay**

實查事實：

- 唯一能涵蓋「所有 route、barrier、host 自己的 overlay entry」的是 root layer：`RenderView` 是 repaint boundary（SDK `rendering/view.dart:315`），root 是一個 `TransformLayer`（`:267-273`）。
- `RenderObject.layer` 標註 `@protected`（`rendering/object.dart:3158-3162`），`debugLayer` 在 release 是 `null`（`:3184-3191`）。
- 本機實測（Flutter 3.47.1 analyzer，在 scratchpad 建臨時套件驗證，已刪除）：在 `RenderProxyBox` 子類別的 instance member 內讀取另一個 `RenderView` 實例的 `.layer`，**沒有任何診斷**；在頂層函式讀取則報 `invalid_use_of_protected_member` warning。既有的 `_RenderLayoutProbeShield extends RenderProxyBox`（`layout_probe.dart:62`）就是合法的存取位置。
- route 層級：`_ModalScope` 對每個 route 包了兩層 `RepaintBoundary`（SDK `widgets/routes.dart:1203`、`:1228`），可以用公開的 `RenderRepaintBoundary.toImage`，而且天然不含 inspector。
- `LayoutProbeShield` 的 `_probing` 旗標（`layout_probe.dart:49`、`:65`）是「探測期間讓 kit UI 透明」的既有先例。inspector 選取層與 FAB 都包在 shield 內（`layout_inspect_overlay.dart:37`、`inspector_fab.dart:29`）。

選項：

- (A) 擷取 root layer，期間讓 inspector（shield 子樹）在一幀內不繪製，擷取完再恢復。保真度最高，排除在結構上成立。代價是 inspector 會消失一幀（可見閃爍）並多一次 frame。此外，隱藏只能做在 paint 層級，不能從 widget tree 移除元件，否則 AC8 的 drag-aim 斷言會失效。
- (B) 擷取命中路徑上最外層的 route `RepaintBoundary`。不閃爍、只用公開 API。但會漏掉該 boundary 以外的東西：下層 route、modal barrier 的半透明遮罩、host 的 overlay entry、boundary 以上祖先的 `Opacity`／`ColorFiltered`。在 dialog 遮罩上會**靜默取到錯色**。

傾向 (A)。核心語意是「畫面上實際顯示的顏色」，(B) 的錯誤是靜默的，比一幀閃爍更糟。請使用者在 0b 裁決是否接受閃爍。

**Q2. 邏輯座標與實體像素對應、抗鋸齒混色**

實查事實：root `TransformLayer` 的 transform 由 `configuration.toMatrix()` 產生，已包含 DPR（`view.dart:269-270`），所以對 root layer 呼叫 `toImage` 時，`bounds` 與 `pixelRatio` 的單位要另外換算。巢狀 `Overlay` 有位移時，選取層用 `_stackOffset` 校正（`layout_inspect_overlay.dart:84`、`:89`、`:94`），但結算點本身已經是 global 座標。

傾向：取包含結算點的那**一個實體像素**，不做平均。抗鋸齒邊緣的混色本來就是畫面上實際顯示的顏色，照實回報即可；平均反而會產生畫面上不存在的顏色。小數 DPR（例如 2.625）的取整規則請在 0b 定案並寫進測試。

**Q3. Web（CanvasKit／skwasm）與 release build 是否可用**

實查事實：

- Web 的 `Scene.toImage`／`toImageSync` 有實作，會先把 layer tree 攤平成 picture 再轉圖（`flutter_web_sdk/lib/_engine/engine/layer/layer_scene_builder.dart:23-32`）。CanvasKit 與 skwasm 都用 `LayerSceneBuilder`（`canvaskit/renderer.dart:150`、`skwasm/skwasm_impl/renderer.dart:168`）。
- Web 上平台視圖不會進入擷取結果（文首 ⚠️）。
- release：`OffsetLayer.toImage`、`Scene.toImage`、`Image.toByteData` 都不是 debug-only，只有 `debugLayer` 不能用。

傾向：所有平台走同一條路徑。Web 在 0b 以實機（`flutter run -d chrome`）驗證一次。若不可行，比照 `showLoupe ?? !kIsWeb` 的先例（`layout_inspect_overlay.dart:41`）加一個內部開關，讓測試可以注入。

**Q4. 非同步取色與結算的競態**

實查事實：見 R3。`_onCopy` 的 chain 比對（`:178-181`）不足以判斷取色結果是否過期。

傾向：每次結算遞增一個世代計數，非同步完成時只接受世代相符的結果，同時檢查 `mounted`。新的點開始時（點擊、拖曳成立）就清掉舊色碼，以滿足 AC2。

**Q5. 色碼放在 `LayoutLevel` 還是獨立狀態**

實查事實：見 R4。`LayoutLevel` 的文件註解定義它是「one `RenderBox` level」的快照（`layout_probe.dart:4-7`），色碼是點的屬性。

傾向：作為 `_LayoutInspectLayerState` 的獨立狀態（例如 `Color?`），不放進 `LayoutLevel`，也不改 `probeLayoutAt`。

**Q6. 平台視圖、透明與半透明像素的判定**（新增）

實查事實：平台視圖的 render 型別都是公開的：`PlatformViewRenderBox`（SDK `rendering/platform_view.dart:681`，Android 與 Web 的 surface 使用）、`RenderAndroidView`（`:76`）、`RenderDarwinPlatformView` 與其子類 `RenderUiKitView`、`RenderAppKitView`（`:292`、`:427`、`:477`）、`TextureBox`（`rendering/texture.dart:38`）。

傾向：命中路徑含平台視圖的 render box 時視為失敗。擷取到 alpha = 0（場景在該點沒有內容）也視為失敗。0 < alpha < 255 怎麼處理（忽略 alpha，或視為失敗）請 0b 裁決。無論哪種，輸出都不含 alpha。`TextureBox` 是否可擷取請實機確認。

**Q7. 測試策略**（新增）

實查事實：見 R7。Clipboard mock 先例在 `layout_inspect_overlay_test.dart:13-28`。

傾向：
- 新測試以 `tester.runAsync` 驅動擷取完成。
- 失敗注入與競態測試需要一個內部注入點（例如可替換的取色函式）。`LayoutInspectOverlay` 不對外匯出，加內部參數不算公開 API 變更（先例：`mayBeObfuscated`、`showLoupe`）。
- 0b 應先排一個 spike 任務，實測 Q1 的 (A) 在 `flutter test` 與實機上都取得到正確像素，再展開其餘任務。

**Q8. 匯出文字中 `color:` 行的位置**（新增）

實查事實：`formatLayoutChain(chain, {required mayBeObfuscated})`（`layout_formatters.dart:26-29`）有逐字比對測試（`layout_formatters_test.dart:30-77`）。標尺模式的匯出是 `chainText + '\n\n' + measurementText`（`layout_inspect_overlay.dart:161-171`）。

傾向：在 `_buildExportText` 組裝，不改 `formatLayoutChain` 的簽章與輸出。色碼是點的屬性，不屬於 chain 中的任何一層。確切位置（標題之後，或全文最後）由 0b 決定，並寫入測試。

**Q9. 拖曳中資訊卡的色碼列**（新增）

背景：拖曳中卡片會即時跟著新目標更新（§P37 Q6 (A)），色碼卻不更新。

選項：
- (A) 拖曳成立就隱藏色碼列，放開後顯示新點的色碼。
- (B) 保留上一個點的色碼並加上標註。

(B) 會讓色碼與卡片上的目標不一致，也違反 AC2。傾向 (A)。

## 7. 執行方式（STAGE 0b 之後）

本規格只定義 What & Why。實作計畫將由 STAGE 0b 產出於 `docs/plans/2026-11-15-layout-inspect-color-sampling.md`。

寫入路徑集中在 `layout_inspect_overlay.dart`、可能的 `layout_probe.dart`，以及兩者的測試檔，任務之間高度耦合。預期採 subagent-driven 序列執行，第一個任務是 Q1／Q3 的 spike 實測；不適合拆成 parallel session。
