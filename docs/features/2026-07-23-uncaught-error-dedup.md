# 功能規格：全局未捕捉例外去重

- 日期：2026-07-23
- 類型：Bug fix（單檔）
- 影響檔案：`lib/src/core/uncaught_error_handler.dart`
- 對應 brainstorm：#1 / 第四部分 §D2

## Why（一句話）

同一次 widget build 崩潰在 Console 產生兩筆一模一樣的 error log，讓開發者無法分辨「崩潰一次還是兩次」，直接干擾排查判斷。

## 使用者故事

作為使用 flutter_inspector_kit 的**開發者 / QA**，當我的 App 在某次 widget build 拋出例外時，我打開 Inspector Console 期望看到**一筆**對應的 error log。

目前的實作在 `attach()` 中掛了兩個會記錄 Flutter error 的 hook：
- `FlutterError.onError` → `_logFlutterError(details, source: 'flutterError')`
- `ErrorWidget.builder` → `_logFlutterError(details, source: 'errorWidget')`

同一次 build 崩潰時，framework 先觸發 `FlutterError.onError`，隨後呼叫 `ErrorWidget.builder` 建立錯誤畫面，**同一個 `FlutterErrorDetails` 物件**被記錄兩次。結果 Console 出現兩筆完全相同的 error，我誤以為崩潰了兩次，浪費時間追一個不存在的第二次崩潰。

## 驗收條件

對齊 `test/core/uncaught_error_handler_test.dart` 既有契約：

1. **去重（identity）**：`dedup: same FlutterErrorDetails logged once across both hooks`
   同一個 `FlutterErrorDetails` 物件先後經 `FlutterError.onError` 與 `ErrorWidget.builder`，`onLog` 只被呼叫一次（`callCount == 1`）。

2. **不吞真實重複崩潰**：`no dedup: distinct FlutterErrorDetails are each logged`
   兩個**不同**的 `FlutterErrorDetails` 物件（不同 exception），各記錄一筆（`callCount == 2`）。

3. **不回歸既有行為**：既有的 `idempotent`、`chain`、`guard` 三個測試保持通過——去重不得改變 host handler 鏈接、`handled` 回傳語意、或 `onLog` 丟例外時的容錯。

## 行為邊界決策：identity 去重（而非 hashCode + 時間窗）

**選定：以 object identity 去重**——記住上一次 log 的 `FlutterErrorDetails` 參考，若下一次傳入的是 `identical` 的同一物件則跳過。

理由（Linus 式：消滅特殊情況優於新增判斷）：
- 既有測試的語意就是「同一物件」。framework 在同一次 build 崩潰中，把**同一個** `FlutterErrorDetails` 實例先後交給兩個 hook——identity 是這個 bug 的精確特徵。
- `exception.hashCode ^ stack.hashCode` + 「2 秒時間窗」引入 magic number 與時間依賴，是為「不確定是不是同一物件」而打的補丁。既然是同一物件，identity 判斷就完全足夠。
- 時間窗有真實副作用：兩次**獨立**的相同型別崩潰若落在 2 秒內會被錯誤吞掉（違反驗收條件 2）。identity 天然免疫——不同崩潰 = 不同物件 = `identical` 為 false。
- 無新資料結構、無新常數、無時鐘讀取：一個 nullable 欄位記住上一筆參考即可。

## 範圍邊界（Out of scope）

- **(a) `PlatformDispatcher.instance.onError` 不涉及**：這是獨立的 async error 來源，記錄自己的 `source: 'platformDispatcher'`，與 build 崩潰的雙 hook 重複問題無關，維持原樣。
- **(b) 跨 build 的真實重複崩潰不可被吞**：同一個 bug 反覆觸發（每次都是新的 `FlutterErrorDetails` 物件）必須各自記錄。去重只針對「同一物件跨兩個 hook」。
- **(c) 不引入新資料模型、不新增相依**：以既有型別與一個 nullable 欄位完成，不加 package、不建新 class。
