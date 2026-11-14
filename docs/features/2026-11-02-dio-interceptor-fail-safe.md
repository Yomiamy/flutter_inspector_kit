# 功能規格：Dio 攔截器全生命週期 Fail-Safe 防禦（§P39）

- **日期**：2026-11-02
- **來源**：`docs/brainstorm/2026-11-15-features-brainstorm.md` §P39（【網路防禦】Dio 攔截器全生命週期 Fail-Safe 雙重防禦）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在宿主 App 中整合 `FlutterInspectorDioInterceptor` 的開發者，當攔截器內部執行期間因非預期例外或 Dart `Error`（如資料格式化異常、二進位字串化、自訂物件拋錯等）崩潰時，
> 我希望**攔截器將所有觀測邏輯封裝在隔離的防禦邊界內，保證單次呼叫 `handler.next(...)` 放行宿主網路連線，絕不因除錯工具內部的錯誤中斷或掛起宿主的業務請求，亦不吞噬下游攔截器的正常異常**，
> 這樣既能徹底守護「Never break userspace」的底線穩定性，又能透過 Inspector 日誌時間軸得知內部異常。

### 為什麼需要這項改進

目前 `FlutterInspectorDioInterceptor` 在 `onRequest`、`onResponse`、`onError` 三個生命週期勾點中，均是裸呼叫格式化邏輯並在末尾執行 `handler.next(...)`。若：
1. 宿主傳入或後端回傳特殊的資料型別，在 `_stringifyData` 或格式化期間拋出非預期例外（如 `StateError`、`FormatException` 等）；
2. 甚至是 Dart `Error`（例如二進位解碼溢位、型別轉換錯誤等）；

當未捕獲的例外逃逸時，Dio 攔截器執行鏈被中斷，未呼叫 `handler.next()`，攔截器的同步例外會使包裝它的 Future 失敗並以 `DioException` 返回給宿主，導致宿主請求因除錯工具內部異常而中斷失敗。

為了解決此問題，必須明確切分「Inspector 觀測邏輯」與「Dio 管道調度（`handler.next`）」的職責邊界：
- 僅對 Inspector 內部的 entry 建構、字串化與日誌寫入進行 `try-catch(Object)` 防禦；
- `handler.next(...)` 位於保護區外作為全域唯一出口，絕不將 `handler.next` 包在 `try` 內（避免捕獲 `handler.next` 自身的同步例外，確保管道調度與除錯觀測職責分離）；
- 消滅任何人為的狀態旗標（如 `handled`）與 `finally` 補丁，達成無條件單一出口與好品味架構。

---

## 2. 範圍邊界

### ✅ 做

- 在 `lib/src/interceptors/dio_interceptor.dart` 中的三大生命週期方法：
  - `onRequest(RequestOptions options, RequestInterceptorHandler handler)`
  - `onResponse(Response response, ResponseInterceptorHandler handler)`
  - `onError(DioException err, ErrorInterceptorHandler handler)`
- 每個方法均遵循「觀測守衛 + 單一出口」架構：
  - 僅對 Inspector 內部記錄與資料解析邏輯包裹 `try` 區塊；
  - 捕捉 `on Object catch (e, st)`（涵蓋所有 `Exception` 與 Dart `Error`）；
  - 捕獲內部錯誤時，以安全 `try-catch` 呼叫 `_inspector.log('DioInterceptor.<method> internal error: $e', level: LogLevel.warning, stackTrace: st.toString());` 記錄至時間軸（其中 `<method>` 對應 `onRequest`、`onResponse`、`onError`）；
  - `handler.next(...)` 位於 `try-catch` 之外，無條件單次執行，確保放行宿主請求且不吞噬下游異常；
- 於 `test/interceptors/dio_interceptor_test.dart` 增加單元測試（採零 Mock 策略）：
  - 建立自訂物件 `_ThrowingData`（`toString()` 拋出 `StateError('boom')`），作為 `options.data` 或 `response.data`，驗證在 `onRequest`、`onResponse`、`onError` 拋錯時仍單次呼叫 `handler.next`，請求不掛起。
  - 驗證攔截器內部異常時，向 `_inspector.registry.log` 成功寫入帶有 `'DioInterceptor.<method> internal error:'` 的 `LogLevel.warning` 記錄。
  - 驗證正常請求、回應、錯誤流程無重複呼叫 `handler.next()`。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 將 `handler.next(...)` 包進 `try` 區塊 | 若下游攔截器拋出業務異常，置於 `try` 內會被 `on Object catch` 誤捕獲並吞噬，破壞宿主異常管線 |
| 引入 `bool handled` 與 `finally` 狀態補丁 | 職責分離後 `handler.next` 自然位於單一出口，狀態變數與條件分支均屬過度工程 |
| 在內部異常時呼叫 `handler.reject(...)` | 攔截器自身錯誤非業務連線錯誤，呼叫 reject 會人為阻斷宿主本該成功的網路連線，嚴重破壞用戶空間 |
| 修改 Dio 客戶端逾時或重試機制 | 保持除錯工具純被動觀測定位，不侵入業務網路行為 |

---

## 3. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | 當 `onRequest` 內部邏輯拋出 Dart `Error`（如 `StateError`）或 `Exception` 時，`handler.next(options)` 必定被執行，且僅執行一次 | 單元測試（`dio_interceptor_test.dart`） |
| 2 | 當 `onResponse` 內部邏輯拋出錯誤時，`handler.next(response)` 必定被執行，且僅執行一次 | 單元測試（`dio_interceptor_test.dart`） |
| 3 | 當 `onError` 內部邏輯拋出錯誤時，`handler.next(err)` 必定被執行，且僅執行一次 | 單元測試（`dio_interceptor_test.dart`） |
| 4 | 當攔截器內部發生異常被捕獲時，向 `_inspector.registry.log` 記錄包含 `'DioInterceptor.<method> internal error:'` 的 `LogLevel.warning` 警告與對應堆疊 | 單元測試（`dio_interceptor_test.dart`） |
| 5 | 下游攔截器在 `handler.next` 之後拋出的異常不會被 Inspector 吞噬 | 單元測試或架構結構保證 |
| 6 | 全部測試通過（`flutter test`）且靜態分析無新增警告（`dart analyze lib/ test/`） | 指令執行驗證 |
