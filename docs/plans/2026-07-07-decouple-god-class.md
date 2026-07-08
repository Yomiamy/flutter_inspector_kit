# 實作計畫：解耦 FlutterInspector God Class（階段二）

> 規格：`docs/features/2026-07-07-decouple-god-class.md`
> workflow-id：`wf-1783358867-b952`

## 設計決策：依賴注入用「回呼」而非持有 inspector

兩個新類別對 `FlutterInspector` 只有極窄的依賴：
- `UncaughtErrorHandler` 只需要一個「記一筆 log」的能力 → 注入 `void Function(FlutterErrorDetails, {required String source})` 或更簡單地注入 `log` 對應的 callback。
- `InspectorOverlayManager` 只需要「點 FAB 時開 dashboard」的能力 → 注入 `void Function(BuildContext) openDashboard`。

**用回呼注入，不持有整個 `FlutterInspector`**：職責窄、無循環依賴、測試時可傳假 callback。這對齊既有 helper（`InspectorRegistry` 建構子注入、field final）的風格。

## 資料結構 / 介面

### `lib/src/core/uncaught_error_handler.dart`
```dart
/// Attaches the three standard Flutter error hooks, chaining any existing host
/// handler. Idempotent and guard-logged.
class UncaughtErrorHandler {
  UncaughtErrorHandler({required this.onError});

  /// Called to record one captured error. Guard-logged by the caller-side hooks.
  final void Function(String message, {String? stackTrace, Map<String, dynamic>? data}) onError;

  FlutterExceptionHandler? _oldFlutterErrorHandler;
  bool Function(Object, StackTrace)? _oldPlatformDispatcherOnError;
  bool _attached = false;

  /// Idempotent: attaches at most once.
  void attach() { ... }   // = 舊 setupErrorHandlers() body

  void _logFlutterError(FlutterErrorDetails details, {required String source}) { ... }
}
```
- 承接舊 `setupErrorHandlers` 的三個 hook（`FlutterError.onError` / `PlatformDispatcher.onError` / `ErrorWidget.builder`）與 `_logFlutterError`。
- 三個既有語意原封搬遷：idempotent（`_attached` guard）、chain（保留 `_old*`）、guard logging（try/catch → `debugPrintStack`）。
- `onError` callback 接到 `FlutterInspector.log(...)`。

### `lib/src/ui/inspector_overlay_manager.dart`
```dart
/// Mounts/removes the inspector FAB overlay. Idempotent.
class InspectorOverlayManager {
  InspectorOverlayManager({required this.onFabTap});

  /// Called when the FAB is tapped, with the FAB's build context.
  final void Function(BuildContext context) onFabTap;

  OverlayEntry? _overlayEntry;

  void attach({required BuildContext context, bool visible = true}) { ... }  // idempotent
  void detach() { ... }
}
```
- `onFabTap` 接到 `FlutterInspector.openDashboard(context)`。

### `FlutterInspector` 改動（純轉發，簽章不變）
- 移除欄位：`_oldFlutterErrorHandler`、`_oldPlatformDispatcherOnError`、`_uncaughtErrorHandlersAttached`、`_overlayEntry`。
- 移除方法本體：`setupErrorHandlers` 的 hook 邏輯、`_logFlutterError`、`attach`/`detach` 的 OverlayEntry 邏輯。
- 新增 `late final UncaughtErrorHandler _errorHandler;`、`late final InspectorOverlayManager _overlayManager;`，constructor 建立（注入 callback）。
- 保留轉發方法：
  - `@visibleForTesting void setupErrorHandlers() => _errorHandler.attach();`
  - `void attach({required BuildContext context, bool visible = true}) => _overlayManager.attach(context: context, visible: visible);`
  - `void detach() => _overlayManager.detach();`
- constructor 的 `if (captureUncaughtErrors) setupErrorHandlers();` 行為不變。

## 任務拆分

| # | 任務 | 檔案 scope | 複雜度 | diff 上限 |
|---|------|-----------|--------|----------|
| 1 | 建 `UncaughtErrorHandler`，搬遷 error hooks + `_logFlutterError`，附單元測試（沿用 `error_capture_test.dart` 的 hook 保存還原樣板） | `lib/src/core/uncaught_error_handler.dart`（新）、`test/core/uncaught_error_handler_test.dart`（新） | 需設計判斷（三個 hook 語意搬遷不可失真） | ≤150 行 |
| 2 | 建 `InspectorOverlayManager`，搬遷 attach/detach OverlayEntry 邏輯，附 widget 測試（沿用 `inspector_fab_test.dart` 樣式） | `lib/src/ui/inspector_overlay_manager.dart`（新）、`test/ui/inspector_overlay_manager_test.dart`（新） | 標準（邏輯簡單但涉及 Overlay widget test） | ≤100 行 |
| 3 | `FlutterInspector` 接線：移除已搬遷的欄位/方法本體，改建構子建立兩個新類別 + 轉發方法；確認 `captureUncaughtErrors` 與 `example/lib` 行為不變 | `lib/src/core/flutter_inspector.dart`（改） | 需設計判斷（跨兩類別接線，不可破壞 public 表面） | ≤80 行淨變動（含大量刪除） |

**依賴順序**：任務 1、2 互相獨立（不同新檔，寫入路徑不重疊）→ **可並行**。任務 3 依賴 1、2 的類別存在 → 必須在 1、2 之後序列執行。

**共享檔**：無。三個任務寫入路徑互不重疊（1/2 各建新檔，3 改 flutter_inspector.dart）。任務 3 是唯一改既有檔者。

## 驗證

- 每個任務跑對應新測試 + `flutter test test/core/error_capture_test.dart`（既有語意鎖定，不可退化）。
- 任務 3 完成後跑**全套** `flutter test` 確認 public 表面無破壞。
- `flutter analyze` 零 warning。

## 絕不簡化提醒（給 implementer 派發時併入）

- error hooks 的 try/catch guard、idempotent guard、chain 舊 handler 三者原封搬遷，不可為縮 diff 省略。
- 不改 public 簽章、不改 `captureUncaughtErrors` 預設、兩新類別不加進 barrel export。
