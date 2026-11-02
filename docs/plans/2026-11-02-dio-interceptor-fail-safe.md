# 實作計畫：Dio 攔截器全生命週期 Fail-Safe 防禦（§P39）

- **日期**：2026-11-02
- **規格**：[`docs/features/2026-11-02-dio-interceptor-fail-safe.md`](../features/2026-11-02-dio-interceptor-fail-safe.md)
- **來源**：`docs/brainstorm/2026-10-31-features-brainstorm.md` §P39
- **Effort**：trivial

---

## 1. 資料結構與設計方向 Trade-off

**零新資料結構、零模型修改、零公開 API 變更、零局部狀態旗標。**

### 核心設計考量（Linus 好品味五層分析）

1. **資料結構**：
   - 拒絕引入 `bool handled` 等狀態變數。
   - 職責徹底分離：Inspector 僅防護其「自身觀測與解析邏輯」，Dio 管道調度（`handler.next`）位於外部單一出口。
2. **邊界情況消滅（Good Taste）**：
   - **消滅下游異常吞噬**：若將 `handler.next` 包入 `try`，下游攔截器或傳輸層的同步異常會被 `on Object catch` 誤捕獲並靜默吞噬。將 `handler.next` 移至 `try-catch` 之後，徹底杜絕誤吞業務異常。
   - **消滅狀態變數與雙調用點**：
     ```dart
     @override
     void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
       try {
         options.extra['_inspector_start_time'] = DateTime.now();
         final entry = NetworkEntry(
           method: options.method,
           url: options.uri.toString(),
           requestHeaders: options.headers,
           requestBody: _stringifyData(options.data),
           sourceDio: sourceDio,
           isReplay: options.extra['_inspector_is_replay'] == true,
         );
         options.extra['_inspector_pending_entry'] = _inspector.logNetwork(entry);
       } on Object catch (e, st) {
         try {
           _inspector.log(
             'DioInterceptor.onRequest internal error: $e',
             level: LogLevel.warning,
             stackTrace: st.toString(),
           );
         } catch (_) {}
       }
       handler.next(options);
     }
     ```
   - 該結構在 `onResponse` 與 `onError` 嚴格對稱應用。
   - `handler.next(...)` 是全域單一出口，語法結構上保證無條件單次執行，徹底消滅 `finally` 與 `if (!handled)` 分支。
3. **破壞性與相容性**：
   - 100% 向後相容，完全不改變正常請求/回應的流程與資料。
   - 異常時一律放行宿主請求，絕不呼叫 `handler.reject()`，嚴守 Never break userspace。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 說明 |
|:---|:---:|:---|
| `lib/src/interceptors/dio_interceptor.dart` | 修改 | 為 `onRequest`、`onResponse`、`onError` 的 Inspector 觀測邏輯包裹 `try-catch(Object)` 防護，保持 `handler.next` 單一出口 |
| `test/interceptors/dio_interceptor_test.dart` | 修改 | 新增單元測試群組，以零 Mock 的 `_ThrowingData` 驗證各勾點拋錯時仍單次轉發，且記錄包含 `'DioInterceptor.<method> internal error:'` 的 warning 日誌 |

---

## 3. 任務拆分

**總任務數：1（單一任務 `[快/便宜]`，改動約 25 行）**

### Task 1 `[快/便宜]`：實作 `FlutterInspectorDioInterceptor` 三勾點 Fail-Safe 防護與單元測試

**寫入路徑**：
- `lib/src/interceptors/dio_interceptor.dart`
- `test/interceptors/dio_interceptor_test.dart`

#### Step 1：先行撰寫失敗測試（TDD Red）

於 `test/interceptors/dio_interceptor_test.dart` 建立輔助類別與測試群組：
```dart
class _ThrowingData {
  @override
  String toString() => throw StateError('custom toString failed');
}
```
新增 `Fail-Safe error handling` 測試群組：
1. **onRequest fail-safe**：`RequestOptions(path: 'http://example.com/api', method: 'POST', data: _ThrowingData())`，呼叫 `interceptor.onRequest(options, handler)`，斷言 handler 收到 `next` 且 `inspector.registry.log.entries` 包含一筆 `LogLevel.warning`，內容含 `'DioInterceptor.onRequest internal error:'`。
2. **onResponse fail-safe**：`Response(requestOptions: options, statusCode: 200, data: _ThrowingData())`，呼叫 `interceptor.onResponse(response, handler)`，斷言 handler 收到 `next` 且記錄包含 `'DioInterceptor.onResponse internal error:'` 的 warning。
3. **onError fail-safe**：`DioException` 其 `response` 的 `data` 為 `_ThrowingData()`，呼叫 `interceptor.onError(err, handler)`，斷言 handler 收到 `next` 且記錄包含 `'DioInterceptor.onError internal error:'` 的 warning。
4. **下游異常不被吞噬**：自訂 `RequestInterceptorHandler` 或驗證下游拋錯正常逃逸出 `interceptor.onRequest`，確認 Inspector 不介入下游異常。

#### Step 2：實作防護邏輯（TDD Green）

修改 `lib/src/interceptors/dio_interceptor.dart`：
- 將 `onRequest`、`onResponse`、`onError` 內部涉及 `entry` 構建與 `_inspector.logNetwork` 的部分包入 `try ... on Object catch (e, st)` 區塊。
- 捕獲內部錯誤時調用：
  `_inspector.log('DioInterceptor.<method> internal error: $e', level: LogLevel.warning, stackTrace: st.toString());`
  外層加安全 `try-catch` 防止日誌自身二次崩潰。
- `handler.next(...)` 位於方法末尾無條件呼叫。

#### Step 3：驗證（TDD Refactor & Verification）

- 執行 `flutter test test/interceptors/dio_interceptor_test.dart` 確認全數通過。
- 執行 `dart analyze lib/ test/` 確認零警告零錯誤。
