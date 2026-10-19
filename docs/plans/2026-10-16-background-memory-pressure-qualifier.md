# 實作計畫：Android 切背景記憶體壓力誤報過濾（§Z1-5 / §P21 既有缺陷修正）

- **日期**：2026-10-16（2026-10-19 決策變更：由「附加狀態修飾」改為「非前景直接丟棄」）
- **規格**：`docs/features/2026-10-16-background-memory-pressure-qualifier.md`
- **Effort**：trivial

---

## 1. 資料結構與設計

**不新增任何資料結構與模型。**

改動純粹在 `LifecycleHandler.didHaveMemoryPressure()` 開頭加一道 guard，就地讀取 `WidgetsBinding.instance.lifecycleState`：
- 若 `lifecycleState != null && lifecycleState != AppLifecycleState.resumed`，直接 return。
- 否則維持既有訊息格式 `Memory pressure$suffix`。

資料流：
```text
OS (TRIM_MEMORY_UI_HIDDEN / onTrimMemory / didReceiveMemoryWarning)
  → WidgetsBinding.handleMemoryPressure()
  → LifecycleHandler.didHaveMemoryPressure()
      ├── lifecycleState 非 null 且非 resumed → return（丟棄）
      └── 組合：'Memory pressure' + suffix
  → onLog (LogLevel.warning)
  → ConsoleTab / Merged Timeline
```

---

## 2. 任務拆分

**總任務數：1（單一任務）**

### Task 1 · 背景丟棄 guard + 註解修正 + 單元測試

**寫入路徑**：
- `lib/src/core/lifecycle_handler.dart`（實作與 doc comment 修正）
- `test/core/lifecycle_handler_test.dart`（單元測試）

#### 1a. 實作 (`lifecycle_handler.dart`)

1. 修改 `didHaveMemoryPressure()`：
   ```dart
   @override
   void didHaveMemoryPressure() {
     final state = WidgetsBinding.instance.lifecycleState;
     if (state != null && state != AppLifecycleState.resumed) return;
     try {
       final page = topPageLabel?.call();
       final suffix = (page == null || page.isEmpty) ? '' : ' · $page';
       onLog('Memory pressure$suffix', level: LogLevel.warning);
     } catch (e, s) {
       debugPrintStack(
         stackTrace: s,
         label: 'inspector memory pressure log failed: $e',
       );
     }
   }
   ```
2. 修正 doc comment：
   - 補充說明 `dart:io` 的 `ProcessInfo.currentRss` 雖不需 channel 但本套件為維護 Web 相容與零 `dart:io` 承諾刻意不用；Google 定義的 anonymous RSS+Swap 則無 in-app API。
   - 說明非前景事件被丟棄的理由（Android 切背景例行送出；App 被殺時記憶體內時間軸一併消失）。

#### 1b. 測試 (`lifecycle_handler_test.dart`)

1. `memory pressure: non-resumed lifecycle states produce no log`：
   - 走訪 `hidden`、`paused`、`inactive`、`detached`，斷言不產生任何 log。
2. `memory pressure: resumed state logs the warning`：
   - 設定狀態為 `resumed` 且有 `topPageLabel`，斷言訊息為 `Memory pressure · HomePage (/home)`。

---

## 3. 驗證

```bash
flutter test test/core/lifecycle_handler_test.dart
flutter test
flutter analyze lib/ test/
```

另需 Android 實機手動確認：example app 切背景後，Console 不出現 `Memory pressure`（✅ 2026-10-19 已確認）。手動觸發方法與 `am send-trim-memory` 的限制見規格「手動觸發方法」一節。

---

## 4. 刻意不做

| 項目 | 理由 |
|:---|:---|
| 新增配置旗標 | 背景事件無排查價值，直接丟棄最簡潔，無須引入配置複雜度 |
| 附加狀態修飾（原方案） | 事件仍是 warning，誤報照樣進過濾與 badge；只是把判讀成本轉給讀者 |
| 引入原生 channel | 違反純 Dart 定位，`WidgetsBinding.instance.lifecycleState` 已能完全解決切背景誤報 |

---

## 5. 風險與回滾

- 改動範圍僅限於 `didHaveMemoryPressure()` 開頭一道 guard，不影響 `didChangeAppLifecycleState` 或其他既有流程。回滾僅需 revert 該方法。
- 依賴「`UI_HIDDEN` 抵達時 `lifecycleState` 已非 `resumed`」的時序，已於 2026-10-19 Android 實機確認成立；即使未來平台改變順序，也只退化為修正前行為，不會更糟。
