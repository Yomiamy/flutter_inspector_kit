# 實作計畫：路由敏感鍵遮蔽不再誤遮布林狀態與效期元數據（§P45）

- **日期**：2026-11-28 ｜ **Effort**：trivial ｜ **總任務數：2**（TDD：1 → 2）
- **規格**：[`docs/features/2026-11-28-routing-sensitive-key-metadata-whitelist.md`](../features/2026-11-28-routing-sensitive-key-metadata-whitelist.md)
- **寫入路徑**：只有 `lib/src/utils/routing_param_extractor.dart`、`test/utils/routing_param_extractor_test.dart`。公開 API 不變。

## 1. 資料結構與方向 Trade-off

**做法**：新增三張常數表、一個正規化 helper `_normalizeKey`，並在 `isSensitiveRoutingKey` 開頭加兩個 `return false` guard clause。原本的函式本體一行都不動，仍用原始 key 判定（也就是規格 §2.1 的第 3 步）。

**結構上就保證「只放行」**：新加的程式碼只有兩個 `return false`，而且都排在原本的本體之前，所以只可能把原本的 `true` 改成 `false`，不可能把 `false` 改成 `true`。規格 §2.2「不新增遮蔽」因此由程式結構保證，不必靠測試逐一證明，C 類測試只是當作回歸防線。

**第 2 步的簡化**：規格 §2.1 第 2 步寫的是「`rest` 是多詞機密名稱 → 交給第 3 步」。實作時這種情況不寫 `return true`，直接讓它落到既有規則。規劃階段已實測，B1–B4（`has_secret_token`、`hasSecretToken`、`is_password_key`、`has_api_key`）全都會被既有規則遮蔽，結果和規格相同，還少一個分支。

| 方案 | 結論 | 理由 |
|:---|:---:|:---|
| A：在既有本體前加兩個 `return false` guard，第 3 步完全不動 | **採用** | lib 只增加 47 行，其中邏輯 6 行，其餘是常數表；縮排 1 層；結構上保證只放行 |
| B：整個函式改成拿正規化後的 token 比對詞表 | 否決 | 會改變第 3 步的行為（`userPINCode` 正規化後是 `user_pincode`，`PIN` 的邊界消失，從遮蔽變成放行，即規格 §2.2 指出的回歸）；diff 大，既有測試風險高 |
| C：把放行規則全部塞進一條 regex（前綴、後綴與 `rest` 的負向判斷） | 否決 | 第 2 步「`rest` 不以機密詞結尾」要寫 negative lookahead／lookbehind，可讀性差，也難和規格表逐條對照 |
| D：照 brainstorm 原文替第 2 步的多詞機密名稱寫 `return true` | 否決 | 多一個分支，結果卻與落到既有規則相同；而且會破壞「新程式碼只會 `return false`」這個結構保證 |

**前綴取 `rest` 的寫法**：用 `RegExp(r'^(?:is|has|can|should)_(.*)$')` 的 capture group，一行就能同時判斷「有沒有布林前綴」並取出 `rest`。如果改用 `Set` 加迴圈，就得多一個「命中哪個前綴」的 nullable 中間值。四個前綴的首字母互不相同，不會有重疊命中的問題。

## 2. 檔案異動清單

| 檔案 | 動作 | 預估 | 改公開 API | 說明 |
|:---|:---:|:---:|:---:|:---|
| `test/utils/routing_param_extractor_test.dart` | 修改 | +101 / -0 | 否 | 在檔尾新增一個 group（4 個 test）與 `_Data` 類別；既有 16 個 test 一字不動 |
| `lib/src/utils/routing_param_extractor.dart` | 修改 | +47 / -0 | 否 | 3 張常數表、`_kCamelHump`、`_normalizeKey`、兩個 guard、doc comment 補兩行 |

本計畫的程式碼片段已在 scratchpad 複製的套件上實際跑過：`dart format` 結果為 0 changed；Red 時 2 個新測試失敗；Green 時 4 個相關檔共 119 個測試、全套 1009 個測試全過；analyze 仍是 7 個既有 info。

## 3. 任務

### Task 1 `[快/便宜]`：把驗收表轉成 table-driven 單元測試（TDD Red）

**寫入路徑**：`test/utils/routing_param_extractor_test.dart`（不改公開 API，+101 行）。既有 import 已包含 `redaction.dart`（`kRedactedValue`）與 `routing_param_extractor.dart`，不必新增。

**開始前**：在 main 上先跑 `rtk flutter test`，記下全套測試總數 B。規劃階段實測 B = 1005，CLAUDE.md 寫的 981 已經過時。

**步驟 1**：把 `main()` 結尾的這段

```dart
      expect(() => params!['id'] = '2', throwsUnsupportedError);
    });
  });
}
```

換成下面這段，也就是在既有 group 之後新增一個 group，並在 `main()` 之後新增 `_Data`：

```dart
      expect(() => params!['id'] = '2', throwsUnsupportedError);
    });
  });

  group('isSensitiveRoutingKey status/metadata whitelist (§P45)', () {
    test('lets through boolean flags and metadata keys', () {
      expect(_Data.releasedKeys.where(isSensitiveRoutingKey), isEmpty);
    });

    test('still redacts credential keys', () {
      expect(
        _Data.credentialKeys.where((k) => !isSensitiveRoutingKey(k)),
        isEmpty,
      );
    });

    test('adds no new redaction', () {
      expect(_Data.plainKeys.where(isSensitiveRoutingKey), isEmpty);
    });

    test('extractArgParams keeps flags and metadata, masks credentials', () {
      final params = extractArgParams(
        arguments: {
          'is_authenticated': false,
          'token_type': 'Bearer',
          'auth_token': 'xyz',
        },
      );
      expect(params, {
        'is_authenticated': 'false',
        'token_type': 'Bearer',
        'auth_token': kRedactedValue,
      });
    });
  });
}

class _Data {
  /// §4.1 A: over-redacted before, let through now.
  static const releasedKeys = [
    'is_authenticated',
    'is_authorized',
    'has_password',
    'has_token',
    'isAuthenticated',
    'hasPassword',
    'canAuth',
    'shouldReauth',
    'hasPin',
    'hasKey',
    'auth_required',
    'auth_enabled',
    'token_expired',
    'token_expires_in',
    'token_expires_at',
    'token_expiry',
    'token_type',
    'auth_mode',
    'auth_method',
    'auth_provider',
    'auth_step',
    'auth_status',
    'tokenType',
    'tokenExpired',
    'tokenExpiresIn',
    'authMode',
    'authStatus',
    'auth-mode',
    'TOKEN_TYPE',
    'is_token_expired',
    'password_required',
    'oauth2Provider',
  ];

  /// §4.1 B: credentials, still redacted.
  static const credentialKeys = [
    'has_secret_token',
    'hasSecretToken',
    'is_password_key',
    'has_api_key',
    'auth_token',
    'authToken',
    'password_reset_token',
    'access_token',
    'refresh_token',
    'auth_code',
    'oauth_state',
    'authorization',
    'apiKey',
    'api_key',
    'X-Api-Key',
    'userPin',
    'userPINCode',
    'userKEYAuth',
    'token_file',
  ];

  /// §4.1 C: never redacted, unchanged.
  static const plainKeys = [
    'isActive',
    'status',
    'keyword',
    'user_pwd',
    'has_db_pwd',
  ];
}
```

- **為什麼用 `where(...)` 搭配 `isEmpty`**：失敗時會一次列出所有不符的 key（實際輸出是 `Actual: WhereIterable<String>:[...]`），不會像在迴圈裡逐一 `expect` 那樣，在第一個失敗就停下。
- **驗證**：執行 `rtk flutter test test/utils/routing_param_extractor_test.dart`，預期結果是 `+18 -2`（A 類共 32 個 key）：
  - 失敗：`lets through boolean flags and metadata keys`（A 類 32 個 key 全部列在 Actual 裡；`oauth2Provider` 原本因含 `auth` 而被遮）、`extractArgParams keeps flags and metadata, masks credentials`（`is_authenticated` 實際值是 `'••••'`）。
  - 通過：`still redacts credential keys`、`adds no new redaction`。B／C 是回歸防線，在 Red 階段本來就該通過。
  - 通過：既有 16 個 test。
- **格式**：`dart format --output=none --set-exit-if-changed test/utils/routing_param_extractor_test.dart` → exit 0。
- **檢查**：`git diff --stat test/` 只能出現 `routing_param_extractor_test.dart`，而且刪除行數為 0。

### Task 2 `[快/便宜]`：加入放行 guard（TDD Green）並跑全套驗證

**寫入路徑**：`lib/src/utils/routing_param_extractor.dart`（不改公開 API，+47 行）。共三處插入，原有程式碼一行都不刪：

**步驟 1**：在 `final RegExp _kSensitiveCamelBoundary = ...;`（第 26 行）之後插入：

```dart

/// Normalized-key suffixes naming status or expiry metadata, not a credential.
const Set<String> _kMetadataSuffixes = {
  '_type',
  '_expires_in',
  '_expires_at',
  '_expired',
  '_expiry',
  '_mode',
  '_method',
  '_provider',
  '_step',
  '_status',
  '_required',
  '_enabled',
};

/// Captures the rest of a boolean-flag key such as `is_authenticated`.
final RegExp _kBooleanPrefix = RegExp(r'^(?:is|has|can|should)_(.*)$');

/// A boolean-flag rest ending in one of these is a multi-word credential name
/// (e.g. `has_secret_token`), so it stays on the strict path.
const Set<String> _kSecretNameSuffixes = {
  '_token',
  '_password',
  '_secret',
  '_key',
  '_apikey',
  '_credential',
  '_pin',
};

final RegExp _kCamelHump = RegExp(r'([a-z0-9])([A-Z])');
```

**步驟 2**：把函式開頭這段

```dart
/// Returns true if [key] is recognized as containing sensitive data.
bool isSensitiveRoutingKey(String key) {
  final lower = key.toLowerCase();
```

換成下面這段。`final lower` 以下的既有本體完全不動：

```dart
/// Returns true if [key] is recognized as containing sensitive data.
///
/// Status/expiry metadata (`token_type`, `authStatus`) and single-word boolean
/// flags (`is_authenticated`, `hasPassword`) are let through first.
bool isSensitiveRoutingKey(String key) {
  final normalized = _normalizeKey(key);
  if (_kMetadataSuffixes.any(normalized.endsWith)) return false;
  final rest = _kBooleanPrefix.firstMatch(normalized)?[1];
  if (rest != null && !_kSecretNameSuffixes.any(rest.endsWith)) return false;
  // Raw key on purpose: normalizing erases the PIN boundary in `userPINCode`.
  final lower = key.toLowerCase();
```

**步驟 3**：在 `bool _isAsciiUpper(String ch) {` 之前插入：

```dart
/// `tokenExpiresIn` / `token-expires-in` → `token_expires_in`.
String _normalizeKey(String key) => key
    .replaceAllMapped(_kCamelHump, (m) => '${m[1]}_${m[2]}')
    .replaceAll('-', '_')
    .toLowerCase();

```

- `_kCamelHump` 的兩個字元，前一個必須是小寫字母或數字，後一個必須是大寫字母，所以兩次比對不可能重疊。`TOKEN_TYPE` 沒有「小寫 → 大寫」的交界，只會被轉成小寫；`X-Api-Key` 會變成 `x_api_key`。
- 每個步驟完成後都可以跑 `dart format --output=none --set-exit-if-changed lib/src/utils/routing_param_extractor.dart`，預期 exit 0（規劃階段已驗證為 0 changed）。
- **驗證**（依序執行）：
  1. `rtk flutter test test/utils/routing_param_extractor_test.dart` → 20 個測試全過。
  2. `rtk flutter test test/utils/routing_param_extractor_test.dart test/interceptors/dio_interceptor_test.dart test/utils/agent_prompt_test.dart test/observers/navigator_observer_test.dart` → 全過（規劃階段實測 119 個）。
  3. `rtk flutter test` → 全過，總數為 B + 4（規劃階段實測 1009）。
  4. `rtk flutter analyze lib/ test/` → 仍是既有 7 個 info：6 個 `deprecated_member_use`，加上 `share_text_web.dart:15` 1 個。
  5. `git diff --stat -- lib/ test/` → 只有上述 2 個檔（不限路徑會帶出工作區既有的 brainstorm 未提交變更）。

## 4. 破壞性檢查

**5 個呼叫端都不修改，但它們的既有測試必須跑過**，也就是 Task 2 驗證第 2 步那 4 個檔：

| 呼叫點 | 對應測試檔 | 規劃階段結果 |
|:---|:---|:---:|
| `routing_param_extractor.dart` `_sanitize` | `test/utils/routing_param_extractor_test.dart` | 全過 |
| `lib/src/interceptors/dio_interceptor.dart:62`（FormData，§P33，含 `token_file`） | `test/interceptors/dio_interceptor_test.dart` | 全過 |
| `lib/src/utils/agent_prompt.dart:294` | `test/utils/agent_prompt_test.dart` | 全過 |
| `lib/src/observers/navigator_observer.dart:122`、`:175` | `test/observers/navigator_observer_test.dart` | 全過 |

- **呼叫端零改動**：`git diff -- lib/src/interceptors lib/src/observers lib/src/utils/agent_prompt.dart` 必須沒有輸出。
- **全 repo 字面值掃描**（規劃階段以 scratch script 比對新舊規則）：掃描 `lib/`、`test/`、`example/lib/` 共 627 個 key 形態的字串字面值，以及所有 `?key=`／`&key=` 形式的 query key。判定結果改變的只有 `KeyValueType`（`test/models/key_value_browser_source_test.dart` 裡的型別名稱，從未傳給 `isSensitiveRoutingKey`）。沒有任何字面值從不遮蔽變成遮蔽。
- **契約內的延伸行為**：以下行為合乎規格，不另外加測試。
  - `hasAPIKey` 正規化後是 `has_apikey`，`rest` 是單詞，所以放行（原本因結尾是 `Key` 而被遮），和規格 §5 對 `has_apikey` 的處理一致。
  - `is_pin`、`isKEY` 也會放行，和 A9 `hasPin`、A10 `hasKey` 屬於同一類。
  - 任何以元數據後綴結尾的 key 都會放行，例如 `private_key_type`。這是規格 §5 第 3 點已接受的取捨。
  - 縮寫會被正規化攤平：`hasAPIToken`→`has_apitoken`、`hasJWTToken`、`isPINCode` 的 `rest` 成為單詞而放行；語意相同的 `hasApiToken`→`has_api_token` 仍遮蔽。屬規則副作用，非漏洞（初審 2026-11-28 指出，使用者已知悉）。
  - `_privkey` 刻意不加入 `_kSecretNameSuffixes`（使用者 2026-11-28 決定），`has_rsa_privkey` 會放行。
- **Never break userspace**：`bool isSensitiveRoutingKey(String key)` 的簽章不變。這個函式沒有從 `lib/flutter_inspector_kit.dart` 這個 barrel 匯出，屬於套件內部的 `src/` API，宿主看到的變化只有遮蔽結果變少。不新增依賴，也不需要動條件匯出的兩側。

## 5. 已拍板：`_passwd`／`_pwd` 不列入機密後綴

**使用者已於 2026-11-28 拍板：維持規格版本**，不加入這兩個詞，`user_pwd`、`has_db_pwd` 維持不遮蔽（C4、C5）。

如果使用者決定改回 brainstorm 原文（第 2、3 步都列 `_passwd`、`_pwd`），需要改動以下各處。重點在第 2 點：**只改第 2 步沒有任何效果**。

1. `_kSecretNameSuffixes` 加入 `'_passwd'`、`'_pwd'`。
2. 在兩個 guard 之後、`final lower` 之前，新增 brainstorm 第 3 步的後綴判定：`if (normalized.endsWith('_passwd') || normalized.endsWith('_pwd')) return true;`。這是整個設計中唯一需要的 `return true`。原因是在本計畫的簡化下，第 2 步不放行的 key 會落到既有規則，而既有規則不認識 `pwd`，所以 `has_db_pwd` 仍然會回傳 `false`。這一行一加，`user_pwd`、`db_pwd`、`userPwd` 都會開始被遮蔽，5 個呼叫端（含 FormData）全部受影響。
3. 第 1 節「結構上保證只放行」的論證不再成立，計畫要改成「放行，加上兩個新的遮蔽詞」。
4. 測試：把 `plainKeys` 的 `user_pwd`、`has_db_pwd` 移到 `credentialKeys`，可以再補 `has_pwd`（`rest` 是單詞，應放行）放進 `releasedKeys`。這樣 Red 階段 `still redacts credential keys` 也會失敗。
5. 規格要同步修改：§2.2 第 2 點、§4.1 C4／C5、§5 第 2 點。CHANGELOG 需要註明「新增遮蔽 `_passwd`／`_pwd` 結尾的 key」這項行為變更（依慣例在 release commit 處理）。

## 6. 驗收對應（規格 §4）

| 規格條目 | 對應 |
|:---|:---|
| §4.1 A1–A31 | `lets through boolean flags and metadata keys`（`_Data.releasedKeys`，另加 `oauth2Provider` 驗證 `[a-z0-9]` 數字駝峰正規化） |
| §4.1 B1–B19 | `still redacts credential keys`（`_Data.credentialKeys`） |
| §4.1 C1–C5 | `adds no new redaction`（`_Data.plainKeys`） |
| §4.2 #1 | `extractArgParams keeps flags and metadata, masks credentials` |
| §4.2 #2 | 既有 16 個 test 不修改即通過（Task 1 檢查刪除行數為 0） |
| §4.2 #3 | Task 2 驗證第 5 步，以及第 4 節的 `git diff` 呼叫端檢查 |
| §4.2 #4 | Task 2 驗證第 3、4 步 |

## 7. 執行方式

依 gen-dev-workflow 的派發煞車規則（單檔 ≤ 20 行且不改公開 API 才在主進程原地修改）：Task 1 是 +101 行，Task 2 是 +47 行（其中邏輯只有 6 行，其餘是 `dart format` 排成一行一個的常數表），兩個任務都不符合字面門檻。

1. **Subagent-Driven，序列執行（建議，符合派發規則）**：Task 1 派 `[快/便宜]` subagent，回報要附上 Red 輸出（`+18 -2`）；verifier 驗收後再派 Task 2（`[快/便宜]`），回報要附上 5 條驗證指令的輸出。兩個任務都是照本計畫逐字貼上程式碼，沒有設計判斷。
2. **主進程原地執行**：程式碼已在規劃階段實跑驗證，貼上即可。如果使用者判斷「6 行邏輯加上常數表」實質上符合煞車門檻的精神，可以選這個方式，省下兩次派發成本。
3. **Parallel Session（不建議）**：Task 2 依 TDD 必須等 Task 1 的 Red 結果，兩者不能並行；總改動也太小，不值得開平行 session。
