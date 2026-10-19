# 實作計畫：Dio 回傳 bytes 時以二進位佔位字串取代 jsonEncode（§Z1-1）

- **日期**：2026-10-18
- **規格**：[`docs/features/2026-10-18-dio-bytes-binary-placeholder.md`](../features/2026-10-18-dio-bytes-binary-placeholder.md)
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §Z1-1
- **Effort**：low

---

## 1. 資料結構與設計方向 Trade-off

**不新增任何資料結構、欄位或公開 API。**

### 方案比較

1. **方案 A（採用）：在 `FlutterInspectorDioInterceptor._stringifyData` 針對 `Uint8List` 回傳帶 `kTruncatedMarker` 的佔位字串**
   - 在 `data is Map || data is List` 之前加入：
     ```dart
     if (data is Uint8List) {
       return '[binary ${data.length} bytes]$kTruncatedMarker';
     }
     ```
   - **優點**：
     - 從源頭消滅 `jsonEncode(Uint8List)` 的 O(N) 字串配置與 CPU 消耗，轉為 O(1)。
     - 佔位字串本身遠短於 `kNetworkBodyMaxLength`（10 KB），進入 `NetworkInspector.add` 時 `NetworkEntry.truncateBody` 會原樣保留、不會重複附加 `kTruncatedMarker`。
     - 以 `kTruncatedMarker` 結尾讓 `entry.isRequestTruncated` 與 `entry.isTruncated` 自然為 `true`，直接複用 `NetworkDetailView` 既有的「停用 Resend 按鈕」與「顯示截斷提示」行為，無需在 `NetworkEntry` 新增 `isBinary` 狀態或額外 `if/else` 分支。
2. **方案 B（不採用）：判斷 `data is List<int>`**
   - **缺點**：宿主若傳送普通 JSON 整數陣列（如 `data: [1, 2, 3]`，在 Dart 中型別即為 `List<int>`），會被誤判為 binary 而失去 JSON 內容。Dio 的 `ResponseType.bytes` 實際回傳型別固定為 `Uint8List`，只判 `Uint8List` 才能精準區分。
3. **方案 C（不採用）：在 `NetworkEntry` 新增 `bool isBinary` 欄位並在 UI 各處特判**
   - **缺點**：破壞資料結構簡潔性，且需同步修改 `copyWith`、`operator ==`、`hashCode` 與 UI 元件，違反好品味與 YAGNI。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 說明 |
|:---|:---:|:---|
| `lib/src/interceptors/dio_interceptor.dart` | 修改 | 匯入 `dart:typed_data`，於 `_stringifyData` 加入 `data is Uint8List` 分支回傳 `'[binary ${data.length} bytes]$kTruncatedMarker'` |
| `test/interceptors/dio_interceptor_test.dart` | 修改 | 新增 `Uint8List` 於 `onRequest`、`onResponse`、`onError` 的佔位與截斷標記測試，以及普通 `List<int>` 不被誤判的測試 |

---

## 3. 任務拆分

**總任務數：1（單一任務 `[快/便宜]`）**

### Task 1 `[快/便宜]`：實作 `_stringifyData` 的 `Uint8List` 二進位佔位與單元測試

**寫入路徑**：
- `lib/src/interceptors/dio_interceptor.dart`
- `test/interceptors/dio_interceptor_test.dart`

#### Step 1：先行撰寫失敗測試（TDD Red）

於 `test/interceptors/dio_interceptor_test.dart` 匯入 `dart:typed_data` 與 `package:flutter_inspector_kit/src/models/network_entry.dart`，並在 `FlutterInspectorDioInterceptor` 群組內新增測試：

```dart
    group('Uint8List binary payload placeholder', () {
      test(
        'onResponse formats Uint8List as binary placeholder with truncated marker',
        () {
          final options = RequestOptions(
            path: 'http://example.com/file.png',
            method: 'GET',
            responseType: ResponseType.bytes,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final bytes = Uint8List.fromList([137, 80, 78, 71]);
          final response = Response<Uint8List>(
            requestOptions: options,
            statusCode: 200,
            data: bytes,
          );
          interceptor.onResponse(response, ResponseInterceptorHandler());

          final entry = inspector.registry.network.entries.first;
          expect(entry.responseBody, '[binary 4 bytes]$kTruncatedMarker');
          expect(entry.isTruncated, isTrue);
        },
      );

      test(
        'onRequest formats Uint8List as binary placeholder and marks request truncated',
        () {
          final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: bytes,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final entry = inspector.registry.network.entries.first;
          expect(entry.requestBody, '[binary 6 bytes]$kTruncatedMarker');
          expect(entry.isRequestTruncated, isTrue);
          expect(entry.isTruncated, isTrue);
        },
      );

      test(
        'onError formats Uint8List response data as binary placeholder',
        () async {
          final options = RequestOptions(
            path: 'http://example.com/error-bytes',
            method: 'GET',
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final errorHandler = ErrorInterceptorHandler();
          final err = DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<Uint8List>(
              requestOptions: options,
              statusCode: 500,
              data: Uint8List.fromList([0xff, 0x00]),
            ),
          );
          interceptor.onError(err, errorHandler);
          // ignore: invalid_use_of_protected_member
          await errorHandler.future.then((_) {}, onError: (_) {});

          final entry = inspector.registry.network.entries.first;
          expect(entry.responseBody, '[binary 2 bytes]$kTruncatedMarker');
          expect(entry.isTruncated, isTrue);
        },
      );

      test('plain List<int> is still serialized as JSON array, not binary', () {
        final options = RequestOptions(
          path: 'http://example.com/numbers',
          method: 'POST',
          data: <int>[137, 80, 78, 71],
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(entry.requestBody, '[137,80,78,71]');
        expect(entry.isRequestTruncated, isFalse);
      });
    });
```

執行 `flutter test test/interceptors/dio_interceptor_test.dart`，確認前 3 個測試因 `Uint8List` 被 `jsonEncode` 成 `'[137,80,78,71]'` 等字串而失敗（Red）。

#### Step 2：修改 `dio_interceptor.dart` 實作（TDD Green）

修改 `lib/src/interceptors/dio_interceptor.dart`：
1. 頂部新增 `import 'dart:typed_data';`（按字母序排在 `import 'dart:convert';` 之後）。
2. 在 `_stringifyData` 內，於 `if (data is String) return data;` 之後加入 `Uint8List` 判斷：

```dart
  String? _stringifyData(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Uint8List) {
      return '[binary ${data.length} bytes]$kTruncatedMarker';
    }
    if (data is Map || data is List) {
      try {
        return jsonEncode(data);
      } catch (_) {
        return data.toString();
      }
    }
    return data.toString();
  }
```

#### Step 3：執行驗證

```bash
flutter test test/interceptors/dio_interceptor_test.dart
flutter test
flutter analyze lib/ test/
```

---

## 4. 執行方式選擇

本計畫可在確認後進入 STAGE 1 建立 Issue 與 Worktree，並於 STAGE 2 以 **Subagent-Driven（單一任務委派 + Verifier 驗收）** 執行。
