# 功能規格：`dart:io` `HttpClient` 層流量擷取與圖片預覽

- **日期**：2026-11-13
- **來源**：gen-grill 需求 brief（使用者已確認 Q1–Q5 與盤問決策）；同類參考 `zero_inspector_kit`（淺層 clone，HEAD `dbb10f4`，v2.4.0，以下簡稱 zero）；既有否決紀錄 `docs/brainstorm/2026-11-11-features-brainstorm.md` 第八部分（:2345、:2391、:2395、:2490、:2506、:2538）
- **類型**：新事件來源（opt-in，預設關閉），加上 Network 詳情頁圖片預覽（Dio 與 `HttpClient` 兩層共用）
- **Effort**：high（三個 `dart:io` 代理、條件匯出、圖片預覽與記憶體預算）｜ **排查價值**：高
- **版號**：**3.0.0（major）**（已裁決 2026-11-13，見 §8 C1）。brief 原定 minor，但新增 `NetworkOrigin.httpClient` 會讓宿主的窮盡式 `switch (entry.origin)` 編譯失敗，屬 breaking change，故改走 major
- **名稱**：本文以 `captureHttpClient`（開關）與 `NetworkOrigin.httpClient`（來源）稱呼，理由見 §5 Q1

---

## 1. 功能概述（What & Why）

### 一句話本質

開關打開時，在 `HttpOverrides` 鏈上串接一層「只看不改」的 `HttpClient` 代理，把 Dio interceptor 以外、所有經 `dart:io` `HttpClient` 送出的請求翻譯成既有的 `NetworkEntry`，推進同一條時間軸。圖片回應另外保留原始位元組供詳情頁預覽，受單張 5 MB、總量 50 MB 限制。

這是**多一個事件來源**，不是多一個系統：擷取層只透過公開的 `FlutterInspector.logNetwork` 寫入（與 WebView adapter 同形，`docs/architecture/overview.md:65`），不持有 buffer、不做 UI。

### 為什麼要做（已逐檔核對的現況）

- Network 分頁的自動來源只有 Dio interceptor（公開匯出於 `lib/flutter_inspector_kit.dart:2`）與 WebView bridge。`lib/` 搜尋 `HttpOverrides`／`HttpClient` 為 0 筆；`lib/src/core/flutter_inspector.dart:151` 寫明套件「never on `dart:io`」，`dart:io` 只出現在條件匯出的 `_io` 側（`lib/src/notifications/network_notifier.dart:10-11`、`lib/src/utils/share_text.dart:8`）。
- 目前看不到的流量都走 `HttpClient()` factory，而 factory 會讀 `HttpOverrides.current`（Dart SDK `_http/http.dart:1348-1354`）：
  - **`Image.network`**：`NetworkImage` 以 `static final HttpClient _sharedHttpClient = HttpClient()..autoUncompress = false;` 取圖（Flutter `painting/_network_image_io.dart:97`），流程是 `getUrl` → `close()` → `consolidateHttpClientResponseBytes`（:120 起）。
  - **`package:http`**：`IOClient([HttpClient? inner]) : _inner = inner ?? HttpClient();`（http 1.6.0 `io_client.dart:101`）；頂層 `http.get()` 等函式每次呼叫都新建 `Client()`（`http.dart:168`）。
  - **第三方 SDK** 直接 `HttpClient()`；**沒掛 inspector interceptor 的 Dio 實例**也一樣：預設 `IOHttpClientAdapter` 以 `HttpClient()` 建 client（dio 5.11.1 `io_adapter.dart:257-264`）。
- 痛點：破圖、載入慢、SDK 請求異常時，時間軸缺了這一段，鏈推斷斷在中間。

### 與既有否決紀錄的關係

brainstorm 第八部分曾以下列理由否決「全域 `HttpOverrides`」（:2345、:2538）。使用者已決定改做，本規格逐條處理：

| 當初的否決理由 | 本規格的處理 |
|:---|:---|
| 強綁 `dart:io`，Web/WASM 編譯失敗 | io／web 條件匯出，web 側空實作（US-5） |
| 與宿主 SSL Pinning／企業代理三方搶奪 | 串接安裝當下的 `HttpOverrides.current`，`createHttpClient` 與 `findProxyFromEnvironment` 都轉給上一層（US-3） |
| `stop()` 把宿主的 `HttpOverrides.global` 抹成 `null`（:2395、:2506） | 不提供任何卸載；`detach()` 不碰 `HttpOverrides`；永不寫入 `null` |
| 關聯 header 污染 HMAC（:2345） | 標記在 header 送出前移除；只在能確定走 `IOHttpClientAdapter` 時才加；簽章 interceptor 的順序限制寫進文件（§7 R3） |
| release 照裝，README 卻宣稱 tree-shaken（:2391） | 預設 `false`；文件誠實寫「開關在所有 build mode 都生效」，由宿主用 `kReleaseMode` 或 flavor 自行決定 |

剩下的代價：開關打開後，套件在 isolate 層級留下一個收不回的全域副作用。這與 `captureUncaughtErrors` 的取捨相同（`flutter_inspector.dart:97-99`），使用者在 brief 中已接受。

### 資料流（概念）

```text
HttpClient() ──► HttpOverrides.current = inspector 層
                  createHttpClient(ctx) = 上一層.createHttpClient(ctx)，再包成代理
代理.openUrl/getUrl/... ──► 底層同名方法 ──► Request 代理
Request 代理：第一次寫 body 或 close() 之前
  ├─ 帶標記：移除標記，整筆不記（Dio interceptor 已記過）
  └─ 無標記：logNetwork(pending)
Response 代理：消費者 listen 時才訂閱底層；chunk 原樣轉出，同時有上限地複製
  └─ done／error／cancel／detachSocket ──► logNetwork(completed, replaces: pending)
NetworkInspector.add：截斷文字 → 5 MB 檢查 → 寫入 buffer → 若總量 > 50 MB，從最舊開始丟位元組
```

---

## 2. 已決定事項（brief，不再討論）

| # | 事項 | 決定 |
|:---:|:---|:---|
| D1 | 兩層分工 | Dio 請求由 interceptor 負責；`HttpClient` 層只補 Dio 以外的流量；interceptor 不退役 |
| D2 | 去重 | `HttpClient` 層啟用時，interceptor 在請求加標記 header；`HttpClient` 代理送出前移除標記，並且不記錄該筆。`HttpClient` 層沒啟用時不加標記 |
| D3 | 安裝 | 比照 `captureUncaughtErrors`，建構時安裝（先例 `flutter_inspector.dart:327`），串接安裝當下的 global slot，永不還原、不設成 `null`。文件寫明「Host 之後才設定的 override 會蓋掉 inspector」。（plan-verifier 第 1 輪）讀取時用 `Zone.root.run(() => HttpOverrides.current)`，因為 `HttpOverrides.current` 是 `Zone.current[...] ?? _global`（SDK `_http/overrides.dart:35-36`），在 `HttpOverrides.runZoned` 內建構時會讀到 zone 的 override，把它串進 global 就會讓 zone 外的流量也走 zone 的 factory |
| D4 | 開關 | 新增一個 bool，預設 `false` |
| D5 | Web | io／web 條件匯出，web 側空實作 |
| D6 | Response body | 文字照常記錄，套用既有截斷規則（`kNetworkBodyMaxLength`，`network_entry.dart:11`、:137-146） |
| D7 | 圖片預覽 | 以內容判斷是不是圖片，Dio 與 `HttpClient` 兩層都適用；單張上限 5 MB，超過只記大小；總預算 50 MB，超過時從最舊的 entry 丟位元組、保留紀錄、預覽改佔位；只支援 `Image.memory` 原生格式（PNG、JPEG、GIF、WebP、BMP），SVG 照文字顯示，解碼失敗退回佔位 |
| D8 | 匯出 | 分享、cURL、診斷報告一律不含圖片位元組，只寫 `[image/png, 34.2 KB]` 這類摘要 |
| D9 | 一體適用 | 所有 `NetworkEntry` 套同一套規則：慢請求標示、通知摘要、敏感 header 遮蔽、診斷報告；列表上標示來源 |
| D10 | 不做 | native client、WebSocket、重送 `HttpClient` 來源的請求、mocking、來源過濾器、interceptor 退役或任何 breaking change（唯一例外：新增 `NetworkOrigin.httpClient`，已裁決 2026-11-13，見 §8 C1） |

---

## 3. 使用者故事與驗收條件

> 作為在 debug 或 staging build 排查破圖、載入慢、第三方 SDK 請求異常的開發者或 QA，
> 我希望打開 `captureHttpClient` 之後，`Image.network`、`package:http` 與 SDK 的請求出現在 Network 分頁，看得到 URL、狀態碼、耗時與圖片內容，
> 而且 Dio 請求不重複、伺服器收不到任何除錯痕跡、宿主的 SSL Pinning 照常生效。

### US-1：非 Dio 流量進入 Network 分頁（brief Q3-1）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1-1 | `captureHttpClient: true` 時，`HttpClient()` 建立的 client 對本機 `HttpServer` 發出 GET 與 POST，各出現一筆 entry，`method`、`url`、`statusCode`、`duration`、request／response headers 正確，`origin == NetworkOrigin.httpClient` | 單元測試（本機 `HttpServer`；`package:http` 只是 transitive 相依，以直接使用 `HttpClient` 驗證等價路徑） |
| 1-2 | entry 在 header 定案時（第一次寫 body 或 `close()`）以 pending 出現；body 串流結束後以 `replaces:` 原地更新為 completed，列表不重複 | 單元測試 |
| 1-3 | 文字 response body 以 UTF-8 解碼記錄並套既有截斷；非 UTF-8 且非圖片的位元組記成與 Dio 相同的 `[binary N bytes]...[truncated]`（`dio_interceptor.dart:26-28`），N 是實際收到的總位元組數 | 單元測試 |
| 1-4 | 連線失敗、回應交出前的 `abort()`、回應串流錯誤時，entry 為 completed 且 `error` 非 null（plan-verifier 第 2 輪：回應交出後 dart:io 的 `abort()` 是 no-op，`http_impl.dart:1702-1709`，entry 由回應本身完成，帶 `statusCode`、`error == null`）；`errorType`、`sourceDio` 為 null，不偽造 Dio 欄位（先例 `webview_bridge_adapter.dart:76-77`） | 單元測試 |
| 1-5 | 呼叫 `detachSocket()`（例如 WebSocket 握手，SDK `websocket_impl.dart:1438`）或消費者 `cancel()` 訂閱後，entry 都會離開 pending，不會永久卡在 pending | 單元測試 |
| 1-6 | 真實 `Image.network` 與 `package:http` 流量出現在 Network 分頁 | 指令加手動驗證：在 scratchpad 建原生 probe app（不寫入 repo、不用 `example/`），模擬器上 debug 與 profile 各跑一次（plan-verifier 第 1 輪）；probe 自己在 loopback 起 `HttpServer`，不依賴外部服務（plan-verifier 第 2 輪） |

### US-2：Dio 只記一次，標記不外洩（brief Q3-2）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 2-1 | 開關 `true`、Dio 使用預設 `IOHttpClientAdapter`、已掛 `FlutterInspectorDioInterceptor(inspector, sourceDio: dio)` 時，**header 成功送出的** Dio 請求只產生一筆 `origin == dio` 的 entry（已裁決 2026-11-13，見 §8 C2：連線前就失敗的 Dio 請求允許記兩筆） | 單元測試（本機 `HttpServer` + 真 Dio） |
| 2-2 | 同一情境下，本機 `HttpServer` 收到的 request headers 不含標記 | 單元測試 |
| 2-3 | 標記不出現在任何 entry 的 `requestHeaders`，也不出現在 cURL、純文字匯出、診斷報告與 Resend 送出的請求 | 單元測試 |
| 2-4 | 開關 `false` 或 web 時，interceptor 不加標記，`RequestOptions.headers` 與現行逐字相同 | 單元測試 |
| 2-5 | 無法確定請求會經過 `IOHttpClientAdapter` 時（未傳 `sourceDio`，或 adapter 是其他型別），interceptor 不加標記。寧可重複記錄，也不把標記送到伺服器 | 單元測試（以非 IO 的 fake adapter 驗證） |
| 2-6 | 沒掛 inspector interceptor 的 Dio 實例，流量由 `HttpClient` 層以 `origin == httpClient` 記錄一次 | 單元測試 |

> 例外（已裁決 2026-11-13，見 §8 C2）：在 `openUrl` 階段就失敗（DNS、拒絕連線、TLS 握手）的 Dio 請求無法辨識，會記兩筆（`origin: dio` 一筆、`origin: httpClient` 一筆）。此為接受的行為，不實作查表登記。

### US-3：宿主的 `HttpOverrides` 照常生效（brief Q3-3）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 3-1 | 建構 inspector 前設定 `HttpOverrides.global = HostOverrides()`；開關 `true` 後，`HttpClient()` 回傳的代理底層就是 `HostOverrides.createHttpClient(context)` 的回傳值，`context` 原樣傳入 | 單元測試 |
| 3-2 | `HttpClient.findProxyFromEnvironment(uri)` 回傳 `HostOverrides.findProxyFromEnvironment` 的結果（SDK 透過 `HttpOverrides.current` 讀取，`http.dart:1634-1643`） | 單元測試 |
| 3-3 | 代理把所有 setter（`badCertificateCallback`、`connectionFactory`、`findProxy`、`authenticate`、`keyLog` 等）轉給底層 client；`HttpClientResponse` 的 `certificate`、`connectionInfo`、`headers` 原物件轉出（Dio `validateCertificate` 依賴 `certificate`，`io_adapter.dart:192-206`；Dio 以 dynamic 讀 `headers.protocolVersion`，必須是同一物件，`io_adapter.dart:218-221`） | 單元測試（fake inner client／response，以 `identical` 斷言） |
| 3-4 | 宿主在 inspector **之後**設定的 `HttpOverrides.global` 取代 inspector：擷取停止，宿主設定照常生效，不拋錯 | 單元測試＋dartdoc／README |

### US-4：預設零接觸（brief Q3-4）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 4-1 | 未傳開關或 `captureHttpClient: false` 時，建構前後 `identical(HttpOverrides.current, before)` 為 true | 單元測試 |
| 4-2 | `detach()` 不讀寫 `HttpOverrides` | 單元測試 |
| 4-3 | 開關 `true` 時，inspector 不會在任何路徑把 `HttpOverrides.global` 設成 `null` 或還原舊值 | 單元測試＋code review |

### US-5：Web 可編譯、不做事（brief Q3-5）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 5-1 | 只依賴本套件的最小專案，`main.dart` 以 `captureHttpClient: true` 建構 inspector，`flutter build web` 成功（作法比照 `docs/plans/2026-09-06-crash-notification.md:147-165`；**不可用 `example/`**，它依賴 native-only 的 ObjectBox） | 指令驗證 |
| 5-2 | web 側是空實作：開關 `true` 不做事、不拋錯，interceptor 不加標記 | 單元測試（web 側是純 Dart stub，VM 測試可直接 import） |
| 5-3 | io 與 web 兩側的函式在 VM 測試中各指派給同一個 typedef，簽章漂移時測試檔編譯失敗；另以 `expect(io.f.runtimeType, web.f.runtimeType)` 逐對比對，擋下 typedef 指派抓不到的「一側多了可選參數」這類子型別漂移（CLAUDE.md 不變式 #4；plan-verifier 第 1 輪） | 單元測試 |

### US-6：圖片預覽與記憶體上限（brief Q3-6）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 6-1 | 回應位元組符合下列 signature 才算圖片，不看 `Content-Type`：PNG（完整 8 bytes）、JPEG（`FF D8 FF`）、GIF（`GIF87a`／`GIF89a`）、WebP（`RIFF....WEBP`）、BMP（`BM` 加上合理的 DIB header 長度）。Dio（`ResponseType.bytes` 的 `Uint8List`）與 `HttpClient` 兩層共用同一個判斷 | 單元測試 |
| 6-2 | 圖片 entry 的 `responseBody` 是摘要字串，例如 `[image/png, 34.2 KB]...[truncated]`，大小用既有 `formatBytes`（`network_formatters.dart:48-58`）。原始位元組放在 entry 的獨立欄位，不進 `==`、`hashCode`、`toString` 與任何匯出（比照 `sourceDio`，`network_entry.dart:110-116`） | 單元測試 |
| 6-3 | 詳情頁 Response Body 區塊顯示 `Image.memory` 預覽；解碼失敗退回佔位文字，不拋例外 | Widget 測試 |
| 6-4 | 單張超過 5 MB：不保留位元組，只留摘要。`HttpClient` 層超過 5 MB 後停止複製、只計數，不會為了量大小而緩衝整張圖 | 單元測試 |
| 6-5 | 所有 entry 的圖片位元組總和超過 50 MB 時，從最舊的 entry 開始丟位元組，直到不超過 50 MB；entry 保留在 buffer，預覽改為佔位 | 單元測試 |
| 6-6 | 淘汰不在 `onMutate` 裡執行，不重入同一個 buffer（`ring_buffer.dart:24-28`） | 單元測試＋code review |
| 6-7 | 既有測試 `test/interceptors/dio_interceptor_test.dart:438-447` 用 PNG 前 4 bytes `[137, 80, 78, 71]`，仍得到 `[binary 4 bytes]...[truncated]`：不完整的 signature 不算圖片 | 既有測試不修改 |
| 6-8 | SVG 走文字路徑，照文字顯示 | 單元測試 |
| 6-9 | 分享、cURL、純文字匯出、診斷報告、agent prompt 只含摘要字串，不含位元組或 base64。這些匯出原本就只讀 `responseBody`（`network_formatters.dart:155-171`、`agent_prompt.dart:255-257`），所以不需要改匯出程式碼 | 單元測試 |
| 6-10 | 預覽解碼限制輸出尺寸（例如 `cacheWidth`），避免 5 MB 的壓縮檔解成數十 MB 的點陣圖；預覽不長期佔用宿主的 `ImageCache` | Widget 測試或 code review（細節交由 0b） |

### US-7：宿主的請求與回應消費者毫無感覺（開放問題 3）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 7-1 | 代理的每個 `HttpClient` 方法都轉呼叫底層**同名**方法；`open(method, host, port, path)` 不改寫成 `openUrl`，也不猜 scheme | 單元測試 |
| 7-2 | Request body 直接寫給底層（write-through），不延遲、不重排、不改內容；inspector 只複製前段供顯示；`flush()` 語意不變 | 單元測試 |
| 7-3 | Response 串流：inspector 自己永不 `listen` 或 `drain`；消費者 listen 時才訂閱底層；chunk 原物件、原順序轉出；pause、resume、cancel 傳回底層；錯誤與 stack trace 原樣轉出；第二次 `listen` 跟原物件一樣拋 `StateError` | 單元測試 |
| 7-4 | `close()` 與 `done` 回傳同一個 response 代理，不重複記錄 | 單元測試 |
| 7-5 | 標記的判斷與移除發生在「第一次寫 body 或 `close()`」之前。理由：dart:io 在 body 串流開始被讀或 `close()` 時才寫出 header（SDK `http_impl.dart:1904-1906`、:1944）；Dio 在 `openUrl` 完成後才設定 header，並且在 `close()` 前先 `addStream` body（`io_adapter.dart:104-112`、:142-161） | 單元測試 |
| 7-6 | 擷取邏輯自己的例外都吞在 inspector 內（記成 warning log），不影響宿主的請求與回應（`overview.md:97-102`） | 單元測試 |

### US-8：一體適用（brief D9）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 8-1 | 慢請求標示、Network 通知摘要、錯誤摘要分組、display-time 敏感 header 遮蔽、診斷報告、merged timeline 對 `httpClient` entry 都生效，而且不新增分支：`isFailed`（`network_entry.dart:123-124`）、`elapsedAt`、遮蔽 formatter 都只讀 `NetworkEntry` 欄位 | 單元測試（至少遮蔽、慢請求、報告各一） |
| 8-2 | 不點進詳情，就能在 Network 分頁列表分辨 `httpClient` 來源（目前列表 `_EntryTile` 完全不顯示來源，`network_tab.dart:243-310`） | Widget 測試 |
| 8-3 | 詳情頁 Resend 停用，沿用既有提示 `Cannot resend: source Dio not available`（`network_detail_view.dart:346-359`），不加新分支 | Widget 測試 |
| 8-4 | `activeRoute` 由 `logNetwork` 在 pending 時蓋章，completed 繼承（`flutter_inspector.dart:505-520`） | 單元測試 |

### US-9：回歸基準（brief Q3-7）

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 9-1 | 既有 606 個測試全數通過，且不修改既有測試 | `flutter test` |
| 9-2 | `flutter analyze lib/ test/` 不超過既有 7 個 info | 指令驗證 |

---

## 4. 範圍邊界

### 做

- `FlutterInspector`：新增 `captureHttpClient`（bool，預設 `false`），建構時安裝。
- 新的 io／web 條件匯出模組：`HttpOverrides` 子類、`HttpClient`／`HttpClientRequest`／`HttpClientResponse` 三個代理、`IOHttpClientAdapter` 型別判斷；web 側空實作。
- `NetworkOrigin` 新列舉值 `httpClient`（已裁決 2026-11-13，見 §8 C1），版號 3.0.0。
- `NetworkEntry`：新增圖片位元組欄位（可選、帶預設值，向後相容）。
- `NetworkInspector.add`：5 MB 與 50 MB 規則。
- `FlutterInspectorDioInterceptor`：標記注入、紀錄中剔除標記、`Uint8List` 圖片判斷與摘要。
- `NetworkDetailView` 圖片預覽；Network 分頁列表來源標示。
- 文件：開關的 dartdoc（安裝順序、lazy static、isolate、zone、release 行為、C2 重複記錄）、README 新段落、README.md:346-348 依 C1 裁決改寫（不再承諾「永不新增列舉值」）、CHANGELOG 3.0.0 寫明 breaking change 與遷移方式、`docs/architecture/overview.md` 擷取層補一列。

### 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| native client（`cupertino_http`、`cronet_http`、`native_dio_adapter`） | brief Q4；它們不經 `HttpClient`，也攔不到 |
| WebSocket 訊框 | brief Q4。握手本身是 HTTP，會照一般 entry 記錄並在 `detachSocket()` 時完成（1-5），不另外過濾 |
| 重送 `HttpClient` 來源的請求 | brief Q4；沿用既有停用提示 |
| 修改 request／response（mocking） | brief Q4；違反「只看不改」 |
| Network 分頁來源過濾器 | brief Q4 |
| interceptor 退役或任何 breaking change | brief Q4（C1 是唯一例外，已裁決 2026-11-13：接受，發 3.0.0） |
| `reinstall` API、給 zone 用的公開 `HttpOverrides` 類別 | zero 為了搶 slot 補上的 `reinstallHttpOverrides()`（`lib/zero_inspector_kit.dart:504-507`）與 `InspectorHttpOverrides`／`createInspectorHttpClient`（`lib/src/interceptors/http_interceptor.dart:185-223`）。YAGNI；以文件說明安裝順序 |
| 任何卸載 API | brief D3；在串接的全域 slot 上 teardown 結構上就不可能做對（§6.2 A2） |
| 劫持 `debugNetworkImageHttpClientProvider` | 見 §5 Q5 |
| 背景 isolate 的流量 | `HttpOverrides.global` 是 isolate 內的 static，見 §7 R5 |
| 上傳（request 端）圖片預覽 | brief 只要求回應 |
| 5 MB／50 MB 可設定 | brief 給定數值；做成具名常數，不開放設定 |
| 內建 build mode 守衛 | staging 常是 release-mode build，是 brief Q2 的目標情境；由宿主自行決定 |
| 替 `autoUncompress == false` 的壓縮回應解壓副本 | `NetworkImage` 才會這樣（`_network_image_io.dart:97`），而伺服器很少 gzip 圖片；判不出圖片就退回 `[binary N bytes]`（§7 R10） |

---

## 5. 開放問題的建議答案

### Q1：開關與 `NetworkOrigin` 新列舉值的命名

**建議**：開關叫 `captureHttpClient`，列舉值叫 `NetworkOrigin.httpClient`。

- **開關**：既有 opt-in 開關都用 `capture*` 前綴（`captureUncaughtErrors` `flutter_inspector.dart:100`、`captureLifecycleEvents` :134、`capturePerformance` :181）。名稱點出被攔截的 `dart:io` 型別（SDK `http.dart:1257` `abstract interface class HttpClient`），讓使用者一眼知道涵蓋範圍：所有建在 `HttpClient` 上的東西都抓，native client 不抓。
  - 不採用 `captureHttpOverrides`：名稱講的是機制，不是抓到什麼。
  - 不採用 `captureAllHttp`／`captureAllNetwork`：言過其實，native client 抓不到。
- **列舉值**：`httpClient` 與開關同名，標示的是**擷取層**，不是 client 函式庫。這和現有定義一致：`dio` 的 doc 是「Captured by `FlutterInspectorDioInterceptor`」（`network_origin.dart:7-8`）。所以沒掛 interceptor 的 Dio 流量標成 `httpClient` 是正確的。
  - 不採用 `http`：會和 `package:http` 混淆，而它只是眾多來源之一。
  - 不採用 `io`／`dartIo`：太模糊。
- **衝突**：新增列舉值與既有公開承諾衝突，已裁決 2026-11-13 採選項 A，見 §8 C1。

### Q2：Dio 的 `IOHttpClientAdapter` 會不會改寫或丟掉標記 header

**結論：不會丟也不會改，標記方案可行，但有兩個時序與範圍限制。**

證據（dio 5.11.1）：

- interceptor 之後，Dio 只在 `_transformData` 補 `content-type`／`content-length`，不刪 header（`dio_mixin.dart:712-748`）。
- adapter 把 `options.headers` 逐一 `request.headers.set(key, value, preserveHeaderCase: ...)`，只略過值為 `null` 的 header（`io_adapter.dart:104-112`，`null` 判斷在 :105）。所以標記值必須是非 null 字串；`HttpHeaders` 查詢不分大小寫，`preserveHeaderCase` 不影響判斷。
- 預設 adapter 經 `HttpClient()` 建 client（`io_adapter.dart:29`、:257-264）；宿主自訂 `createHttpClient: () => HttpClient(context: ...)` 也一樣經 factory，會被串接到。

限制：

1. **時序**：header 在 `openUrl` 完成**之後**才設定（`io_adapter.dart:80`、:95 之後才到 :104），而 body 在 `close()` 之前先以 `addStream` 寫出（:142-161）。所以代理必須在「第一次寫 body 或 `close()`」之前檢查並移除標記（驗收 7-5）。在 `openUrl` 回傳時檢查一定看不到標記，zero 就是在這裡檢查（§6.2 A4）。
2. **範圍**：標記只在經過 `IOHttpClientAdapter` 時才會被我們移除。用其他 adapter 的 Dio（`native_dio_adapter`、`dio_http2_adapter` 等）若也加標記，標記就會原封不動送到伺服器。因此 interceptor 只在**能證明**走 `IOHttpClientAdapter` 時才加標記（`sourceDio?.httpClientAdapter is IOHttpClientAdapter`，驗收 2-5）。README 的標準用法本來就會傳 `sourceDio`（README.md:165）。（plan-verifier 第 1 輪）這只能證明 `sourceDio` 的 adapter，無法證明實際送出請求的 Dio：`dio.clone(httpClientAdapter: X)` 會沿用 interceptor（dio 5.11.1 `dio_mixin.dart:851`），`sourceDio` 也可能傳錯；`IOHttpClientAdapter(createHttpClient: 既有 client)` 或覆寫 `fetch` 的子類也會繞過代理。這些情況下標記會外洩，見 R14。`IOHttpClientAdapter` 來自 `package:dio/io.dart`（會帶入 `dart:io`），所以型別判斷必須放在條件匯出的 io 側。
3. **紀錄中剔除**：interceptor 存的是 `options.headers` 這個 Map 本身的參照（`dio_interceptor.dart:67`、:105、:160）。標記如果直接加進這個 Map，就會出現在 entry、cURL 與 Resend 裡，所以建 entry 時必須剔除（驗收 2-3；zero 在 `lib/src/interceptors/dio_interceptor.dart:93-96` 也這樣做）。
4. **標記採用逐請求 token（5(c) 裁決選項 B）**：攔截器在 `liveDioMarkers` 以 `WeakReference` 登記 `options.headers`，由 `HttpClient` 代理在送出 header 當下移除標記並同步清空 `requestOptions.headers` 裡的標記，避免後續 `onResponse`／`onError` 攔截器在重試或刷新 token 時誤帶標記（僅連線前失敗後換另一個 Dio 重送屬已知殘留）。

### Q3：三個代理的實作範圍（response 要 tee，又不能破壞消費者）

**建議範圍**：

- **`HttpClient` 代理**：完整實作介面，每個成員都轉給底層的**同名**成員；只包裝回傳的 `Future<HttpClientRequest>`。`get`／`getUrl`／`open` 等便利方法各自轉同名方法，不統一改寫成 `openUrl`（驗收 7-1）。URL 用回傳 request 的 `uri`，不自己組。
- **`HttpClientRequest` 代理**：完整轉發。在第一次呼叫 `add`／`addError`／`addStream`／`write*`／`flush`／`close` 之前跑一次「header 定案」：讀並移除標記，決定記或不記，快照 request headers。body 採 write-through：先轉給底層，再有上限地複製（驗收 7-2）。`close()` 與 `done` 共用同一個 response 代理（驗收 7-4）。
- **`HttpClientResponse` 代理**：寫成 `extends Stream<List<int>> implements HttpClientResponse`，**只覆寫 `listen`**。Stream 其他 30 多個方法都建立在 `listen` 上，自然繼承（SDK `http.dart:1915` 的介面是 `implements Stream<List<int>>`）。`listen` 第一次被呼叫時才訂閱底層，chunk 原樣轉出、同時複製；在 done／error／cancel 時完成 entry，`detachSocket()` 也會完成 entry。其餘成員（`headers`、`certificate`、`connectionInfo`、`compressionState`、`contentLength`、`redirects`、`redirect()`、`cookies`、`persistentConnection`、`reasonPhrase`、`statusCode`、`isRedirect`）一律原值轉出，不包裝、不改寫（驗收 3-3）。
- **每筆請求的複製上限**：用前 12 bytes 判斷是不是圖片。是圖片就最多複製 5 MB，超過後只計數；不是圖片就只複製夠產生 10 KB 文字的量（UTF-8 每字最多 4 bytes，約 40 KB），之後只計數。

**證據**：消費者實際用到的成員有 Dio（`io_adapter.dart:98-101` `abort`，:138-140 三個 setter，:192-206 `certificate`，:208-233 `headers`／`statusCode`／`redirects`／`reasonPhrase`，:224 `cast()`）、`package:http`（`io_client.dart:146` `abort`，:176 `listen`，:204-223 各欄位，`io_streamed_response.dart:32` `detachSocket`）、Flutter（`consolidate_response.dart:58-79` 讀 `contentLength`、`compressionState`、`listen`）。

**方向比較**：

| 方向 | 作法 | 取捨 |
|:---|:---|:---|
| A（建議） | 繼承 `Stream`，只覆寫 `listen`；其他成員原值轉出 | 程式碼最短；stream 語意（single-subscription、pause、cancel）由底層保證 |
| B | 逐一手寫 30 多個 Stream 方法（zero 的作法） | 每個方法都要寫對；zero 每次呼叫都重建一條 transform stream（§6.2 A7） |
| C | 宿主一取 response 就由 inspector 先讀完整個 body、再餵回去 | 改變時序與記憶體峰值，大檔與 SSE 直接壞掉，違反「只看不改」 |

### Q4：50 MB 預算的計帳與淘汰放在哪裡

**建議：放在 `NetworkInspector.add`，在寫入 buffer 之後、`onMutate` 之外執行；總量每次掃描算出，不維護計數器。**

- `NetworkInspector.add` 已經是 network 寫入的唯一入口，截斷規則也在這裡做（`network_inspector.dart:36-52`）。5 MB 與 50 MB 放同一處，手動 `logNetwork` 帶進來的 entry 也一體適用。
- `RingBuffer.add` 滿了會靜默 `removeAt(0)`，沒有淘汰回呼（`ring_buffer.dart:35-41`）。維護累加計數器會漂移，每次掃描 buffer 加總（最多 500 筆）最笨也最不會錯，`clear()` 也自然歸零。只有新 entry 帶位元組時總量才可能上升，所以只在這時候掃。
- 淘汰：由舊到新，用 `_buffer.replace(old, 去掉位元組的副本)` 換掉，直到總量不超過 50 MB。位元組欄位不進 `==`，副本與原物件相等，`replace` 會找到原位置（`ring_buffer.dart:47-54`），書籤也照樣比對得到。
- 不變式 #1：`add` 先完成 `_buffer.add`（其 `onMutate` → `_bump` 已返回），之後才依序呼叫 `replace`；每次 `replace` 的 `onMutate` 都是獨立、非巢狀的呼叫，不在 `onMutate` 裡寫同一個 buffer（`ring_buffer.dart:24-28`）。`onAdd`（通知）只對新 entry 觸發一次。
- pending entry 沒有位元組，不會被淘汰換掉，所以擷取層持有的 `replaces:` 指標不會失效。

| 方向 | 作法 | 取捨 |
|:---|:---|:---|
| A（建議） | 位元組放 entry 欄位；在 `NetworkInspector.add` 掃描並淘汰 | 單一資料來源；entry 被 ring buffer 擠掉時位元組一起釋放 |
| B | 旁邊另開 `Expando`／`Map` 存位元組 | 需要 `RingBuffer` 的淘汰通知，等於修改核心結構；entry 換新物件時還要搬位元組 |
| C | 在擷取層計預算，滿了就不再存新的（zero `lib/src/services/inspector_service.dart:189-207`） | 與 brief「丟最舊」相反；越新的事件越缺資料，而新事件正是鏈推斷需要的 |

### Q5：`NetworkImage._sharedHttpClient` 是 `static final`

**事實**：Dart 的 static 欄位在第一次讀取時才初始化。`_httpClient` getter 只在 `_loadAsync` 讀（`_network_image_io.dart:99-108`、:120），所以 client 是在**第一張網路圖開始載入時**才建立，不是 app 啟動時。只要 inspector 在第一張網路圖之前建構就抓得到；反之整個 process 都漏抓（hot restart 會重置 static）。dart:io WebSocket 的 `static final HttpClient _httpClient`（`websocket_impl.dart:1310`）同理。

**陷阱**：README 範例把 inspector 寫成頂層 `final inspector = FlutterInspector(...)`（README.md:81-86），頂層變數同樣是 lazy，第一次被讀取才建構。照 README 寫法，是在 `MyApp.build` 讀 `inspector.navigatorObserver` 時才建構，通常早於子 widget 的圖片載入；但 `main()` 裡 `runApp` 之前就建立的 client（DI 容器註冊 `http.Client()`、SDK 初始化）一定會漏。

**建議：只寫文件，不寫程式。** dartdoc 與 README 要求「打開 `captureHttpClient` 時，在 `main()` 開頭就建構（或讀取一次）inspector」，並說明 lazy static 的原因。

**不採用**：劫持 `debugNetworkImageHttpClientProvider`。它包在 `assert` 裡（`_network_image_io.dart:101-106`），profile 與 release（包括 staging）都無效；而且它是另一個全域單一 slot，會重蹈搶 slot 的覆轍。

### Q6：多個 inspector 同時開啟開關

**建議：每個 isolate 只安裝一次。** 第一個開啟的 inspector 安裝；之後開啟的 inspector 不再安裝，只在 debug 模式提示一次。dartdoc 沿用既有措辭「Enable this on a single, app-wide inspector」（`flutter_inspector.dart:93-96`、:122-124）。interceptor 加標記的條件是「本 isolate 已安裝 `HttpClient` 層」，不看自己所屬的 inspector。如此每筆請求在整個 process 只會被一層記錄。

| 方向 | 結果 | 判斷 |
|:---|:---|:---|
| A（建議） | 只裝一層，`HttpClient` 流量進第一個開啟的 inspector | 簡單、行為可預測 |
| B | 每個 inspector 各疊一層 | 最外層代理先看到標記並移除，內層看不到，就把 Dio 流量當成非 Dio 再記一次；每筆請求還要穿過 N 層代理 |
| C | 安裝時拆掉前面 inspector 的層（zero 的拆層迴圈，`http_interceptor.dart:203-208`） | 只有最後一個 inspector 抓得到，前面的 inspector 靜默失去擷取 |

**交由 0b**：安裝 guard 的形式，以及提供 `@visibleForTesting` 的重置。

### Q7：條件匯出兩側的簽章一致（不變式 #4）

**建議**：

- 只開一對 `_io`／`_web` 檔案，對外面積越小越好：一個安裝函式，加一個「adapter 是不是 `IOHttpClientAdapter`」的判斷函式。條件寫 `dart.library.js_interop`，與既有兩組一致（`network_notifier.dart:10-11`、`share_text.dart:8`）。
- 共用的 typedef 與標記常數放在第三個平台中立檔，兩側都 import。`dart:io` 與 `package:dio/io.dart` 只能出現在 io 側。
- 兩道把關：
  1. web 側是純 Dart stub，不 import `dart:js_interop`／`package:web`，所以 VM 測試可以直接 import，把兩側函式各指派給同一個 typedef；簽章漂移時測試檔編譯失敗（驗收 5-3）。既有的 `share_text_web.dart` 用了 js_interop，做不到這點，所以過去只能靠 web build。
  2. 最小專案跑 `flutter build web`（驗收 5-1，作法比照 `docs/plans/2026-09-06-crash-notification.md:147-165`）。

---

## 6. zero_inspector_kit：借鏡與刻意避開

以下路徑都以 zero repo 根目錄為基準（HEAD `dbb10f4`，v2.4.0）。只讀原始碼，沒有執行。

### 6.1 借鏡

| # | 借什麼 | zero 出處 | 本規格怎麼用 |
|:---:|:---|:---|:---|
| B1 | 安裝時串接 `HttpOverrides.current`，而不是覆蓋 | `lib/src/interceptors/http_interceptor.dart:97-99` | D3；同時比照 SDK 自己的 `_HttpOverridesScope`（`_http/overrides.dart:95-123`），也轉發 `findProxyFromEnvironment` |
| B2 | 只有 `HttpClient` 層在運作時，Dio interceptor 才加標記，而且紀錄裡剔除標記 | `lib/src/interceptors/dio_interceptor.dart:84-87`、:93-96 | D2、驗收 2-3／2-4 |
| B3 | `close()` 與 `done` 共用同一個 response 代理 | `lib/src/interceptors/inspector_http_client.dart:306-309`、:652-664 | 驗收 7-4 |
| B4 | 消費者取消訂閱時也要完成紀錄 | `lib/src/interceptors/inspector_response_proxy.dart:340-375` | 驗收 1-5 |
| B5 | tee 時設複製上限，超過就只轉發 | `lib/src/interceptors/inspector_response_proxy.dart:21`、:305-316 | Q3 的分型上限 |
| B6 | 魔術位元組判斷，並以長度守衛防 `RangeError` | `lib/src/ui/widgets/inspector_image_preview.dart:62-94`（守衛在 :63） | 驗收 6-1，BMP 改嚴格（A9） |
| B7 | `Image.memory` 限高，`errorBuilder` 退回文字 | `lib/src/ui/widgets/inspector_image_preview.dart:132-143` | 驗收 6-3 |
| B8 | 解碼 UTF-8 前綴時對齊字元邊界 | `lib/src/interceptors/http_interceptor.dart:14-55` | 0b 可參考（驗收 1-3） |

### 6.2 刻意避開

| # | zero 的缺陷 | 出處 | 本規格的作法 |
|:---:|:---|:---|:---|
| A1 | 全域 slot 互搶：宿主之後設定的 override 讓 inspector 失效，只好補 `reinstallHttpOverrides()` | brainstorm :2395、:2506；`lib/zero_inspector_kit.dart:504-507`；`lib/src/interceptors/http_interceptor.dart:135-158` | 不提供 reinstall；文件寫明安裝順序，宿主永遠贏（驗收 3-4） |
| A2 | `stop()` 還原舊值，曾把宿主的 `HttpOverrides.global` 抹成 `null`、卸掉 SSL Pinning | brainstorm :2395、:2506、:2538。HEAD 已在 `http_interceptor.dart:110-118` 加 `identical` 守衛，但若宿主之後的 override 串接了 zero 那層，`stop()` 之後那層仍會被呼叫：在串接的 slot 上 teardown 結構上就做不對 | 不 teardown，永不寫 `null`（驗收 4-2、4-3） |
| A3 | release 照裝，README 卻宣稱 tree-shaken；之後改用 dart-define 守衛加改寫 `pubspec.yaml` 的 CLI | brainstorm :2391；HEAD `lib/src/utils/environment.dart:86-87` | 預設關閉、明確 opt-in、文件誠實；不加隱藏守衛 |
| A4 | 在 `openUrl` 回傳的 `.then` 裡讀標記。那時 Dio 還沒設定 header（dio `io_adapter.dart:80-112`），依程式碼推論：標記永遠讀不到、不會被移除、會送到伺服器，而且 Dio 請求會被記兩次（**未執行，依時序推論**） | `lib/src/interceptors/inspector_http_client.dart:109-121` | 在第一次寫 body 或 `close()` 前檢查（驗收 7-5） |
| A5 | 會送出去的 Dio 標記沒有限定 adapter 型別 | `lib/src/interceptors/dio_interceptor.dart:84-87` | 只在能證明走 `IOHttpClientAdapter` 時才加（驗收 2-5） |
| A6 | request body 先緩衝、到 `close()` 才送出，改變送出時序，`flush()` 也名不副實 | `lib/src/interceptors/inspector_http_client.dart:349-375`、:483-487 | write-through（驗收 7-2） |
| A7 | response 代理手寫 30 多個 Stream 方法，每次呼叫都重建一條 `_wrappedStream`；`connectionInfo` 回傳 `null`；改寫 `contentLength`；`statusCode` getter 有副作用 | `lib/src/interceptors/inspector_response_proxy.dart:219-503`、:282-330、:213、:160-184、:137-141 | 繼承 `Stream` 只覆寫 `listen`；所有成員原值轉出（Q3、驗收 3-3） |
| A8 | `open()` 改寫成 `openUrl`，用 port 猜 scheme；便利方法全部繞道 | `lib/src/interceptors/inspector_http_client.dart:13-38`、:202-241 | 每個方法轉給同名方法（驗收 7-1） |
| A9 | `InspectorHttpOverrides` 沒有覆寫 `findProxyFromEnvironment`，宿主 override 的代理設定在鏈上遺失（SDK 經 `HttpOverrides.current` 讀，`http.dart:1634-1643`） | `lib/src/interceptors/http_interceptor.dart:185-213` | 轉給上一層（驗收 3-2） |
| A10 | 圖片以 base64 字串塞進 body 文字（多 1/3 記憶體、只能 64 KB、匯出也帶著 base64），預覽再從文字反解 | `lib/src/interceptors/inspector_response_proxy.dart:96-127`；`lib/src/ui/widgets/inspector_image_preview.dart:28-51` | 原始位元組放獨立欄位，body 只放摘要（驗收 6-2、6-9） |
| A11 | BMP 只看 `BM` 兩個位元組，以 `BM` 開頭的文字 body 會被誤判成圖片 | `lib/src/ui/widgets/inspector_image_preview.dart:92` | BMP 另外檢查 DIB header（驗收 6-1） |
| A12 | 全域 body 預算用完後，新請求就不存 body | `lib/src/services/inspector_service.dart:189-207`；`lib/src/interceptors/inspector_response_proxy.dart:305-307` | 丟最舊、保留最新（Q4） |
| A13 | Mocking 規則改寫 request／response，為此還要先 `drain` 原回應 | `lib/src/interceptors/inspector_http_client.dart:396-433`；`lib/src/interceptors/inspector_response_proxy.dart:377-404` | 範圍外，只看不改 |

---

## 7. 技術限制、風險與誠實邊界

| # | 限制或風險 | 規格層級的處理 |
|:---:|:---|:---|
| R1 | 宿主在 inspector 之後設定 `HttpOverrides.global`，擷取會靜默停止 | 宿主永遠贏，什麼都不會壞；dartdoc 與 README 寫明（驗收 3-4） |
| R2 | 比 inspector 先建立的 lazy static client 會被永久漏抓（`_network_image_io.dart:97`、`websocket_impl.dart:1310`、DI 註冊的 client） | 文件要求在 `main()` 開頭建構 inspector（Q5） |
| R3 | 會把所有 header 一起簽章的 interceptor（例如部分 SigV4 實作）如果排在 inspector interceptor **之後**，會把標記簽進去；我們移除標記後，伺服器驗簽失敗 | 文件要求開關打開時把 `FlutterInspectorDioInterceptor` 放在最後一個（這樣紀錄的 header 也剛好等於實際送出的 header） |
| R4 | `HttpOverrides.runZoned` 建立的 zone override 優先於 global（SDK `overrides.dart:35-36`），該 zone 內的流量漏抓 | 文件註明；不提供 zone 版公開 API（YAGNI） |
| R5 | `HttpOverrides.global` 是 isolate 內的 static，`compute`／`Isolate.run` 裡的請求漏抓 | 文件註明 |
| R6 | Dart SDK 若替 `HttpClient`／`HttpClientRequest`／`HttpClientResponse` 新增成員，`implements` 代理會編譯失敗，連開關 `false` 的使用者也受影響 | 交由 0b：評估加 `noSuchMethod` 兜底（新 SDK 照樣編譯，但會掩蓋漏寫的成員）或維持全部明確轉發 |
| R7 | 圖片多的頁面會把 API 請求擠出 500 筆的 buffer，鏈推斷因而斷裂 | 預設關閉；文件建議調大 `bufferSize`（`flutter_inspector.dart:289`）；來源過濾器不在範圍 |
| R8 | 測試隔離：`HttpOverrides.global` 是 static，flutter_test 會先裝一個回 400 的 `_MockHttpOverrides`（`flutter_test/_binding_io.dart:26-27`、`binding.dart:1288-1290`） | 開關 `true` 的測試必須自行儲存與還原 `HttpOverrides.global`，並重置安裝 guard；真實請求用不初始化 binding 的 `test()` 加本機 `HttpServer` |
| R9 | 書籤 Set 與開著的詳情頁持有舊 entry 指標，被淘汰的位元組要等它們釋放才回收 | 量小，只記錄不處理 |
| R10 | `autoUncompress == false`（`NetworkImage`）時，副本是壓縮後的位元組；伺服器對圖片 gzip 時判不出圖片 | 退回 `[binary N bytes]`，不解壓（範圍外） |
| R11 | ~~列表的 size 欄位對圖片顯示的是摘要字串的大小~~ | 已修正（1f9b29a）：`NetworkEntry.requestBodyLength`／`responseBodyLength` 記錄實際大小，size 優先採用；只有未量到大小的摘要（如 FormData）才顯示「size reflects the stored text」提示 |
| R12 | 請求進行中，Dio 的 `RequestOptions.headers` 帶著標記，宿主自己讀 `requestOptions.headers` 會看到 | 0b 決定在 `onResponse`／`onError` 移除。（plan-verifier 第 1 輪）Dio 的 response／error interceptor 與 request 同序（`dio_mixin.dart:534`、:564、:577），inspector 排最後時，其他 interceptor 的 `onResponse`／`onError` 會先看到標記，見 R14 (c) |
| R13 | 連線建立前就失敗的 Dio 請求會重複記錄 | 已裁決 2026-11-13 接受（§8 C2）；寫進 dartdoc 與 README |
| R14 | （plan-verifier 第 1 輪）標記外洩與漏記路徑：(a) `dio.clone(httpClientAdapter: X)` 沿用 interceptor，或 `sourceDio` 傳錯；(b) `IOHttpClientAdapter(createHttpClient: 既有 client)`，或覆寫 `fetch` 的子類；(c) 其他 interceptor 在 R12 移除前就看得到標記，經別的 Dio retry／token refresh 重送時，非 IO adapter 會外洩，IO adapter 且未掛 inspector 會被 HttpClient 層靜默略過不記 | (a)(b) 寫進 dartdoc 與 README；只有「傳了 `sourceDio`、而且它就是實際送出請求的 Dio」時才保證不重複記錄。(c) 的處理**待使用者裁決**，選項見計畫 §9 |

---

## 8. 需使用者裁決的衝突

### C1：新增 `NetworkOrigin` 列舉值 vs.「不做 breaking change」與 README 承諾

- **衝突**：brief 開放問題 1 預設要新增列舉值；但 brief Q4 排除任何 breaking change，而且 README.md:346-348 明文承諾不新增：「Never add or expect custom `NetworkOrigin` enum values … Host applications frequently use exhaustive `switch (entry.origin)` expressions. Adding new values … would break exhaustive matching at compile time」。Dart 3 會對 enum 的 `switch` 做窮盡檢查，宿主若有不含 wildcard 的 `switch (entry.origin)`，升級後就編譯失敗。
- **選項 A**：新增 `NetworkOrigin.httpClient`。資料結構正確（一個維度、三個值）。代價是違反 README 承諾，semver 上算 breaking。要同步改寫 README.md:346-348，CHANGELOG 明列影響，版號由使用者決定（照 brief 走 minor，或改走 3.0.0）。
- **選項 B**：不加列舉值，另加一個欄位標示擷取層。會出現「`origin: webview` 配上 `httpClient`」這種不合法組合，等於用特殊情況補資料結構。
- **選項 C**：沿用 `NetworkOrigin.dio`。違反 D9「列表上標示來源」，還會把非 Dio 流量標成 Dio，誤導排查。
- **建議：A**。破壞發生在編譯期、修正只要一行；但這是 brief 之外的取捨，必須由使用者明確同意才能進 0b。
- **裁決（已裁決 2026-11-13）**：採**選項 A**，新增 `NetworkOrigin.httpClient`，版號發 **3.0.0（major）**，不走 minor。配套：
  1. 改寫 `README.md:346-348`（及 `README.zh-TW.md` 對應段落）「Never add or expect custom `NetworkOrigin` enum values」：改為說明 3.0.0 刻意新增 `httpClient`，未來新增列舉值只會出現在 major 版並寫進 CHANGELOG；自訂 entry 仍不要自行設成 `webview` 或 `httpClient`。
  2. `CHANGELOG.md` 3.0.0 寫明 breaking change 與遷移方式：宿主的窮盡式 `switch (entry.origin)` 要補一個 `NetworkOrigin.httpClient` 分支（或改用 wildcard）。
  3. 版號 3.0.0 同步 4 處（`pubspec.yaml`、`README.md`、`CHANGELOG.md`、`lib/src/version.dart`），`README.zh-TW.md` 一併更新。

### C2：在 `openUrl` 階段就失敗的 Dio 請求

- **事實**：Dio 在 `openUrl` 完成後才設 header（`io_adapter.dart:80`、:95、:104-112）；dart:io 的 `openUrl` 要等連線建立才完成，所以 DNS 失敗、拒絕連線、TLS 握手失敗都在 `openUrl` 階段拋出。那時標記還不存在，`HttpClient` 層分不出是不是 Dio 請求。
- **選項 A（建議）**：照樣記錄這類失敗（`origin: httpClient`）；Dio 的 `onError` 也會記一筆，所以連線層失敗的 Dio 請求會有兩筆、來源標示不同。把驗收 2-1 精確化為「header 成功送出的 Dio 請求只記一次」，並寫進文件。
- **選項 B**：連線失敗一律不記。會漏掉非 Dio 流量最重要的破圖原因（DNS、TLS 失敗），不建議。
- **選項 C**：interceptor 另外登記「進行中的 Dio 請求（method + uri）」，`HttpClient` 層在 `openUrl` 失敗時查表略過。可以做到只記一次，但多一個共用結構和一個啟發式（同時有同 method、同 URL 的非 Dio 請求時可能誤略）。
- **建議：A**；若使用者堅持驗收 2-1 不打折扣，改採 C。
- **裁決（已裁決 2026-11-13）**：採**選項 A**。接受「連線前就失敗（`openUrl` 階段：DNS、拒絕連線、TLS）的 Dio 請求會被記兩次」。驗收 2-1 改為「header 成功送出的 Dio 請求只記一次」；**不實作**選項 C 的查表登記。此行為寫進 `captureHttpClient` 的 dartdoc 與 README。

---

## 9. 交由 STAGE 0b 決定

1. 標記 header 的名稱與固定值（Q2 第 4 點：不需要逐請求 ID）。
2. `IOHttpClientAdapter` 判斷函式與安裝函式的確切簽章、平台中立檔的位置（Q7）。
3. 單次安裝 guard 的形式、第二個 inspector 的 debug 提示、`@visibleForTesting` 重置（Q6）。
4. entry 時間定義。建議：`timestamp` 取 `openUrl` 呼叫時刻；completed 發生在 body 結束、錯誤、取消或 `detachSocket` 時；`duration` 涵蓋到 body 結束，「載入慢」才量得到。
5. 消費者取消算不算失敗。建議不算，否則捲動列表會冒出大量紅字；但 entry 必須離開 pending。
6. 文字與二進位的判定、UTF-8 前綴對齊（可參考 §6.1 B8）、request body 複製上限，以及 `write()` 的編碼處理。
7. 圖片欄位命名，以及 `copyWith` 怎麼清除位元組（現行 `??` 寫法無法設成 null，`network_entry.dart:149-189`）。
8. 預覽 UI：顯示尺寸、`cacheWidth`、`ImageCache` 處理、佔位文案（區分「超過 5 MB」與「被預算淘汰」）。
9. 列表來源標示的樣式；Console 分頁的合併時間軸列要不要也標。
10. 是否在 `onResponse`／`onError` 把標記從 `requestOptions.headers` 移除（R12）。
11. SDK 介面演進的對策（R6）。
12. 測試策略：本機 `HttpServer`、`HttpOverrides` 儲存與還原、guard 重置（R8）。
13. example 示範頁要不要加。注意 `example/lib/main.dart` 目前有使用者尚未 commit 的改動。
14. 版號與 4 處同步（`pubspec.yaml`、`README.md`、`CHANGELOG.md`、`lib/src/version.dart`），在 release commit 處理；版號為 3.0.0（C1 已裁決 2026-11-13）。

---

## 10. 規格出口條件

- ~~使用者裁決 §8 C1 與 C2。~~ 已完成（已裁決 2026-11-13：C1 採 A、發 3.0.0；C2 採 A、不做查表）。
- US-1 至 US-9 的驗收條件確認為可測試、可驗收。
- §4 範圍邊界與 §7 誠實邊界確認。
- §5 的命名（`captureHttpClient`、`NetworkOrigin.httpClient`）與 Q4、Q6 的建議方向確認。
