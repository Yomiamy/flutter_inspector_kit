# 實作計畫：Replay 結果顯示狀態碼（§Z4-2）

- **日期**：2026-10-18
- **規格**：[`docs/features/2026-10-18-replay-result-status-code.md`](../features/2026-10-18-replay-result-status-code.md)
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §Z4-2
- **Effort**：trivial

---

## 1. 資料結構與設計方向 Trade-off

**不新增任何資料結構、模型或公開 API。**

### 方案比較

1. **方案 A（採用）：在 `_ResendActionState._resend` 內收斂 `statusCode` 與 `failureText` 後單點顯示 SnackBar**
   - 正常回應（`response.statusCode`）與 `DioExceptionType.badResponse`（`e.response?.statusCode`）本質都是「伺服器已回傳 HTTP 回應」，兩者提取 `int? statusCode` 後共用同一條格式化邏輯：`statusCode != null ? 'Resent → $statusCode' : 'Request resent'`。
   - 非 `badResponse` 的 `DioException` 設定 `failureText = 'Resend failed: ${e.type.name}'`；其餘未預期例外設定 `failureText = 'Resend failed'`。
   - **優點**：不碰 `Options.validateStatus`（確保 `FlutterInspectorDioInterceptor.onError` 照常攔截 4xx/5xx 重送並記錄 `error`），同時消除原本 4 處重複的 `messenger.showSnackBar(...)` 呼叫。
2. **方案 B（不採用）：設定 `Options(validateStatus: (_) => true)` 讓所有狀態碼都走 `try` 分支**
   - **缺點**：會改變 `Dio` 對 4xx/5xx 的拋錯行為，導致 `FlutterInspectorDioInterceptor` 走 `onResponse` 而非 `onError`，破壞既有 Test 4 所驗證的 `replays.first.error != null` 行為契約。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 說明 |
|:---|:---:|:---|
| `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | 修改 | `_ResendActionState._resend` 將狀態碼與 `DioExceptionType.name` 帶入 SnackBar 訊息 |
| `test/ui/tabs/network_detail_view_test.dart` | 修改 | 同步更新 `Resend action` 群組內 Test 3、Test 4、Test 4b 三處 SnackBar 字串斷言 |

---

## 3. 任務拆分

**總任務數：1（單一任務 `[快/便宜]`）**

### Task 1 `[快/便宜]`：更新 `_ResendActionState._resend` SnackBar 訊息與對應 Widget 測試

**寫入路徑**：
- `lib/src/ui/dashboard/tabs/network/network_detail_view.dart`
- `test/ui/tabs/network_detail_view_test.dart`

#### Step 1：先行更新測試斷言（TDD Red）

修改 `test/ui/tabs/network_detail_view_test.dart`：
1. Test 3（line 376）：
   ```dart
   // Success snackbar shown.
   expect(find.text('Resent → 200'), findsOneWidget);
   ```
2. Test 4（lines 379–417）：
   ```dart
   // Test 4: badResponse (500) resend → error entry recorded + "Resent → 500" snackbar
   testWidgets(
     'resend badResponse (500) records error entry and shows status code',
     (tester) async {
       ...
       // badResponse is treated as successful transmission with status code.
       expect(find.text('Resent → 500'), findsOneWidget);
     },
   );
   ```
3. Test 4b（lines 420–455）：
   ```dart
   // Test 4b: connection failure resend → "Resend failed: connectionError" snackbar
   testWidgets('resend connection failure shows resend failed with error type', (
     tester,
   ) async {
     ...
     expect(find.text('Resend failed: connectionError'), findsOneWidget);
   });
   ```

執行 `flutter test test/ui/tabs/network_detail_view_test.dart` 確認上述 3 個測試因舊字串而失敗（Red）。

#### Step 2：修改 `_ResendActionState._resend` 實作（TDD Green）

修改 `lib/src/ui/dashboard/tabs/network/network_detail_view.dart`（lines 387–409）：

```dart
    int? statusCode;
    String? failureText;
    try {
      final response = await dio.request<dynamic>(
        req.url,
        data: req.body,
        options: Options(
          method: req.method,
          headers: req.headers,
          extra: <String, dynamic>{'_inspector_is_replay': true},
        ),
      );
      statusCode = response.statusCode;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        statusCode = e.response?.statusCode;
      } else {
        failureText = 'Resend failed: ${e.type.name}';
      }
    } catch (_) {
      failureText = 'Resend failed';
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
    final text =
        failureText ??
        (statusCode != null ? 'Resent → $statusCode' : 'Request resent');
    messenger.showSnackBar(SnackBar(content: Text(text)));
```

#### Step 3：執行驗證

```bash
flutter test test/ui/tabs/network_detail_view_test.dart
flutter test
flutter analyze lib/ test/
```

---

## 4. 執行方式選擇

本計畫可在確認後進入 STAGE 1 建立 Issue 與 Worktree，並於 STAGE 2 以 **Subagent-Driven（單一任務委派 + Verifier 驗收）** 執行。
