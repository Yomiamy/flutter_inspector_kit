# 實作計畫：Dio `ResponseBody` 與原始 `Stream` 安全友善佔位（§P34）

- **日期**：2026-11-07 ｜ **Effort**：trivial ｜ **總任務數：2**（TDD：1 → 2）
- **規格**：[`docs/features/2026-11-07-dio-responsebody-stream-placeholder.md`](../features/2026-11-07-dio-responsebody-stream-placeholder.md)

## 1. 資料結構與方向 Trade-off

**純字串佔位，零新模型、零 `NetworkEntry` 欄位、零公開 API。** `requestBody`／`responseBody` 仍是 `String?`，`_stringifyData` 只多一條規則：`ResponseBody` 或 `Stream` 回傳 `'[stream]$kTruncatedMarker'`。marker 沿用既有 `isRequestTruncated` → Resend 停用路徑，UI、formatter 不用改。

| 方案 | 結論 | 理由 |
|:---|:---:|:---|
| A：`is` 型別檢查回傳固定佔位 | 採用 | `is` 不呼叫串流任何方法；與 `[binary N bytes]` 同構，+4 行 |
| B：tee／`StreamSplitter` 替換 `data` 旁路擷取 | 否決 | 改寫宿主的請求／回應物件，違反 Never break userspace；規格明列排除 |
| C：比對 `runtimeType.toString()` 辨識 | 否決 | 依賴 Dio／SDK 私有類名（`_ControllerStream`），換版即失效 |

**破壞性**：只有 `ResponseBody`／`Stream` 的輸出由 `Instance of '...'` 改為佔位，原字串無可依賴語意；其他型別路徑不變。各分支型別互斥（已用 Dio 5.11.1 實測 `ResponseBody is Stream == false`、`FormData` 不是 `Stream`），落點順序不影響結果。

## 2. 檔案異動清單

| 檔案 | 動作 | 預估 | 說明 |
|:---|:---:|:---:|:---|
| `test/interceptors/dio_interceptor_test.dart` | 修改 | +約 75 | `dart:async` import、`_TrackedStream` helper、§P34 群組 2 個測試 |
| `lib/src/interceptors/dio_interceptor.dart` | 修改 | +4 | `_stringifyData` 一個分支；無新 import（`ResponseBody` 由 `package:dio/dio.dart` 匯出） |

main 上的測試檔已有 `Uint8List binary payload placeholder` 與 `Fail-Safe error handling (§P39)` 群組、helper `_ThrowingData`／`_ThrowingRequestHandler`；**沒有** §P33 的 `FormData` 群組與 `redaction.dart` import。

## 3. 任務

### Task 1 `[快/便宜]`：撰寫串流佔位測試（TDD Red）

**寫入路徑**：`test/interceptors/dio_interceptor_test.dart`。第 1 行加 `import 'dart:async';`，`_ThrowingRequestHandler` 之後加 helper：

```dart
/// Single-subscription stream; a second listen would throw StateError.
class _TrackedStream {
  _TrackedStream(List<int> bytes) {
    _controller
      ..add(Uint8List.fromList(bytes))
      ..close();
  }

  late final _controller = StreamController<Uint8List>(
    onListen: () => listened = true,
  );
  bool listened = false;

  Stream<Uint8List> get stream => _controller.stream;
}
```

在 `Uint8List binary payload placeholder` 群組之後、§P39 群組之前插入（避開 §P33 在 §P39 之後的插入點）：

```dart
    group('ResponseBody / Stream placeholder (§P34)', () {
      test('onResponse renders [stream] without subscribing', () async {
        final upload = _TrackedStream([1, 2, 3]);
        final download = _TrackedStream([4, 5]);
        final options = RequestOptions(
          path: 'http://example.com/sse',
          method: 'POST',
          data: upload.stream,
        );
        interceptor.onRequest(options, RequestInterceptorHandler());
        final pending = inspector.registry.network.entries.single;
        expect(pending.requestBody, '[stream]$kTruncatedMarker');
        expect(pending.isRequestTruncated, isTrue);

        interceptor.onResponse(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody(download.stream, 200),
          ),
          ResponseInterceptorHandler(),
        );

        final entry = inspector.registry.network.entries.single;
        expect(entry.isComplete, isTrue);
        expect(entry.requestBody, pending.requestBody);
        expect(entry.responseBody, '[stream]$kTruncatedMarker');
        expect(upload.listened, isFalse);
        expect(download.listened, isFalse);
        // The host can still consume both single-subscription streams.
        expect(await upload.stream.expand((c) => c).toList(), [1, 2, 3]);
        expect(await download.stream.expand((c) => c).toList(), [4, 5]);
      });

      test('onError renders [stream] without subscribing', () async {
        final upload = _TrackedStream([1, 2, 3]);
        final download = _TrackedStream([4, 5]);
        final options = RequestOptions(
          path: 'http://example.com/upload',
          method: 'POST',
          data: upload.stream,
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final errorHandler = ErrorInterceptorHandler();
        interceptor.onError(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 500,
              data: ResponseBody(download.stream, 500),
            ),
          ),
          errorHandler,
        );
        // ignore: invalid_use_of_protected_member
        await errorHandler.future.then((_) {}, onError: (_) {});

        final entry = inspector.registry.network.entries.single;
        expect(entry.requestBody, '[stream]$kTruncatedMarker');
        expect(entry.responseBody, '[stream]$kTruncatedMarker');
        expect(upload.listened, isFalse);
        expect(download.listened, isFalse);
        expect(await upload.stream.expand((c) => c).toList(), [1, 2, 3]);
        expect(await download.stream.expand((c) => c).toList(), [4, 5]);
      });
    });
```

- 驗收對應（規格第 4 節）：測試 1 → #1、#3、#4、#5；測試 2 → #2、#4（與 onRequest 斷言同一字串）、#5。`Stream<Uint8List>` 屬於 `Stream<List<int>>`（已實測），對應 #3 上傳情境。兩段片段已用 `dart format --language-version=3.10` 驗過，零差異。
- **驗證／驗收**：`rtk flutter test test/interceptors/dio_interceptor_test.dart` → 2 個新測試失敗在佔位斷言（實際值 `Instance of '_ControllerStream<Uint8List>'`），其餘既有測試全過。

### Task 2 `[快/便宜]`：實作 `_stringifyData` 分支（TDD Green）＋全套驗證

**寫入路徑**：`lib/src/interceptors/dio_interceptor.dart`。在 Map/List 區塊之後、最後的 `return data.toString();` 正上方插入（避開 §P33 在 `Uint8List` 後的插入點，三方合併可自動完成）：

```dart
    // Never listen: host streams are single-subscription, a 2nd listen throws.
    if (data is ResponseBody || data is Stream) {
      return '[stream]$kTruncatedMarker';
    }
```

- `ResponseBody` 沒有實作 `Stream`（串流在 `.stream` 欄位），兩個 `is` 缺一不可；不需額外 `try`，三個 hook 外層既有 §P39 `on Object catch` 已涵蓋。
- **驗證／驗收**：`rtk flutter test test/interceptors/dio_interceptor_test.dart` → `rtk flutter test` → `rtk flutter analyze lib/ test/`；單檔全綠；全套全綠（Task 1 前先實測記下全套測試總數 B，完成後須為 B + 2）；analyze 仍只有既有 7 個 info（6 個 `deprecated_member_use`、1 個 `share_text_web.dart:15`）。

## 4. 與 §P33（PR #243，未合併）的衝突處理

- **`dio_interceptor.dart`**：§P33 在 `Uint8List` 分支後插入 `FormData` 分支；本項插在最後的 `toString()` 之前，兩者相隔 Map/List 區塊，預期自動合併。型別互斥，順序不影響行為。後合併的一方仍須重跑 Task 2 三條驗證指令。
- **測試檔**：本項群組在 §P39 之前、§P33 群組在之後；`dart:async` 在第 1 行、§P33 的 import 在 `network_entry.dart` 之後，預期不衝突。

## 5. 執行方式

1. **主進程原地執行（建議）**：總改動約 80 行、2 個檔；Task 2 只有 4 行，符合「單檔 ≤ 20 行且無公共 API 變更」的派發煞車。1 → 2 完成後交 verifier 驗收。
2. **Subagent-Driven，序列執行**：Task 1 派 `[快/便宜]` subagent（回報附 Red 輸出），Task 2 主進程原地完成。
3. **Parallel Session（不建議）**：Task 2 依 TDD 必須等 Task 1 的 Red，無法並行。
