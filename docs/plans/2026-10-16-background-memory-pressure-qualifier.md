# 實作計畫：Android 切背景記憶體壓力修飾標籤（§Z1-5 / §P21 既有缺陷修正）

- **日期**：2026-10-16
- **規格**：`docs/features/2026-10-16-background-memory-pressure-qualifier.md`
- **Effort**：trivial

---

## 1. 資料結構與設計

**不新增任何資料結構與模型。**

改動純粹在 `LifecycleHandler.didHaveMemoryPressure()` 中就地讀取 `WidgetsBinding.instance.lifecycleState`：
- 若 `lifecycleState != null && lifecycleState != AppLifecycleState.resumed`，訊息加入 ` (app ${lifecycleState.name})` 修飾。
- 若 `lifecycleState == null || lifecycleState == AppLifecycleState.resumed`，維持既有訊息格式 `Memory pressure$suffix`。
- `topPageLabel` 後綴格式保持於訊息末尾：`Memory pressure$stateQualifier$suffix`。

資料流：
```text
OS (TRIM_MEMORY_UI_HIDDEN / onTrimMemory)
  → WidgetsBinding.handleMemoryPressure()
  → LifecycleHandler.didHaveMemoryPressure()
      ├── 讀取 WidgetsBinding.instance.lifecycleState
      └── 組合：'Memory pressure' + stateQualifier + suffix
  → onLog (LogLevel.warning)
  → ConsoleTab / Merged Timeline
```

---

## 2. 任務拆分

**總任務數：1（單一任務）**

### Task 1 · 狀態修飾實作 + 註解修正 + 單元測試 + CHANGELOG

**寫入路徑**：
- `lib/src/core/lifecycle_handler.dart`（實作與 doc comment 修正）
- `test/core/lifecycle_handler_test.dart`（單元測試）
- `CHANGELOG.md`（Unreleased 記錄）

#### 1a. 實作 (`lifecycle_handler.dart`)

1. 修改 `didHaveMemoryPressure()`：
   ```dart
   @override
   void didHaveMemoryPressure() {
     try {
       final page = topPageLabel?.call();
       final suffix = (page == null || page.isEmpty) ? '' : ' · $page';
       final state = WidgetsBinding.instance.lifecycleState;
       final stateQualifier =
           (state != null && state != AppLifecycleState.resumed)
               ? ' (app ${state.name})'
               : '';
       onLog('Memory pressure$stateQualifier$suffix', level: LogLevel.warning);
     } catch (e, s) {
       debugPrintStack(
         stackTrace: s,
         label: 'inspector memory pressure log failed: $e',
       );
     }
   }
   ```
2. 修正 `lifecycle_handler.dart:66-67` doc comment：
   補充說明 `dart:io` 的 `ProcessInfo.currentRss` 雖不需 channel 但本套件為維護 Web 相容與零 `dart:io` 承諾刻意不用；Google 定義的 anonymous RSS+Swap 則無 in-app API。

#### 1b. 測試 (`lifecycle_handler_test.dart`)

新增測試案例：
1. `memory pressure: non-resumed lifecycle states add (app <state>) qualifier`：
   - 走訪 `hidden`、`paused`、`inactive`、`detached`，斷言訊息分別含 `(app hidden)`、`(app paused)`、`(app inactive)`、`(app detached)`。
2. `memory pressure: non-resumed state preserves topPageLabel suffix`：
   - 設定狀態為 `hidden` 且有 `topPageLabel`，斷言訊息為 `Memory pressure (app hidden) · HomePage (/home)`。
3. `memory pressure: resumed state produces no qualifier`：
   - 設定狀態為 `resumed`，斷言訊息仍為 `Memory pressure`（有 page 時為 `Memory pressure · HomePage (/home)`）。

#### 1c. 文件

- `CHANGELOG.md` 於 Unreleased 增列修正項目。

---

## 3. 驗證

```bash
flutter test test/core/lifecycle_handler_test.dart
flutter test
flutter analyze lib/ test/
```

---

## 4. 刻意不做

| 項目 | 理由 |
|:---|:---|
| 新增配置旗標 | 需求本質為修正誤導性資訊，直接在訊息加上上下文最簡潔，無須引入配置複雜度 |
| 引入原生 channel | 違反純 Dart 定位，`WidgetsBinding.instance.lifecycleState` 已能完全解決切背景誤報 |
| 抽共用 helper | 僅於此處單行判斷，抽 helper 是不必要的過度抽象 |

---

## 5. 風險與回滾

改動範圍僅限於 `didHaveMemoryPressure()` 內部的一行狀態讀取與字串串接，不影響 `didChangeAppLifecycleState` 或其他既有流程。回滾僅需 revert 該方法。
