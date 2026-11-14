# 實作計畫：Inspect layout 拖曳瞄準與觸控放大鏡（§P37）

> **給執行 agent**：依 `subagent-driven-development`（建議）或 `executing-plans` 逐任務執行；步驟以 `- [ ]` 追蹤。執行者必須同時讀本計畫與規格。

- **日期**：2026-10-31（plan-verifier 初審 REVISE 後第 1 次修正）
- **規格**：[`docs/features/2026-10-31-layout-inspect-touch-loupe.md`](../features/2026-10-31-layout-inspect-touch-loupe.md)（已經使用者確認；本次修正同步更正了 R1、Q1、Q7 與 AC2 的事實描述，見 §9）
- **來源**：`docs/brainstorm/2026-11-15-features-brainstorm.md` §P37
- **Effort**：Low~Medium ｜ **總任務數：4**（STAGE 2 起手執行 `wf-state.sh set <檔> total_tasks=4`）

**Goal**：在 `Inspect layout` 模式加入按住拖曳瞄準，搭配 `RawMagnifier` 放大鏡與十字準星；放開手指的結果與在同一點單點完全相同。

**Architecture**：在既有攔截層的同一個 `GestureDetector` 加上 `onPanStart`、`onPanUpdate`、`onPanEnd`，把 `_onTapUp` 的主體抽成 `_probeAt(Offset)`，讓 tap、拖曳中、放開（含系統取消）都走同一條探測／結算路徑。新增的狀態只有 `Offset? _aim`。放大鏡是 `Stack` 的最後一個子元件，只在 `_aim != null && showLoupe` 時建立。

**Tech Stack**：Flutter 內建 `GestureDetector`、`RawMagnifier`、`MagnifierDecoration`、`IgnorePointer`、`MediaQuery.sizeOf`／`paddingOf`。沒有新依賴。

**實際使用的 SDK：Flutter 3.47.1。** `.fvm/version` 寫的是 3.38.3，但它沒有生效：
- 這個檔案未納入版控（被 ignore），新的 worktree 裡不會有。
- `~/fvm/versions/` 只裝了 3.44.1 與 3.47.1，沒有 3.38.3；`.fvm/` 底下也沒有 `flutter_sdk` 連結。
- PATH 上的 `flutter` 是 `~/fvm/default`，指向 3.47.1；`.dart_tool/package_config.json` 的 `flutterVersion` 也是 `3.47.1`。

本計畫用到的 API（`RawMagnifier` 3.7+，`MediaQuery.sizeOf`／`paddingOf` 與 `FakeViewPadding` 3.10+）都早於 `pubspec.yaml` 的 Dart `^3.10.1` 下限，在 3.38 上同樣可用。

## Global Constraints

- 純 Dart。`pubspec.yaml` 的 `dependencies` 不變，不引入狀態管理庫。
- 不新增公開 API，`lib/flutter_inspector_kit.dart` 匯出清單不變。`LayoutInspectOverlay` 未匯出，`show()` 的新參數屬內部介面。
- 不碰 `InspectorRegistry`、`RingBuffer`、`revision`、`mergedTimeline`，不寫 log。
- 空狀態提示字串 `Tap a widget to inspect`（`layout_inspect_overlay.dart:212`）一字不改。
- `test/ui/layout_inspect/layout_inspect_overlay_test.dart` 與 `layout_probe_test.dart` 一行都不改。
- debug／profile／release 皆可用，不使用 `kDebugMode` 或 `assert` 才生效的 API。Web（`kIsWeb`）不建立 `RawMagnifier`。
- 放大鏡常數寫死：倍率 `2`、直徑 `96`、與指尖間距 `32`、十字線寬 `1`（logical px）。
- **不接 `onPanCancel`**：它在每次普通單點都會觸發（§1 Q7）。
- 程式風格依 `.claude/rules/flutter-styles.md`：禁用 `!`、加尾逗號、不寫 `_buildX()`、跑 `dart format`（**只格式化本次碰到的目錄**，見 Task 4）。
- 使用者文件（README、CHANGELOG、架構文件）只寫「超過手勢 slop」，不寫死 18px 或 `kTouchSlop`。
- `flutter analyze lib/ test/` 只能有既有的 7 個 info。
- 測試指令一律加 `rtk`，例如 `rtk flutter test test/ui/layout_inspect/`。

---

## 1. 開放問題定案（規格 §6 Q1–Q9）

每題的定案都已在 scratchpad 原型上驗證，證據見 §7。

| # | 定案 | 理由 |
|:--|:--|:--|
| Q1 偏移與 clamp | 放大鏡預設放在手指**正上方**，下緣與探測點相距 `_loupeGap = 32`。**只有在放大鏡頂端仍位於頂部 safe area 之下時才放上方**（`above - radius >= MediaQuery.paddingOf(context).top`），否則翻到手指下方。水平方向 clamp 到 `[r, width - r]`。`focalPointOffset = aim - center`，由實際中心算出。 | 垂直方向至少隔 32 px，所以永遠不蓋住探測點。納入 safe area 後，放大鏡不會藏到狀態列或瀏海底下（審查 N4）。clamp 後若沿用固定 offset，準星會在邊緣錯位，所以 offset 必須由實際中心反推。四角、中心與 safe area 翻轉都有測試。 |
| Q2 倍率／直徑 | 倍率 `2`、直徑 `96`。 | 放大鏡內看到實際 48×48 的範圍，正好是 Material 最小觸控目標。像素實測確認確實是 2 倍放大（§7-6）。 |
| Q3 不攔截手勢 | 外面包一層 `IgnorePointer`。 | 探測端已由 `LayoutProbeShield` 處理（`:23`）；手勢路由在 PointerDown 時就定了，放大鏡搶不到進行中的拖曳。`RawMagnifier` 的鏡頭本身沒有 `IgnorePointer`（SDK `magnifier.dart:539` 只包了裝飾層），第二根手指按上去會被接住。包一層只要一行，寫法也和藍框（`:140`）一致。 |
| Q4 節流 | 不節流。程式碼留 `shortcut:` 註解，寫明日後升級為「每個 frame 最多探測一次」。 | 目前沒有量測到問題（YAGNI）。拆成兩條探測路徑會威脅 AC4，所以不採用。 |
| Q5 共用結算 | 抽出 `_probeAt(Offset)`，由 `onTapUp`、`onPanStart`、`onPanUpdate` 呼叫；`onPanEnd` 以最後的 `_aim` 再呼叫一次。不使用 `DragEndDetails.globalPosition`。 | 詳見 §2。「最終位置」定義為**最後一次瞄準點**，也就是使用者在準星裡看到的點。 |
| Q6 拖曳中的資訊卡 | 即時更新。 | 走 `_probeAt` 自然就有，零額外程式碼；放開前就能確認名稱與尺寸。 |
| Q7 系統取消（**更正**） | **不接 `onPanCancel`。** 已成立的拖曳被系統取消時，SDK 送出的是 `onPanEnd`，等同在最後瞄準點放開。 | 原計畫讀錯了 SDK 語意（審查 B1）。`DragGestureRecognizer.didStopTrackingLastPointer`（SDK `gestures/monodrag.dart:753-765`）在 `accepted` 狀態走 `_checkEnd()`，PointerCancel 也走這條（`:724-726`）；只有在 `possible` 狀態（pan 尚未成立，也就是每次普通單點）才走 `_checkCancel()`。原本的 `_onPanCancel` 對拖曳毫無作用，還讓每次單點多一次 `setState`。已用 spike 實測證實（§7-2），並有永久測試覆蓋：拖曳中用第二指切到上一層，取消後回到 `1 / N`，證明確實經過 `_onPanEnd` 結算。 |
| Q8 可發現性 | **提示字串不改，只寫在 README 與 CHANGELOG**（維持現案，交使用者裁決）。 | 手指點偏時自然會滑一下修正，位移超過手勢 slop 就會進入瞄準，功能會在使用中被發現。在卡片上加字會增加 320dp 窄螢幕版面（既有測試 `:277-324`）的風險。 |
| Q9 Web 可測性 | `show()` 新增內部具名參數 `bool? showLoupe`，預設 `!kIsWeb`，沿用 `mayBeObfuscated ?? !kDebugMode` 的先例（維持現案，交使用者裁決）。 | VM 上跑測試時 `kIsWeb` 恆為 false，不參數化就測不到 Web 分支。`LayoutInspectOverlay` 未匯出，不是公開 API 變更。 |

**門檻實測**（§7-1）：
- **觸控**：位移 17 px 仍是 tap，19 px 即成立 pan。tap 在超過 touch slop 時退出，pan 便被預設判勝，所以實際門檻是 `kTouchSlop`，不是 `kPanSlop`（36）。Android 上這個 slop 會改用平台提供的 touchSlop（`DeviceGestureSettings`）。
- **滑鼠**：位移 1.5 px 仍是 tap，2.5 px 即成立 pan。桌面上點擊時若手抖超過約 2 px，放大鏡會閃一下，但放開後以最後瞄準點結算，結果與點擊相同（審查 N2）。
- 原計畫的 Task 1（spike gate）已刪除（審查 N1）。永久版本就是 Task 2 的兩支 `kTouchSlop ± 2` 測試，它們跟著全套測試跑，SDK 行為若改變會直接變紅。

---

## 2. 資料結構與手勢結算路徑

### 狀態（全部在 `_LayoutInspectLayerState`）

| 欄位 | 既有／新增 | 語意 | 由誰寫入 |
|:--|:--|:--|:--|
| `_chain`, `_index`, `_copied` | 既有 | 目前的父鏈快照、所在層級、複製回饋 | 只有 `_probeAt` 會整組覆寫；`_onParent`、`_onChild`、`_onCopy` 只動各自欄位，與現況相同 |
| `_aim : Offset?` | **新增** | 非 null 代表正在拖曳，值為目前的探測點 | `_aimAt` 設值；**只有** `_onPanEnd` 清成 null（放開與系統取消都走這裡） |

沒有新的 model，也不寫入 buffer。放大鏡顯示的條件是 `_aim != null && widget.showLoupe`。

### 手勢 → 結算

```
onTapUp(p)        ──────────────────────────────► _probeAt(p)
onPanStart(p)  ─► _aimAt(p) ─► _aim = p ─────────► _probeAt(p)
onPanUpdate(p) ─► _aimAt(p) ─► _aim = p ─────────► _probeAt(p)
onPanEnd       ─► aim = _aim; _aim = null ───────► _probeAt(aim)
  （放開，或已成立的拖曳被系統 PointerCancel；SDK monodrag.dart:753-765）
（不接 onPanCancel：它只在 pan 未成立、即每次普通單點時觸發）
```

### 為什麼 AC4 由結構保證

1. 放開時呼叫的就是單點那一個函式（`_probeAt`），輸入也相同（最後的瞄準點）。結算邏輯只有一份。
2. `_probeAt` 不讀 `_aim`，也不讀拖曳過程中的任何狀態；它會整組覆寫 `_chain`、`_index = 0`、`_copied = false`。所以拖曳途中發生的任何變化，都會在放開時被覆寫掉。
3. **測試真的能抓到「沒有結算」的情況**（審查 B2）：拖曳到 target 後、放開前，用**第二根手指**按 `Parent`，斷言出現 `2 / `。放開後必須回到 `1 / `，而且與「同樣先切到 `2 / ` 再單點 target」的結果逐欄相等。0b 已實測：刪掉結算那一行（`if (aim != null) _probeAt(aim);`）後，這支測試與系統取消那支都會變紅（§7-4）。

---

## 3. 方案 trade-off

| 方案 | 內容 | 結論 |
|:--|:--|:--|
| **A（採用）** | 在同一個 `GestureDetector` 加 `onPan*`，共用 `_probeAt`，放大鏡做成 `Stack` 最後一個子元件 | 程式碼最少，手勢競技場天然區分 tap 與 pan；放大鏡在 shield 內，自動對探測透明。 |
| B | 用 `MagnifierController` 加獨立的 `OverlayEntry` | 多一個 entry 的生命週期要管，還要另外包 shield；它提供的進出場動畫是規格排除的項目。不採用。 |
| C | 改用 `Listener` 處理原始指標事件 | 等於在手勢競技場之外重寫 tap 與 pan 的仲裁，直接威脅 AC5。不採用。 |
| D | 拖曳中改走輕量探測 | 會出現第二條探測路徑，AC4 不再由結構保證。不採用。 |

其他取捨：
- **卡片即時更新**：代價是跨過螢幕中線時卡片會翻轉。
- **包 `IgnorePointer`**：只對多指觸控有用，但成本一行。
- **`showLoupe` 參數**：多一個內部參數，換來 Web 分支能被自動化測試覆蓋。
- **safe area 翻轉**：多讀一個 `paddingOf`，換來放大鏡不藏到瀏海底下。

---

## 4. 檔案異動清單

| 檔案 | 動作 | 任務 |
|:--|:--:|:--|
| `lib/src/ui/layout_inspect/layout_inspect_overlay.dart` | 修改 | 1、2 |
| `test/ui/layout_inspect/layout_inspect_drag_aim_test.dart` | 新增 | 1、2 |
| `README.md`（功能表 :37、說明段 :135、:137） | 修改 | 3 |
| `CHANGELOG.md`（頂部新增 `## Unreleased`） | 修改 | 3 |
| `docs/architecture/overview.md`（:69） | 修改 | 3 |
| `docs/architecture/file-reference.md`（:93） | 修改 | 3 |

不動的檔案：`layout_probe.dart`、`inspector_fab.dart`、`dashboard_modal.dart`、`pubspec.yaml`、`lib/flutter_inspector_kit.dart`、兩支既有測試檔。brainstorm §P37 的狀態回寫交給 STAGE 6 的 `gen-sync-docs-by-branchs`。

---

## 5. 任務拆分

### 並行總覽

| # | 標題 | 等級 | 寫入檔 | 可否並行 |
|:--|:--|:--|:--|:--|
| 1 | 共用結算路徑 `_probeAt` 與拖曳瞄準（不含放大鏡） | `[快/便宜]` | `layout_inspect_overlay.dart`、`layout_inspect_drag_aim_test.dart` | 可與 3 並行；與 2 寫同兩個檔，**不可並行** |
| 2 | 放大鏡、十字準星、safe area 翻轉與 `showLoupe` | `[快/便宜]` | 同上兩檔 | 必須在 1 之後；可與 3 並行 |
| 3 | 文件同步（README／CHANGELOG／架構文件） | `[快/便宜]` | `README.md`、`CHANGELOG.md`、`docs/architecture/overview.md`、`docs/architecture/file-reference.md` | 與 1、2 寫入路徑完全不重疊，可並行 |
| 4 | SDK 確認與全套驗證 | `[原地修改]` | 無（只驗證） | 最後執行 |

> 任務 1、2 的程式碼已在原型上逐字驗證（§7），所以標為 `[快/便宜]`；verifier 若退回，依規則升一級成 `[標準]`。

---

### Task 1 `[快/便宜]`：共用結算路徑 `_probeAt` 與拖曳瞄準（不含放大鏡）

**Files**：
- Modify：`lib/src/ui/layout_inspect/layout_inspect_overlay.dart:48-74`（state 欄位與 `_onTapUp`）、`:131-135`（`GestureDetector`）
- Create：`test/ui/layout_inspect/layout_inspect_drag_aim_test.dart`

**Interfaces**：
- Consumes：既有 `probeLayoutAt(RenderObject, Offset)`（`layout_probe.dart:61`）、`LayoutInspectOverlay.show(OverlayState, {bool? mayBeObfuscated})`
- Produces（Task 2 會用到）：state 欄位 `Offset? _aim`；方法 `void _probeAt(Offset globalPosition)`、`void _aimAt(Offset globalPosition)`；測試檔的 `_Data`、`_pumpInspect`、`_loupe`、`_frameRect`、`_cardTexts`

- [ ] **Step 1：寫失敗測試**（建立 `test/ui/layout_inspect/layout_inspect_drag_aim_test.dart`）

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/ui/layout_inspect/layout_inspect_overlay.dart';
import 'package:flutter_inspector_kit/src/ui/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static const Rect rectA = Rect.fromLTWH(24, 60, 120, 40);
  static const Rect rectB = Rect.fromLTWH(300, 60, 60, 60);
  static const Offset blank = Offset(600, 300);
  static const BoxDecoration frame = BoxDecoration(
    border: Border.fromBorderSide(
      BorderSide(color: ThemeColor.color2196F3, width: ThemeSize.space2),
    ),
  );
}

Future<void> _pumpInspect(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fromRect(
              rect: _Data.rectA,
              child: const ColoredBox(color: Color(0xFF336699)),
            ),
            Positioned.fromRect(
              rect: _Data.rectB,
              child: const ColoredBox(color: Color(0xFFAA00AA)),
            ),
          ],
        ),
      ),
    ),
  );
  final overlay = Overlay.of(
    tester.element(find.byType(Scaffold)),
    rootOverlay: true,
  );
  LayoutInspectOverlay.show(overlay);
  await tester.pump();
}

Finder get _loupe => find.byType(RawMagnifier);

Rect _frameRect(WidgetTester tester) => tester.getRect(
  find.byWidgetPredicate(
    (w) => w is DecoratedBox && w.decoration == _Data.frame,
  ),
);

List<String?> _cardTexts(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();

void main() {
  group('LayoutInspectOverlay drag-to-aim', () {
    testWidgets('frame and card follow the RenderBox under the finger', (
      tester,
    ) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(_Data.rectA.center);
      await tester.pump();
      expect(_frameRect(tester), _Data.rectA);
      expect(find.text('size: 120.0 × 40.0'), findsOneWidget);

      await gesture.moveTo(_Data.rectB.center);
      await tester.pump();
      expect(_frameRect(tester), _Data.rectB);
      expect(find.text('size: 60.0 × 60.0'), findsOneWidget);
      expect(find.textContaining('1 / '), findsOneWidget);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('release settles exactly like a tap at the last aim point', (
      tester,
    ) async {
      await _pumpInspect(tester);
      final target = _Data.rectB.center;

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(target);
      await tester.pump();
      // A second finger steps up the chain mid-drag, so the release has
      // something to overwrite.
      await tester.tap(find.byTooltip('Parent'));
      await tester.pump();
      expect(find.textContaining('2 / '), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(find.textContaining('1 / '), findsOneWidget);
      expect(_loupe, findsNothing);
      final dragTexts = _cardTexts(tester);
      final dragFrame = _frameRect(tester);

      // Same pre-release state, then a plain tap at the same point.
      await tester.tap(find.byTooltip('Parent'));
      await tester.pump();
      expect(find.textContaining('2 / '), findsOneWidget);
      await tester.tapAt(target);
      await tester.pump();

      expect(_cardTexts(tester), dragTexts);
      expect(_frameRect(tester), dragFrame);
      expect(dragFrame, _Data.rectB);
    });

    testWidgets('a cancelled drag settles at the last aim point: the SDK '
        'sends onPanEnd, not onPanCancel', (tester) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(_Data.rectB.center);
      await tester.pump();
      await tester.tap(find.byTooltip('Parent'));
      await tester.pump();
      expect(find.textContaining('2 / '), findsOneWidget);

      await gesture.cancel();
      await tester.pump();

      expect(_loupe, findsNothing);
      expect(find.textContaining('1 / '), findsOneWidget);
      expect(_frameRect(tester), _Data.rectB);
    });

    testWidgets('drag starting on the info card does not enter aim mode', (
      tester,
    ) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Tap a widget to inspect')),
      );
      await gesture.moveBy(const Offset(0, -(kTouchSlop * 3)));
      await tester.pump();
      expect(_loupe, findsNothing);

      await gesture.up();
      await tester.pump();
      expect(find.text('Tap a widget to inspect'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2：確認失敗**

Run：`rtk flutter test test/ui/layout_inspect/layout_inspect_drag_aim_test.dart`
Expected：`+1 -3`。失敗的 3 個是 `frame and card follow…`、`release settles…`、`a cancelled drag…`：沒有 pan，就沒有藍框，也沒有 `Parent` 按鈕可按。通過的 1 個是守門測試 `drag starting on the info card…`，紅燈階段本來就會過，用來防止實作後回歸。0b 預跑結果相同。

- [ ] **Step 3：實作**（修改 `layout_inspect_overlay.dart`）

3a. 在 state 欄位（`:49-52`）的 `Timer? _copiedTimer;` 之後加一行：

```dart
  Offset? _aim;
```

3b. 把整個 `_onTapUp`（`:63-74`）換成以下內容：

```dart
  void _onTapUp(TapUpDetails details) => _probeAt(details.globalPosition);

  void _onPanStart(DragStartDetails details) => _aimAt(details.globalPosition);

  void _onPanUpdate(DragUpdateDetails details) =>
      _aimAt(details.globalPosition);

  // Settles through the tap path at the last crosshair point, so a release
  // gives exactly what a tap there would. The SDK also routes a pointer
  // cancel of an accepted drag here, not to onPanCancel.
  void _onPanEnd(DragEndDetails _) {
    final aim = _aim;
    setState(() => _aim = null);
    if (aim != null) _probeAt(aim);
  }

  // shortcut: probes on every pointer move; throttle to once per frame if
  // drag jank shows up on large widget trees.
  void _aimAt(Offset globalPosition) {
    setState(() => _aim = globalPosition);
    _probeAt(globalPosition);
  }

  void _probeAt(Offset globalPosition) {
    final anchor = context.findRenderObject();
    if (anchor == null) return;
    final hit = probeLayoutAt(anchor, globalPosition);
    if (hit.isEmpty) return;
    _copiedTimer?.cancel();
    setState(() {
      _chain = hit;
      _index = 0;
      _copied = false;
    });
  }
```

3c. 在 `GestureDetector`（`:131-135`）的 `onTapUp: _onTapUp,` 之後加入以下三行。**不要加 `onPanCancel`**：

```dart
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
```

- [ ] **Step 4：確認通過**

Run：`rtk flutter test test/ui/layout_inspect/`
Expected：12 個全過（既有 8 個加新增 4 個）。
Run：`rtk flutter analyze lib/src/ui/layout_inspect test/ui/layout_inspect`
Expected：`No issues found!`

- [ ] **Step 5：確認結算那一行真的被測到**（選做，30 秒）。暫時刪掉 `if (aim != null) _probeAt(aim);` 再跑 Step 4 的測試指令，預期 `release settles…` 與 `a cancelled drag…` 兩個 FAIL（0b 在 Task 1 狀態下實測 `+10 -2`）。看完立刻還原，`git diff` 應只剩 Step 3 的改動。

- [ ] **Step 6：Commit**

```bash
dart format lib/src/ui/layout_inspect test/ui/layout_inspect
git add lib/src/ui/layout_inspect/layout_inspect_overlay.dart test/ui/layout_inspect/layout_inspect_drag_aim_test.dart
git commit -m "feat(layout-inspect): drag to aim with a live outline (#<STAGE 1 issue 編號>)"
```

---

### Task 2 `[快/便宜]`：放大鏡、十字準星、safe area 翻轉與 `showLoupe`

**Files**：
- Modify：`lib/src/ui/layout_inspect/layout_inspect_overlay.dart`（頂部常數、`show()`、`_LayoutInspectLayer`、`build()`、新增 `_Loupe`）
  - 下方標註的行號是**修改前原檔**的行號，Task 1 之後會位移，定位時以引用的錨點文字為準。
- Modify：`test/ui/layout_inspect/layout_inspect_drag_aim_test.dart`

**Interfaces**：
- Consumes：Task 1 的 `_aim`、`_pumpInspect`、`_loupe`、`_Data`
- Produces：`LayoutInspectOverlay.show(OverlayState overlay, {bool? mayBeObfuscated, bool? showLoupe})`；`_LayoutInspectLayer.showLoupe`（`bool`）；私有 widget `_Loupe({required Offset aim})`

- [ ] **Step 1：加入門檻、幾何與 safe area 的失敗測試**（貼在 `drag starting on the info card…` 之後、`group` 結束的 `});` 之前）

```dart
    testWidgets('movement within kTouchSlop stays a tap and never shows the '
        'loupe', (tester) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.rectA.center);
      await gesture.moveBy(const Offset(kTouchSlop - 2, 0));
      await tester.pump();
      expect(_loupe, findsNothing);

      await gesture.up();
      await tester.pump();
      expect(_loupe, findsNothing);
      expect(find.text('size: 120.0 × 40.0'), findsOneWidget);
    });

    testWidgets('movement past kTouchSlop enters aim mode with the loupe', (
      tester,
    ) async {
      await _pumpInspect(tester);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
      await tester.pump();
      expect(_loupe, findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(_loupe, findsNothing);
    });

    testWidgets('loupe stays on screen, off the finger, and its crosshair '
        'targets the probe point', (tester) async {
      await _pumpInspect(tester);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final points = [
        const Offset(1, 1),
        Offset(screen.width - 1, 1),
        Offset(1, screen.height - 1),
        Offset(screen.width - 1, screen.height - 1),
        screen.center(Offset.zero),
      ];

      final gesture = await tester.startGesture(_Data.blank);
      for (final p in points) {
        await gesture.moveTo(p);
        await tester.pump();

        final rect = tester.getRect(_loupe);
        final magnifier = tester.widget<RawMagnifier>(_loupe);
        expect(rect.contains(p), isFalse, reason: 'covers finger at $p');
        expect(
          (Offset.zero & screen).intersect(rect),
          rect,
          reason: 'off screen at $p',
        );
        expect(
          rect.center + magnifier.focalPointOffset,
          offsetMoreOrLessEquals(p),
          reason: 'crosshair misses $p',
        );
      }

      await gesture.up();
      await tester.pump();
    });

    testWidgets('loupe flips below the finger when the room above is inside '
        'the top safe area', (tester) async {
      tester.view.padding = FakeViewPadding(
        top: 50 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      await _pumpInspect(tester);
      // Room above the screen edge, but not above a 50px status bar.
      const aim = Offset(400, 140);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(aim);
      await tester.pump();

      final rect = tester.getRect(_loupe);
      final magnifier = tester.widget<RawMagnifier>(_loupe);
      expect(rect.top, greaterThan(aim.dy));
      expect(
        rect.center + magnifier.focalPointOffset,
        offsetMoreOrLessEquals(aim),
      );

      await gesture.up();
      await tester.pump();
    });
```

Run：`rtk flutter test test/ui/layout_inspect/layout_inspect_drag_aim_test.dart`
Expected：`+5 -3`。失敗的是 `movement past kTouchSlop…`、`loupe stays on screen…`、`loupe flips below…`（找不到 `RawMagnifier`）；`movement within kTouchSlop…`（守門）與 Task 1 的 4 個都通過。0b 預跑結果相同。

- [ ] **Step 2：加入 Web 分支的失敗測試**

2a. 把 helper 的簽章與 `show` 呼叫改成可以傳 `showLoupe`：

```dart
Future<void> _pumpInspect(WidgetTester tester, {bool? showLoupe}) async {
```

```dart
  LayoutInspectOverlay.show(overlay, showLoupe: showLoupe);
```

2b. 在 `loupe flips below…` 之後加入：

```dart
    testWidgets('showLoupe false (web) aims and settles without RawMagnifier', (
      tester,
    ) async {
      await _pumpInspect(tester, showLoupe: false);

      final gesture = await tester.startGesture(_Data.blank);
      await gesture.moveTo(_Data.rectB.center);
      await tester.pump();
      expect(_loupe, findsNothing);
      expect(_frameRect(tester), _Data.rectB);

      await gesture.up();
      await tester.pump();
      expect(find.text('size: 60.0 × 60.0'), findsOneWidget);
    });
```

Run：`rtk flutter test test/ui/layout_inspect/layout_inspect_drag_aim_test.dart`
Expected：編譯失敗，`:41:38: Error: No named parameter with the name 'showLoupe'.`

- [ ] **Step 3：實作**（修改 `layout_inspect_overlay.dart`）

3a. 在 `import 'layout_probe.dart';`（`:10`）之後、`/// Manages the tap-to-inspect…` 之前加入：

```dart
const double _loupeDiameter = 96;
const double _loupeScale = 2;
// Clearance between the fingertip and the loupe edge, so the finger never
// covers the lens.
const double _loupeGap = 32;
const double _crosshairWidth = 1;
```

3b. 把 `show()`（`:16-32`）整段換成：

```dart
  /// Inserts the layout inspection overlay into [overlay].
  ///
  /// Repeated calls while the overlay is already active are ignored.
  /// [showLoupe] defaults to `!kIsWeb`: the drag loupe is skipped on web.
  static void show(
    OverlayState overlay, {
    bool? mayBeObfuscated,
    bool? showLoupe,
  }) {
    if (_entry != null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => LayoutProbeShield(
        child: _LayoutInspectLayer(
          entry: entry,
          mayBeObfuscated: mayBeObfuscated ?? !kDebugMode,
          showLoupe: showLoupe ?? !kIsWeb,
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
```

3c. `_LayoutInspectLayer`（`:35-46`）的建構式與欄位改成：

```dart
  const _LayoutInspectLayer({
    required this.entry,
    required this.mayBeObfuscated,
    required this.showLoupe,
  });

  final OverlayEntry entry;
  final bool mayBeObfuscated;
  final bool showLoupe;
```

3d. 在 `build()` 的 `final level = _chain.isEmpty ? null : _chain[_index];`（`:123`）之後加入：

```dart
    final aim = _aim;
```

3e. 在 `Stack` 最後一個子元件 `Align(...)` 結束的 `),`（`:167`）之後、`],`（`:168`）之前加入：

```dart
        // Last child: the loupe magnifies what is painted before it,
        // including the frame.
        if (aim != null && widget.showLoupe) _Loupe(aim: aim),
```

3f. 在 `_LayoutInspectLayerState` 類別結尾（`:171`）與 `class _LayoutInfoCard`（`:173`）之間加入。十字準星直接內聯成 `const Stack`，不另外抽 widget（審查 N8）：

```dart
class _Loupe extends StatelessWidget {
  const _Loupe({required this.aim});

  final Offset aim;

  @override
  Widget build(BuildContext context) {
    const radius = _loupeDiameter / 2;
    final screen = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final above = aim.dy - _loupeGap - radius;
    // shortcut: needs a screen >= 96 wide (clamp throws below that) and
    // >= 256 tall below the safe area; guard both if tiny windows matter.
    final center = Offset(
      aim.dx.clamp(radius, screen.width - radius),
      above - radius >= safeTop ? above : aim.dy + _loupeGap + radius,
    );
    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius,
      width: _loupeDiameter,
      height: _loupeDiameter,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(_loupeDiameter),
          magnificationScale: _loupeScale,
          focalPointOffset: aim - center,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(
                color: ThemeColor.color2196F3,
                width: ThemeSize.space2,
              ),
            ),
          ),
          // Crosshair: drawn over the lens, not magnified.
          child: const Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: _crosshairWidth,
                height: double.infinity,
                child: ColoredBox(color: ThemeColor.color2196F3),
              ),
              SizedBox(
                width: double.infinity,
                height: _crosshairWidth,
                child: ColoredBox(color: ThemeColor.color2196F3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

> `_Loupe` 回傳 `Positioned`，放在 `Stack.children` 中可以正常作用，先例是 `InspectorFab`（`inspector_fab.dart:26`）。既有 `build()` 的 `MediaQuery.of(context).size.height`（`:124`）不動，維持最小 diff。

- [ ] **Step 4：確認通過**

Run：`rtk flutter test test/ui/layout_inspect/`
Expected：17 個全過（既有 8 個加新增 9 個）。
Run：`rtk flutter analyze lib/src/ui/layout_inspect test/ui/layout_inspect`
Expected：`No issues found!`

- [ ] **Step 5：Commit**

```bash
dart format lib/src/ui/layout_inspect test/ui/layout_inspect
git add lib/src/ui/layout_inspect/layout_inspect_overlay.dart test/ui/layout_inspect/layout_inspect_drag_aim_test.dart
git commit -m "feat(layout-inspect): add a touch loupe with crosshair while aiming (#<STAGE 1 issue 編號>)"
```

---

### Task 3 `[快/便宜]`：文件同步（可與 Task 1、2 並行）

**Files**：`README.md`、`CHANGELOG.md`、`docs/architecture/overview.md`、`docs/architecture/file-reference.md`（純文件，不需要測試；完成後以 `git diff` 自查）

**措辭規則**：只寫「超過手勢 slop」，不寫死 18px 或 `kTouchSlop`（Android 用平台 touchSlop，滑鼠約 2 px）。

- [ ] **Step 1：`README.md` 功能表（:37）**。把該列中的 `and copy or share the whole chain as text; works in release builds |` 改成：

```markdown
and copy or share the whole chain as text; for small targets, press and drag to aim with a magnifier and crosshair above your finger (below it near the top edge); works in release builds |
```

再把同一列結尾的 `paste the exact numbers into the bug ticket instead of a screenshot |` 改成：

```markdown
paste the exact numbers into the bug ticket instead of a screenshot; a 16×16 icon hidden under your fingertip is reached by dragging the crosshair onto it |
```

- [ ] **Step 2：`README.md` 說明段**。在 `:135` 段落之後、`:137`（`It needs no setup…`）之前插入一段：

```markdown
For small targets such as a 16×16 icon, press and drag instead of tapping. Once your finger moves past the gesture slop, a magnifier above it — or below it near the top of the screen — shows the area underneath with a crosshair on the exact point being probed, and the outline and card follow the widget under the crosshair as you move. Release to select it; the result is the same as tapping that point. With a mouse, a click that drifts a couple of pixels briefly shows the magnifier, with the same result as a click. The magnifier is not shown on web; dragging still aims there.
```

再把 `:137` 的 `Values are a snapshot taken at the moment of the tap; if the layout changes, tap again.` 改成：

```markdown
Values are a snapshot taken when you tap or release; if the layout changes, select again.
```

- [x] **Step 3：`CHANGELOG.md`** — ❌ **STAGE 2 撤銷（2026-11-01，使用者裁決）**：`## Unreleased` 會讓 `test/version_test.dart:77-93`（#172 加入的守門：CHANGELOG 頂端標題必須等於 pubspec 版號）變紅；下方先例 `3f485c8`／`001d19c` 早於該守門，已過時。自 2.6.0 起 CHANGELOG 只在發版 commit 修改，故本條目**延至發版時由 `gen-update-publish-info` 以 `## <新版號>` 寫入**，本案不改 CHANGELOG。下方文字保留作為發版時的條目草稿：

```markdown
## Unreleased

### Added
* **Drag to aim in Inspect layout**: Small widgets are hard to hit with a tap because the finger covers them. Press and drag instead: once the finger moves past the gesture slop, a magnifier above it (below it near the top of the screen) shows the area underneath with a crosshair on the exact point being probed, the outline and card follow the widget under it, and releasing selects it exactly as a tap at that point would. Taps behave as before. Works in every build mode; the magnifier is skipped on web, where dragging still aims.

```

> **`## Unreleased` 先例查證（審查 N5）**：有先例而且相容。
> - `3f485c8`（feat(lifecycle)）在 feature commit 裡新增了 `## Unreleased` 區塊。
> - 下一次 release `001d19c`（chore(release): bump version to 2.5.0）把 `## Unreleased` 原地**改名**成 `## 2.5.0`，再併入同版其他條目。
> - 落差：`gen-update-publish-info` SKILL.md 的步驟 3 只寫「在最上方新增 `## $VERSION` 區塊」，沒有提到如何處理既有的 `## Unreleased`。照字面執行會在它上面再疊一個版本區塊，留下孤兒。
> - 處置：本計畫沿用先例，release 時由 publisher 依 `001d19c` 的做法改名合併。是否另案在該 skill 補一句，交使用者決定，不在本案範圍。

- [ ] **Step 4：`docs/architecture/overview.md:69`**。在該行結尾（`…的 `hitTest` 回傳 false。`）之後接上：

```markdown
按住拖曳（超過手勢 slop）進入瞄準：每次移動都以手指位置重跑 `probeLayoutAt`，框線與資訊卡即時跟隨；手指上方以 `RawMagnifier` 放大並以十字準星標出探測點，上方空間落入頂部 safe area 時改放到下方（Web 不顯示放大鏡）。放開時（含系統取消已成立的拖曳，SDK 一律送 `onPanEnd`）以最後的瞄準點走與單點相同的 `_probeAt` 結算。
```

- [ ] **Step 5：`docs/architecture/file-reference.md:93`**。把 `資訊卡（父鏈上下切換、複製／分享）。` 改成：

```markdown
資訊卡（父鏈上下切換、複製／分享）；按住拖曳可瞄準，手指上方（靠近上緣時改到下方）顯示 `RawMagnifier` 放大鏡與十字準星（Web 不顯示）。
```

- [ ] **Step 6：Commit**

```bash
git add README.md CHANGELOG.md docs/architecture/overview.md docs/architecture/file-reference.md
git commit -m "docs(layout-inspect): document drag-to-aim and the touch loupe (#<STAGE 1 issue 編號>)"
```

---

### Task 4 `[原地修改]`：SDK 確認與全套驗證（最後執行）

- [ ] **Step 0：確認 SDK**。Run：`rtk proxy flutter --version`。Expected：第一行為 `Flutter 3.47.1 • channel stable`。若不是 3.47.1，記下實際版本：Task 2 的 `kTouchSlop ± 2` 門檻測試就是該 SDK 下的實測，只要它們是綠的，門檻結論就成立；若它們變紅，停下來回報，並更正 README 措辭與規格 R1。
- [ ] **Step 1：格式**。Run：`dart format --output=none --set-exit-if-changed lib/src/ui/layout_inspect test/ui/layout_inspect`。Expected：exit 0（`0 changed`）。**只檢查本次碰到的目錄**：repo 另有 6 個既有檔案未格式化（`console_tab.dart` 與 5 個測試檔），對整個 `lib/ test/` 跑會 exit 1。也**不要**執行 `make format`。
- [ ] **Step 2：靜態分析**。Run：`rtk flutter analyze lib/ test/`。Expected：恰好 7 個 info，位置是 `export_report_sheet.dart:161`、`:162`，`console_tab.dart:22`、`:594`，`network_tab.dart:293`、`:331`，`share_text_web.dart:15`。
- [ ] **Step 3：全套測試**。Run：`rtk flutter test`。Expected：全過。0b 原型實測 765 個（原有 756 個加新增 9 個）；若 worktree 基準數不同，以「失敗 0、比基準多 9 個」為準。
- [ ] **Step 4：零破壞自查**。Run：`git diff --stat main -- pubspec.yaml lib/flutter_inspector_kit.dart test/ui/layout_inspect/layout_inspect_overlay_test.dart test/ui/layout_inspect/layout_probe_test.dart lib/src/ui/layout_inspect/layout_probe.dart`。Expected：沒有輸出。
- [ ] **Step 5：死碼自查**。Run：`rtk proxy grep -n "onPanCancel:" lib/src/ui/layout_inspect/layout_inspect_overlay.dart`。Expected：沒有命中（只抓具名參數接線；`_onPanEnd` 註解內提到 onPanCancel 屬正常）。
- [ ] **Step 6：暫存檔自查**。Run：`git status --short`。Expected：沒有未追蹤的暫存檔。
- [ ] **Step 7：實機手動檢查（交 STAGE 3／QA）**：在有瀏海的觸控實機上執行 `cd example && flutter run`，開啟 Inspect layout，拖曳到小 icon 上。確認以下幾點：
  - 準星對準 icon，藍框出現在放大鏡內。
  - 手指靠近狀態列時，放大鏡翻到手指下方。
  - 放開後資訊卡內容正確。
  - 桌面（macOS）上用滑鼠點擊時，手抖不會改變結果。

---

## 6. 執行方式建議

| 方式 | 適用 | 評估 |
|:--|:--|:--|
| **Subagent-driven（建議）** | Task 1、2、3 | Task 1 與 2 寫同兩個檔，交給 implementer **序列**執行，每個任務各自經 verifier 驗收；Task 3 是純文件，可與 Task 1 同時派發。Task 4 由主進程原地執行（派發煞車）。 |
| 主進程直接實作 | 全部 | 程式碼已在原型上逐字驗證，主進程做最快；但這樣繞過了「實作與驗收分離」，不建議。 |
| Parallel session | — | 唯一能並行的只有 Task 3（文件），另開 session 不划算，不建議。 |

建議批次：
- **批次 A**：Task 1 與 Task 3 並行（兩個 subagent）。
- **批次 B**：Task 2（Task 1 通過驗收後執行，同一位 implementer）。
- **批次 C**：Task 4（主進程）。

---

## 7. 0b 預驗證紀錄（修正後重跑）

做法：把 repo 複製到 scratchpad（排除 `.git`、`example`），套用本計畫的程式碼，SDK 為 Flutter 3.47.1。repo 本身沒有改動，複本驗證完已刪除。

1. **門檻**：
   - 觸控：位移 17 → `taps=1 panStarts=0`；位移 19 → `taps=0 panStarts=1`。
   - 滑鼠：位移 0.9 與 1.5 → tap；位移 2.5 → pan。
2. **`onPanCancel` 語意（B1）**：
   - 普通單點：`{tapUp: 1, start: 0, end: 0, cancel: 1}`，也就是**每次單點都觸發 onPanCancel**。
   - 已成立的拖曳後 `gesture.cancel()`：`{tapUp: 0, start: 1, end: 1, cancel: 0}`，也就是**送 onPanEnd**。
   - 與 SDK `monodrag.dart:753-765` 相符。
3. **Task 1 紅綠燈**：
   - 原始 overlay 跑 Task 1 測試檔：`+1 -3`。
   - 套用 Task 1 實作後跑整個 `test/ui/layout_inspect/`：12 個全過，analyze 沒有問題。
4. **B2 紅燈實證**：刪掉 `if (aim != null) _probeAt(aim);` 後，失敗的都是 `release settles exactly like a tap…` 與 `a cancelled drag settles…` 兩支：在完整實作上只跑新測試檔為 `+7 -2`，在 Task 1 狀態下跑整個目錄為 `+10 -2`。還原後全綠。
5. **Task 2 紅綠燈**：
   - Step 1 測試對 Task 1 實作：`+5 -3`。
   - Step 2 測試：`:41:38` 出現 `No named parameter with the name 'showLoupe'`。
   - 套用 Task 2 實作後：17 個全過。
   - **N4 紅燈實證**：把翻轉條件還原成舊的 `above >= radius`，`loupe flips below…` FAIL（`+8 -1`）。
6. **全套**：
   - `flutter test` 765 個全過。
   - `flutter analyze lib/ test/` 恰好 7 個 info，全部是 Task 4 Step 2 列出的既有位置。
   - `dart format` 對 `layout_inspect` 兩個目錄為 0 changed。
   - 首輪 0b 的像素實測（2 倍放大、`center + focalPointOffset` 語意、藍框出現在放大鏡內）不受本次修正影響，沒有重跑。

---

## 8. 自我審查：規格覆蓋對照

| 規格 AC | 對應 |
|:--|:--|
| AC1 進入拖曳瞄準 | Task 1（`frame and card follow…`、`drag starting on the info card…`）、Task 2（`movement past kTouchSlop…`） |
| AC2 放大鏡 | Task 2（門檻、幾何、出界、準星、safe area 翻轉、單點不顯示）。放開後消失由 Task 1 的 `release settles…` 斷言；**系統取消已成立的拖曳時，SDK 送 `onPanEnd`，等同在最後瞄準點放開**，由 Task 1 的 `a cancelled drag settles…` 斷言放大鏡消失且回到 `1 / N`。`IgnorePointer` 寫在 Task 2 的程式碼 |
| AC3 藍框即時跟隨 | Task 1（`frame and card follow…`）。探測為空時維持上一結果：`_probeAt` 原樣保留 `hit.isEmpty` 早退，由結構保證 |
| AC4 放開等同單點 | Task 1（`release settles…`，第二指製造差異，刪結算行即變紅）加上 §2 的結構論證 |
| AC5 單點零改變 | Global Constraints（既有測試與提示字串不改）、Task 2（`movement within kTouchSlop…`）、Task 4 Step 4 |
| AC6 平台與 build mode | Task 2（`showLoupe false…`）；程式碼沒有使用 `kDebugMode` 或 assert 才生效的 API |
| AC7 零副作用 | Task 4 Step 4（`pubspec.yaml`、匯出檔零 diff）；實作沒有 import registry 或 buffer |
| AC8 測試與分析 | Task 4 |
| AC9 文件同步 | Task 3 |

Placeholder 掃描：唯一的待填處是 commit message 結尾的 issue 編號，必須等 STAGE 1 建立後才會有。名稱在 Task 1 與 Task 2 之間一致（`_probeAt`、`_aimAt`、`_aim`、`showLoupe`、`_Loupe`、`_pumpInspect`、`_loupe`、`_frameRect`、`_cardTexts`、`_Data`）。計畫內已沒有 `_onPanCancel` 或 `_Crosshair`。

---

## 9. 本次修正對照（plan-verifier 初審 REVISE #1）

| 項目 | 處置 |
|:--|:--|
| B1 `onPanCancel` 死碼 | 刪除 `_onPanCancel` 與接線。Q7 改寫為「系統取消時 SDK 送 onPanEnd，等同在最後瞄準點放開」，§2 表格與流程圖、§8 AC2 同步更正。取消測試改名並加入第二指切層的斷言，以測試證實語意（§7-2、§7-4）。規格 Q7 與 AC2 同步更正。 |
| B2 AC4 測試抓不到 | 改採方案 (a)：拖曳中以第二指按 `Parent` 並斷言 `2 / `；放開後須回 `1 / ` 並與單點逐欄相等。刪掉拖曳前半段的 tap A 加 Parent。已實測刪結算行即變紅（§7-4）。 |
| N1 刪 Task 1 與 SDK 釐清 | 原 Task 1 已刪，總任務數改為 4，批次同步更新。Task 4 Step 0 加 `flutter --version`。實際使用的 SDK 已釐清為 3.47.1（見檔頭）。 |
| N2 措辭 | 使用者文件只寫「超過手勢 slop」；README 註明滑鼠點擊手抖會閃一下放大鏡、結果不變。規格 R1 同步更正為實測結果。 |
| N4 safe area | 翻轉條件改為 `above - radius >= MediaQuery.paddingOf(context).top`，新增測試，並實測舊條件下該測試會變紅。規格 Q1 與 AC2 同步補入。 |
| N5 CHANGELOG 先例 | 已查證 `3f485c8` 與 `001d19c`，沿用 `## Unreleased`；skill 文字的落差寫在 Task 3 Step 3。 |
| N6 README | 功能表 :37 與新段落都補上拖曳，以及「靠上緣時翻到下方」。 |
| N8 內聯與 `sizeOf` | `_Crosshair` 內聯為 `const Stack`；`_Loupe` 改用 `MediaQuery.sizeOf`／`paddingOf`。 |
| N3、Q8 | 依指示維持現案，交使用者裁決。 |
