# 實作計畫：Dio `FormData`（Multipart）上傳摘要化與欄位脫敏（§P33）

- **日期**：2026-11-07
- **規格**：[`docs/features/2026-11-07-dio-formdata-summary.md`](../features/2026-11-07-dio-formdata-summary.md)
- **來源**：`docs/brainstorm/2026-11-04-features-brainstorm.md` §P33（源自 §Z1-9）
- **Effort**：trivial

---

## 1. 資料結構與設計方向 Trade-off

**零新資料結構、零模型欄位、零公開 API 變更、零新 option。** `NetworkEntry.requestBody` 仍然是 `String?`，`FormData` 只是多了一種「轉成字串」的規則。

### 1.1 方案比較

1. **方案 A（採用）：在 `_stringifyData` 新增 `data is FormData` 分支，擷取時產生已遮蔽的摘要字串**
   - 與既有 `Uint8List` 分支同構：同樣輸出佔位字串、同樣以 `kTruncatedMarker` 結尾，直接沿用 `isRequestTruncated` → Resend 停用的既有路徑，UI 與 formatter 都不用改。
   - 遮蔽沿用 `isSensitiveRoutingKey` + `kRedactedValue`，前例是 `navigator_observer.dart` 擷取路由參數時遮蔽。
   - `_stringifyData` 是實例方法，可以直接讀 `_inspector.redactSensitiveData`，不用改簽章。
   - 改動約 17 行，集中在單一檔案。
2. **方案 B（不採用）：`NetworkEntry` 保存原始 `FormData` 參照，到顯示／匯出時才格式化**
   - `MultipartFile` 持有產生 bytes 的 closure（`fromBytes` 會留住整個 `List<int>`），放進 500 筆的 `RingBuffer` 等於把上傳檔案的 bytes 一起留在記憶體裡。
   - 要動 `NetworkEntry` 的欄位、`copyWith`、`==`／`hashCode`，`network_formatters.dart`、`NetworkDetailView`、`agent_prompt.dart` 也都要各自加分支。好處只有「匯出時才遮蔽」，代價卻是整條資料流都要改。
3. **方案 C（不採用）：擷取時保留原值，匯出時再由 formatter 解析摘要字串來遮蔽**
   - 欄位值本身可能含 `, ` 或 `=`，從字串反解析不可靠；而且 UI 詳情頁不經過 formatter，仍會顯示原文密碼。這是用解析器補資料結構的洞。

### 1.2 本次決定的設計細節

| 問題 | 決定 | 理由 |
|:---|:---|:---|
| 排列順序 | **先 `files`、後 `fields`**，兩組各自維持 Dio 列表順序 | Dio 實際送出順序是先 fields 後 files（`form_data.dart:180-193`），這裡刻意偏離，取捨是：檔案排前面，10 KB 整體截斷就只會截到欄位值，優先保留檔案 metadata（檔案摘要總長 < 10 KB 時），省掉單欄位截斷這個特例 |
| 分隔符 | 項目之間用 `, `，key 與值之間用 `=`；檔案寫成 `key=filename (N B)` | 照 §P33 原規格的範例格式，檔案和欄位都用 `key=` 開頭，靠 ` (N B)` 後綴區分 |
| 單一欄位值過長 | **不另外截斷** | `NetworkInspector.add` → `NetworkEntry.truncateBody` 已有 10 KB 兜底（含 surrogate pair 防護），再加一層上限就多一個常數和分支；超長 `String` body 本來也是走同一條路 |
| 空表單 | `[FormData: empty]` | 照規格；用 `parts.isEmpty` 一個條件處理，不另外寫分支 |
| `filename` 為 null | `<unnamed>` | 照規格 |
| 結尾標記 | 一律附 `kTruncatedMarker` | 讓 `isRequestTruncated == true`，Resend 自動停用（`network_detail_view.dart` 的 `_ResendAction._disabled`） |
| 三處呼叫一致性 | 不需要特別處理 | 摘要只取決於 `(FormData metadata, final bool redactSensitiveData)`；`fields`／`files`／`length`／`filename` 都是一般欄位，Dio 在 `dio_mixin.dart:721（`_transformData`）` 呼叫 `finalize()`、把 stream 讀完之後仍可讀取（已在 Dio 5.11.1 實測：`readAsBytes()` 前後摘要逐字相同） |
| `finalize()` | 不呼叫 | `FormData.finalize()` 第二次呼叫會拋 `StateError`（`form_data.dart:165`），Inspector 若先呼叫就等於弄壞宿主的上傳 |

### 1.3 破壞性分析

- 只有 `data is FormData` 的情況會改變輸出：原本是 `Instance of 'FormData'`，這個字串沒有任何使用者能依賴的語意。`String`／`Uint8List`／`Map`／`List` 等其他型別的路徑完全不變。
- 分支內若拋例外，會被 §P39 既有的 `on Object catch` 接住，`handler.next` 照常執行，宿主請求不受影響。
- `FormData`／`MultipartFile.fromBytes` 在 Web 上也能用，不涉及條件匯出。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 預估行數 | 說明 |
|:---|:---:|:---:|:---|
| `test/interceptors/dio_interceptor_test.dart` | 修改 | +約 150 | 新增 1 個 import，以及 `FormData multipart summary (§P33)` 群組（7 個測試） |
| `lib/src/interceptors/dio_interceptor.dart` | 修改 | +約 17 | 新增 2 個 import，以及 `_stringifyData` 的 `FormData` 分支 |
| `lib/src/core/flutter_inspector.dart` | 修改 | +4 | 只改 `redactSensitiveData` 的 dartdoc（不動 API） |

---

## 3. 任務拆分

**總任務數：3**（全部 `[快/便宜]`，依 TDD 順序執行：1 → 2 → 3）

| Task | 寫入檔案 | 預估行數 | 測試 | 依賴 |
|:---:|:---|:---:|:---|:---|
| 1 | `test/interceptors/dio_interceptor_test.dart` | +約 150 | 7 個新測試，預期全部失敗（Red） | 無 |
| 2 | `lib/src/interceptors/dio_interceptor.dart` | +約 17 | 7 個新測試轉綠＋該檔既有測試 | Task 1 |
| 3 | `lib/src/core/flutter_inspector.dart` | +4 | 全套 `flutter test`＋`flutter analyze` | Task 2（只有驗證需要等 Task 2；寫入路徑不重疊） |

---

### Task 1 `[快/便宜]`：撰寫 `FormData` 摘要測試（TDD Red）

**寫入路徑**：`test/interceptors/dio_interceptor_test.dart`
**預估行數**：+約 150

#### Step 1：新增 import

在既有 import 區塊（`network_entry.dart` 之後）加上：

```dart
import 'package:flutter_inspector_kit/src/utils/redaction.dart';
```

（`FormData`、`MultipartFile` 已由 `package:dio/dio.dart` 匯入，`kTruncatedMarker` 已由 `network_entry.dart` 匯入。）

#### Step 2：新增測試群組

在 `group('Fail-Safe error handling (§P39)', ...)` 之後、外層 `group('FlutterInspectorDioInterceptor', ...)` 結束之前，加入下面這段（已用 `dart format` 排過版）：

```dart
    group('FormData multipart summary (§P33)', () {
      test(
        'onRequest lists files before fields and never finalizes the FormData',
        () {
          final formData = FormData.fromMap({
            'name': 'Alice',
            'avatar': MultipartFile.fromBytes(
              List<int>.filled(1024, 0),
              filename: 'avatar.png',
            ),
          });
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: formData,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());

          final entry = inspector.registry.network.entries.first;
          expect(
            entry.requestBody,
            '[FormData: avatar=avatar.png (1024 B), name=Alice]$kTruncatedMarker',
          );
          expect(entry.isRequestTruncated, isTrue);
          expect(formData.isFinalized, isFalse);
          expect(formData.files.single.value.isFinalized, isFalse);
        },
      );

      test('empty FormData renders the empty placeholder', () {
        final options = RequestOptions(
          path: 'http://example.com/upload',
          method: 'POST',
          data: FormData(),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(entry.requestBody, '[FormData: empty]$kTruncatedMarker');
        expect(entry.isRequestTruncated, isTrue);
      });

      test('file without a filename renders <unnamed>', () {
        final options = RequestOptions(
          path: 'http://example.com/upload',
          method: 'POST',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes([1, 2, 3]),
          }),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(
          entry.requestBody,
          '[FormData: file=<unnamed> (3 B)]$kTruncatedMarker',
        );
        expect(entry.isRequestTruncated, isTrue);
      });

      test('masks sensitive field values when redactSensitiveData is true', () {
        final options = RequestOptions(
          path: 'http://example.com/login',
          method: 'POST',
          data: FormData.fromMap({'username': 'alice', 'password': 'hunter2'}),
        );
        interceptor.onRequest(options, RequestInterceptorHandler());

        final entry = inspector.registry.network.entries.first;
        expect(
          entry.requestBody,
          '[FormData: username=alice, password=$kRedactedValue]$kTruncatedMarker',
        );
        expect(entry.requestBody, isNot(contains('hunter2')));
        expect(entry.isRequestTruncated, isTrue);
      });

      test('keeps raw field values when redactSensitiveData is false', () {
        final rawInspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
          redactSensitiveData: false,
        );
        final options = RequestOptions(
          path: 'http://example.com/login',
          method: 'POST',
          data: FormData.fromMap({'password': 'hunter2'}),
        );
        FlutterInspectorDioInterceptor(
          rawInspector,
        ).onRequest(options, RequestInterceptorHandler());

        final entry = rawInspector.registry.network.entries.first;
        expect(
          entry.requestBody,
          '[FormData: password=hunter2]$kTruncatedMarker',
        );
        expect(entry.isRequestTruncated, isTrue);
      });

      test(
        'onResponse keeps the onRequest summary after Dio drains the FormData',
        () async {
          final formData = FormData.fromMap({
            'password': 'hunter2',
            'avatar': MultipartFile.fromBytes([1, 2], filename: 'a.png'),
          });
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: formData,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());
          final requestSummary =
              inspector.registry.network.entries.single.requestBody;
          // Dio finalizes and streams the FormData while sending it.
          await formData.readAsBytes();

          interceptor.onResponse(
            Response(requestOptions: options, statusCode: 201),
            ResponseInterceptorHandler(),
          );

          final entry = inspector.registry.network.entries.single;
          expect(entry.isComplete, isTrue);
          expect(entry.requestBody, requestSummary);
          expect(
            entry.requestBody,
            '[FormData: avatar=a.png (2 B), password=$kRedactedValue]$kTruncatedMarker',
          );
        },
      );

      test(
        'onError keeps the onRequest summary after Dio drains the FormData',
        () async {
          final formData = FormData.fromMap({
            'password': 'hunter2',
            'avatar': MultipartFile.fromBytes([1, 2], filename: 'a.png'),
          });
          final options = RequestOptions(
            path: 'http://example.com/upload',
            method: 'POST',
            data: formData,
          );
          interceptor.onRequest(options, RequestInterceptorHandler());
          final requestSummary =
              inspector.registry.network.entries.single.requestBody;
          await formData.readAsBytes();

          final errorHandler = ErrorInterceptorHandler();
          interceptor.onError(
            DioException(requestOptions: options, error: 'fail'),
            errorHandler,
          );
          // ignore: invalid_use_of_protected_member
          await errorHandler.future.then((_) {}, onError: (_) {});

          final entry = inspector.registry.network.entries.single;
          expect(entry.isComplete, isTrue);
          expect(entry.requestBody, requestSummary);
          expect(
            entry.requestBody,
            '[FormData: avatar=a.png (2 B), password=$kRedactedValue]$kTruncatedMarker',
          );
        },
      );
    });
```

測試與驗收條件的對應：

| 測試 | 驗收條件（規格第 4 節） |
|:---|:---|
| `onRequest lists files before fields and never finalizes the FormData` | #1、#2、#7 |
| `empty FormData renders the empty placeholder` | #3、#7 |
| `file without a filename renders <unnamed>` | #4、#7 |
| `masks sensitive field values when redactSensitiveData is true` | #5、#7 |
| `keeps raw field values when redactSensitiveData is false` | #6、#7 |
| `onResponse keeps the onRequest summary after Dio drains the FormData` | #8 |
| `onError keeps the onRequest summary after Dio drains the FormData` | #8 |

#### Step 3：確認 Red

```bash
rtk flutter test test/interceptors/dio_interceptor_test.dart
```

預期：7 個新測試全部失敗，實際值是 `Instance of 'FormData'`；其餘既有測試維持通過。

---

### Task 2 `[快/便宜]`：實作 `_stringifyData` 的 `FormData` 分支（TDD Green）

**寫入路徑**：`lib/src/interceptors/dio_interceptor.dart`
**預估行數**：+約 17

#### Step 1：新增 import

依字母序接在 `import '../models/network_entry.dart';` 之後：

```dart
import '../utils/redaction.dart';
import '../utils/routing_param_extractor.dart';
```

#### Step 2：在 `Uint8List` 分支之後插入 `FormData` 分支

完成後 `_stringifyData` 會是這樣（只有 `FormData` 那段是新增的）：

```dart
  String? _stringifyData(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Uint8List) {
      return '[binary ${data.length} bytes]$kTruncatedMarker';
    }
    if (data is FormData) {
      // Files first: the 10 KB body cap then trims field values, not files.
      final redact = _inspector.redactSensitiveData;
      final parts = [
        for (final MapEntry(:key, value: file) in data.files)
          '$key=${file.filename ?? '<unnamed>'} (${file.length} B)',
        for (final MapEntry(:key, :value) in data.fields)
          redact && isSensitiveRoutingKey(key)
              ? '$key=$kRedactedValue'
              : '$key=$value',
      ];
      // The marker disables Replay: a summary is not a resendable payload.
      return '[FormData: ${parts.isEmpty ? 'empty' : parts.join(', ')}]'
          '$kTruncatedMarker';
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

說明：
- `MapEntry(:key, :value)` 的解構寫法與 `routing_param_extractor.dart` 的 `_sanitize` 一致。
- 參數 `data` 宣告為 `dynamic`，但 `is FormData` 會讓它型別提升，所以 `data.files`／`data.fields` 有完整型別（已在 Dart 3.13.1 + Dio 5.11.1 下以同樣形狀的程式碼跑過 `dart analyze`，無任何問題）。
- 不需要額外處理 `try`：`onRequest`／`onResponse`／`onError` 外層既有的 §P39 `on Object catch` 已經涵蓋這段。

#### Step 3：確認 Green

```bash
rtk flutter test test/interceptors/dio_interceptor_test.dart
```

預期：該檔全部測試通過（包含 7 個新測試）。

---

### Task 3 `[快/便宜]`：補 `redactSensitiveData` dartdoc，並跑全套驗證

**寫入路徑**：`lib/src/core/flutter_inspector.dart`
**預估行數**：+4（只改文件註解）

#### Step 1：補 dartdoc

把：

```dart
  /// Whether to mask sensitive headers (e.g. `Authorization`, `Cookie`,
  /// `Set-Cookie`, `X-Api-Key`) in all share/export paths (cURL, plain text).
  ///
  /// Defaults to `true` so secrets never leak to the clipboard, a share sheet,
  /// or a screenshot unless the host explicitly opts out.
  final bool redactSensitiveData;
```

改成：

```dart
  /// Whether to mask sensitive headers (e.g. `Authorization`, `Cookie`,
  /// `Set-Cookie`, `X-Api-Key`) in all share/export paths (cURL, plain text).
  ///
  /// Dio `FormData` field values under sensitive-looking keys (e.g.
  /// `password`, `token`) are masked at capture time instead, because a
  /// multipart body is only ever stored as a summary string.
  ///
  /// Defaults to `true` so secrets never leak to the clipboard, a share sheet,
  /// or a screenshot unless the host explicitly opts out.
  final bool redactSensitiveData;
```

#### Step 2：全套驗證

```bash
rtk flutter test
rtk flutter analyze lib/ test/
```

預期：
- `flutter test` 全綠（既有測試數 + 7）。
- `flutter analyze lib/ test/` 仍只有既有的 7 個 info（6 個 `deprecated_member_use`、1 個 `share_text_web.dart:15`），沒有新增。

---

## 4. 執行方式選擇

依 `gen-dev-workflow` STAGE 2 的派發規則，可以選擇下列方式：

1. **Subagent-Driven，序列執行（建議）**
   - Task 1（單檔約 150 行）：派給 `[快/便宜]` subagent，回報時須附上 Red 的測試輸出。
   - Task 2（單檔約 17 行，無公共 API 變更）、Task 3（單檔 4 行，只改 dartdoc）：都符合「派發煞車」條件（單檔 ≤ 20 行且無公共 API 變更），由主進程原地修改並原地跑測試，不派 subagent。
   - 最後由 verifier 兩階段驗收。
2. **Parallel Session（不建議）**
   - Task 3 的寫入路徑與 Task 1、2 都不重疊，理論上可以並行；但它只有 4 行，而 Task 2 依 TDD 必須等 Task 1 的 Red 完成，開並行 session／worktree 的成本比省下的時間還高。
3. **主進程全程原地執行**
   - 總改動約 170 行、3 個檔案、改動直接明確，也可以由主進程依 Task 1 → 2 → 3 直接完成，省掉派發開銷。

---

## 5. 範圍外（交接備忘）

- README（Network 段落第 353 行附近的 binary placeholder 說明）與 CHANGELOG：依專案慣例在 release commit 統一更新，屆時再補一句 `FormData` 摘要說明。
- `docs/brainstorm/2026-11-04-features-brainstorm.md` §P33 的狀態標記（⬜ → ✅）：PR merge 後再處理。
- §P34 `ResponseBody`／`Stream` 佔位：另開 PR。
