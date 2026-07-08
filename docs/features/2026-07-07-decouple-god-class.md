# 功能規格：解耦 FlutterInspector God Class（階段二）

> 來源：`docs/architecture/2026-07-05-architecture_comparison_report.md` 階段二
> workflow-id：`wf-1783358867-b952`

## What & Why

`FlutterInspector`（`lib/src/core/flutter_inspector.dart`，348 行）目前同時扮演三種角色：核心 Registry 門面、**全域錯誤攔截器**、**FAB Overlay 掛載器**。後兩者與「對外 Facade API」職責無關，卻和核心邏輯纏在同一個 class，違反 SRP。本次把這兩組職責各抽成一個單一職責類別，讓 `FlutterInspector` 回歸乾淨的 Facade。

**Why now**：階段一（UI 層 widget class 拆分）、階段三的 firstWhere 安全、Entry immutable 都已落地，God Class 是報告三階段中唯一實質未動工、且有架構意義的項目。

## 使用者故事

- 作為 package 維護者，我希望錯誤攔截邏輯獨立成 `UncaughtErrorHandler`，能單獨閱讀、測試、修改，不必在 348 行的 God Class 裡翻找。
- 作為 package 維護者，我希望 FAB Overlay 的 attach/detach 獨立成 `InspectorOverlayManager`，UI 掛載邏輯與核心邏輯分離。
- 作為 **package 使用者**，我希望這次重構對我**完全無感**——`FlutterInspector(...)` 建構、`attach`/`detach`、`captureUncaughtErrors` 旗標、`setupErrorHandlers()` 全部照舊可用，我的 `example/lib` 不需改一行。

## 驗收條件

1. **新增 `lib/src/core/uncaught_error_handler.dart`**：承接 `setupErrorHandlers` 與 `_logFlutterError` 的完整邏輯，保留三個既有語意——(a) idempotent（重複 attach 只掛一次）、(b) chain 既有 host handler（`FlutterError.onError` / `PlatformDispatcher.onError` / `ErrorWidget.builder` 保留並轉發舊 handler）、(c) guard logging（logging 失敗只 `debugPrintStack`，永不中斷對 host handler 的轉發）。
2. **新增 `lib/src/ui/inspector_overlay_manager.dart`**：承接 `attach({context, visible})` / `detach()` 的 `OverlayEntry` 邏輯，保留 idempotent 語意（`_overlayEntry != null` 時 attach 直接 return）。
3. **`FlutterInspector` public API 簽章零變更**（Never break userspace）：
   - `attach({required BuildContext context, bool visible})`、`detach()` 保留為轉發方法。
   - `setupErrorHandlers()`（`@visibleForTesting`）保留為轉發方法。
   - `captureUncaughtErrors` 建構子旗標續存，行為不變（`true` 時 constructor 自動接上 error hooks）。
   - 其餘所有 getter / 記錄 API / clear 方法不受影響。
4. **既有測試全綠**：`test/core/error_capture_test.dart` 直接呼叫 `setupErrorHandlers()` 並驗證三個 process-global hook 的保存/還原——此檔**不改**仍須通過（若需改，僅限 import 路徑，且需說明）。
5. **兩個新類別各有單元測試**：
   - `test/core/uncaught_error_handler_test.dart`：沿用 `error_capture_test.dart` 的 setUp/tearDown hook 保存還原樣板。
   - overlay 測試沿用 `test/ui/inspector_fab_test.dart` 的 widget test 樣式（overlay 目前零測試，此為淨新增覆蓋）。
6. `FlutterInspector` 行數明顯下降（報告目標 100 行內為理想值，非硬性門檻；真正的驗收是「兩組職責移出、public 表面不變」）。

## 範圍邊界（Out of scope）

- **不動階段一/三的既有成果**：不引入 Controller、不改 Entry、不碰 UI tab 拆分。
- **不改 public API 語意**：純內部搬遷 + 轉發，不趁機「改良」簽章或加參數。
- **不動 error hooks 的 process 生命週期策略**：hooks 仍常駐（detach 只移 FAB，不 teardown error hooks），維持既有註解記載的設計。
- **barrel export 不變**：兩個新類別定位為 internal，依既有慣例（`InspectorRegistry`/`RingBuffer` 皆未 export）**不加進** `lib/flutter_inspector_kit.dart`。
- **不改 `captureUncaughtErrors` 預設值**（維持 `false`）。

## 絕不簡化（安全邊界）

- error hooks 的 try/catch guard 不可為了縮 diff 移除——它防止 logging 失敗中斷 host 的錯誤轉發（資料遺失 / 崩潰吞掉）。
- idempotent guard（`_uncaughtErrorHandlersAttached`、`_overlayEntry != null`）不可省——重複掛載會洩漏 OverlayEntry 或重複攔截。
- chain 舊 handler 的邏輯不可簡化為「直接覆蓋」——會破壞使用者自己註冊的錯誤處理。

## 關鍵風險

- **最大風險是「搬遷中改變語意」**：三個 error hook 的 chain/guard/idempotent 行為由 `error_capture_test.dart` 鎖定，搬遷後必須逐一對照通過，不可只搬程式碼不驗證語意。
- 兩個類別如何持有 `FlutterInspector` 的依賴（`log()` 方法、`openDashboard`）需在 STAGE 0b 計畫定清楚——建構子注入 vs 回呼，避免循環依賴。
