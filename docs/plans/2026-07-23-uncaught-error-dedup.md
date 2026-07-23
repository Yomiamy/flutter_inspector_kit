# 實作計畫：全局未捕捉例外去重（identity dedup）

- 日期：2026-07-23
- 對應規格：`docs/features/2026-07-23-uncaught-error-dedup.md`
- 類型：Bug fix（單檔、low-effort）
- 實作檔：`lib/src/core/uncaught_error_handler.dart`（唯一）
- 測試檔：`test/core/uncaught_error_handler_test.dart`（已寫好，TDD red 完成，本次不動）

## 核心決策（已鎖定）

以 **object identity** 去重：記住上一次 log 的 `FlutterErrorDetails` 參考，
下一次進 `_logFlutterError` 時若 `identical(details, _lastLoggedDetails)` 為 true 則 early return。
兩個 hook（`FlutterError.onError`、`ErrorWidget.builder`）共用同一 guard。

## 資料結構異動

新增單一實例欄位：

| 欄位 | 型別 | 初值 | 為何 nullable |
|------|------|------|---------------|
| `_lastLoggedDetails` | `FlutterErrorDetails?` | `null`（不寫初值，Dart 預設 null） | attach 後、第一次崩潰前沒有「上一筆」；null 代表「尚無前一筆可比對」，第一筆 `identical(details, null)` 恆為 false，自然放行。 |

- 無新常數、無時鐘、無 Queue/ring buffer、無新相依、無新 class。
- 只需保留「上一筆」的理由（**已知邊界**）：build 崩潰的實際順序是
  `onError(A)` 緊接 `errorWidget(A)`，framework 不會在兩者之間插入其他
  `FlutterErrorDetails`。因此單一 nullable 參考即可涵蓋全部驗收條件；
  ring buffer 是為不存在的交錯情境所做的過度設計。
- `PlatformDispatcher.instance.onError` 不走 `_logFlutterError`，天然不受此欄位影響。

## 檔案異動清單

### `lib/src/core/uncaught_error_handler.dart`

1. 在欄位區（`_attached` 附近）新增：
   `FlutterErrorDetails? _lastLoggedDetails;`
   並加一行 `// ponytail:` 註解說明「只記上一筆足矣」的已知邊界。
2. 在 `_logFlutterError` 進入處加入 guard：
   - `if (identical(details, _lastLoggedDetails)) return;`
   - 通過後 `_lastLoggedDetails = details;`，再照原邏輯 build `data` 並呼叫 `onLog`。
3. 其餘邏輯（chain、wrap、try/catch 容錯、`data` 組裝）完全不動。

## 任務拆分

單一任務（單檔、單欄位、一個 guard）。

| # | 任務 | 寫入 scope | 複雜度等級 |
|---|------|-----------|-----------|
| 1 | 在 `UncaughtErrorHandler` 新增 `_lastLoggedDetails` 欄位，於 `_logFlutterError` 入口加入 `identical` guard 與記錄上一筆參考，使既有測試轉綠 | `lib/src/core/uncaught_error_handler.dart` | **機械性** |

理由：改動局限單一函式入口 + 單欄位宣告，無設計分歧、無跨檔整合，測試契約已固定。

## 驗證方式

```bash
flutter test test/core/uncaught_error_handler_test.dart
```

- 目標：5 個測試全綠（3 既有 + 2 新增）。
- 去重生效：`dedup: same FlutterErrorDetails logged once across both hooks`（callCount == 1）。
- 不吞真實重複：`no dedup: distinct FlutterErrorDetails are each logged`（callCount == 2）。
- 不回歸：`idempotent`、`chain`、`guard` 維持通過。

## 破壞性分析（對既有行為零破壞）

- **chain / wrap 不變**：guard 只在 `_logFlutterError` 內攔截「是否呼叫 `onLog`」，
  host handler 鏈接（`_oldFlutterErrorHandler`、`original(details)`）在 guard 之外，
  無論是否去重都照常執行 → `chain` 測試不受影響。
- **`handled` 回傳語意不變**：`PlatformDispatcher.onError` 分支完全未觸及 `_lastLoggedDetails`，
  回傳值來源不變 → `guard` 測試的 `handled == true` 成立。
- **容錯不變**：`_logFlutterError` 仍在各 hook 的 try/catch 內，去重 early return 不拋例外。
- **idempotent 不變**：`_attached` 邏輯未動；去重與重複 attach 是正交關注點。
- **不同物件不被吞**：`identical` 對不同 `FlutterErrorDetails` 恆為 false，
  跨 build 的真實重複崩潰（每次新物件）各自記錄 → 符合範圍邊界 (b)。
