# 實作計畫：修復 Inspector 自身頁面污染 NavigatorTab

- **日期**：2026-07-26
- **狀態**：STAGE 0b — 待執行
- **規格來源**：`docs/features/2026-07-26-inspector-route-pollution.md`（已確認，方案 B）
- **類型**：bug fix，最小 diff

---

## 1. 技術決策（Decisions）

以下六項為規格 §7 要求 STAGE 0b 細化的內容。每項附「為何這樣、為何不那樣」。

### D1. 共用常數：值與放置位置

**新檔**：`lib/src/observers/inspector_route_names.dart`

```dart
// Route names for the inspector's own UI. The observer filters on this
// prefix so inspector navigation never lands in the host app's Navigator
// history. Producers (dashboard UI) and the consumer (the observer) must
// share this one definition — a second copy is how the original bug happened.

/// Prefix every inspector-owned route name starts with.
///
/// Deliberately verbose and package-qualified: it must not collide with a
/// host app's own route names, which are typically path-like (`/home`) or
/// short identifiers. `startsWith` on this prefix is the whole filter.
const String kInspectorRoutePrefix = 'flutter_inspector_';

/// The dashboard modal itself.
///
/// The value is frozen: it shipped on pub.dev and users may already filter
/// on this exact string in their own NavigatorObserver.
const String kInspectorDashboardRoute = 'flutter_inspector_dashboard';

const String kInspectorLogDetailRoute = 'flutter_inspector_log_detail';
const String kInspectorNetworkDetailRoute = 'flutter_inspector_network_detail';
const String kInspectorTableRowsRoute = 'flutter_inspector_table_rows';
const String kInspectorCellDetailsRoute = 'flutter_inspector_cell_details';
const String kInspectorExportReportRoute = 'flutter_inspector_export_report';
```

**前綴值 `'flutter_inspector_'` 的理由**：`kInspectorDashboardRoute` 的值被規格 §5.2 凍結為 `'flutter_inspector_dashboard'`，前綴必須是它的真前綴，否則 dashboard 本體會漏過過濾（AC-1 第三條回歸）。`'flutter_inspector_'` 是同時滿足「凍結值的前綴」與「辨識度足夠」的最長選擇。規格 AC-2 點名的三個使用者 route 樣本 `/flutter`、`/inspector`、`/home` 皆不以此開頭 → 不誤殺。

**放在 `lib/src/observers/` 的理由**：
- 常數的**語意所有者是過濾規則**（observer），UI 只是規則的遵守方。放在判斷端，依賴方向是 `ui/ → observers/`，單向。
- 反向（放 `lib/src/ui/dashboard/`）會讓 `observers/` 依賴 `ui/`，把過濾邏輯綁在 UI 層上，方向錯誤。
- 放 `lib/src/utils/` 也可行，但 `utils/` 現有內容（redaction、formatters、table_sort）皆為無狀態純函式工具，route 命名契約不屬於這個語意群。
- 新檔只依賴 Flutter 基礎庫（helper 需 `package:flutter/material.dart` 取得 `BuildContext` / `WidgetBuilder` / `MaterialPageRoute`），不 import 本專案任何模組 → 不可能與 `ui/` 形成循環相依。測試端 `test/observers/navigator_observer_test.dart` 已 import 同目錄的 observer，路徑自然。
- 檔名 `snake_case`，符合 §2.4。

**慣例對齊**：file 層級 `const String kXxx` + 檔頭說明註解，與 `lib/src/utils/redaction.dart:6`、`lib/src/webview/webview_bridge_js.dart:5` 完全同形。

**不做**：不建 `enum` 或 `class InspectorRoutes { static const ... }`。專案沒有這個慣例，且 `const String` 已足夠（Ponytail：不為單一用途加抽象）。

### D2. Helper：簽章與 assert

**放置**：與常數同檔 `lib/src/observers/inspector_route_names.dart`。

**理由**：helper 的全部價值就是「掛上前綴合規的名字」，它是常數契約的執行者，兩者同生共死。分兩檔會讓「單一來源」變兩個檔案，違反 AC-3 的精神。同檔也讓 UI 端只需一行 import。

```dart
/// Pushes an inspector-owned page route, tagged so the navigator observer
/// can keep it out of the host app's navigation history.
///
/// Every page route opened from inside the dashboard must go through here.
/// [name] must start with [kInspectorRoutePrefix]; a stray name would
/// silently become the next pollution source, so it fails loudly in debug.
void pushInspectorRoute(
  BuildContext context,
  String name,
  WidgetBuilder builder,
) {
  assert(
    name.startsWith(kInspectorRoutePrefix),
    'Inspector route name "$name" must start with '
    '"$kInspectorRoutePrefix" or the navigator observer will leak it into '
    'the host app history.',
  );
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: builder,
    ),
  );
}
```

此 helper 需 `import 'package:flutter/widgets.dart';`（`BuildContext` / `Navigator` / `MaterialPageRoute` 皆在 widgets 之外——`MaterialPageRoute` 在 `material.dart`，故實際 import `package:flutter/material.dart'`）。此 import 不會造成循環：`navigator_observer.dart` 已 import `flutter/widgets.dart`。

**簽章決策逐條**：

| 決策 | 選擇 | 理由 |
|---|---|---|
| 回傳型別 | `void` | 4 個呼叫端全部是 `onTap: () => ...` 的 fire-and-forget，無一使用回傳的 `Future`。回傳 `Future<void>` 會製造未 await 的 future（lint 噪音）且無人消費。**Ponytail：不為零個消費者留回傳值。** |
| 泛型 `<T>` | 不加 | 沒有 detail view 回傳值。單一實作的泛型是投機抽象。 |
| 參數形式 | `context` 與 `name` 為 positional，`builder` 為 positional | 依 §2.8：3 個參數但型別全異、順序語意明確（誰、叫什麼、長什麼樣），且與 `Navigator.push(context, route)` 的既有直覺一致。不強制 named。 |
| 統一 `Navigator.of(context).push` vs `Navigator.push(context, ...)` | helper 內統一用 `Navigator.of(context).push`；呼叫端形式差異隨之消失 | 這正是收斂的附帶收益——`database_tab.dart:181` 的 `Navigator.push(context, ...)` 特例被 helper 吃掉。 |
| `MaterialPageRoute<void>` 顯式泛型 | 加 | 避免推導成 `dynamic`。 |

**assert 條件**：`name.startsWith(kInspectorRoutePrefix)`。滿足 AC-3 第四條「誤用在 debug build 當場失敗」。用 `startsWith` 而非 `==` 某清單，是因為新增 detail view 時只需宣告一個新常數，不需改 helper。

**不做**：不加 `assert(context.mounted)`（呼叫點皆在同步 `onTap` 內，無 async gap）；不加 `useRootNavigator` 參數（規格 §4 明確 out-of-scope）。

### D3. B 類 bottom sheet 接線

**決策：不寫第二個 helper。2 處各自在既有的 `showModalBottomSheet` 呼叫加一行 `routeSettings:`。**

```dart
showModalBottomSheet<void>(
  context: context,
  routeSettings: const RouteSettings(name: kInspectorCellDetailsRoute),
  builder: ...,
);
```

**理由**（規格 §6「不可假設能套同一個 helper」「強行把 bottom sheet 塞進 page route helper 是為統一而統一」）：
- 兩處的 `showModalBottomSheet` 參數已經不同（`export_report_sheet.dart` 有 `isScrollControlled: true`，`table_rows_view.dart` 沒有），且 `showModalBottomSheet` 另有 `backgroundColor`、`shape`、`constraints` 等十餘個參數。包一個 helper 就得決定透傳哪些、或寫死；兩者都比多一行 `routeSettings:` 差。
- 一個只被呼叫 2 次、內容是「原封不動轉呼叫 + 塞一個參數」的 wrapper，是 Ponytail 明令的不必要抽象。
- 「單一來源」的實質內容是**共用同一份常數與前綴**（規格 §6 原文），而非同一個函式。這裡兩處都 import 同一份常數，契約已滿足。

**assert 覆蓋落差（已知且接受）**：B 類 2 處不經過 helper，故不受 D2 的 assert 保護。緩解手段為 D6 的防回歸測試（AC-5）：測試直接斷言 `entries` 為空，任何未掛 `routeSettings` 的新 bottom sheet 都會讓測試失敗。**測試守 B 類，assert 守 A 類**，兩者合起來覆蓋 AC-3。這是形狀差異的必然結果，不是漏洞。

### D4. `_isInspectorRoute` 的新規則

```dart
bool _isInspectorRoute(Route<dynamic> route) =>
    route.settings.name?.startsWith(kInspectorRoutePrefix) ?? false;
```

**逐項對照風險（規格 §5.2 最高風險項）**：

| 要求 | 本實作如何滿足 |
|---|---|
| AC-2：`name == null` 的**使用者** route 仍被記錄 | `?.` 讓 null 短路到 `?? false` → 回傳 `false` → **不排除** → 照常記錄。null 走的是「保留」而非「丟棄」。 |
| 規格 §5.2：用 `startsWith` 而非 `contains` | 直接使用 `startsWith`。`contains` 會誤殺名為 `/settings/flutter_inspector_help` 之類的使用者 route。 |
| AC-1 第三條：dashboard 本體維持排除 | `'flutter_inspector_dashboard'.startsWith('flutter_inspector_')` 為 `true`，行為不變。 |
| AC-2 第三條：`/flutter`、`/inspector`、`/home` 不受影響 | 三者皆不以 `flutter_inspector_` 開頭。 |
| AC-3 第二條：只依賴一個來源 | 唯一依賴 `kInspectorRoutePrefix`。 |

**不做**：不改 `didPush` / `didPop` / `didReplace` / `didRemove` 的簽章與結構（規格 §5.1 明令簽章不得變更）；不改 `_record`、`_resolveWidgetType`。本檔淨 diff = 1 行邏輯 + 1 行 import。

### D5. 7 處污染點逐檔異動清單

行號為 2026-07-26 實查確認，與規格一致。

| # | 檔案:行 | 類別 | 異動 | route name 常數 |
|---|---|---|---|---|
| 1 | `lib/src/ui/dashboard/dashboard_modal.dart:32` | C | `'flutter_inspector_dashboard'` 字面值 → `kInspectorDashboardRoute`（**值不變**）。加 import。`const RouteSettings(...)` 維持 `const`（常數是編譯期常數）。 | `kInspectorDashboardRoute` |
| 2 | `lib/src/ui/dashboard/tabs/console_tab.dart:171-175` | A | `Navigator.of(context).push(MaterialPageRoute(builder: ...))` → `pushInspectorRoute(context, kInspectorLogDetailRoute, (_) => LogDetailView(entry: entry))` | `kInspectorLogDetailRoute` |
| 3 | `lib/src/ui/dashboard/tabs/console_tab.dart:196-203` | A | 同上 → `pushInspectorRoute(context, kInspectorNetworkDetailRoute, (_) => NetworkDetailView(entry: entry, redactSensitiveData: redactSensitiveData))` | `kInspectorNetworkDetailRoute` |
| 4 | `lib/src/ui/dashboard/tabs/network_tab.dart:268-275` | A | 同 #3 形狀 | `kInspectorNetworkDetailRoute` |
| 5 | `lib/src/ui/dashboard/tabs/database_tab.dart:180-190` | A | `Navigator.push(context, MaterialPageRoute(builder: (context) => TableRowsView(...)))` → `pushInspectorRoute(context, kInspectorTableRowsRoute, (_) => TableRowsView(source: selectedSource, tableName: table.name))`。順帶消除 `Navigator.push(context, ...)` 這個形式特例。 | `kInspectorTableRowsRoute` |
| 6 | `lib/src/ui/dashboard/tabs/database/table_rows_view.dart:118-121` | B | `showModalBottomSheet` 加 `routeSettings: const RouteSettings(name: kInspectorCellDetailsRoute)` | `kInspectorCellDetailsRoute` |
| 7 | `lib/src/ui/dashboard/export_report_sheet.dart:19-24` | B | `showModalBottomSheet<void>` 加 `routeSettings: const RouteSettings(name: kInspectorExportReportRoute)`；`isScrollControlled: true` 等既有參數不動 | `kInspectorExportReportRoute` |

**#2～#5 的 import 調整**：4 個檔案加入 `inspector_route_names.dart` 的相對 import；若移除 `MaterialPageRoute` 後該檔不再需要某個 import，順手清掉（實測時以 `dart analyze` 為準，不預先猜測——各檔皆 import `material.dart` 整包，實際不會有 unused import）。

**#3 與 #4 共用同一個常數**：兩處推的都是 `NetworkDetailView`，同一種頁面就該同一個名字。不為「兩個入口」造兩個常數。

### D6. 測試策略（TDD）

四項測試工作，全部落在 `test/observers/navigator_observer_test.dart`（既有檔）與一個新檔。

**T-a（守 AC-2，最高風險）— 新增單元測試**：無名稱的使用者 route 仍被記錄。規格 §5.3 指出這是既有測試的缺口。

```dart
test('records an unnamed user route (name == null must not be dropped)', () {
  final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
  observer.didPush(route, null);

  expect(inspector.navigatorInspector.entries.length, 1);
  expect(inspector.navigatorInspector.entries.first.routeName, isNull);
});
```

**T-b（守 AC-2 第三條）— 新增單元測試**：名稱近似但不以前綴開頭的使用者 route 仍被記錄。

```dart
test('records user routes whose names merely resemble the prefix', () {
  for (final name in ['/flutter', '/inspector', '/home', 'flutter_x']) {
    observer.didPush(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => const SizedBox(),
      ),
      null,
    );
  }
  expect(inspector.navigatorInspector.entries.length, 4);
});
```

**T-c（AC-4 + AC-3）— 修改既有測試**：`test/observers/navigator_observer_test.dart:109` 的硬編 `'flutter_inspector_dashboard'` 改為 `kInspectorDashboardRoute`。**這不是放寬斷言**——常數的值與原字面值完全相同，測試語意零變化，只是把測試端也接到單一來源上（AC-3）。其餘 7 個既有測試一字不改。

**T-d（守 AC-5，防回歸）— 新檔 `test/observers/inspector_route_filter_test.dart`**：端到端 widget test，掛真實 observer 到真實 Navigator，逐一開啟 6 個 inspector route name，斷言 `entries` 全程為空，且同一個 Navigator 上的使用者 route 照常記錄。

```dart
testWidgets('no inspector-owned route reaches the entries buffer',
    (tester) async {
  final inspector = FlutterInspector();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [inspector.navigatorObserver],
      home: const SizedBox(),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));

  const names = [
    kInspectorDashboardRoute,
    kInspectorLogDetailRoute,
    kInspectorNetworkDetailRoute,
    kInspectorTableRowsRoute,
    kInspectorCellDetailsRoute,
    kInspectorExportReportRoute,
  ];

  for (final name in names) {
    navigator.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
  }

  expect(inspector.navigatorInspector.entries, isEmpty);

  // The same observer still records the host app's own navigation.
  navigator.push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/user-page'),
      builder: (_) => const SizedBox(),
    ),
  );
  await tester.pumpAndSettle();
  expect(inspector.navigatorInspector.entries.length, 1);
});
```

此測試同時覆蓋 push 與 pop（AC-1 第二條），且因為它斷言的是**常數清單**，未來新增 detail view 時只要作者宣告了常數卻忘了接線，測試不會保護；但只要作者**沒**宣告常數（即完全繞過收斂入口），A 類會被 assert 擋下、B 類會在下方 T-e 被擋下。

**T-e（守 AC-5 的 UI 端，B 類 assert 缺口的補償）— 新增 2 則 widget test**，併入 `test/observers/inspector_route_filter_test.dart`：驗證 2 處 bottom sheet 實際掛上了名稱。用最小成本做法——直接斷言掛了 observer 的 app 中開啟該 sheet 後 `entries` 為空。

```dart
testWidgets('opening the export sheet does not pollute entries',
    (tester) async { /* pump ExportReportSheet.show + assert entries isEmpty */ });
```

`table_rows_view` 的 cell details sheet 需要 `DatabaseBrowserSource`，成本較高；若在實作時發現需要建 mock source 才能觸發，改以 `routeSettings` 的靜態驗證替代（斷言 `_showCellDetails` 的 route name），並在 PR 說明中記錄。**先嘗試端到端，落地不可行才降級。**

**明確不需修改的測試（規格 §5.3 逐條回覆，已實查全文）**：

| 測試檔 | 實查結論 |
|---|---|
| `test/ui/tabs/console_tab_test.dart` | ✅ **不需修改**。全檔 13 則測試僅斷言 `find.byType(LogDetailView/NetworkDetailView)` 與 tile 顏色、排序，**無任何一則觸及 route name 或 `navigatorInspector.entries`**。且其 `MaterialApp` 未掛 observer。 |
| `test/ui/export_report_sheet_test.dart` | ✅ **不需修改**。斷言集中在 sheet 內的文字、勾選狀態與 share channel 內容，未觸及 route。其 `pumpSheet` 的 `MaterialApp` 未掛 observer。 |
| `navigator_tab_test.dart`、`navigator_active_stack_test.dart`、`navigator_stack_resolver_test.dart`、`navigator_inspector_test.dart`、`models/navigator_entry_test.dart` | ✅ 讀取端 / 不經 observer 過濾，不受影響。 |

**結論：本次修復不需放寬或修改任何既有斷言。** 唯一的既有測試改動是 T-c 的字面值 → 常數替換，值不變。

---

## 2. 檔案異動總覽

| 檔案 | 動作 | 淨變更規模 |
|---|---|---|
| `lib/src/observers/inspector_route_names.dart` | **新增** | ~45 行（常數 + helper + 註解） |
| `lib/src/observers/navigator_observer.dart` | 修改 | 1 行邏輯 + 1 行 import |
| `lib/src/ui/dashboard/dashboard_modal.dart` | 修改 | 1 行 + import |
| `lib/src/ui/dashboard/tabs/console_tab.dart` | 修改 | 2 處 + import |
| `lib/src/ui/dashboard/tabs/network_tab.dart` | 修改 | 1 處 + import |
| `lib/src/ui/dashboard/tabs/database_tab.dart` | 修改 | 1 處 + import |
| `lib/src/ui/dashboard/tabs/database/table_rows_view.dart` | 修改 | 1 行 + import |
| `lib/src/ui/dashboard/export_report_sheet.dart` | 修改 | 1 行 + import |
| `test/observers/navigator_observer_test.dart` | 修改 | +2 測試、1 行常數替換 |
| `test/observers/inspector_route_filter_test.dart` | **新增** | ~80 行 |
| `CHANGELOG.md` | 修改 | 1 條 bug fix |

**新增檔案數：2（1 lib + 1 test）。** 無新增依賴、無新增 export。

**`lib/flutter_inspector_kit.dart` 不動**：實查其 export 清單（11 行）不含 `src/observers/` 與 `src/ui/dashboard/`。`inspector_route_names.dart` 保持內部檔案，**不加入 export**——使用者不需要也不該直接呼叫 `pushInspectorRoute`（規格 §4「不改公開 API 形狀」）。測試以 `package:flutter_inspector_kit/src/...` 深路徑 import，與既有測試（`navigator_observer_test.dart:2-4`）同慣例。

---

## 3. 任務拆分

任務粒度 2–5 分鐘。相依順序：**T1 → (T2 ‖ T3 ‖ T4 ‖ T5 ‖ T6) → (T7 ‖ T8) → T9**。T7 與 T8 寫入不同測試檔、互無資料相依，可並行（與下方 Wave 3 一致）。

### T1｜建立共用常數與 helper（TDD 起點）

- **複雜度**：`標準`（設計判斷已在 D1/D2 定案，執行為機械性，但是所有後續任務的地基）
- **寫入 scope**：`lib/src/observers/inspector_route_names.dart`（新檔）
- **可並行**：❌ 無（所有其他任務的前置）
- **內容**：依 D1 建立 6 個 route name 常數 + `kInspectorRoutePrefix`；依 D2 建立 `pushInspectorRoute` 含 `assert`。檔頭寫「為何存在」的註解。
- **驗收**：`dart analyze lib/src/observers/inspector_route_names.dart` 零 issue；`kInspectorDashboardRoute` 的值逐字元等於 `'flutter_inspector_dashboard'`。

---

### T2｜`_isInspectorRoute` 改為前綴比對（🔴 最高風險）

- **複雜度**：`最強推論`（單行改動，但誤寫即造成資料遺失。必須確認 null 走「保留」分支）
- **寫入 scope**：`lib/src/observers/navigator_observer.dart`
- **可並行**：✅ 可與 T3–T6 並行（寫入路徑不重疊）
- **前置**：T1
- **內容**：依 D4 改為 `route.settings.name?.startsWith(kInspectorRoutePrefix) ?? false`，加 import。四個 `did*` 覆寫一字不改。
- **驗收**：`flutter test test/observers/navigator_observer_test.dart` — 既有 8 則測試（含 `'ignores inspector dashboard route'`）全綠。
- **⚠️ 檢查點**：改完自問「使用者 `MaterialPageRoute(builder: ...)` 沒給 name，會被排除嗎？」答案必須是「不會」。

---

### T3｜dashboard_modal 字面值收斂（C 類，#1）

- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/ui/dashboard/dashboard_modal.dart`
- **可並行**：✅ 與 T2、T4、T5、T6 並行
- **前置**：T1
- **內容**：`dashboard_modal.dart:32` 的字面值換成 `kInspectorDashboardRoute`，加相對 import `../../observers/inspector_route_names.dart`。**值不得改變**（規格 §5.2）。
- **驗收**：`flutter test test/ui/dashboard_modal_test.dart`（若存在）與 `dart analyze` 綠。

---

### T4｜console_tab 兩處改走 helper（A 類，#2 #3）

- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/ui/dashboard/tabs/console_tab.dart`
- **可並行**：✅
- **前置**：T1
- **內容**：D5 表格 #2、#3。`_LogEntryRow.onTap`（171–175 行）與 `_NetworkEntryRow.onTap`（196–203 行）改為 `pushInspectorRoute(...)`。保留尾隨逗號。
- **驗收**：`flutter test test/ui/tabs/console_tab_test.dart` 全綠（**不修改任何斷言**——實查確認該檔無 route 相關斷言）。

---

### T5｜network_tab + database_tab 改走 helper（A 類，#4 #5）

- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/ui/dashboard/tabs/network_tab.dart`、`lib/src/ui/dashboard/tabs/database_tab.dart`
- **可並行**：✅
- **前置**：T1
- **內容**：D5 表格 #4、#5。#5 順帶把 `Navigator.push(context, ...)` 形式統一掉，並把 builder 參數名 `(context)` 改為 `(_)`（未使用）。
- **驗收**：`flutter test test/ui/tabs/network_tab_test.dart test/ui/tabs/database_tab_test.dart` 全綠。

---

### T6｜兩處 bottom sheet 掛 routeSettings（B 類，#6 #7）

- **複雜度**：`快/便宜`
- **寫入 scope**：`lib/src/ui/dashboard/tabs/database/table_rows_view.dart`、`lib/src/ui/dashboard/export_report_sheet.dart`
- **可並行**：✅
- **前置**：T1
- **內容**：D3 + D5 表格 #6、#7。各加一行 `routeSettings: const RouteSettings(name: kInspectorXxxRoute)`，其餘參數（`isScrollControlled` 等）一字不動。**不建立 wrapper 函式。**
- **驗收**：`flutter test test/ui/export_report_sheet_test.dart test/ui/tabs/database/table_rows_view_test.dart`（後者若存在）全綠，**不修改任何斷言**。

---

### T7｜observer 測試：補 AC-2 缺口 + 常數收斂

- **複雜度**：`標準`（新增測試需正確表達「null 必須被保留」的語意）
- **寫入 scope**：`test/observers/navigator_observer_test.dart`
- **可並行**：❌ 與 T8 寫入不同檔可並行，但兩者皆需 T1–T6 完成
- **前置**：T1、T2
- **內容**：依 D6 加入 T-a（無名稱 route 仍記錄）、T-b（近似名稱不誤殺）；把第 109 行的硬編字串換成 `kInspectorDashboardRoute`。既有 8 則其餘測試一字不改。
- **驗收**：該檔 10 則測試全綠。**額外驗證**：暫時把 `_isInspectorRoute` 改成 `name == null || name.startsWith(...)`，T-a 必須失敗；驗證後還原。（確認新測試真的守得住）

---

### T8｜防回歸端到端測試（AC-5）

- **複雜度**：`標準`（新檔、需真實 Navigator 與 observer 接線）
- **寫入 scope**：`test/observers/inspector_route_filter_test.dart`（新檔）
- **可並行**：✅ 可與 T7 並行（不同檔）
- **前置**：T1–T6 全部完成（測的是完整接線後的行為）
- **內容**：依 D6 的 T-d、T-e。T-d 遍歷 6 個常數斷言 `entries` 為空 + 使用者 route 照常記錄；T-e 至少覆蓋 `ExportReportSheet.show`（cell details sheet 若需 mock source 成本過高，降級為 route name 靜態驗證並在 commit message 註明）。
- **驗收**：新檔全綠；**負向驗證**：暫時移除 `export_report_sheet.dart` 的 `routeSettings` 一行，T-e 必須失敗；驗證後還原。

---

### T9｜全套測試 + CHANGELOG

- **複雜度**：`快/便宜`
- **寫入 scope**：`CHANGELOG.md`
- **可並行**：❌ 最後一步
- **前置**：T1–T8
- **內容**：
  1. `dart format .` + `dart analyze`（零 issue）
  2. `flutter test`（全套；依既有慣例，`magical_tap_test` 有 10 分鐘 timeout，跑全套時預留時間）
  3. CHANGELOG 加一條 bug fix：「Inspector 自身的 detail view / bottom sheet 不再被記錄進宿主 app 的 Navigator 軌跡」。無 API 變更、無使用者遷移動作（規格 §5.4）。
- **驗收**：全套測試綠、analyze 零 issue、AC-1～AC-5 逐條打勾。

---

## 4. 並行執行建議

**Wave 1（序列）**：T1

**Wave 2（5 路並行，寫入路徑互不重疊）**：
```text
T2  → lib/src/observers/navigator_observer.dart
T3  → lib/src/ui/dashboard/dashboard_modal.dart
T4  → lib/src/ui/dashboard/tabs/console_tab.dart
T5  → lib/src/ui/dashboard/tabs/network_tab.dart, database_tab.dart
T6  → lib/src/ui/dashboard/tabs/database/table_rows_view.dart, export_report_sheet.dart
```

**Wave 3（2 路並行）**：T7、T8

**Wave 4（序列）**：T9

### 執行方式選擇

| 方式 | 適用 | 說明 |
|---|---|---|
| **A. Subagent-driven（建議）** | 本計畫 | Wave 2 的 5 個任務全是 `快/便宜` 或單行機械改動，適合一次派 5 個 subagent 並行。Wave 3 派 2 個。總計 3 輪往返。**T2 建議由主 session 親自執行**（`最強推論`，最高風險，不外包）。 |
| **B. Parallel session** | 不建議 | 檔案數少、單檔改動小，跨 session 的協調成本高於收益。Wave 2 的 5 個任務加起來不超過 15 分鐘。 |
| **C. 全序列** | 保守選項 | T1→T2→…→T9 依序執行。總時長約 30–40 分鐘（含測試）。若對並行寫入有疑慮，此為安全退路。 |

**推薦：A（T2 由主 session 自行執行，T3–T6 派 4 個 subagent 並行，T7/T8 派 2 個並行）。**

---

## 5. 出口檢查（對照規格 AC）

| AC | 由哪個任務保證 |
|---|---|
| AC-1 dashboard 內所有 route 不進 entries | T2（過濾規則）+ T3–T6（接線）+ T8（驗證，含 pop） |
| AC-2 使用者導航不誤殺（🔴） | T2（`?? false` 保留 null）+ T7（T-a、T-b 守住） |
| AC-3 單一來源 + debug assert | T1（常數與 helper）+ T3–T6（全數走收斂入口）+ T7（測試端也接常數） |
| AC-4 既有測試不回歸、不放寬斷言 | T4/T5/T6 各自驗收 + T9 全套。實查確認**零則既有斷言需修改**。 |
| AC-5 新增污染點被擋下 | T1 的 assert（A 類）+ T8（B 類與整體） |

## 6. 明確不做（Out-of-scope 覆述）

不改 `useRootNavigator`、不改 NavigatorTab UI、不動 `NavigatorStackResolver`、不改 `NavigatorEntry`、不加使用者開關、不清理歷史髒資料、不改公開 API 形狀、不 export `inspector_route_names.dart`。
