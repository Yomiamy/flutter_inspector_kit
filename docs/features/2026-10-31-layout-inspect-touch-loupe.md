# 功能規格：Inspect layout 拖曳瞄準與觸控放大鏡 (Drag-to-Aim & Touch Loupe)（§P37）

- **日期**：2026-10-31
- **來源**：[`docs/brainstorm/2026-11-15-features-brainstorm.md`](../brainstorm/2026-11-15-features-brainstorm.md) §P37（:2118-2131），延伸 §P31（:1996-2031，規格見 [`2026-10-17-tap-to-inspect-layout.md`](2026-10-17-tap-to-inspect-layout.md)）。需求 brief 已於 2026-10-31 與使用者逐項確認。
- **Effort**：原估 Low；因 §P37 假設的拖曳探測實際不存在、需一併新增，上修為 **Low~Medium** ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. 背景與問題 (What & Why)

§P31 的 `Inspect layout` 模式是「單點即查」：手指放開時以該點做一次 hit test，框出命中的 `RenderBox` 並顯示資訊卡。對 16×16 icon、幾 px 寬的 padding 這類小元件，這個互動有個結構性問題：**手指按下時正好擋住目標，放開後看到藍框才知道命中了誰**。點偏了只能再點一次、再看一次，反覆試到對為止。

實查現況：

- 攔截層的手勢只有 `onTapUp`（`lib/src/ui/layout_inspect/layout_inspect_overlay.dart:130-136`），探測與結算只在放開那一刻發生一次（`_onTapUp`，`:63-74`）。按下到放開之間沒有任何回饋。
- 手指移動超過 tap slop 時，tap 會被手勢系統取消（SDK `gestures/recognizer.dart:724-736`），這次觸控什麼都不發生。
- `lib/` 內沒有任何 `RawMagnifier` / `Magnifier` 使用（grep 零命中）。
- **§P37 的前提不成立**：brainstorm（:2123）寫的是「在長按拖曳探測時展示放大視窗」，但現有程式碼沒有長按、也沒有拖曳探測。放大鏡只有在「手指按著、探測點持續更新」時才有意義，所以本項必須**同時新增拖曳瞄準模式**，放大鏡掛在它上面。

**本功能**：在 `Inspect layout` 模式下新增「按住拖曳瞄準」。手指按下並移動後進入瞄準狀態，手指旁出現放大鏡，以十字準星標出實際探測點；藍框即時跟著命中的 `RenderBox` 走；放開手指即以該點結算，結果與在同一點單點完全相同。單點行為完全不變。

互動採 **pan（按住拖曳）**，不用長按：pan 必須移動超過 slop 才成立，不會和 tap 搶同一個觸控；長按則會在「按住不動想看清楚」時與 tap 的時間門檻糾纏。

## 2. 使用者故事 (User Stories)

- 身為 QA，我在實機想查一個 16×16 的 icon。我在它附近按下、往它拖，看著放大鏡裡的十字準星落到 icon 上、藍框剛好框住 icon，再放開——資訊卡直接顯示這個 icon 的 size 與 constraints，不用反覆點。
- 身為開發者，我想確認一段細 padding 到底屬於 `Padding` 還是它的 child。我拖著手指跨過邊界，看藍框在兩個 `RenderBox` 之間切換，在放開前就確定自己要的是哪一個。
- 身為已經習慣單點的 QA，我照舊點一下就查，不會冒出放大鏡、不會多任何延遲。
- 身為在 release 版實機回報 bug 的 QA，拖曳瞄準與放大鏡和單點一樣在 release build 可用。

## 3. 驗收條件 (Acceptance Criteria)

以下「探測點」指傳給 `probeLayoutAt(anchor, globalPosition)`（`lib/src/ui/layout_inspect/layout_probe.dart:61`）的 `globalPosition`，即手指當下的 global 座標。

1. **進入拖曳瞄準**
   - 在攔截層（資訊卡以外的區域）按下並移動超過手勢 slop 後進入瞄準狀態；之後每次指標移動都以當下手指位置呼叫既有的 `probeLayoutAt`，**不另寫第二套探測邏輯**。
   - 從資訊卡上開始的拖曳不進入瞄準；資訊卡各按鈕行為不變。
   - 驗證：widget test 以 `tester.startGesture` + `moveTo` 模擬拖曳，斷言瞄準狀態成立（放大鏡出現，見 AC2）。

2. **放大鏡**（非 Web 平台）
   - 瞄準期間顯示以 Flutter 內建 `RawMagnifier` 實作的放大鏡，倍率與直徑為寫死的 `const` 常數。
   - **不被手指遮擋**：放大鏡的範圍（rect）不包含探測點。
   - **十字準星對位**：放大鏡中央畫十字準星；準星所對應的螢幕座標（放大鏡中心 + `focalPointOffset`）**恰等於**探測點。手指靠近螢幕邊緣、放大鏡被 clamp 時此等式仍須成立。
   - **不出界**：手指位於螢幕四角與四邊時，放大鏡完整落在螢幕範圍內；手指上方的空間若落在頂部 safe area（狀態列、瀏海）內，放大鏡改放到手指下方。（2026-10-31 STAGE 0b 審查補入）
   - **不干擾探測與手勢**：放大鏡不出現在 `probeLayoutAt` 的命中路徑中，也不中斷進行中的拖曳。
   - 拖曳結束（放開，或已成立的拖曳被系統取消）後放大鏡消失；單點全程不出現放大鏡。
   - 驗證：widget test 斷言 `find.byType(RawMagnifier)` 在拖曳中為一個、放開後與單點時為零；以放大鏡 rect 與 `focalPointOffset` 計算準星座標並與探測點比對；在四角各做一次拖曳斷言 rect 不出界。

3. **藍框即時跟隨**
   - 每次移動後，藍框等於當下探測點命中路徑上第一個 `RenderBox` 的 rect；手指從元件 A 移到元件 B 時，藍框隨之從 A 切到 B。
   - 每次探測都把層級重設到目標本身（等同新的單點，`_index = 0`）。
   - 探測結果為空時維持上一個結果，與單點的 `hit.isEmpty` 早退一致（`layout_inspect_overlay.dart:67`）。
   - 驗證：widget test 拖曳跨過兩個已知 rect 的元件，逐段斷言藍框 rect。

4. **放開即結算，結果等同單點**
   - 放開手指後的父鏈、目前層級、藍框與資訊卡內容（widget／render 型別名、size、constraints、offset、`i / N`），與「在同一最終位置單點一次」**完全相同**。
   - 結算後停留在選取模式，可照常切換父鏈、複製、分享、再次點選或拖曳。
   - 驗證：widget test 先拖曳到 P 放開並記錄卡片文字與藍框 rect，再於 P 單點一次，兩者逐欄相等。

5. **單點零改變**
   - 既有 `test/ui/layout_inspect/layout_inspect_overlay_test.dart`（4 個 `testWidgets`）與 `layout_probe_test.dart` **不修改**即全綠。
   - 空狀態提示字串 `Tap a widget to inspect`（`layout_inspect_overlay.dart:212`）原文不變——既有測試以精確字串斷言（`layout_inspect_overlay_test.dart:76`、`:199`、`:221`）。
   - 位移未超過 slop 的觸控仍走單點路徑，結果與現行行為一致。

6. **平台與 build mode**
   - debug／profile／release 皆可用：不使用任何僅在 `assert` 內生效或以 `kDebugMode` 控制的 API（同 §P31）。
   - Web（`kIsWeb`）：不建立 `RawMagnifier`；拖曳瞄準、藍框即時跟隨、放開結算照常運作。
   - 驗證：非 Web 行為由 widget test 覆蓋；Web 分支的驗證方式由 STAGE 0b 決定（見 §6 Q9）。

7. **零副作用**（沿用 §P31 驗收條件 8）
   - 拖曳中與結算時不寫入任何 buffer、不動 `revision`、不進 `mergedTimeline`、不產生 log 或 navigator 事件。
   - 不新增依賴（`pubspec.yaml` 的 `dependencies` 不變）；不新增公開 API（`lib/flutter_inspector_kit.dart` 匯出清單不變）。

8. **測試與靜態分析**
   - 新增 widget test 覆蓋 AC1–AC4。
   - `flutter test` 全綠；`flutter analyze lib/ test/` 不超出既有 7 個 info。

9. **文件同步**
   - `CHANGELOG.md` 條目延至發版時寫入（`test/version_test.dart` 要求頂端標題等於 pubspec 版號，2026-11-01 裁決）；`README.md:135` 的 Inspect layout 說明補上拖曳瞄準；`docs/architecture/overview.md:69` 與 `docs/architecture/file-reference.md:93` 的 `LayoutInspectOverlay` 描述同步更新。

## 4. 範圍邊界 (Scope & Boundaries)

### 包含

- `_LayoutInspectLayer` 手勢層新增拖曳瞄準狀態（`layout_inspect_overlay.dart:121-170`）。
- 放大鏡與十字準星、藍框即時跟隨、放開結算與單點共用同一條結算路徑。
- Web 平台不顯示放大鏡的條件分支。
- 對應的 widget test、CHANGELOG、README 與架構文件同步。

### 不做（使用者已確認）

- 可調倍率、可調直徑或任何放大鏡設定項。
- 取色器。
- 放大鏡內顯示座標、尺寸或任何文字。
- §P36 雙元件間距標尺（另案）。
- 拖曳中寫入時間軸或 log。

### 不做（沿用或由決策推得）

- **長按觸發**：已決定採 pan。
- **滑鼠 hover 瞄準**：滑鼠不是主要場景；滑鼠按住拖曳時依 SDK 預設行為運作，不另做調整。
- **多指觸控的特殊處理**：沿用 SDK 預設。
- **放大鏡進出場動畫**（如 `MagnifierController`）與觸覺回饋（haptics）。
- **選取模式中隱藏 inspector FAB**：見 §5 R2，接受現況。
- **§P31 已排除的項目仍排除**：整棵樹瀏覽、修改屬性、屬性白名單。
- **釐清「即時更新」**：§P31 排除的是「同一個目標在畫面變動後自動刷新」，本項仍不做。拖曳中的藍框更新是「依手指新位置重新探測」，每次探測照樣產生不可變的 `LayoutLevel` 快照（`layout_probe.dart:8-33`），不持有 render object，與 §P31 的快照語意一致。

## 5. 相依與風險

### 相依

- **`RawMagnifier`**（`package:flutter/widgets.dart`，Flutter 3.7 起提供）。本機 SDK 3.47.1 已核對建構式：`RawMagnifier({child, decoration, clipBehavior, focalPointOffset, magnificationScale, required size})`（SDK `widgets/magnifier.dart:458-466`）；`child` 的官方說明即為「tinting 或畫 crosshair-like UI」（`:468-471`），十字準星直接用 `child` 實作，不需另行疊層。
- **SDK 下限**：`pubspec.yaml:15` 宣告 `flutter: ">=3.10.0"`，但 `pubspec.yaml:14` 的 `sdk: ^3.10.1`（Dart）才是實際的有效下限（Dart 3.10 隨 Flutter 3.38 系列發佈，0b 如需引用請再查證）。兩者都高於 3.7，`RawMagnifier` 可用性無虞。
- **既有探測**：`probeLayoutAt`（`layout_probe.dart:61-131`）與 `LayoutProbeShield`（`:39-54`）**原樣沿用、不修改**。整個選取模式 overlay 已被 `LayoutProbeShield` 包住（`layout_inspect_overlay.dart:23`），放在其內的放大鏡天然對探測透明。
- **pan 手勢先例**：`InspectorFab` 已用 `GestureDetector.onPanUpdate` 實作拖曳（`lib/src/ui/widgets/inspector_fab.dart:31`）。
- `LayoutInspectOverlay` 未從 `lib/flutter_inspector_kit.dart` 匯出，調整其內部或 `show()` 參數不算公開 API 變更。

### 風險

- **R1 手勢競技場（tap 與 pan 同掛一個 `GestureDetector`）**：tap recognizer 在移動超過 `kTouchSlop`（18 logical px）時自行 reject（SDK `gestures/recognizer.dart:724-736`）；此時競技場只剩 pan，會被預設判勝（SDK `gestures/arena.dart:254-255`）。因此實際觸發門檻推論約為 18 px，而非 `PanGestureRecognizer` 自身的 `kPanSlop`（36 px，SDK `gestures/constants.dart:76`）。**0b 已實測證實**（Flutter 3.47.1：觸控位移 17 px 仍是 tap、19 px 即成立 pan）。門檻實際是「手勢 slop」：觸控預設 `kTouchSlop`，Android 會改用平台提供的 touchSlop（`DeviceGestureSettings`）；滑鼠約 2 px（實測 1.5 px 仍是 tap、2.5 px 即成立 pan），所以桌面上點擊時若手抖超過 2 px，放大鏡會閃一下，但放開後的結果與點擊相同。唯一可觀察的行為差異是：過去移動超過 slop 的「手滑點擊」會被取消、什麼都不發生，現在會變成拖曳並在最後瞄準點結算。這正是本功能要的行為，不算破壞 AC5 所指的單點。
- **R2 放大鏡取樣的是「繪製順序在它之前」的畫面**：`RawMagnifier` 以 `BackdropFilterLayer` 實作（SDK `widgets/magnifier.dart:536-537` 註解、`:601` 起的 `_RenderMagnification`）。這帶來三個後果：
  - 放大鏡必須畫在藍框之後，藍框才會出現在放大鏡裡。
  - inspector FAB 位於較低的 `OverlayEntry`，會出現在放大鏡畫面中，但探測會穿透它（`inspector_fab.dart:29` 的 `LayoutProbeShield`）。手指在 FAB 上時，放大鏡看到的是 FAB，藍框標的卻是 FAB 底下的 app 元件。這與 §P31 現行的「點 FAB 位置命中底下元件」語意一致，視為可接受。
  - 拖曳靠近資訊卡時，放大鏡中會看到資訊卡。
- **R3 拖曳中探測的成本**：`probeLayoutAt` 每次呼叫都完整遍歷 element tree 來反查 widget 名稱（`layout_probe.dart:101-116`）。拖曳時呼叫頻率等於指標事件頻率，在大型 app 上可能掉幀。見 §6 Q4。
- **R4 資訊卡上下翻轉**：卡片位置取決於 `_chain.first.rect.center.dy` 是否超過螢幕一半（`layout_inspect_overlay.dart:124-126`）。若拖曳中卡片跟著更新，手指跨過螢幕中線時卡片會上下跳。見 §6 Q6。
- **R5 Web 分支不在預設測試涵蓋範圍**：`flutter test` 在 VM 上執行，`kIsWeb` 恆為 `false`，「Web 不顯示放大鏡」無法被既有測試流程驗到。見 §6 Q9。
- **R6 結算座標的來源**：本機 SDK 的 `DragEndDetails.globalPosition` 會帶入最後位置（SDK `gestures/monodrag.dart:895` 等），但其預設值為 `Offset.zero`（`gestures/drag_details.dart:212`），且不保證在宣告的版本下限內都存在。見 §6 Q5。
- **R7 文件漂移**：brainstorm §P37（:2123）的前提「長按拖曳探測」與實況不符。STAGE 4 回寫 brainstorm 狀態時一併修正描述。

## 6. 留給 STAGE 0b 的設計開放問題（附建議）

Q1–Q5 來自需求 brief；Q6–Q9 是撰寫本規格時實查新發現的問題。

**Q1. 放大鏡相對手指的偏移與螢幕邊緣 clamp**
建議：預設放在手指正上方，下緣與探測點保持足以避開指腹的距離（約 32 logical px）。上方空間不足（放大鏡頂端會進入頂部 safe area）時翻到手指下方；水平方向 clamp 在螢幕範圍內。clamp 之後放大鏡中心不再對準手指，所以 `focalPointOffset` 必須由「探測點減去實際放大鏡中心」算出，不能寫死成常數，否則 AC2 的準星對位會在邊緣失效。

**Q2. 倍率與直徑**
建議：倍率 `2.0`，直徑 `96` logical px，可看到實際 48×48 的範圍，正好是 Material 最小觸控目標，16×16 icon 連同周邊脈絡都放得下。§P37 原提的 80 px 也可行，0b 擇一寫成常數即可。

**Q3. 放大鏡如何不攔截手勢**
實查事實：
- 探測端已由 `LayoutProbeShield` 處理。整個 overlay 都在 shield 內（`layout_inspect_overlay.dart:23`），放大鏡不會出現在 `probeLayoutAt` 的命中路徑中，不需要另外處理。
- 手勢端：Flutter 在 PointerDown 時就決定該指標的 hit test 路徑。放大鏡在 pan 成立後才出現，無法搶走進行中拖曳的 move／up 事件。
- `RawMagnifier` 內部只對裝飾層包了 `IgnorePointer`（SDK `widgets/magnifier.dart:539`），放大鏡本體（`_RenderMagnification`，一個 `RenderProxyBox`）仍可被命中。所以只有「第二根手指剛好按在放大鏡上」會被它擋住。

§P37 寫的「強制包 `IgnorePointer` 才能讓 LayoutProbe 平滑命中」理由不成立。但這個結論本身無害，而且只要一行，與藍框現有的寫法一致（`layout_inspect_overlay.dart:140`）。建議照包，當作多指觸控的保險。

**Q4. 拖曳中重跑 `probeLayoutAt` 是否需要節流**
建議：先不節流，直接重用（YAGNI）。實機 profile 確認掉幀後，再升級為「只記最新座標，每個 frame 最多探測一次」。不建議把探測拆成「拖曳中只做 hit test、放開才反查名稱」兩條路徑：那會產生第二條結算路徑，直接威脅 AC4 的等價性。

**Q5. pan 結束與 tap 共用同一條結算路徑**
建議：把 `_onTapUp` 的主體（`layout_inspect_overlay.dart:63-74`）抽成 `_probeAt(Offset globalPosition)`，由 `onTapUp`、`onPanStart`、`onPanUpdate`、`onPanEnd` 共同呼叫，AC4 就由結構保證成立。`onPanEnd` 使用最後一次 update 記下的座標，不依賴 `DragEndDetails.globalPosition`（R6）。`onPanStart` 也探測一次，藍框在拖曳一成立時就出現。

**Q6. 拖曳中資訊卡怎麼顯示**（新增）
選項：
- (A) 跟著即時更新：走 Q5 的共用路徑就自然做到，零額外程式碼。
- (B) 拖曳中隱藏。
- (C) 凍結為拖曳前的內容。

建議 (A)。卡片會依 R4 上下翻轉，但翻轉規則本來就是「讓卡片避開目標」，拖曳時同樣適用。放開前還能先看到名稱與尺寸，直接加強「放開前就確定目標」的價值。

**Q7. 系統取消拖曳時的處理**（新增）
~~建議接 `onPanCancel`~~：0b 審查查證後更正。SDK 在已成立的拖曳遇到 PointerCancel 時送出的是 `onPanEnd`（`gestures/monodrag.dart:724-726`、`:753-765` 的 `accepted` 分支）；`onPanCancel` 只在 pan **尚未成立**時觸發，也就是每次普通單點都會觸發。定案：不接 `onPanCancel`，系統取消等同在最後瞄準點放開，結果同樣與單點相同。

**Q8. 可發現性**（新增）
AC5 要求提示字串 `Tap a widget to inspect` 一字不改，因此不能直接改成「Tap or drag…」。選項：
- (A) 只寫在 README／CHANGELOG。
- (B) 在提示下方加一行獨立的次要文字（例如 `Drag to aim with a magnifier`）。另起一個 `Text` 不影響既有的 `find.text` 精確比對。

QA 不讀 README，所以 (B) 對本功能的實際價值較高。但這不在 brief 的成功標準內，請使用者在 0b 裁決。

**Q9. Web 分支的可測性**（新增）
建議沿用 `mayBeObfuscated ?? !kDebugMode` 的既有先例（`layout_inspect_overlay.dart:19`、`:26`；測試直接傳參，見 `layout_inspect_overlay_test.dart:194`），讓 `show()` 多一個內部具名參數（例如 `showLoupe`），預設為 `!kIsWeb`，測試就能以 `false` 驗證 Web 行為。`LayoutInspectOverlay` 未對外匯出，這不是公開 API 變更。另一個選擇是接受「只以 code review 驗證 `kIsWeb` 分支」。

## 7. 執行方式（STAGE 0b 之後）

本規格只定義 What & Why。實作計畫將由 STAGE 0b 產出於 `docs/plans/2026-10-31-layout-inspect-touch-loupe.md`。寫入路徑集中在 `layout_inspect_overlay.dart` 與其測試檔，任務之間高度耦合，預期採 subagent-driven 序列執行；不適合拆成 parallel session。
