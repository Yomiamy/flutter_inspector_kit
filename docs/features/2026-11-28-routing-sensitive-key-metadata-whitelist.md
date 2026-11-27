# 功能規格：路由敏感鍵遮蔽（`isSensitiveRoutingKey`）不再誤遮布林狀態與效期元數據（§P45）

- **日期**：2026-11-28
- **來源**：`docs/brainstorm/2026-11-18-features-brainstorm.md` §P45
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. 使用者故事

> 我是開發者或 QA，正在查「為什麼被導去登入頁」「為什麼深層連結被擋下」。打開路由事件或 Network 詳情時，
> 我想直接看到 `is_authenticated: false`、`token_expired: true`、`auth_mode: oauth` 這類**狀態與元數據**的原值；`auth_token`、`apiKey`、`userPin` 這類**真正的憑證**則照舊遮蔽，
> 這樣不必關掉遮蔽、也不必另外加 log，就能把跳轉的來龍去脈串起來。

### 為什麼需要這項改進

`lib/src/utils/routing_param_extractor.dart` 的 `isSensitiveRoutingKey` 會拿 `_kSensitiveSubstrings`（含 `auth`、`token`、`password`…）對 key 做**不限位置的子字串比對**（`lower.contains(pattern)`）。只要 key 裡出現這些字，不論它出現在哪個位置、整個 key 指的是什麼，一律遮成 `••••`。結果是：

| 被誤遮的 key | 實際語意 |
|:---|:---|
| `is_authenticated`、`is_authorized`、`has_password`、`isAuthenticated`、`hasPassword`、`canAuth` | 布林狀態旗標 |
| `token_expired`、`token_expires_in`、`token_expires_at`、`token_expiry` | 效期資訊 |
| `token_type`、`auth_mode`、`auth_method`、`auth_provider`、`auth_step`、`auth_status`、`authStatus` | 認證方式／流程元數據 |
| `auth_required`、`auth_enabled` | 開關設定 |

排查登入跳轉時最需要看的正是這些值，現在卻全被自家的除錯工具遮掉。這違反了本專案「排查靠鏈推斷」的設計哲學，也違反 §D5「遮罩不應成為排查絆腳石」的原則。

---

## 2. 判定規則（使用者可見行為契約）

### 2.1 三步判定

先把 key 換成**正規化形式**：在「小寫字母或數字 → 大寫字母」的交界插入 `_`，`-` 一律換成 `_`，再全部轉小寫。例如 `tokenType` → `token_type`、`auth-mode` → `auth_mode`、`TOKEN_TYPE` → `token_type`、`isAuthenticated` → `is_authenticated`。接著依序判定，**先命中的規則決定結果**：

1. **元數據後綴放行**：正規化形式若以 `_type`、`_expires_in`、`_expires_at`、`_expired`、`_expiry`、`_mode`、`_method`、`_provider`、`_step`、`_status`、`_required`、`_enabled` 結尾 → **不遮蔽**。
2. **布林前綴放行**：正規化形式若以 `is_`、`has_`、`can_`、`should_` 開頭，先去掉前綴，剩下的部分稱為 `rest`：
   - `rest` 以 `_token`、`_password`、`_secret`、`_key`、`_apikey`、`_credential`、`_pin` 結尾（代表 `rest` 是多個詞組成、最後一個詞是機密詞的名稱，例如 `secret_token`、`password_key`）→ 不放行，交給第 3 步，結果必定是遮蔽。
   - 其餘情況（`rest` 只有一個詞，例如 `password`、`authenticated`）→ **不遮蔽**。
   - 注意：必須先去掉前綴再檢查 `rest`。若直接檢查整串是否以 `_password` 結尾，`has_password` 裡 `has_` 的底線會被當成後綴的一部分，`has_password` 就會被誤判成機密。
3. **既有規則兜底**：沒有被第 1、2 步放行的 key，交給**現行**的 `_kSensitiveSubstrings` / `_kSensitiveWords` / camelCase 邊界規則判定。這一步拿**原始 key** 比對，判定邏輯與今天完全相同。

### 2.2 約束

- **正規化形式只用在第 1、2 步的放行判定**，第 3 步一律用原始 key。原因是正規化會把縮寫攤平：`userPINCode` 正規化後是 `user_pincode`，若改拿它跑既有規則，`PIN` 的 camelCase 邊界就消失了，結果從遮蔽變成放行，屬於行為回歸。
- **只放行、不新增遮蔽**：新規則只會讓原本遮蔽的 key 改成不遮蔽，不會讓任何原本不遮蔽的 key 變成遮蔽。所以第 2 步的機密後綴表只收既有規則本來就涵蓋的詞，**不加入** brainstorm 原文列出的 `_passwd`、`_pwd`（理由見 §5）。
- **公開 API 不變**：`isSensitiveRoutingKey(String key)` 的簽章不變，仍是純函式，不新增任何設定項。

### 2.3 一併受益的呼叫端

`isSensitiveRoutingKey` 在 `lib/` 裡只定義一次，以下 5 個呼叫點會一起換成新行為，**呼叫端不必修改**：

| 呼叫點 | 受益場景 |
|:---|:---|
| `routing_param_extractor.dart` `_sanitize` | 路由 query／arguments 參數 Map（`extractQueryParams` / `extractArgParams`） |
| `lib/src/interceptors/dio_interceptor.dart:62` | Dio `FormData` 欄位值與檔名遮蔽（§P33），例如 `auth_status=unverified` 會顯示原值 |
| `lib/src/utils/agent_prompt.dart:294` | AI Prompt 匯出的路由參數 |
| `lib/src/observers/navigator_observer.dart:122` | 存下的 `arguments` Map 逐鍵遮蔽 |
| `lib/src/observers/navigator_observer.dart:175` | `Uri`／字串 arguments 的 query 遮蔽 |

放行後安全性不變：在 navigator arguments 這條路徑上，key 被放行只代表不再整個替換成 `••••`，它的值若是 Map／List，仍會照舊遞迴遮蔽裡面的敏感 key。

---

## 3. 範圍邊界

### ✅ 做

- `lib/src/utils/routing_param_extractor.dart`：`isSensitiveRoutingKey` 加入 §2.1 第 1、2 步的放行判定，第 3 步沿用現有邏輯。
- `test/utils/routing_param_extractor_test.dart`：依 §4 的鍵→預期表補單元測試。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| `kSensitiveHeaderKeys` / `redactHeaders`（HTTP header 遮蔽） | 那是另一套規則，與路由鍵無關 |
| 新增 opt-out 設定或可自訂的白名單 | 沒有人提出這個需求；要全部關掉，已有 `redactSensitiveData: false` |
| 修改 5 個呼叫端 | 只改共用函式，呼叫端自然受益 |
| 擴充敏感字詞表（`pwd`、`passwd`、`otp`、`cvv` 等） | 會新增遮蔽，與本功能「只放行」的方向相反；FormData 規格（§P33）已列為已知限制，要做請另開 |
| 依值的內容判斷是否機密 | 判定只看 key，維持純函式 |
| 為每個呼叫端各補整合測試 | 5 處共用同一個函式，函式層的測試就涵蓋了；呼叫端既有測試全綠即可 |
| README（第 988 行附近的遮蔽說明）與 CHANGELOG 更新 | 依專案慣例，在 release commit 統一處理 |

---

## 4. 驗收條件

### 4.1 鍵→預期表（可直接轉成 `isSensitiveRoutingKey` 單元測試）

`true` = 遮蔽，`false` = 不遮蔽。「現行」欄是改動前的結果，方便確認變化方向。

**A. 原本誤遮、改動後放行（`true` → `false`）**

| # | key | 現行 | 預期 | 依據 |
|:---:|:---|:---:|:---:|:---|
| A1 | `is_authenticated` | true | **false** | 第 2 步，`rest` = `authenticated` |
| A2 | `is_authorized` | true | **false** | 第 2 步 |
| A3 | `has_password` | true | **false** | 第 2 步，`rest` = `password`（單詞） |
| A4 | `has_token` | true | **false** | 第 2 步 |
| A5 | `isAuthenticated` | true | **false** | 第 2 步（camelCase） |
| A6 | `hasPassword` | true | **false** | 第 2 步（camelCase） |
| A7 | `canAuth` | true | **false** | 第 2 步（camelCase） |
| A8 | `shouldReauth` | true | **false** | 第 2 步（camelCase） |
| A9 | `hasPin` | true | **false** | 第 2 步（原本因結尾是 `Pin` 被遮） |
| A10 | `hasKey` | true | **false** | 第 2 步（原本因結尾是 `Key` 被遮） |
| A11 | `auth_required` | true | **false** | 第 1 步 `_required` |
| A12 | `auth_enabled` | true | **false** | 第 1 步 `_enabled` |
| A13 | `token_expired` | true | **false** | 第 1 步 `_expired` |
| A14 | `token_expires_in` | true | **false** | 第 1 步 `_expires_in` |
| A15 | `token_expires_at` | true | **false** | 第 1 步 `_expires_at` |
| A16 | `token_expiry` | true | **false** | 第 1 步 `_expiry` |
| A17 | `token_type` | true | **false** | 第 1 步 `_type` |
| A18 | `auth_mode` | true | **false** | 第 1 步 `_mode` |
| A19 | `auth_method` | true | **false** | 第 1 步 `_method` |
| A20 | `auth_provider` | true | **false** | 第 1 步 `_provider` |
| A21 | `auth_step` | true | **false** | 第 1 步 `_step` |
| A22 | `auth_status` | true | **false** | 第 1 步 `_status` |
| A23 | `tokenType` | true | **false** | 第 1 步（camelCase） |
| A24 | `tokenExpired` | true | **false** | 第 1 步（camelCase） |
| A25 | `tokenExpiresIn` | true | **false** | 第 1 步（camelCase，多段） |
| A26 | `authMode` | true | **false** | 第 1 步（camelCase） |
| A27 | `authStatus` | true | **false** | 第 1 步（camelCase） |
| A28 | `auth-mode` | true | **false** | 第 1 步（kebab-case） |
| A29 | `TOKEN_TYPE` | true | **false** | 第 1 步（全大寫） |
| A30 | `is_token_expired` | true | **false** | 第 1 步比第 2 步先判定 |
| A31 | `password_required` | true | **false** | 第 1 步 |

**B. 真憑證，維持遮蔽（`true` → `true`）**

| # | key | 現行 | 預期 | 依據 |
|:---:|:---|:---:|:---:|:---|
| B1 | `has_secret_token` | true | **true** | 第 2 步，`rest` = `secret_token` 以 `_token` 結尾 |
| B2 | `hasSecretToken` | true | **true** | 同上（camelCase） |
| B3 | `is_password_key` | true | **true** | 第 2 步，`rest` 以 `_key` 結尾 |
| B4 | `has_api_key` | true | **true** | 第 2 步，`rest` = `api_key`（偏保守，見 §5） |
| B5 | `auth_token` | true | **true** | 第 3 步 |
| B6 | `authToken` | true | **true** | 第 3 步 |
| B7 | `password_reset_token` | true | **true** | 第 3 步（`_token` 不在第 1 步的白名單） |
| B8 | `access_token` | true | **true** | 第 3 步 |
| B9 | `refresh_token` | true | **true** | 第 3 步 |
| B10 | `auth_code` | true | **true** | 第 3 步（OAuth authorization code 是憑證；`_code` 不在白名單） |
| B11 | `oauth_state` | true | **true** | 第 3 步（`_state` 不在白名單） |
| B12 | `authorization` | true | **true** | 第 3 步 |
| B13 | `apiKey` | true | **true** | 第 3 步 |
| B14 | `api_key` | true | **true** | 第 3 步 |
| B15 | `X-Api-Key` | true | **true** | 第 3 步 |
| B16 | `userPin` | true | **true** | 第 3 步 |
| B17 | `userPINCode` | true | **true** | 第 3 步用原始 key（守住 §2.2 的回歸） |
| B18 | `userKEYAuth` | true | **true** | 第 3 步 |
| B19 | `token_file` | true | **true** | 第 3 步（FormData 檔案 key，§P33 驗收 9） |

**C. 原本就不遮、維持不遮（`false` → `false`）**

| # | key | 現行 | 預期 | 依據 |
|:---:|:---|:---:|:---:|:---|
| C1 | `isActive` | false | **false** | 既有 `extractArgParams` 測試使用的 key |
| C2 | `status` | false | **false** | 沒有前導 `_`，不屬於後綴 |
| C3 | `keyword` | false | **false** | 既有行為 |
| C4 | `user_pwd` | false | **false** | 不新增遮蔽（§2.2、§5） |
| C5 | `has_db_pwd` | false | **false** | `_pwd` 不在第 2 步的機密後綴表 |

### 4.2 整合與回歸

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | `extractArgParams(arguments: {'is_authenticated': false, 'token_type': 'Bearer', 'auth_token': 'xyz'})` 回傳 `is_authenticated` = `'false'`、`token_type` = `'Bearer'`，`auth_token` = `kRedactedValue` | 單元測試 |
| 2 | 既有 `routing_param_extractor_test.dart` 全部 case 不修改即通過，包含 `redacts sensitive keys when redact is true`（`password`、`authToken`、`api_key`、`secret`、`access_token`、`userPin`、`pinCode`、`keyCode`、`key`、`apiKey` 遮蔽；`username`、`shipping`、`spinner`、`keyboard` 不遮）與 `userPIN`／`userKEY`／`userPINCode`／`userKEYAuth` 遮蔽、`shippingAddress`／`donkey` 不遮 | 單元測試 |
| 3 | `isSensitiveRoutingKey` 的簽章不變，5 個呼叫端沒有任何改動 | `git diff` 檢查 |
| 4 | 全套測試通過（`flutter test`），`flutter analyze lib/ test/` 不超過既有 7 個 info | 指令執行 |

---

## 5. 已知取捨

- **「`rest` 是否多詞」是保守的經驗法則**：`has_api_key`、`has_reset_password` 其實也是布林值，但因為 `rest` 是多詞且以機密詞結尾，仍會遮蔽；`has_apikey`（單詞）則放行。這裡寧可多遮，也不讓 `has_secret_token` 這類真憑證名稱漏網，這是 brainstorm 原本的設計選擇。
- **偏離 brainstorm 原文：不加 `_passwd`、`_pwd`**：brainstorm 第 2、3 步的機密後綴表列了這兩個詞，但既有規則並不涵蓋它們。加進去會讓 `user_pwd`、`has_db_pwd` 從不遮變成遮，這與 brainstorm 自己在破壞性評估寫的「僅將誤遮的布林與效期欄位解放出來」互相矛盾；而且只在第 2 步加、第 3 步不加，`has_db_pwd` 遮蔽而 `db_pwd` 不遮，前後不一致。所以本規格維持「只放行」。要擴充字詞表，請另開功能，與 §P33 的已知限制一併處理。
- **元數據後綴可能碰巧蓋住真憑證**：如果宿主自訂了一個叫 `xxx_type` 或 `xxx_status`、裡面卻放憑證的 key，會被放行。這種命名違反慣例，實務上很少見；若真的遇到，請宿主改 key 名（關掉遮蔽反而會暴露更多）。這是依實用主義做出的取捨。
