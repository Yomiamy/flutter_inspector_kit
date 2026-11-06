# 功能規格：Dio `FormData`（Multipart）上傳摘要化與欄位脫敏（§P33）

- **日期**：2026-11-07
- **來源**：`docs/brainstorm/2026-11-04-features-brainstorm.md` §P33（源自 §Z1-9）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在 App 中上傳大頭貼、或送出含檔案表單的開發者／QA，打開 Network 詳情查看該筆請求時，
> 我希望 **Request Body 列出這次上傳帶了哪些文字欄位、哪些檔案（欄位名、檔名、大小）**，而且密碼這類敏感欄位預設遮蔽，
> 這樣我能直接確認「檔案有沒有帶上、欄位值對不對」，不用另外加 log 或接 proxy 抓包。

### 為什麼需要這項改進

`lib/src/interceptors/dio_interceptor.dart` 的 `_stringifyData` 目前只處理 `String`、`Uint8List`、`Map`/`List` 三種型別，其餘一律 `toString()`。Multipart 上傳時 `requestOptions.data` 是 `FormData`，結果 Request Body 只會顯示：

```
Instance of 'FormData'
```

這等於檔案上傳類請求在 Inspector 裡完全是盲區。另一方面，若改成直接把欄位原值印出來，`password` 這類欄位會原文進入時間軸、複製與分享內容，形成資安外洩。

---

## 2. 輸出格式契約（使用者可見行為）

`requestOptions.data` 為 `FormData` 時，`NetworkEntry.requestBody` 是一段摘要字串：

```
[FormData: <項目1>, <項目2>, ...]...[truncated]
```

| 項目 | 規則 | 範例 |
|:---|:---|:---|
| 排列順序 | **先檔案、後欄位**，兩組各自保留 Dio 列表中的原始順序 | `avatar=avatar.png (1024 B), name=Alice` |
| 分隔符 | `, `（逗號＋空白） | — |
| 檔案項目 | `<key>=<filename> (<length> B)`；`filename` 為 null 時顯示 `<unnamed>` | `file=<unnamed> (3 B)` |
| 欄位項目 | `<key>=<value>` | `name=Alice` |
| 敏感欄位 | `redactSensitiveData == true`（預設）且 key 命中 `isSensitiveRoutingKey` 時，值換成 `kRedactedValue`（`••••`）；`false` 時保留原值 | `password=••••` |
| 空表單 | 無欄位也無檔案 | `[FormData: empty]...[truncated]` |
| 結尾 | 一律附上 `kTruncatedMarker`（`...[truncated]`） | — |

說明：

- 範例中的 `...[truncated]` 即 `kTruncatedMarker`。結尾帶這個標記會讓 `NetworkEntry.isRequestTruncated == true`，詳情頁既有的 Resend 按鈕因此自動停用（提示「Cannot resend: request body truncated」），避免使用者把摘要字串當成 payload 重送到後端。這與既有 `Uint8List` 的 `[binary N bytes]` 佔位行為一致。
- 遮蔽在**擷取時**完成：摘要一旦產生就是字串，匯出時已無法再拆回欄位，所以只能在擷取當下套用 redact。這與 `navigator_observer.dart` 擷取路由參數時遮蔽的作法相同。
- 檔案項目只輸出 key、檔名、bytes，不受 redact 影響（不含檔案內容）。
- 整體長度仍受既有 `kNetworkBodyMaxLength`（10 KB）截斷保護（`NetworkInspector.add`）。由於檔案排在前面，即使超長欄位值觸發截斷，被截掉的也只會是欄位值，檔案 metadata 會優先保留（檔案摘要總長 < 10 KB 時必定可見）。
- `onRequest`、`onResponse`、`onError` 三處都對同一個 `requestOptions.data` 產生摘要，三者結果必須逐字相同。Dio 在送出時會 `finalize()` 並讀完 `FormData` 的 stream，但 `fields`／`files`／`length`／`filename` 都只是普通欄位，讀完之後仍可讀取。
- **已知限制**：遮蔽沿用 `isSensitiveRoutingKey` 字詞表，`pwd`／`passwd`／`otp`／`cvv` 等不在表內的 key 會以原值進時間軸；日後 §P45 調整該函式時，FormData 遮蔽會連動改變。JSON body 內的 `password` 仍不遮蔽（不在本範圍）。

---

## 3. 範圍邊界

### ✅ 做

- `lib/src/interceptors/dio_interceptor.dart`：`_stringifyData` 新增 `data is FormData` 分支，依第 2 節格式輸出摘要。
- `lib/src/core/flutter_inspector.dart`：在 `redactSensitiveData` 的 dartdoc 補一段，說明 `FormData` 敏感欄位會在擷取時遮蔽（僅改文件註解，不動 API）。
- `test/interceptors/dio_interceptor_test.dart`：補齊第 4 節驗收條件對應的單元測試。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 讀取檔案內容（hex／文字預覽） | 只摘要 metadata；讀內容需消耗 stream，會破壞宿主上傳 |
| 呼叫 `FormData.finalize()` / `MultipartFile.finalize()` | `FormData` 只能 finalize 一次，Inspector 呼叫後宿主送出時會拋 `StateError`，等於直接弄壞宿主的請求 |
| `FormData` Replay 重送 | 摘要不是可重送的 payload；靠結尾 `kTruncatedMarker` 自動停用 Resend |
| 修改 `lib/src/utils/network_formatters.dart`（如 cURL 輸出 `-F`） | formatter 處理的是字串，摘要已在擷取時遮蔽，不需改動；cURL `-F` 重建屬另一個功能 |
| 單一欄位值的獨立截斷上限 | 整體已有 10 KB 截斷兜底，加上「先檔案、後欄位」的排序，就不需要第二層上限 |
| 對值中的 `,`、`=` 做跳脫 | 摘要是給人看的，不是給機器解析的；不可重送，也就不需要可逆格式 |
| 遮蔽檔案 key 或檔名、輸出 `contentType` | 不在需求內 |
| 擴充 `isSensitiveRoutingKey` 的敏感字詞表 | 沿用既有規則，與路由參數遮蔽保持一致 |
| §P34 `ResponseBody` / `Stream` 佔位 | 另開 PR |
| README、CHANGELOG 更新 | 依專案慣例，於 release commit 統一處理 |

---

## 4. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | 同時含欄位與檔案的 `FormData`，`requestBody` 為 `[FormData: avatar=avatar.png (1024 B), name=Alice]$kTruncatedMarker`（先檔案、後欄位，不論 Map 宣告順序） | 單元測試 |
| 2 | `onRequest` 之後 `formData.isFinalized` 與 `MultipartFile.isFinalized` 皆為 false，代表 Inspector 沒有消耗 stream | 單元測試 |
| 3 | 空 `FormData()` 輸出 `[FormData: empty]$kTruncatedMarker` | 單元測試 |
| 4 | `MultipartFile.fromBytes` 未給 `filename` 時，輸出 `file=<unnamed> (3 B)` | 單元測試 |
| 5 | `redactSensitiveData` 為預設 `true` 時，`password` 欄位輸出 `password=$kRedactedValue`，`requestBody` 不含原值 | 單元測試 |
| 6 | `redactSensitiveData: false` 時，`password` 欄位保留原值 | 單元測試 |
| 7 | 上述摘要皆使 `entry.isRequestTruncated == true`（Resend 自動停用） | 單元測試 |
| 8 | `FormData` 經 `readAsBytes()` 消耗（模擬 Dio 送出）後，`onResponse` 與 `onError` 產生的 `requestBody` 與 `onRequest` 逐字相同 | 單元測試 |
| 9 | 既有測試全數通過（`flutter test`），`flutter analyze lib/ test/` 不超過既有 7 個 info | 指令執行驗證 |
