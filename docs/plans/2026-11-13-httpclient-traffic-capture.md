# 實作計畫：`dart:io` `HttpClient` 層流量擷取與圖片預覽（STAGE 0b）

> **For Claude:** REQUIRED: 使用 superpowers:subagent-driven-development（若有 subagent）或 superpowers:executing-plans 執行本計畫。步驟以 checkbox（`- [ ]`）追蹤。
>
> **語言**：繁體中文；程式碼、識別字、指令保留原文。遵守 `.claude/rules/flutter-styles.md`（const 正確性、尾隨逗號、widget 提取為獨立 class、**禁止 `.then()`**）。

- **日期**：2026-11-13 ｜ **Effort**：high ｜ **總任務數：21**（T12b 待裁決、T18b 選做）
- **規格**：[`docs/features/2026-11-13-httpclient-traffic-capture.md`](../features/2026-11-13-httpclient-traffic-capture.md)（C1、C2 已裁決 2026-11-13；plan-verifier 第 1 輪同步 D3、1-6、5-3、Q2 第 2 點、R12、R14）
- **版號**：**3.0.0**（C1：新增 `NetworkOrigin.httpClient` 屬 breaking change）
- **基準（planner 於 2026-11-13 實測）**：`rtk flutter test` 共 **817** 個測試全過（CLAUDE.md 與規格 9-1 寫的「606」已過時，以 817 為準）；`rtk flutter analyze lib/ test/` 共 **7** 個 info，與 CLAUDE.md 一致。
- **使用者裁決（2026-11-13，已定案，優先於下文任何「待裁決」字樣）**：
  - **R6 → 選項 2**：T7／T8／T9 三個代理各加一行 `noSuchMethod` 兜底（§9.1）。
  - **5(c) → 選項 B**：T12b 為**必做**，T13／T16／T17／T18a／T19 依「採用 T12b」的相依關係執行（§9.2）。
  - **D3 → 同意修改 `CLAUDE.md`**：T16 在不變式 #4 的條件匯出清單加入 `http_client_capture`，並把測試基準 606 改為實測值。
  - plan-verifier 第 3 輪的 3 項不阻擋建議（§7 風險 13 措辭、§9.2 選項 B 殘留補充、規格 7-2 措辭）於 T16 一併處理。

### 修訂紀錄：plan-verifier 第 1 輪

| 項目 | 修改位置 |
|:---|:---|
| 必改 1：`close()` 包住並回傳 `_inner.close()`，`done` 包住 `_inner.done`；改成 async helper 加 `rethrow`，不用 `.then`；原風險 4 刪除 | T7 `_capture`、T8 `_track`／`close`／`done`、§7 |
| 必改 2：install 以 `Zone.root.run(() => HttpOverrides.current)` 讀取 global slot | §1 第 12 點、T5、規格 D3 |
| 必改 3：`abort` 先轉給底層，再直接完成 entry | T8 |
| 必改 4：1-6 拆成 T18a（必做，scratchpad 原生 probe）與 T18b（選做，example） | T18a、T18b、§5、T19、規格 1-6 |
| 必改 5：外洩與漏記路徑 (a)(b)(c)；修正 D-3 與 dartdoc 說法；(c) 列入待裁決並提出 T12b | §1 第 13–14 點、D-3、T6、T12b、T16、§7 風險 1、§9.2、規格 Q2、R12、R14 |
| 必改 6：簽章測試逐對比對 `runtimeType` | T5、規格 5-3 |
| 建議 1：修正 3 處「never touches `dart:io`」；T16 加入 CLAUDE.md #4 與 `overview.md:86-90` | T6、T16 |
| 建議 2：tee 包進 `_guard`，並且先轉出、再 tee | T9、T10、§2.3 |
| 建議 3：去重需要傳 `sourceDio` | T6、T16 |
| 建議 4：R6 統一為待裁決 | D-4、§7 風險 2、§9.1 |
| 建議 5：6-6 加不可重入旗標，11 筆 url 彼此不同 | T4 |
| 建議 6：6-9 抽查加上診斷報告與分享 | T13 |
| 建議 7：tagged pending header 快照寫進 CHANGELOG | T19 |
| 建議 8：`!kReleaseMode` 在 `flutter test` 下也是 true | T6、T16 |
| 建議 9：Wave 2／3 重複列出 T7 | §5 |

### 修訂紀錄：plan-verifier 第 2 輪

| 項目 | 修改位置 |
|:---|:---|
| R2-1：Dio 的 request stream 執行期是 `Stream<Uint8List>`，用 `transform(StreamTransformer<List<int>, List<int>>…)` 會拋 TypeError。改成 `stream.map`，並補直接以 `Stream<Uint8List>` 呼叫的測試。scratchpad 原型已實測（§1 第 15 點） | §1 第 15 點、§2.3 第 6 列、T10 |
| R2-2：`close()` 不再拿 `_inner.done` 做 identical 探測，改用共用 memo `_tracked`；寫明「先讀 `done` 再 `close()`」的取捨。`_track` 最多執行一次，`_response ??=` 因此多餘，已刪 | §1 第 7 點、T8、T9、§7 |
| R2-3：`abort` 只在回應交出前完成 entry（`_responded`）；補「回應到達後才 abort」的測試 | §1 第 16 點、§2.3 第 4 列、T8、T9、規格 1-4 |
| R2-4：T12b 的 registry 孤兒清理（重新標記前移除舊 token、值改存 `WeakReference` 並延遲剪枝、相等才移除）；warning 措辭改為「可能」；寫入清單加 `dio_interceptor_test.dart`；T8、T12 的測試不依賴 `kDioMarkerValue` | T8、T12、T12b、§9.2 |
| §9.1 選項 2 如實描述測試覆蓋；兩個選項都擋不住既有成員改簽章；T8 一律補 request 成員往返表格測試 | T8、§9.1 |
| 建議 1：R2-2 的 memo 讓 T8 自己就能通過「close 與 done 是不同物件」的測試，留在 T8；「回應到達後 abort 的 statusCode 斷言」需要 T9 的包裝，放在 T9 | T8、T9 |
| 建議 2：T4 的不可重入旗標註明限制 | T4 |
| 建議 3：T18a 改用 probe 自己起的本機 `HttpServer` | T18a、規格 1-6 |

---

## 0. 目標與架構

**Goal**：開關打開時，在 `HttpOverrides` 鏈上串一層只看不改的 `HttpClient` 代理，把 Dio interceptor 以外的 `dart:io` 流量翻成既有 `NetworkEntry`（`origin: httpClient`），經 `FlutterInspector.logNetwork` 推進同一條時間軸。圖片回應另外保留位元組供詳情頁預覽（單張 5 MB、總量 50 MB）。

**這是多一個事件來源，不是多一個系統**：擷取層不持有 buffer、不做 UI，只呼叫公開的 `logNetwork`，與 `WebViewBridgeAdapter` 同形。

```text
FlutterInspector(captureHttpClient: true)
  └─ installHttpClientCapture(this)                 ← 條件匯出；web 為空實作
       previous = Zone.root.run(() => HttpOverrides.current)   ← global slot，不取 zone override
       HttpOverrides.global = _InspectorHttpOverrides(previous)

HttpClient() ─► _InspectorHttpOverrides.createHttpClient(ctx)
                 = _CapturingHttpClient(previous.createHttpClient(ctx))
openUrl/getUrl/open/... ─► 底層同名方法 ─► _CapturingRequest
   第一次 add/addError/addStream/write*/flush/close 之前：_finalize()
     ├─ headers 有 x-flutter-inspector-dio：removeAll，整筆不記
     └─ 否則 logNetwork(pending)
   close() 包 _inner.close()、done 包 _inner.done，共用一個 _tracked memo 與 _completed
   abort() 轉給底層；只在回應交出前直接完成 entry
   ─► _CapturingResponse（只覆寫 listen）
     消費者 listen 才訂閱底層；chunk 原物件先轉出，再經 _Tee 有上限地複製
     done / error / cancel / detachSocket ─► logNetwork(completed, replaces: pending)
NetworkInspector.add：截斷文字 → >5 MB 丟位元組 → 寫入 buffer → 總量 >50 MB 時由舊到新丟位元組
```

---

## 1. 讀 codebase 後的關鍵事實（設計地基）

1. **單一寫入入口**：`NetworkInspector.add`（`lib/src/inspectors/network_inspector.dart:36-52`）負責截斷；`FlutterInspector.logNetwork`（`lib/src/core/flutter_inspector.dart:505-520`）負責 `activeRoute` 蓋章，completed 繼承 pending 的錨點。擷取層只要呼叫 `logNetwork`，8-4 自動成立。
2. **`RingBuffer.replace` 用 `==` 找位置**（`lib/src/core/ring_buffer.dart:47-54`），`onMutate` 內禁止寫同一個 buffer（:24-28）。位元組欄位不進 `==`，所以「去掉位元組的副本」能被 `replace` 找到原位置，書籤 Set 也照樣比得到。
3. **`copyWith` 用 `??`**（`lib/src/models/network_entry.dart:149-189`），無法把欄位設成 null，需要一個顯式清除參數。
4. **`dart:io` 只能出現在條件匯出的 io 側**，比照 `network_notifier.dart:10-11`、`share_text.dart:8`（`dart.library.js_interop`）。「never on `dart:io`」這類說法出現在 `flutter_inspector.dart:151`、`README.md:1303`、`README.zh-TW.md:1135`，要改成「只在條件匯出後面」（T6、T16）。
5. **lib 內沒有任何 `switch (entry.origin)`**：唯一用到的是 `network_detail_view.dart:135` 的 `entry.origin.name`。新增列舉值不會讓套件自己編譯失敗；會壞的是宿主的窮盡式 switch（C1 已接受）。
6. **Dio 的 `IOHttpClientAdapter` 會快取 `HttpClient`**（dio 5.11.1 `lib/src/adapters/io_adapter.dart:57`、:241）。它在 `openUrl` 完成後才設 header（:80-112），body 用 `addStream`（:142-161），之後才 `close()`。
7. **dart:io 的 `close()` 回傳 `done`，而 `done` 本身會快取**（SDK 3.13.1 `_http/http_impl.dart:1531-1542`）。如果代理讓 `close()` 和 `done` 各自追蹤一個 future，「忽略 `close()` 回傳值、只 await `done`」的呼叫端就會多出一個無人處理的錯誤。所以 T8 讓兩者共用同一個 memo `_tracked`（plan-verifier 第 2 輪）。
8. **`version_test.dart` 會檢查 CHANGELOG 最上面的版號標題是否等於 pubspec**。CHANGELOG 的 3.0.0 段落只能在 T19 寫。
9. **`flutter_test` 初始化 binding 時會裝一個回 400 的 `_MockHttpOverrides`**（規格 R8）。凡是測試會改到 `HttpOverrides` 的檔案，一律只用 `test()`，並在 `tearDown` 還原 global 與 install guard。
10. **`package:flutter/foundation.dart` 已匯出 `Uint8List`**（`consolidate_response.dart:11`）。已 import foundation 的檔案若再加 `import 'dart:typed_data'`，會多一個 `unnecessary_import` info，超出基準。
11. **原型實測**（scratchpad，Dart 3.13.1，用完已刪）：
    - 標記在「第一次寫入或 `close()`」之前移除時，本機 server 4 次請求都沒收到標記。
    - `extends Stream` 只覆寫 `listen` 時，第二次 `listen` 會同步拋 `StateError`；`first`、`drain`、`cast` 都正常。
    - 同步 `StreamController` 在 **done 之後也會呼叫 `onCancel`**，所以完成紀錄必須只執行一次，而且先到的 done 為準。
12. **`HttpOverrides.current` 是 `Zone.current[...] ?? _global`**（SDK `_http/overrides.dart:35-36`）。若在 `HttpOverrides.runZoned` 內建構 inspector，直接讀 `current` 會把 zone 的 override 升格成 global 的上一層。因此 install 用 `Zone.root.run(() => HttpOverrides.current)`；root zone 沒有 zone value，讀到的就是 `_global`。
13. **`Dio.clone` 會沿用 interceptor**（dio 5.11.1 `dio_mixin.dart:851` `addAll(interceptors ?? this.interceptors)`）。clone 換掉 adapter 時，interceptor 的 `sourceDio` 仍指向原本的 Dio。
14. **Dio 的 request、response、error 三段 interceptor 走同一個順序**（`dio_mixin.dart:534`、:564、:577）。inspector 排最後時，它的 `onResponse`／`onError` 也是最後才執行，其他 interceptor 在那之前都看得到 `requestOptions.headers` 裡的標記。
15. **Dio 送進 `addStream` 的 body 執行期型別是 `Stream<Uint8List>`**（`io_adapter.dart:144`；`progress_stream/io_progress_stream.dart:6`、:17-23）。對它呼叫 `transform(StreamTransformer<List<int>, List<int>>.fromHandlers(...))` 會因 covariance 在執行期拋 TypeError，而且 **analyzer 不會報錯**。scratchpad 原型（plan-verifier 第 2 輪，Dart 3.13.1，驗完已刪）實測：
    - `transform` 拋 `_TypeError: type '_StreamHandlerTransformer<List<int>, List<int>>' is not a subtype of type 'StreamTransformer<Uint8List, List<int>>'`。
    - `stream.map((c) { tee; return c; })` 通過，chunk 與原物件 `identical`。
    - 先 `.cast<List<int>>()` 再 `transform` 也通過。
    - 真實 `HttpClient.addStream(stream.map(...))` 送出 `Stream<Uint8List>` 時，伺服器收到完整 bytes。
16. **dart:io 的 `abort()` 在回應交出後是 no-op**（`http_impl.dart:1702-1709`：只有 `_responseCompleter` 還沒完成時才報錯並 `destroy()`）。同一個原型實測：回應到達後才 `abort()`，body 仍完整讀到。

---

## 2. 資料結構與方向 trade-off

### 2.1 新增或變動的資料

| 資料 | 位置 | 說明 |
|:---|:---|:---|
| `NetworkOrigin.httpClient` | `network_origin.dart` | 列舉值加在最後（C1） |
| `NetworkEntry.responseImageBytes`（`Uint8List?`） | `network_entry.dart` | 不進 `==`、`hashCode`、`toString` 與匯出，比照 `sourceDio`；`copyWith(clearResponseImageBytes: true)` 可清除 |
| `kImageMaxBytes`（5 MB）、`kImageBudgetBytes`（50 MB）、`kImageSniffBytes`（18） | 新檔 `utils/image_bytes.dart` | 不從 barrel 匯出 |
| `kDioMarkerHeader = 'x-flutter-inspector-dio'`、值固定為 `'1'` | 新檔 `interceptors/http_client_capture_common.dart` | 若 5(c) 採 T12b，改成逐請求 token 加上 live registry（§9.2） |
| `_installed`（`_InspectorHttpOverrides?`） | io 側模組層級變數 | once-per-isolate guard，也是「標記安全嗎」的判斷依據 |

### 2.2 方向比較

**D-1 圖片位元組放哪裡**

| 方案 | 結論 | 理由 |
|:---|:---:|:---|
| A：entry 欄位，在 `NetworkInspector.add` 掃描並淘汰 | 採用 | 單一資料來源；entry 被 ring buffer 擠掉時位元組一起釋放 |
| B：旁邊另開 `Expando`／`Map` | 否決 | 需要 `RingBuffer` 的淘汰回呼，等於修改核心結構 |
| C：在擷取層計預算，滿了就不存新的 | 否決 | 與「丟最舊」相反 |

**D-2 Response 代理**

| 方案 | 結論 | 理由 |
|:---|:---:|:---|
| A：`extends Stream` 只覆寫 `listen`；先 `_inner.listen`，再用同步 `StreamController` 轉出 | 採用 | 看得到 cancel（1-5）；第二次 listen 同步拋錯；pause、resume、cancel 原路傳回；原型已驗證 |
| B：直接回傳 `_inner.listen(...)` 的 subscription | 否決 | `Stream.first`／`firstWhere` 會 `listen(null)` 再呼叫 `onData`，tap 被換掉，cancel 也看不到 |
| C：`_inner.transform(...)` | 否決 | `StreamTransformer.fromHandlers` 沒有 cancel 回呼 |

**D-3 interceptor 何時加標記**（plan-verifier 第 1 輪修正說法）

條件：`_installed != null && identical(HttpOverrides.current, _installed) && sourceDio?.httpClientAdapter is IOHttpClientAdapter`。

**這個條件只能證明 `sourceDio` 會經過代理，無法證明實際送出請求的 Dio 會經過。** 因此保證是：**只有「傳了 `sourceDio`、而且它就是實際送出請求的 Dio」時，Dio 請求才不會重複記錄，標記也不會外洩。** 已知的例外：

- (a) `dio.clone(httpClientAdapter: X)` 沿用 interceptor（§1 第 13 點），或 `sourceDio` 傳錯。
- (b) `IOHttpClientAdapter(createHttpClient: () => 既有 client)` 回傳的是 inspector 建構前就建好的 client，或 adapter 子類覆寫了 `fetch`。
- (c) 其他 interceptor 在 R12 移除之前，就從 `requestOptions.headers` 看到標記（§1 第 14 點）。

(a)(b) 只能靠文件說明；(c) 待使用者裁決（§9.2）。

| 方案 | 結論 | 理由 |
|:---|:---:|:---|
| A：上述三項條件 | 採用 | 宿主之後蓋掉 global、在 `runZoned` 的 zone 內、未傳 `sourceDio`、非 IO adapter，都不加標記，寧可重複也不外洩 |
| B：只看「曾經安裝過」 | 否決 | 宿主之後設了 global（3-4）時，標記就會送到伺服器 |

**D-4 SDK 介面演進（R6）**：**待使用者裁決**，選項與建議見 §9.1。計畫預設採**選項 1**（只寫明確轉發），因為這是先前的指示；T7、T8、T9 各註明採用選項 2 時要加的那一行。

### 2.3 規格 §9 交辦事項的決定

| # | 事項 | 決定 |
|:---:|:---|:---|
| 1 | 標記 | `x-flutter-inspector-dio: 1`，非 null 字串（Dio 會略過 null 值，`io_adapter.dart:105`）；5(c) 若採 T12b，改成逐請求 token |
| 2 | 簽章與中立檔 | 3 個函式：`installHttpClientCapture(FlutterInspector)`、`shouldTagDioRequest(Dio?)`、`@visibleForTesting resetHttpClientCaptureForTesting()`；typedef 與常數放在 `http_client_capture_common.dart`；測試以 typedef 指派加上 `runtimeType` 相等雙重把關 |
| 3 | guard | io 側 `_installed`；install 以 `Zone.root.run(() => HttpOverrides.current)` 取上一層；後來開啟的 inspector 不安裝，`kDebugMode` 下 `debugPrint`；reset 只清 guard |
| 4 | 時間定義 | `timestamp` 為 open 系列方法被呼叫的時刻；completed 發生在 done、error、cancel、`detachSocket`、回應交出前的 `abort`（交出後 dart:io 的 abort 是 no-op，由回應本身完成 entry），或 `close`／`done` future 失敗時；`duration` 量到該時刻 |
| 5 | 消費者取消 | 不算失敗：completed、`error == null`，body 為已收到的部分 |
| 6 | 文字與二進位 | `_Tee` 先取 18 bytes 判斷：圖片上限 5 MB，其他 40 KB；之後只計數。**先轉出、再 tee**，tee 包在 `_guard` 內。唯一例外是 `addStream`：用 `stream.map` 在同一個同步回呼裡先 tee、再回傳原物件，不延遲也不改物件（plan-verifier 第 2 輪，§1 第 15 點）。UTF-8 前綴最多退 3 bytes 對齊；失敗就是 `[binary N bytes]...[truncated]` |
| 7 | 欄位命名 | `responseImageBytes`；`copyWith(clearResponseImageBytes: true)` |
| 8 | 預覽 UI | `Response Body` 正上方獨立的 `DetailSection('Response Preview')`；`ResizeImage(width: 1024)`、高度 200、`dispose` 時 `evict()`；`errorBuilder` 顯示佔位文字。沒有位元組時沿用摘要文字當佔位 |
| 9 | 列表來源標示 | subtitle 在 `origin != dio` 時加 `origin.name`；Console 不標 |
| 10 | R12 | `onResponse`／`onError` 一開始就移除標記；更早移除的方案見 §9.2 |
| 11 | R6 | 待裁決（§9.1） |
| 12 | 測試策略 | 本機 `HttpServer`，以 host `HttpOverrides` 注入 fake；`test()` only；還原 global 並 reset guard |
| 13 | example | 1-6 的真實流量由 T18a（scratchpad 原生 probe，必做）驗證；example 示範頁為 T18b（選做，需先與使用者確認） |
| 14 | 版號 | T19：3.0.0，同步 4 處加上 `README.zh-TW.md` |

---

## 3. 檔案異動清單

| 檔案 | 動作 | 預估 | 任務 |
|:---|:---:|:---:|:---:|
| `lib/src/models/network_origin.dart` | 改 | +3 | T1 |
| `lib/src/models/network_entry.dart` | 改 | +16 | T2 |
| `lib/src/utils/image_bytes.dart` | 新 | +50 | T3 |
| `lib/src/inspectors/network_inspector.dart` | 改 | +25 | T4 |
| `lib/src/interceptors/http_client_capture.dart` | 新 | +9 | T5 |
| `lib/src/interceptors/http_client_capture_common.dart` | 新 | +20（T12b 再 +18） | T5、T12b |
| `lib/src/interceptors/http_client_capture_web.dart` | 新 | +16 | T5 |
| `lib/src/interceptors/http_client_capture_io.dart` | 新 | ≈+430 | T5、T7–T10、T12b |
| `lib/src/core/flutter_inspector.dart` | 改 | +55（dartdoc 約 45）、:151 改 1 行 | T6 |
| `lib/src/interceptors/dio_interceptor.dart` | 改 | +22（T12b 再 +16） | T11、T12、T12b |
| `lib/src/ui/dashboard/tabs/network/network_detail_view.dart` | 改 | +40 | T14 |
| `lib/src/ui/dashboard/tabs/network_tab.dart` | 改 | +2 | T15 |
| `README.md`、`README.zh-TW.md` | 改 | 各 +55／−5 | T16、T19 |
| `docs/architecture/overview.md`、`docs/architecture/file-reference.md` | 改 | +4、+5 | T16 |
| `CLAUDE.md`（不變式 #4 清單） | 改 | +1 | T16，**需使用者明確同意** |
| `CHANGELOG.md`、`pubspec.yaml`、`lib/src/version.dart` | 改 | +35、1、1 | T19 |
| 新測試檔：`test/utils/image_bytes_test.dart`、`test/interceptors/http_client_capture_signature_test.dart`、`test/interceptors/http_client_capture_test.dart`、`test/core/flutter_inspector_capture_http_client_test.dart` | 新 | 合計 ≈+1000 | 各任務 |
| 既有測試檔：`network_entry_test`、`network_inspector_test`、`dio_interceptor_test`、`network_detail_view_test`、`network_tab_test`、`network_formatters_test`、`diagnostic_report_test` | 只新增 group，**不修改既有 test**（9-1） | 合計 ≈+480 | 各任務 |
| scratchpad `http_probe/`、`web_probe/` | 只在 scratchpad | 不入庫 | T17、T18a |
| `example/lib/demos/http_client_demo.dart`、`example/lib/main.dart`、`example/pubspec.yaml` | 新／改 | +40、+4、+1 | T18b（選做） |

`lib/flutter_inspector_kit.dart`（barrel）不改；`pubspec.yaml` 不新增依賴（`package:dio/io.dart` 屬既有 dio）。

---

## 4. 任務

> 每個任務的共同驗收：該任務的測試檔全綠；`rtk flutter analyze lib/ test/` 仍只有 7 個 info。
> 會改 `HttpOverrides` 的測試檔一律使用下列 fixture，並只用 `test()`：
>
> ```dart
> HttpOverrides? saved;
> setUp(() => saved = HttpOverrides.current);
> tearDown(() {
>   HttpOverrides.global = saved;
>   resetHttpClientCaptureForTesting();
> });
> ```

### T1 `[快/便宜]`：`NetworkOrigin.httpClient`（C1）與 8-1 回歸測試

- **寫入**：`lib/src/models/network_origin.dart`、`test/utils/network_formatters_test.dart`、`test/utils/diagnostic_report_test.dart`
- **相依**：無 ｜ **預估**：lib +3、test +45 ｜ **驗收**：C1、8-1（遮蔽、報告）
- [ ] **Red**：
  - `network_formatters_test.dart` 新 group `httpClient origin (8-1)`：對 `origin: NetworkOrigin.httpClient`、`requestHeaders: {'Authorization': 'Bearer secret'}` 的 entry 執行 `buildCurl`，結果含 `••••`、不含 `secret`。
  - `diagnostic_report_test.dart` 新 test：以既有 `_report(network: [...], errorsOnly: true)` 放一筆 `origin: httpClient`、`statusCode: 500`、`isComplete: true`、`timestamp: _minutesAgo(1)` 的 entry，報告含該 URL。
  - 執行後應因列舉值不存在而編譯失敗。
- [ ] **Green**：

```dart
  /// Captured by the `captureHttpClient` layer from `dart:io` `HttpClient`
  /// traffic (`Image.network`, `package:http`, SDKs, Dio without the
  /// inspector interceptor).
  httpClient,
```

- **驗證**：`rtk flutter test test/utils/network_formatters_test.dart test/utils/diagnostic_report_test.dart`

### T2 `[快/便宜]`：`NetworkEntry.responseImageBytes`

- **寫入**：`lib/src/models/network_entry.dart`、`test/models/network_entry_test.dart`
- **相依**：無 ｜ **預估**：lib +16、test +55 ｜ **驗收**：6-2（欄位不進 `==`／`hashCode`／`toString`）
- [ ] **Red**：新 group `responseImageBytes (transient)`：
  - 預設為 null。
  - 只差位元組的兩筆 entry 互相 `==`，`hashCode` 也相等。
  - `toString()` 不含位元組。
  - `copyWith(statusCode: 200)` 沿用同一個位元組物件（`identical`）。
  - `copyWith(clearResponseImageBytes: true)` 得到 null，且與原 entry `==`。
- [ ] **Green**：建構子加 `this.responseImageBytes,`；欄位：

```dart
  /// Raw bytes of an image response, kept only for the detail-view preview.
  ///
  /// Set when the body starts with a complete PNG/JPEG/GIF/WebP/BMP signature;
  /// [responseBody] then holds a summary such as
  /// `[image/png, 34.2 KB]...[truncated]`. Dropped above 5 MB, and from the
  /// oldest entries once all previews exceed 50 MB.
  ///
  /// Like [sourceDio], excluded from [operator ==], [hashCode], [toString] and
  /// every export: an entry is the same event with or without its preview.
  final Uint8List? responseImageBytes;
```

  `copyWith` 加兩個參數：

```dart
    Uint8List? responseImageBytes,
    bool clearResponseImageBytes = false,
  // ...
      responseImageBytes: clearResponseImageBytes
          ? null
          : responseImageBytes ?? this.responseImageBytes,
```

  不要另外 import `dart:typed_data`（§1 第 10 點）。
- **驗證**：`rtk flutter test test/models/network_entry_test.dart`

### T3 `[快/便宜]`：`image_bytes.dart`（signature 判斷與摘要）

- **寫入**：`lib/src/utils/image_bytes.dart`（新）、`test/utils/image_bytes_test.dart`（新）
- **相依**：無 ｜ **預估**：lib +50、test +80 ｜ **驗收**：6-1、6-7（判斷層）、6-8、6-2（摘要格式）
- [ ] **Red**：表格式測試：
  - PNG：完整 8 bytes 判為 `image/png`；`[137, 80, 78, 71]` 為 null（6-7）。
  - JPEG：`FF D8 FF` 判為 jpeg，`FF D8` 為 null。
  - GIF：`GIF87a`／`GIF89a` 判為 gif，`GIF8` 為 null。
  - WebP：`RIFF....WEBP` 判為 webp，`RIFF....WAVE` 與過短的 `RIFF` 皆為 null。
  - BMP：`BM` + 12 bytes + DIB 長度 40（little-endian）判為 bmp；`'BMW is a car'` 與不足 18 bytes 的 `BM...` 皆為 null。
  - SVG：`<svg ...>` 與 `<?xml ...` 為 null（6-8）。空陣列為 null。
  - `imageSummary('image/png', 35021) == '[image/png, 34.2 KB]$kTruncatedMarker'`。
- [ ] **Green**：

```dart
import '../models/network_entry.dart';
import 'network_formatters.dart';

/// Largest image whose bytes are kept for a preview.
const int kImageMaxBytes = 5 * 1024 * 1024;

/// Preview bytes kept across all network entries; the oldest lose theirs first.
const int kImageBudgetBytes = 50 * 1024 * 1024;

/// Bytes needed to recognise every supported signature (BMP's DIB size ends
/// at offset 18).
const int kImageSniffBytes = 18;

const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _jpeg = [0xFF, 0xD8, 0xFF];
const _gif87a = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61];
const _gif89a = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
const _riff = [0x52, 0x49, 0x46, 0x46];
const _webp = [0x57, 0x45, 0x42, 0x50];
const _bm = [0x42, 0x4D];
// BITMAPCOREHEADER, OS/2 v2 and BITMAPINFOHEADER through V5. Checking the
// header size keeps a text body that happens to start with "BM" out.
const _dibHeaderSizes = {12, 16, 40, 52, 56, 64, 108, 124};

/// MIME type of an image `Image.memory` can decode, judged only by the
/// leading signature of [bytes] (never by `Content-Type`); `null` otherwise,
/// SVG included.
String? imageMimeType(List<int> bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (at(0, _png)) return 'image/png';
  if (at(0, _jpeg)) return 'image/jpeg';
  if (at(0, _gif87a) || at(0, _gif89a)) return 'image/gif';
  if (at(0, _riff) && at(8, _webp)) return 'image/webp';
  if (at(0, _bm) && bytes.length >= kImageSniffBytes) {
    final dib = bytes[14] | bytes[15] << 8 | bytes[16] << 16 | bytes[17] << 24;
    if (_dibHeaderSizes.contains(dib)) return 'image/bmp';
  }
  return null;
}

/// Body text recorded for an image. The marker keeps Resend disabled and tags
/// the body as a summary, like `[binary N bytes]`.
String imageSummary(String mime, int totalBytes) =>
    '[$mime, ${formatBytes(totalBytes)}]$kTruncatedMarker';
```

- **驗證**：`rtk flutter test test/utils/image_bytes_test.dart`

### T4 `[標準]`：`NetworkInspector.add` 的 5 MB 與 50 MB 規則

- **寫入**：`lib/src/inspectors/network_inspector.dart`、`test/inspectors/network_inspector_test.dart`
- **相依**：T2、T3 ｜ **預估**：lib +25、test +85 ｜ **驗收**：6-4（入口層）、6-5、6-6
- [ ] **Red**：新 group `image bytes budget`。共用一個 `Uint8List(kImageMaxBytes)`，前 8 bytes 寫入 PNG signature；總量是加總長度，重複使用同一物件不會吃掉 50 MB 記憶體。**11 筆 entry 的 url 彼此不同**（`/img/$i`），避免 `replace` 以 `==` 撞到別筆。
  - `kImageMaxBytes + 1` bytes 存入後為 null，`responseBody` 不變；剛好 `kImageMaxBytes` 則保留。
  - `bufferCapacity: 20`、連續加 11 筆：前 10 筆全保留；第 11 筆加入後最舊那筆變成 null，其他保留，`entries.length == 11`（6-5）。
  - 6-6 不可重入斷言：

```dart
      var inMutate = false;
      var mutations = 0;
      late final NetworkInspector net;
      net = NetworkInspector(
        bufferCapacity: 20,
        onMutate: () {
          expect(inMutate, isFalse, reason: 'onMutate re-entered');
          inMutate = true;
          mutations++;
          net.entries; // reading inside onMutate is allowed
          inMutate = false;
        },
      );
```

    第 11 筆加入時 `mutations` 增加 2（add、replace 各一），`onAdd` 只被呼叫 1 次，最後一次 `onMutate` 讀到的總量 ≤ 50 MB。
    限制（plan-verifier 第 2 輪）：旗標只抓得到**本測試實際走過的路徑**上的巢狀 `onMutate`。是否有其他路徑在 `onMutate` 內寫 buffer，仍須 code review 確認；`_evictImageBytes` 只在 `_buffer` 寫入返回之後、`add` 回傳之前呼叫。
  - pending（無位元組）以 `replaces:` 換成帶位元組的 completed 時，仍在原位置。
- [ ] **Green**：

```dart
  NetworkEntry add(NetworkEntry entry, {NetworkEntry? replaces}) {
    final requestBody = NetworkEntry.truncateBody(entry.requestBody);
    final responseBody = NetworkEntry.truncateBody(entry.responseBody);
    final oversized = (entry.responseImageBytes?.length ?? 0) > kImageMaxBytes;

    if (requestBody != entry.requestBody ||
        responseBody != entry.responseBody ||
        oversized) {
      entry = entry.copyWith(
        requestBody: requestBody,
        responseBody: responseBody,
        clearResponseImageBytes: oversized,
      );
    }
    if (replaces == null || !_buffer.replace(replaces, entry)) {
      _buffer.add(entry);
    }
    // Runs after the write above has returned, never inside onMutate
    // (CLAUDE.md invariant #1).
    if (entry.responseImageBytes != null) _evictImageBytes();
    onAdd?.call(entry, _buffer.length);
    return entry;
  }

  /// Drops preview bytes from the oldest entries until all previews fit in
  /// [kImageBudgetBytes]. The stripped copy is `==` to the original, so
  /// [RingBuffer.replace] finds its slot and bookmarks still match.
  void _evictImageBytes() {
    final oldestFirst = _buffer.items.reversed; // items is a snapshot
    var total = 0;
    for (final e in oldestFirst) {
      total += e.responseImageBytes?.length ?? 0;
    }
    for (final e in oldestFirst) {
      if (total <= kImageBudgetBytes) return;
      final bytes = e.responseImageBytes;
      if (bytes == null) continue;
      _buffer.replace(e, e.copyWith(clearResponseImageBytes: true));
      total -= bytes.length;
    }
  }
```

- **驗證**：`rtk flutter test test/inspectors/network_inspector_test.dart`

### T5 `[標準]`：條件匯出骨架、install guard、標記判斷與簽章把關

- **寫入**（全為新檔）：`lib/src/interceptors/http_client_capture.dart`、`http_client_capture_common.dart`、`http_client_capture_web.dart`、`http_client_capture_io.dart`；`test/interceptors/http_client_capture_signature_test.dart`、`test/interceptors/http_client_capture_test.dart`
- **相依**：無 ｜ **預估**：lib +92、test +145 ｜ **驗收**：3-1（context 原樣傳入）、3-2、3-4、4-3、5-2、5-3、Q6 guard、D3（zone）
- [ ] **Red 1（簽章，5-3、5-2）**：`http_client_capture_signature_test.dart`

```dart
import 'dart:io' show HttpOverrides;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture_common.dart';
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture_io.dart'
    as io;
import 'package:flutter_inspector_kit/src/interceptors/http_client_capture_web.dart'
    as web;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('io and web expose the same signatures (invariant #4)', () {
    // Compile-time guard: a drifted signature fails to compile this file.
    const installs = <InstallHttpClientCapture>[
      io.installHttpClientCapture,
      web.installHttpClientCapture,
    ];
    const tags = <ShouldTagDioRequest>[
      io.shouldTagDioRequest,
      web.shouldTagDioRequest,
    ];
    const resets = <ResetHttpClientCapture>[
      io.resetHttpClientCaptureForTesting,
      web.resetHttpClientCaptureForTesting,
    ];
    expect([installs, tags, resets].map((l) => l.length), [2, 2, 2]);
    // Assignability is subtyping: one side gaining an optional parameter
    // still compiles above. Exact runtime types catch that too.
    expect(
      io.installHttpClientCapture.runtimeType,
      web.installHttpClientCapture.runtimeType,
    );
    expect(
      io.shouldTagDioRequest.runtimeType,
      web.shouldTagDioRequest.runtimeType,
    );
    expect(
      io.resetHttpClientCaptureForTesting.runtimeType,
      web.resetHttpClientCaptureForTesting.runtimeType,
    );
  });

  test('web stub does nothing and never tags (5-2)', () {
    final before = HttpOverrides.current;
    web.installHttpClientCapture(
      FlutterInspector(navigatorKey: GlobalKey<NavigatorState>()),
    );
    expect(identical(HttpOverrides.current, before), isTrue);
    expect(web.shouldTagDioRequest(Dio()), isFalse);
  });
}
```

- [ ] **Red 2（install，`http_client_capture_test.dart`，套 fixture）**：加入 test 專用的 `_HostOverrides extends HttpOverrides`：記錄 `createHttpClient` 收到的 `context` 與被呼叫次數，`findProxyFromEnvironment` 固定回傳 `'PROXY host:9'`。測試項目：
  - 3-1：裝 host 後再 install，`HttpClient(context: ctx)` 時 host 收到的 context 與 `ctx` `identical`，呼叫次數為 1。
  - 3-2：`HttpClient.findProxyFromEnvironment(Uri.parse('http://a.test'))` 等於 `'PROXY host:9'`。
  - 4-3／Q6：install 後 `current` 非 null 且不是 host；再 install 一次，`current` 不變（`identical`）。
  - 3-4：install 後設 `HttpOverrides.global = later`，`HttpClient()` 由 `later` 建立，不拋錯，`shouldTagDioRequest(Dio())` 為 false。
  - **D3（zone）**：在 zone 內 install，zone 外的 client 不可由 zone factory 建立：

```dart
    test('installs over the global slot, not a zone override (D3)', () {
      var zoneCalls = 0;
      HttpOverrides.runZoned(
        () => installHttpClientCapture(inspector),
        createHttpClient: (context) {
          zoneCalls++;
          throw StateError('zone factory reached outside its zone');
        },
      );
      HttpClient().close(force: true); // outside the zone
      expect(zoneCalls, 0);
    });
```

  - 標記判斷：未 install 時 false；install 後 `Dio()`（VM 預設 `IOHttpClientAdapter`）為 true；`null` 為 false；`Dio()..httpClientAdapter = _FakeAdapter()` 為 false（`_FakeAdapter implements HttpClientAdapter`）。
- [ ] **Green**：

```dart
// http_client_capture.dart
/// Platform-adaptive `dart:io` HttpClient capture.
///
/// Native platforms chain an `HttpOverrides` layer; web builds resolve to a
/// no-op stub so the package's web import graph stays free of `dart:io`.
library;

export 'http_client_capture_common.dart';
export 'http_client_capture_io.dart'
    if (dart.library.js_interop) 'http_client_capture_web.dart';
```

```dart
// http_client_capture_common.dart
import 'package:dio/dio.dart';

import '../core/flutter_inspector.dart';

/// Header the Dio interceptor adds so the HttpClient layer skips requests Dio
/// already records. The layer removes it before the headers are sent.
const String kDioMarkerHeader = 'x-flutter-inspector-dio';

/// Value of [kDioMarkerHeader]; Dio drops null header values.
const String kDioMarkerValue = '1';

// `_io` and `_web` must both match these (CLAUDE.md invariant #4);
// test/interceptors/http_client_capture_signature_test.dart checks both.
typedef InstallHttpClientCapture = void Function(FlutterInspector inspector);
typedef ShouldTagDioRequest = bool Function(Dio? dio);
typedef ResetHttpClientCapture = void Function();
```

```dart
// http_client_capture_web.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/flutter_inspector.dart';

/// Web has no `dart:io` HttpClient: the flag is accepted and ignored.
void installHttpClientCapture(FlutterInspector inspector) {}

/// Never tag on web: nothing would strip the marker before it is sent.
bool shouldTagDioRequest(Dio? dio) => false;

/// No state to reset on web.
@visibleForTesting
void resetHttpClientCaptureForTesting() {}
```

```dart
// http_client_capture_io.dart（T5 版本；T7 起擴充）
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../core/flutter_inspector.dart';

/// The overrides this isolate installed; also the once-per-isolate guard.
_InspectorHttpOverrides? _installed;

/// Chains an inspector layer onto the global `HttpOverrides` slot, once per
/// isolate.
///
/// Never restored or set to `null`: the slot is shared, so a later host
/// override simply replaces this layer and the host keeps working.
void installHttpClientCapture(FlutterInspector inspector) {
  if (_installed != null) {
    if (kDebugMode) {
      debugPrint(
        'flutter_inspector_kit: captureHttpClient is already active in this '
        'isolate; this inspector will not capture HttpClient traffic.',
      );
    }
    return;
  }
  // `current` is `zone value ?? global`; read the global slot itself so a
  // zone override is never promoted to apply outside its zone.
  final previous = Zone.root.run(() => HttpOverrides.current);
  final overrides = _InspectorHttpOverrides(previous);
  _installed = overrides;
  HttpOverrides.global = overrides;
}

/// Whether a request from [dio] will pass the layer that strips the marker:
/// this isolate's layer is the current one and [dio] uses
/// `IOHttpClientAdapter`. It proves this for [dio] only, not for whichever
/// Dio actually sends the request.
bool shouldTagDioRequest(Dio? dio) =>
    _installed != null &&
    identical(HttpOverrides.current, _installed) &&
    dio?.httpClientAdapter is IOHttpClientAdapter;

/// Forgets the install guard. Tests restore `HttpOverrides.global` themselves.
@visibleForTesting
void resetHttpClientCaptureForTesting() => _installed = null;

class _InspectorHttpOverrides extends HttpOverrides {
  _InspectorHttpOverrides(this._previous);

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _previous?.createHttpClient(context) ?? super.createHttpClient(context);

  // SDK reads this through HttpOverrides.current, so the host's proxy
  // settings would be lost without forwarding it.
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      _previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);
}
```

  T5 的 overrides 不持有 inspector（避免 `unused_field`），T7 才加。
- **驗證**：`rtk flutter test test/interceptors/http_client_capture_signature_test.dart test/interceptors/http_client_capture_test.dart`

### T6 `[標準]`：`FlutterInspector.captureHttpClient` 開關與 dartdoc

- **寫入**：`lib/src/core/flutter_inspector.dart`、`test/core/flutter_inspector_capture_http_client_test.dart`（新）
- **相依**：T5 ｜ **預估**：lib +55、test +55 ｜ **驗收**：4-1、4-2、3-4 的 dartdoc、Q6（inspector 層級）、R14 的文件部分
- [ ] **Red**（套 fixture）：
  - 4-1：不傳開關、或傳 `false` 時，建構前後 `identical(HttpOverrides.current, before)`。
  - `true` 時 `current` 改變而且非 null；`shouldTagDioRequest(Dio())` 為 true。
  - 4-2：`detach()` 前後 `current` `identical`。
  - Q6：第二個開關為 `true` 的 inspector 不會改變 `current`。
- [ ] **Green**：
  - import `'../interceptors/http_client_capture.dart'`；建構子加 `this.captureHttpClient = false,`；建構子本體**最後一行**加 `if (captureHttpClient) installHttpClientCapture(this);`。
  - `:151` 改成 `This package depends on no device-info plugin, and imports `dart:io` only behind conditional exports, so web builds stay free of it.`
  - dartdoc：

```dart
  /// Whether to record traffic sent through `dart:io` `HttpClient` —
  /// `Image.network`, `package:http`'s `IOClient`, third-party SDKs, and Dio
  /// instances without [FlutterInspectorDioInterceptor] — as
  /// [NetworkOrigin.httpClient] entries. Image responses keep their bytes
  /// (up to 5 MB each, 50 MB in total) for a preview in the detail view.
  ///
  /// Defaults to `false`. Does nothing on web. Native clients
  /// (`cupertino_http`, `cronet_http`, `native_dio_adapter`) are not captured.
  ///
  /// Notes:
  /// - Installed at construction by chaining onto the global `HttpOverrides`
  ///   slot, so the host's own overrides (SSL pinning, proxies) keep working.
  ///   It is never uninstalled: [detach] does not touch it, and the inspector
  ///   never restores `HttpOverrides.global` or sets it to `null`.
  /// - Construct the inspector at the top of `main()`, before any client is
  ///   created or any Dio instance sends its first request. Clients created
  ///   earlier — lazy statics such as `Image.network`'s shared client, a
  ///   `http.Client()` in a DI container, a Dio adapter's cached client — are
  ///   never captured.
  /// - If the host sets `HttpOverrides.global` *after* constructing the
  ///   inspector, that override replaces this layer and capture silently
  ///   stops (the host always wins — nothing breaks). Traffic inside
  ///   `HttpOverrides.runZoned` and in other isolates is not captured.
  /// - Enable this on a single, app-wide inspector: only the first enabled
  ///   inspector in an isolate installs the layer.
  /// - A Dio request is recorded once — by [FlutterInspectorDioInterceptor],
  ///   not again here — only when the interceptor was given `sourceDio` and
  ///   that Dio is the one actually sending the request. The interceptor
  ///   then adds a marker header that this layer removes before the headers
  ///   are sent. Without `sourceDio` no marker is added and the request is
  ///   recorded twice.
  /// - Keep the interceptor *last* in `dio.interceptors`: an interceptor
  ///   after it that signs all headers would sign the marker.
  /// - The marker reaches the server when a request bypasses this layer even
  ///   though `sourceDio` says it would not: a `dio.clone(httpClientAdapter:)`
  ///   that keeps the interceptor, a wrong `sourceDio`, an
  ///   `IOHttpClientAdapter(createHttpClient:)` returning a client created
  ///   before the inspector, or an adapter subclass overriding `fetch`.
  /// - Other interceptors' `onResponse` / `onError` still see the marker in
  ///   `requestOptions.headers`. Resending those options through another Dio
  ///   (retry, token refresh) can send the marker, or make this layer skip
  ///   the request silently. [依 §9.2 裁決改寫；採 T12b 時改為只剩
  ///   「連線前就失敗後的重送」]
  /// - A Dio request that fails before connecting (DNS, refused connection,
  ///   TLS handshake) is recorded twice.
  /// - Takes effect in every build mode, release included. Gate it with a
  ///   flavor flag or `bool.fromEnvironment`; `!kReleaseMode` is also true
  ///   under `flutter test`, so the layer would be installed in your tests.
  final bool captureHttpClient;
```

- **驗證**：`rtk flutter test test/core/flutter_inspector_capture_http_client_test.dart`

### T7 `[標準]`：`_CapturingHttpClient`（同名轉發與連線失敗紀錄）

- **寫入**：`lib/src/interceptors/http_client_capture_io.dart`、`test/interceptors/http_client_capture_test.dart`
- **相依**：T1、T5 ｜ **預估**：lib +110、test +150 ｜ **驗收**：7-1、3-3（client setter）、3-1（包成代理）、1-4（連線失敗）
- [ ] **Red**：
  - 7-1：test 專用 `_FakeClient implements HttpClient`，以 `noSuchMethod` 記錄 `Invocation`，open 系列回傳 `opener()`；經 `_HostOverrides(fake)` 注入。表格式呼叫 14 個 open 方法，每次 `fake.calls.single.memberName` 都是**同名** Symbol。
  - 3-3：setter-only 的 6 個 callback 傳到 fake 時與傳入值 `identical`；`addCredentials`、`addProxyCredentials`、`close(force: true)` 的參數原樣轉出。另外不注入 host，對真實 client 測 5 組 getter／setter 往返。
  - 1-4：連到已關閉的 port，`getUrl` 拋原本的 `SocketException`（stack 不變）；inspector 有 1 筆 completed entry：`origin == httpClient`、`error != null`、`errorType == null`、`sourceDio == null`。
- [ ] **Green**：`_InspectorHttpOverrides` 加 `final FlutterInspector _inspector`，`createHttpClient` 改成回傳 `_CapturingHttpClient(<原本的值>, _inspector)`。新增：

```dart
/// Forwards every member to the same-named member of [_inner]; only the
/// requests it opens are wrapped (spec 7-1).
class _CapturingHttpClient implements HttpClient {
  _CapturingHttpClient(this._inner, this._inspector);

  final HttpClient _inner;
  final FlutterInspector _inspector;

  Future<HttpClientRequest> _capture(
    Future<HttpClientRequest> opening,
    String method,
    String url,
  ) async {
    final start = DateTime.now(); // runs before the first await
    final HttpClientRequest request;
    try {
      request = await opening;
    } on Object catch (error, stackTrace) {
      _guard(
        _inspector,
        () => _inspector.logNetwork(
          NetworkEntry(
            method: method,
            url: url,
            origin: NetworkOrigin.httpClient,
            timestamp: start,
            duration: DateTime.now().difference(start),
            error: error.toString(),
            errorStackTrace: stackTrace.toString(),
            isComplete: true,
          ),
        ),
      );
      rethrow;
    }
    return request; // T8: _CapturingRequest(request, _inspector, start)
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _capture(_inner.openUrl(method, url), method, '$url');

  // Without a request there is no scheme to read; a scheme-relative URL is
  // honest, a guessed one is not.
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _capture(
    _inner.open(method, host, port, path),
    method,
    '//$host:$port$path',
  );

  // ...其餘 12 個比照辦理，見下方清單
}

/// Runs capture bookkeeping; its own failures become a warning log and never
/// reach the host's request or response (spec 7-6).
void _guard(FlutterInspector inspector, void Function() body) {
  try {
    body();
  } on Object catch (e, st) {
    try {
      inspector.log(
        'HttpClient capture internal error: $e',
        level: LogLevel.warning,
        stackTrace: st.toString(),
      );
    } on Object catch (_) {}
  }
}
```

  **成員清單（逐一明確轉發）**：
  - getter／setter：`idleTimeout`、`connectionTimeout`、`maxConnectionsPerHost`、`autoUncompress`、`userAgent`
  - 只有 setter：`authenticate`、`connectionFactory`、`findProxy`、`authenticateProxy`、`badCertificateCallback`、`keyLog`
  - 方法：`addCredentials`、`addProxyCredentials`、`close({bool force = false})`
  - open 系列：`getUrl`、`postUrl`、`putUrl`、`deleteUrl`、`patchUrl`、`headUrl` 用固定 method 與 `'$url'`；`get`、`post`、`put`、`delete`、`patch`、`head` 用 `'//$host:$port$path'`

  若 §9.1 裁決採選項 2，類別尾端加 `@override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);`（T8、T9 同）。
- **驗證**：`rtk flutter test test/interceptors/http_client_capture_test.dart`

### T8 `[標準]`：`_CapturingRequest`（header 定案、標記移除、pending、write-through、close／done／abort）

- **寫入**：`lib/src/interceptors/http_client_capture_io.dart`、`test/interceptors/http_client_capture_test.dart`
- **相依**：T7 ｜ **預估**：lib +135、test +240 ｜ **驗收**：7-2、7-4、7-5、1-2（pending 出現的時機）、2-2（代理層級）、7-6、1-4（`abort`）、R6 漏轉發把關
- [ ] **Red**：測試檔加入 `_TestServer`（`HttpServer.bind(InternetAddress.loopbackIPv4, 0)`，記錄每次收到的 `HttpHeaders`）；先建 `/text` 與 `/slow` 兩個路由，後者會等測試放行才回應。
  - 1-2：`final req = await HttpClient().getUrl(url)` 之後 0 筆；呼叫 `req.close()` 後同步出現 1 筆 pending。
  - 7-5／2-2：`openUrl('POST')` → `req.headers.set(kDioMarkerHeader, 'x')` → `addStream(Stream.value([1, 2, 3]))` → `close()`。server 收到的 headers 沒有標記，inspector 0 筆。標記值一律用字面值，不依賴 `kDioMarkerValue`，因此 T12b 改成 token 時這裡不受影響（plan-verifier 第 2 輪）。
  - 7-2：經 `_FakeRequest` 注入。`add(chunk)` 回來時 fake 已收到同一個 chunk，順序一致；`flush()`、`addError(e)` 都轉給 fake；`write('é')` 時 fake 收到 `write('é')`；`writeAll(['a', 'b'], ',')`、`writeln('c')`、`writeCharCode(0x41)` 分別讓 fake 收到 `write('a,b')`、`write('c\n')`、`write('A')`。
  - 7-4：真 server 時 `identical(await req.close(), await req.done)`，entry 只有 1 筆。
  - **close 與 done 是不同物件時**（R2-2）：`_FakeRequest` 的 `close()` 回傳以 201 回應完成的 future，`done` 回傳以 202 回應完成的另一個 future。先 `close()` 時，`(await req.close()).statusCode == 201`，之後 `await req.done` 與其 `identical`。這個斷言只依賴 `_tracked` memo，T8 自己就能通過（建議 1）。
  - **忽略 `close()` 回傳值、只 await `done`**：真 server `/slow`，呼叫 `req.close()` 不 await，接著 `req.abort()`；`await expectLater(req.done, throwsA(anything))`。測試不得出現 unhandled async error。
  - 1-4（abort，R2-3）：
    - `write('x')` 之後不 close、直接 `abort()`：entry 為 completed 且 `error != null`。
    - `close()` 之後、回應到達前 `abort()`：`done` 以原例外失敗，entry 只 completed 一次。
    - **回應到達後才 `abort()`**：entry **仍是 pending、`error == null`**（dart:io 此時 abort 是 no-op）。讀完 body 後帶 `statusCode` 的完成斷言需要 T9 的包裝，放在 T9。
  - **request 成員往返表格測試**（不論 §9.1 怎麼裁決都加，能抓漏轉發）：
    - 經真 server 的 proxy request 做 6 組 set／get 往返：`persistentConnection`、`followRedirects`、`maxRedirects`、`contentLength`、`bufferOutput`、`encoding`（`latin1`）。
    - 經 `_FakeRequest`：`headers`、`cookies`、`connectionInfo` 與 fake 的物件 `identical`；`method`、`uri` 相等。
  - 7-6：fake request 的 `headers` getter 拋錯時，`close()` 照常轉給 fake，inspector 多一筆 warning log，network 0 筆。
- [ ] **Green**：`_capture` 的 `return request;` 改成 `return _CapturingRequest(request, _inspector, start);`。新增：

```dart
/// Write-through request proxy. Decides "already recorded by Dio or not" once,
/// right before the first body write or close: that is when dart:io sends
/// the headers, and after Dio has set them (spec 7-5).
class _CapturingRequest implements HttpClientRequest {
  _CapturingRequest(this._inner, this._inspector, this._start);

  final HttpClientRequest _inner;
  final FlutterInspector _inspector;
  final DateTime _start;
  bool _finalized = false;
  bool _completed = false;
  bool _responded = false;
  NetworkEntry? _pending;
  Future<HttpClientResponse>? _tracked;

  void _finalize() {
    if (_finalized) return;
    _finalized = true;
    _guard(_inspector, () {
      final headers = _inner.headers;
      if (headers[kDioMarkerHeader] != null) {
        headers.removeAll(kDioMarkerHeader); // Dio's interceptor records it
        return;
      }
      _pending = _inspector.logNetwork(
        NetworkEntry(
          method: _inner.method,
          url: _inner.uri.toString(),
          requestHeaders: _headerMap(headers),
          origin: NetworkOrigin.httpClient,
          timestamp: _start,
        ),
      );
    });
  }

  /// Awaits the response once for both [close] and [done] (spec 7-4).
  /// Failures complete the entry and are rethrown unchanged.
  Future<HttpClientResponse> _track(Future<HttpClientResponse> response) async {
    final HttpClientResponse value;
    try {
      value = await response;
    } on Object catch (error, stackTrace) {
      _complete(error: error, stackTrace: stackTrace);
      rethrow;
    }
    _responded = true;
    return _wrap(value);
  }

  // One memo for both: dart:io's close() returns done (http_impl.dart:
  // 1536-1542), so a caller may ignore one and await the other.
  @override
  Future<HttpClientResponse> get done => _tracked ??= _track(_inner.done);

  @override
  Future<HttpClientResponse> close() {
    _finalize();
    final closing = _inner.close(); // always forwarded: this sends the request
    return _tracked ??= _track(closing);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _inner.abort(exception, stackTrace);
    // After the response is out, dart:io's abort is a no-op
    // (http_impl.dart:1702-1709) and the body completes the entry.
    if (!_responded) {
      _complete(error: exception ?? 'aborted', stackTrace: stackTrace);
    }
  }

  HttpClientResponse _wrap(HttpClientResponse response) => response; // T9

  void _complete({Object? error, StackTrace? stackTrace}) {
    final pending = _pending;
    if (pending == null || _completed) return;
    _completed = true;
    _guard(_inspector, () {
      _inspector.logNetwork(
        pending.copyWith(
          duration: DateTime.now().difference(_start),
          error: error?.toString(),
          errorStackTrace: stackTrace?.toString(),
          isComplete: true,
        ),
        replaces: pending,
      );
    });
  }

  @override
  void add(List<int> data) {
    _finalize();
    _inner.add(data);
  }

  // dart:io's own writeAll/writeln/writeCharCode are built on write, so one
  // write of the same text sends the same bytes; toString and the iterable
  // run exactly once.
  @override
  void write(Object? object) {
    final text = '$object';
    _finalize();
    _inner.write(text);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  // addError / addStream / flush：先 _finalize() 再轉同名方法
}

Map<String, dynamic> _headerMap(HttpHeaders headers) {
  final map = <String, dynamic>{};
  headers.forEach((name, values) => map[name] = values.join(','));
  return map;
}
```

  **其餘成員清單（逐一明確轉發）**：
  - getter／setter：`persistentConnection`、`followRedirects`、`maxRedirects`、`contentLength`、`bufferOutput`、`encoding`
  - getter：`method`、`uri`、`headers`、`cookies`、`connectionInfo`
  - 方法：`addError`、`addStream`、`flush` 先 `_finalize()` 再轉同名方法

  **memo 的兩個邊緣情況**（R2-2）：
  - verifier 範例寫的是 `_tracked ??= _track(_inner.close())`。若 `done` 先被讀過，`??=` 不會求值右邊，`_inner.close()` 就不會被呼叫，**請求根本不會送出**。所以這裡先無條件呼叫 `_inner.close()`，再做 memo。
  - 「先讀 `done` 再 `close()`」時，`close()` 回傳 `done` 的 memo，`_inner.close()` 回傳的 future 不另外追蹤。dart:io 兩者是同一物件，沒有差別。若宿主自訂的 client 讓兩者不同、而且 close 的那個失敗，該錯誤不會反映到 entry，也可能成為無人處理的錯誤。這是為了不讓同一個錯誤被追蹤兩次而接受的取捨，列於 §7 風險 12。
- **驗證**：`rtk flutter test test/interceptors/http_client_capture_test.dart`

### T9 `[標準]`：`_CapturingResponse`（只覆寫 `listen`）與完成時機

- **寫入**：`lib/src/interceptors/http_client_capture_io.dart`、`test/interceptors/http_client_capture_test.dart`
- **相依**：T8 ｜ **預估**：lib +80、test +140 ｜ **驗收**：7-3、1-5、1-4（串流錯誤；回應到達後的 abort）、3-3（response 成員 `identical`）、1-2（completed 原地取代）
- [ ] **Red**：注入 `_FakeRequest` 與 `_FakeResponse`（`extends Stream<List<int>> implements HttpClientResponse`，由 `StreamController` 驅動，記錄 `onListen`、`onPause`、`onResume`、`onCancel`）。
  - 7-3：`close()` 回來後 fake 的 `onListen` 未觸發；listen 後收到的 chunk 與送出的 `identical`、順序一致；pause、resume、cancel 都傳到 fake；error 與 stack 相同；第二次 `listen` 同步拋 `StateError`。
  - 3-3：`headers`、`certificate`、`connectionInfo`、`redirects`、`cookies` 與 fake 的回傳 `identical`；其餘 getter 相等。
  - 1-5：消費者 `cancel()` 後 entry 為 completed 且 `error == null`；`detachSocket()` 也會讓 entry completed。
  - 1-4（串流錯誤）：entry 為 completed，`error != null`，`statusCode` 為 fake 的值。
  - 1-2：真 server 時，消費完 body 後仍只有 1 筆，`isComplete == true`。
  - 完成只記一次：done 之後 `onCancel` 仍會觸發，entry 不會被覆寫成 partial。
  - **回應到達後才 abort**（R2-3 後半）：真 server，`await req.close()` 後 `abort()`；讀完 body 後 entry 為 completed，`statusCode == 200`、`error == null`。
  - `redirect('GET', uri, true)` 以相同參數轉給 fake（plan-verifier 第 2 輪，補 R6 覆蓋）。
- [ ] **Green**：`_wrap` 改成下面這樣。`_tracked` 讓 `_track` 最多執行一次，`_wrap` 也只會被呼叫一次，所以不需要 `_response ??=` memo（plan-verifier 第 2 輪）：

```dart
  HttpClientResponse _wrap(HttpClientResponse response) =>
      _pending == null ? response : _CapturingResponse(response, this);
```

  `_complete` 加參數 `_CapturingResponse? response` 與 `bool whole = false`，並帶入 `statusCode: response?.statusCode`、`responseHeaders: response == null ? null : _headerMap(response.headers)`（body 在 T10）。新增：

```dart
/// Subscribes to [_inner] only when the consumer listens and forwards every
/// chunk, pause, resume, cancel and error unchanged (spec 7-3). All other
/// Stream methods are built on [listen].
class _CapturingResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _CapturingResponse(this._inner, this._owner);

  final HttpClientResponse _inner;
  final _CapturingRequest _owner;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<List<int>>(sync: true);
    // Subscribed before returning: a second listen throws StateError right
    // here, as the original does.
    final source = _inner.listen(
      controller.add, // T10: forward first, then tee
      onError: (Object error, StackTrace stackTrace) {
        _owner._complete(response: this, error: error, stackTrace: stackTrace);
        controller.addError(error, stackTrace);
      },
      onDone: () {
        _owner._complete(response: this, whole: true);
        controller.close();
      },
    );
    controller
      ..onPause = source.pause
      ..onResume = source.resume
      // Also fires after done; _complete runs once, so done wins.
      ..onCancel = () {
        _owner._complete(response: this);
        return source.cancel();
      };
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<Socket> detachSocket() {
    _owner._complete(response: this);
    return _inner.detachSocket();
  }

  // 其餘成員：同名轉發
}
```

  **其餘成員清單**：`statusCode`、`reasonPhrase`、`contentLength`、`compressionState`、`persistentConnection`、`isRedirect`、`redirects`、`headers`、`cookies`、`certificate`、`connectionInfo`、`redirect([method, url, followLoops])`。`redirect()` 回傳的新 response 不包裝。
- **驗證**：`rtk flutter test test/interceptors/http_client_capture_test.dart`

### T10 `[標準]`：body 擷取（`_Tee`、文字／二進位／圖片）

- **寫入**：`lib/src/interceptors/http_client_capture_io.dart`、`test/interceptors/http_client_capture_test.dart`
- **相依**：T9、T2、T3 ｜ **預估**：lib +70、test +140 ｜ **驗收**：1-1、1-3、6-1（HttpClient 層）、6-4（HttpClient 層）、7-6（tee 例外）、R2-1
- [ ] **Red**：`_TestServer` 擴充路由：`/echo`（POST 原樣回傳）、`/png`（`_Data.png1x1`）、`/big`（PNG signature 加 6 MB 的 0）、`/binary`（`[0xFF, 0xFE, 0x00, 0x80]`）、`/long`（60 KB 的 `a`）、`/utf8`（`'é' * 30000`）。

```dart
class _Data {
  // Valid 1x1 PNG (70 bytes; IHDR/IDAT/IEND CRCs verified).
  static final png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );
}
```

  - 1-1：GET `/text` 與 POST `/echo`（`write('{"a":1}')`）各 1 筆，檢查 `method`、`url`、`statusCode`、`duration`、request／response headers、`origin`；POST 的 `requestBody == '{"a":1}'`。
  - 1-3：`/long` 的 `responseBody` 長度為 `kNetworkBodyMaxLength + kTruncatedMarker.length`；`/utf8` 不會被誤判成 binary；`/binary` 為 `[binary 4 bytes]$kTruncatedMarker`。
  - 6-1：`/png` 的 `responseBody == '[image/png, 70 B]$kTruncatedMarker'`，位元組與 `png1x1` 相等。
  - 6-4：`/big` 的 `responseBody == '[image/png, 6.0 MB]$kTruncatedMarker'`，`responseImageBytes == null`。
  - **以 `Stream<Uint8List>` 呼叫 `addStream`**（R2-1）：`req.addStream(Stream<Uint8List>.fromIterable([Uint8List.fromList(utf8.encode('{"a":1}'))]))` 不拋錯；`/echo` 收到相同 bytes；entry 的 `requestBody == '{"a":1}'`。另外用 `_FakeRequest` 驗證 fake 收到的 chunk 與送出的 `identical`。
- [ ] **Green**：

```dart
/// Keeps a bounded prefix of a byte stream and counts the rest (spec Q3).
/// The cap is picked once the signature is visible: [kImageMaxBytes] for
/// images, [_kTextCopyBytes] otherwise.
class _Tee {
  final BytesBuilder _copy = BytesBuilder();
  int total = 0;
  int? _cap;

  void add(List<int> chunk) {
    total += chunk.length;
    final cap = _cap;
    if (cap != null && _copy.length >= cap) return;
    _copy.add(chunk);
    if (cap == null && _copy.length >= kImageSniffBytes) {
      _cap = imageMimeType(_copy.toBytes()) != null
          ? kImageMaxBytes
          : _kTextCopyBytes;
    }
  }

  Uint8List takeBytes() => _copy.takeBytes();
}

/// At most 4 UTF-8 bytes per code point, so a copy cut at this size decodes
/// to more than kNetworkBodyMaxLength UTF-16 units and NetworkInspector.add
/// appends the marker itself.
const int _kTextCopyBytes = 4 * kNetworkBodyMaxLength;

({String? text, Uint8List? image}) _describe(_Tee tee, {required bool whole}) {
  if (tee.total == 0) return (text: null, image: null);
  final head = tee.takeBytes();
  final complete = whole && head.length == tee.total;
  final mime = imageMimeType(head);
  if (mime != null) {
    return (text: imageSummary(mime, tee.total), image: complete ? head : null);
  }
  return (
    text: _decodeUtf8(head, exact: complete) ??
        '[binary ${tee.total} bytes]$kTruncatedMarker',
    image: null,
  );
}

/// A cut prefix may end inside a character: drop up to 3 trailing bytes
/// before calling it binary.
String? _decodeUtf8(Uint8List bytes, {required bool exact}) {
  final maxDrop = exact ? 0 : 3;
  for (var drop = 0; drop <= maxDrop && drop <= bytes.length; drop++) {
    try {
      return utf8.decode(Uint8List.sublistView(bytes, 0, bytes.length - drop));
    } on FormatException {
      continue;
    }
  }
  return null;
}
```

  接線一律**先轉出、再 tee**，而且 tee 包在 `_guard` 內：
  - `_CapturingRequest` 加 `final _Tee _body = _Tee();`。`add`：`_inner.add(data);` 之後 `_guard(_inspector, () => _body.add(data));`。`write`：`_inner.write(text);` 之後 `_guard(_inspector, () => _body.add(encoding.encode(text)));`。
  - `addStream` 用 `map`（plan-verifier 第 2 輪）。Dio 傳進來的是執行期 `Stream<Uint8List>`，`transform` 會拋 TypeError（§1 第 15 點）。`map` 在同一個同步回呼裡先 tee、再回傳原物件，不延遲也不改物件；tee 包在 `_guard` 內，失敗也不影響轉出：

```dart
  @override
  Future addStream(Stream<List<int>> stream) {
    _finalize();
    // Not transform(): Dio passes a runtime Stream<Uint8List>, and a
    // StreamTransformer<List<int>, List<int>> fails its covariant check.
    return _inner.addStream(
      stream.map((chunk) {
        _guard(_inspector, () => _body.add(chunk));
        return chunk;
      }),
    );
  }
```

  - `_CapturingResponse` 加 `final _Tee _body = _Tee();`，`listen` 的 onData 改成：

```dart
      (chunk) {
        controller.add(chunk);
        _guard(_owner._inspector, () => _body.add(chunk));
      },
```

  - `_complete` 加入：

```dart
      final body = response == null ? null : _describe(response._body, whole: whole);
      // ...copyWith 內：
          requestBody: _describe(_body, whole: true).text,
          responseBody: body?.text,
          responseImageBytes: body?.image,
```

  import：`dart:convert`、`dart:typed_data`、`../utils/image_bytes.dart`。若 analyze 對 `BytesBuilder` 報 deprecated 或 ambiguous，改成 `import 'dart:io' hide BytesBuilder;`。
  已知界線：消費者 cancel 或串流錯誤時，body 是已收到的部分，不另加 marker。
- **驗證**：`rtk flutter test test/interceptors/http_client_capture_test.dart`

### T11 `[快/便宜]`：Dio interceptor 的 `Uint8List` 圖片摘要與位元組

- **寫入**：`lib/src/interceptors/dio_interceptor.dart`、`test/interceptors/dio_interceptor_test.dart`
- **相依**：T2、T3 ｜ **預估**：lib +12、test +70 ｜ **驗收**：6-1（Dio 層）、6-2（Dio 層）、6-7（既有測試不修改）
- [ ] **Red**：新 group `Uint8List image summary (US-6)`，**不動既有群組**：
  - `Response<Uint8List>(data: png1x1)` 經 `onResponse`：`responseBody == '[image/png, 70 B]$kTruncatedMarker'`，`identical(entry.responseImageBytes, data)`。
  - 經 `onError` 時結果相同。
  - request 的 PNG body 記成 image 摘要。
  - `[137, 80, 78, 71]` 的 `responseImageBytes == null`。
- [ ] **Green**：

```dart
    if (data is Uint8List) {
      final mime = imageMimeType(data);
      return mime == null
          ? '[binary ${data.length} bytes]$kTruncatedMarker'
          : imageSummary(mime, data.length);
    }
```

  `onResponse` 加 `responseImageBytes: _imageBytes(response.data),`；`onError` 加 `responseImageBytes: _imageBytes(err.response?.data),`。helper：

```dart
  // The 5 MB cap and the 50 MB budget live in NetworkInspector.add.
  static Uint8List? _imageBytes(Object? data) =>
      data is Uint8List && imageMimeType(data) != null ? data : null;
```

- **驗證**：`rtk flutter test test/interceptors/dio_interceptor_test.dart`

### T12 `[標準]`：Dio interceptor 的標記注入、紀錄剔除與 R12

- **寫入**：`lib/src/interceptors/dio_interceptor.dart`、`test/interceptors/dio_interceptor_test.dart`
- **相依**：T5、T11（同檔，序列） ｜ **預估**：lib +10、test +80 ｜ **驗收**：2-3、2-4、2-5、R12
- [ ] **Red**：新 group `HttpClient-layer marker (US-2)`，套 fixture：
  - 2-3：install 後 `dio = Dio()`，interceptor 帶 `sourceDio: dio`。`onRequest` 後 `options.headers[kDioMarkerHeader]` 為 `isNotNull`（不比對 `kDioMarkerValue`，T12b 改成 token 時不必修改這個測試；plan-verifier 第 2 輪），但 pending 的 `requestHeaders`，以及 `buildCurl`、`buildPlainText`、`buildReplayRequest(...).headers`、`buildAgentPrompt` 的輸出都沒有。`onResponse` 後 `options.headers` 已不含標記，completed 的 `requestHeaders` 也沒有。
  - 2-4：未安裝時，`options.headers` 內容不變，且 `identical(entry.requestHeaders, options.headers)`。
  - 2-5：已安裝但沒傳 `sourceDio`，或 adapter 為 `_FakeAdapter` 時，不加標記。
- [ ] **Green**：`onRequest` 建立 entry 之前：

```dart
      final tagged = shouldTagDioRequest(sourceDio);
      if (tagged) options.headers[kDioMarkerHeader] = kDioMarkerValue;
      final entry = NetworkEntry(
        // ...
        // The marker is ours: record a copy without it. Untagged requests keep
        // the live map, as before.
        requestHeaders: tagged
            ? (Map.of(options.headers)..remove(kDioMarkerHeader))
            : options.headers,
```

  `onResponse`、`onError` 的 `try` 第一行：`<requestOptions>.headers.remove(kDioMarkerHeader);`。
- **驗證**：`rtk flutter test test/interceptors/dio_interceptor_test.dart`

### T12b `[標準]`（**待使用者裁決 5(c)，建議採用**）：代理在 header 定案時從 live `RequestOptions.headers` 拿掉標記

- **寫入**：`http_client_capture_common.dart`、`http_client_capture_io.dart`、`dio_interceptor.dart`、`test/interceptors/http_client_capture_test.dart`、`test/interceptors/dio_interceptor_test.dart`
- **相依**：T10、T12 ｜ **預估**：lib +34、test +140 ｜ **驗收**：R14 (c)、registry 不留孤兒、(a)(b) 外洩偵測
- [ ] **Red**（`http_client_capture_test.dart`，真 Dio 加 `_TestServer`；server 加 `/401` 路由）：
  - (c) 移除時機：在 inspector 之前插入一個 interceptor，記錄自己在 `onResponse` 看到的 `requestOptions.headers`；斷言其中**不含**標記。
  - token refresh：Dio A（掛 inspector，IO）打 `/401`；排在 inspector 之前的 interceptor 在 `onError` 用 Dio B（無 inspector，IO）重送 `err.requestOptions`。Dio B 的請求以 `origin == httpClient` **被記錄**，server 兩次都沒收到標記。
  - **registry 不留孤兒**：依序跑完下列 5 種情境後，每一種都斷言 `liveDioMarkers.isEmpty`：
    - GET
    - POST
    - 401 後經 Dio B 重送
    - 連線失敗後經**同一個** Dio 重送（`dio.fetch(err.requestOptions)`）
    - 連線失敗後經 Dio B 重送：這是已知殘留，再斷言 Dio B 的請求**沒有**被記錄，測試名稱寫明 `known residual (plan §9.2)`
  - 相等才移除：讓 live map 已持有新 token2 時，代理以舊 token1 定案，live map 的 token2 不被移除。
  - (a) 偵測：`dio.clone(httpClientAdapter: _FakeAdapter())` 沿用 interceptor，`_FakeAdapter` 回傳 200；`onResponse` 後有一筆 warning log，內容含 `may have reached the server`。
- [ ] **Red**（`dio_interceptor_test.dart`，不起 server，套 fixture）：
  - `onRequest` 後 registry 有 1 筆，`target` 與 `options.headers` `identical`。
  - 同一個 `RequestOptions` 再走一次 `onRequest`：舊 token 已移除、只剩新 token。
  - `onResponse`／`onError` 後 registry 清空。
  - 未 install 時 `onRequest` 不碰 registry（2-4 仍成立）。
- [ ] **Green**：
  - common 檔：刪除 `kDioMarkerValue`（T8、T12 的測試都不引用它），新增：

```dart
/// Live `RequestOptions.headers` of tagged Dio requests, keyed by marker
/// token. The HttpClient layer takes the marker back out of the live map as
/// soon as the headers are sent, before any response or error interceptor
/// can see it and resend it elsewhere. Values are weak so an orphaned token
/// never keeps a request's headers alive.
final Map<String, WeakReference<Map<String, dynamic>>> liveDioMarkers = {};

var _markerSeq = 0;
const int _kMarkerPruneAt = 64;

/// Registers [headers] under a fresh token and returns the token.
String registerDioMarker(Map<String, dynamic> headers) {
  // Orphans only appear when Dio skips the interceptor's onResponse/onError
  // (an earlier interceptor resolving without following ones); prune lazily.
  if (liveDioMarkers.length >= _kMarkerPruneAt) {
    liveDioMarkers.removeWhere((_, ref) => ref.target == null);
  }
  final token = '${++_markerSeq}';
  liveDioMarkers[token] = WeakReference(headers);
  return token;
}
```

  - interceptor `onRequest`（取代 T12 的加標記那兩行）：

```dart
      // A resent RequestOptions still carries its previous token: retire it
      // first, tagged or not, so it can neither leak nor linger.
      final stale = options.headers.remove(kDioMarkerHeader);
      if (stale != null) liveDioMarkers.remove(stale);
      final tagged = shouldTagDioRequest(sourceDio);
      if (tagged) {
        options.headers[kDioMarkerHeader] = registerDioMarker(options.headers);
      }
```

  - interceptor `onResponse`（取代 T12 的 R12 那一行）：

```dart
      final token = response.requestOptions.headers.remove(kDioMarkerHeader);
      if (token != null) {
        liveDioMarkers.remove(token);
        // Headers were sent, yet the HttpClient layer never took the marker.
        _inspector.log(
          'The inspector marker header may have reached the server: this Dio '
          'request did not pass the captureHttpClient layer. Check that '
          'sourceDio is the Dio sending it (dio.clone keeps interceptors).',
          level: LogLevel.warning,
        );
      }
```

    `onError` 只移除 header 與 registry，不記 warning（連線前就失敗屬於 C2，不是外洩）。
  - 代理 `_finalize` 的標記分支：

```dart
      final token = headers[kDioMarkerHeader]?.first;
      if (token != null) {
        headers.removeAll(kDioMarkerHeader); // Dio's interceptor records it
        final live = liveDioMarkers.remove(token)?.target;
        // A resend may already carry a newer token; leave that one alone.
        if (live != null && live[kDioMarkerHeader] == token) {
          live.remove(kDioMarkerHeader);
        }
        return;
      }
```

  - 同步更新：規格 Q2 第 4 點（固定值改為逐請求 token）、T6 dartdoc 的 (c) bullet、T16 README。
  - **殘留**：連線前就失敗（標記還沒被代理拿掉）之後，經**另一個** Dio 重送。IO adapter 且未掛 inspector 時被靜默略過，非 IO adapter 時外洩。**連線失敗正是 retry 最主要的觸發情境**；常見的 retry 套件經同一個 Dio 重送（`dio.fetch`），會重新標記所以不受影響，只有換 Dio 重送時才中。
- **驗證**：`rtk flutter test test/interceptors/http_client_capture_test.dart test/interceptors/dio_interceptor_test.dart`

### T13 `[標準]`：端到端（真 Dio 與本機 `HttpServer`）

- **寫入**：`test/interceptors/http_client_capture_test.dart`（只加測試；紅燈時修正落在 io 或 interceptor 檔）
- **相依**：T6、T10、T12（若採用 T12b 也要先完成） ｜ **預估**：test +115 ｜ **驗收**：2-1（C2 版）、2-2、2-6、C2 行為鎖定、8-4、6-9
- [ ] 2-1／2-2：`FlutterInspector(captureHttpClient: true)`，Dio 掛 `FlutterInspectorDioInterceptor(inspector, sourceDio: dio)`。GET 與 POST（JSON body，走 `addStream`）各打一次，entries 各恰好 1 筆 `origin == dio`；server 收到的 headers 沒有標記。
- [ ] 2-6：沒掛 interceptor 的 `Dio()` 打 `/text`，得到 1 筆 `origin == httpClient`。
- [ ] C2 鎖定：有掛 interceptor 的 Dio 打已關閉的 port，entries 為 2 筆（一筆 `dio` 且 `errorType == connectionError`，一筆 `httpClient` 且有 `error`）。測試名稱寫明 `accepted per spec §8 C2`。
- [ ] 8-4：push `/a` 後送出請求，在 body 消費前再 push `/b`；pending 與 completed 的 `activeRoute` 都對應 `/a`。
- [ ] 6-9 抽查：`/png` entry 經過下列每一種匯出，都只含摘要，不含 `iVBOR`（base64 前綴）也不含 `[137, 80`：
  - `buildCurl`
  - `buildPlainText`（即分享走的文字，`network_detail_view.dart:313`）
  - `buildAgentPrompt`
  - `buildDiagnosticReport(logInspector: inspector.logInspector, networkEntries: inspector.networkEntries, navigatorEntries: inspector.navigatorEntries, databaseEntries: inspector.databaseEntries, now: DateTime.now())`
- **驗證**：`rtk flutter test test/interceptors/http_client_capture_test.dart` → `rtk flutter test` → `rtk flutter analyze lib/ test/`

### T14 `[標準]`：`NetworkDetailView` 圖片預覽

- **寫入**：`lib/src/ui/dashboard/tabs/network/network_detail_view.dart`、`test/ui/tabs/network_detail_view_test.dart`
- **相依**：T2 ｜ **預估**：lib +40、test +80 ｜ **驗收**：6-3、6-10、8-3
- [ ] **Red**：
  - 6-3：帶 `png1x1` 時有 1 個 `Image`，其 `image` 是 `ResizeImage` 且 `width == 1024`。帶「PNG signature 加垃圾」時，經 `tester.runAsync(...)` 解碼後 `pump()`，顯示 `Preview unavailable: the image could not be decoded`，`tester.takeException()` 為 null。
  - 沒有位元組時沒有 `Image`，Response Body 照常顯示摘要。
  - 6-10：卸載後，`imageCache.statusForKey(key).untracked` 為 true。
  - 8-3：`origin: httpClient` 且無 `sourceDio` 時，Resend 停用，tooltip 為 `Cannot resend: source Dio not available`。
- [ ] **Green**：在 Response Body 區塊正上方加：

```dart
          if (entry.responseImageBytes case final bytes?)
            DetailSection(
              title: 'Response Preview',
              child: _ImagePreview(bytes),
            ),
```

  檔尾新增：

```dart
/// Decodes at most [_decodeWidth] px wide and evicts on dispose, so a preview
/// never leaves a full-size bitmap in the host's ImageCache (spec 6-10).
class _ImagePreview extends StatefulWidget {
  const _ImagePreview(this.bytes);

  final Uint8List bytes;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  static const int _decodeWidth = 1024;
  static const double _height = 200;

  late final ImageProvider _image = ResizeImage(
    MemoryImage(widget.bytes),
    width: _decodeWidth,
  );

  @override
  void dispose() {
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: _image,
      height: _height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      errorBuilder: (_, _, _) =>
          const Text('Preview unavailable: the image could not be decoded'),
    );
  }
}
```

- **驗證**：`rtk flutter test test/ui/tabs/network_detail_view_test.dart`

### T15 `[快/便宜]`：Network 列表來源標示

- **寫入**：`lib/src/ui/dashboard/tabs/network_tab.dart`、`test/ui/tabs/network_tab_test.dart`
- **相依**：T1 ｜ **預估**：lib +2、test +45 ｜ **驗收**：8-2、8-1（慢請求）
- [ ] **Red**：`httpClient` entry 的 subtitle 含 `httpClient`；`dio` entry 不含 `dio`；`httpClient` 且耗時 3s 的 completed entry 顯示 `🐢 SLOW`。
- [ ] **Green**：import `'../../../models/network_origin.dart'`，`subtitleParts` 最後加 `if (entry.origin != NetworkOrigin.dio) entry.origin.name,`。
- **驗證**：`rtk flutter test test/ui/tabs/network_tab_test.dart`

### T16 `[快/便宜]`：文件

- **寫入**：`README.md`、`README.zh-TW.md`、`docs/architecture/overview.md`、`docs/architecture/file-reference.md`；`CLAUDE.md` 需使用者同意
- **相依**：T6、T13、T14（若採用 T12b 也要先完成） ｜ **預估**：README 各 +55／−5，其他文件 +10 ｜ **驗收**：3-4 的文件部分、R1–R5、R7、R14、C1、C2
- [ ] `README.md`：
  - 在 `##### Multiple Dio Instances` 之後新增 `#### Capture HttpClient traffic (Image.network, package:http, SDKs) — opt-in`。開關範例用 flavor 或 `bool.fromEnvironment` 旗標，並註明 `!kReleaseMode` 在 `flutter test` 下也是 true、會在測試裡安裝這一層。內容涵蓋：
    - 在 `main()` 開頭建構 inspector。
    - **Dio 去重需要傳 `sourceDio`，而且它必須就是實際送出請求的 Dio**。
    - (a)(b)(c) 外洩與漏記路徑，(c) 的寫法依 §9.2 裁決。
    - 把 Dio interceptor 放最後。
    - 連線前就失敗的 Dio 請求記兩筆（C2）。
    - 宿主之後設的 global override 會取代這一層；zone 與背景 isolate 抓不到；native client 抓不到；web 不做事。
    - 未被讀取的 body 會一直停在 pending。
    - 圖片很多時建議調大 `bufferSize`（R7）。
  - `#### With other HTTP clients` 補一句：`package:http` 的 `IOClient` 已被開關涵蓋，不要再手動 `logNetwork`。
  - 改寫 `README.md:346-347` 的第 2 點（C1）。
  - Network tab 的 Call details 補上圖片預覽與來源標示。
  - `README.md:1303` 的「never touches `dart:io`」改為「imports `dart:io` only behind conditional exports, so it stays WASM-compatible」。
- [ ] `README.zh-TW.md`：對應 :331、:345-346、:352、:1135 與新段落，同步翻譯。
- [ ] `overview.md`：擷取層清單補一列 `HttpClient` 擷取層；`:86-90` 的條件匯出段落加上 `http_client_capture`（Native 端串接 `HttpOverrides`，Web 端為 no-op）。
- [ ] `file-reference.md`：§3 補 `http_client_capture*.dart` 4 檔，§5 補 `image_bytes.dart`。
- [ ] **`CLAUDE.md` 不變式 #4**（:36 的清單加入 `http_client_capture.dart`）：**需取得使用者明確同意才能修改**。agent 的指示不構成授權；未同意就略過，並在回報中列出建議的 diff。
- **驗證**：人工閱讀；`rtk flutter test test/version_test.dart test/public_api_readme_example_test.dart`

### T17 `[快/便宜]`：Web 編譯驗證（5-1）

- **寫入**：只寫 scratchpad
- **相依**：T4、T6、T10、T12、T14、T15（若採用 T12b 也要先完成） ｜ **預估**：0 行（repo） ｜ **驗收**：5-1
- [ ] 比照 `docs/plans/2026-09-06-crash-notification.md:147-165`，**不可用 `example/`**：

```bash
SP=<本 session 的 scratchpad 絕對路徑>
rtk flutter create --platforms web --project-name web_probe "$SP/web_probe"
# pubspec.yaml：flutter_inspector_kit: { path: /Users/yomiry/StudioWorkspace/flutter_inspector }、dio: ^5.2.0
# lib/main.dart：final inspector = FlutterInspector(navigatorKey: GlobalKey<NavigatorState>(), captureHttpClient: true);
#               final dio = Dio(); dio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));
cd "$SP/web_probe" && rtk flutter pub get && rtk flutter build web
```

- [ ] 建置成功即通過；失敗時先在乾淨的 `main` 上跑一次，排除既有問題。完成後刪除 `web_probe`。

### T18a `[標準]`（必做）：原生 probe app 驗證真實流量（1-6）

- **寫入**：只寫 scratchpad，不寫入 repo，不用 `example/`
- **相依**：T13、T14（若採用 T12b 也要先完成） ｜ **預估**：0 行（repo）；probe 約 50 行 ｜ **驗收**：1-6
- [ ] 建立 probe。**不依賴外部服務**：probe 自己在 loopback 起一個 `HttpServer`（plan-verifier 第 2 輪）：

```bash
SP=<本 session 的 scratchpad 絕對路徑>
rtk flutter create --platforms android,ios,macos --project-name http_probe "$SP/http_probe"
# pubspec.yaml：flutter_inspector_kit: { path: /Users/yomiry/StudioWorkspace/flutter_inspector }、http: ^1.6.0
# macOS：macos/Runner/DebugProfile.entitlements 補 com.apple.security.network.client
#   （模板只有 network.server；profile 也使用 DebugProfile）
# Android：debug／profile 的 manifest 模板已有 INTERNET 權限；loopback 不受 cleartext 限制，
#   若仍被擋，只在 probe 的 manifest 加 android:usesCleartextTraffic="true"
```

- [ ] `lib/main.dart`（probe 專用）：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:http/http.dart' as http;

final navigatorKey = GlobalKey<NavigatorState>();
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before any client exists: Image.network's shared client is a lazy static.
  final inspector = FlutterInspector(
    navigatorKey: navigatorKey,
    captureHttpClient: true,
  );
  // HttpServer is not an HttpClient, so serving does not record anything.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    if (request.uri.path == '/image.png') {
      response
        ..headers.contentType = ContentType('image', 'png')
        ..add(_png);
    } else {
      response
        ..headers.contentType = ContentType.json
        ..write('{"ok":true}');
    }
    await response.close();
  });
  final base = 'http://127.0.0.1:${server.port}';
  runApp(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: Center(child: Image.network('$base/image.png', width: 64)),
      ),
    ),
  );
  await http.get(Uri.parse('$base/json'));
  await Future<void>.delayed(const Duration(seconds: 5));
  for (final e in inspector.networkEntries) {
    debugPrint(
      'PROBE ${e.origin.name} ${e.statusCode} complete=${e.isComplete} '
      '${e.url} body=${e.responseBody} image=${e.responseImageBytes?.length}',
    );
  }
}
```

- [ ] 執行：**debug 與 profile 各一次**。iOS 模擬器不支援 profile，請用 Android 模擬器（Apple Silicon 上選 arm64 image）跑兩種模式，或 iOS 模擬器跑 debug、`-d macos` 跑 profile。
  - `rtk flutter devices` 選裝置。
  - 背景執行 `rtk flutter run -d <id>`，讀到 `PROBE` 行後送出 `q` 結束；再用 `--profile` 重跑一次。
- [ ] **通過條件**（兩種模式都要）：
  - `PROBE httpClient 200 complete=true http://127.0.0.1:<port>/image.png body=[image/png, 70 B]...[truncated] image=70`
  - `PROBE httpClient 200 complete=true http://127.0.0.1:<port>/json body={"ok":true} image=null`
- [ ] 選做的人工確認：在 debug 模式開啟 dashboard，Network 分頁看得到兩筆 `httpClient`，並可預覽圖片。結束後刪除 `http_probe`。

### T18b `[快/便宜]`（選做）：example 示範頁

- **寫入**：`example/lib/demos/http_client_demo.dart`（新）、`example/lib/main.dart`、`example/pubspec.yaml`
- **相依**：T18a ｜ **預估**：+40、+4、+1
- [ ] **與使用者未提交的改動合併時需先確認**：`example/lib/main.dart` 目前有未 commit 的 `leak_tracker` import、`LeakTracking.start()`、`redactSensitiveData: false`。取得同意後只**追加** `captureHttpClient: true,` 與一個按鈕。`example/pubspec.yaml` 加 `http: ^1.6.0`（只限 example，不影響 lib 依賴）。

### T19 `[快/便宜]`：版號 3.0.0 與 CHANGELOG（最後執行）

- **寫入**：`pubspec.yaml`、`lib/src/version.dart`、`README.md`、`README.zh-TW.md`、`CHANGELOG.md`
- **相依**：T1–T17、**T18a**（T12b、T18b 若執行也要先完成） ｜ **預估**：4 處 1 行、zh-TW 1 行、CHANGELOG +35 ｜ **驗收**：C1 版號、9-1、9-2
- [ ] 版號 4 處加 zh-TW：`version: 3.0.0`、`packageVersion = '3.0.0'`、`README.md:65` 與 `README.zh-TW.md:65` 改成 `^3.0.0`。
- [ ] `CHANGELOG.md` 最上方：

```markdown
## 3.0.0

### Breaking changes
* **`NetworkOrigin` gains `httpClient`**: entries captured by the new `HttpClient` layer carry `NetworkOrigin.httpClient`. An exhaustive `switch (entry.origin)` without a wildcard no longer compiles — add one branch:
  ```dart
  final label = switch (entry.origin) {
    NetworkOrigin.dio => 'Dio',
    NetworkOrigin.webview => 'WebView',
    NetworkOrigin.httpClient => 'HttpClient', // new in 3.0.0
  };
  ```
  Nothing else changes. New `NetworkOrigin` values will only ship in major versions.

### Added
* **HttpClient traffic capture (opt-in)**: `captureHttpClient: true` records `Image.network`, `package:http`, third-party SDK and interceptor-less Dio traffic sent through `dart:io` `HttpClient` …（安裝時機、宿主 override 優先、Dio 去重需要正確的 `sourceDio`、連線前失敗記兩筆、所有 build mode 都生效、web 不做事）
* **Image response preview**: PNG / JPEG / GIF / WebP / BMP responses (Dio `Uint8List` and the HttpClient layer) show a preview in the Network detail view; up to 5 MB per image and 50 MB in total, oldest previews dropped first. Exports only contain the summary.
* **Network list shows the origin** of non-Dio entries (`httpClient`, `webview`).
* `NetworkEntry.responseImageBytes`.

### Changed
* **Dio image bodies are summarized**: a `Uint8List` request or response body that starts with a complete image signature is recorded as `[image/png, 34.2 KB]` instead of `[binary N bytes]`. Other binary bodies are unchanged.
* **Pending Dio entries snapshot their request headers when `captureHttpClient` is on**: for a request the interceptor marks, the pending entry keeps a copy of the headers taken in `onRequest` (without the marker), so headers added by interceptors that run later do not appear until the request completes. Without `captureHttpClient` nothing changes.
```

- [ ] 全套驗證：`rtk flutter test`（應為 **817 + 本次新增數**，既有測試一個都不改）→ `rtk flutter analyze lib/ test/`（仍 7 個 info）→ 對**本次改動的檔案**跑 `dart format --set-exit-if-changed <files>`（零差異）。使用者裁決 D5（2026-11-13）：main 上既有 7 個檔案的 format 漂移不在本 PR 修正，另開 chore。

---

## 5. 相依圖與並行

```text
Wave 1（並行）  ：T1  T2  T3  T5
Wave 2（並行）  ：T4[T2,T3]  T6[T5]  T7[T1,T5]  T11[T2,T3]  T14[T2]  T15[T1]
Wave 3（兩條鏈並行）：io 鏈 T8[T7] → T9 → T10   ｜   Dio 鏈 T12[T5,T11]
Wave 3.5（待裁決）：T12b[T10,T12]
Wave 4          ：T13[T6,T10,T12,(T12b)]
Wave 5（並行）  ：T16[T6,T13,T14]  T17[所有 lib 任務]  T18a[T13,T14]
Wave 6          ：T18b（選做）[T18a] → T19（最後）[T1–T17, T18a, (T12b), (T18b)]
```

| 任務 | 寫入路徑 | 可與誰並行 |
|:---:|:---|:---|
| T1 | `network_origin.dart`、`network_formatters_test`、`diagnostic_report_test` | T2、T3、T5 |
| T2 | `network_entry.dart`、`network_entry_test` | T1、T3、T5 |
| T3 | `utils/image_bytes.dart`、`image_bytes_test` | T1、T2、T5 |
| T5 | `interceptors/http_client_capture*.dart`、兩個新測試檔 | T1、T2、T3 |
| T4 | `network_inspector.dart`、`network_inspector_test` | T6、T7、T11、T14、T15 |
| T6 | `flutter_inspector.dart`、`test/core/flutter_inspector_capture_http_client_test.dart` | T4、T7、T11、T14、T15 |
| T7→T8→T9→T10 | `http_client_capture_io.dart`、`http_client_capture_test` | 彼此序列；可與 T4、T6、T11、T12、T14、T15 並行 |
| T11→T12 | `dio_interceptor.dart`、`dio_interceptor_test` | 彼此序列；可與 io 鏈、T14、T15 並行 |
| T12b | common、io、`dio_interceptor.dart`、`http_client_capture_test` | 不可並行（同時碰兩條鏈的檔案） |
| T14 | `network_detail_view.dart`、`network_detail_view_test` | Wave 2–3 其他任務 |
| T15 | `network_tab.dart`、`network_tab_test` | Wave 2–3 其他任務 |
| T16 | README×2、architecture×2（CLAUDE.md 需同意） | T17、T18a |
| T17、T18a | 只寫 scratchpad | 彼此並行，也可與 T16 並行 |
| T19 | 版號 4 處、zh-TW、CHANGELOG | 無（最後） |

**並行注意**：寫入路徑不重疊，不等於編譯圖不重疊。`flutter_inspector.dart` 與 io 檔互相 import，在同一個 working tree 同時跑 T6 與 io 鏈，任何一方改到一半都會讓另一方的測試編不過。Parallel Session 必須用各自的 git worktree。

---

## 6. 不變式檢核

| 不變式 | 本計畫的處理 | 把關 |
|:---|:---|:---|
| #1 `onMutate` 不重入 | 淘汰在 `_buffer.add`／`replace` 返回之後才執行；擷取層只透過 `logNetwork` 寫入 | T4 的不可重入旗標測試＋code review |
| #2 `mergedTimeline` 不做防禦性複製 | 不動 registry；Dio 的 `Uint8List` 以參照保存；淘汰是換掉 buffer 裡的物件 | 既有 `inspector_registry_merged_timeline_test` 全綠 |
| #3 緩衝型與即時查詢型分流 | HttpClient 層是緩衝型事件來源 | 設計 |
| #4 `_io`／`_web` 簽章一致 | typedef 指派加上 `runtimeType` 相等，再加 web build | T5＋T17 |
| #5 不引入新依賴 | `package:dio/io.dart` 屬既有 dio；`http` 只出現在 scratchpad probe 與選做的 example | `pubspec.yaml` diff 只有版號 |

---

## 7. 風險與不確定點

1. **標記外洩與漏記（最大風險；D-3）**：`shouldTagDioRequest` 只能證明 `sourceDio` 會經過代理。
   - (a) `dio.clone(httpClientAdapter: X)` 沿用 interceptor（`~/.pub-cache/hosted/pub.dev/dio-5.11.1/lib/src/dio_mixin.dart:851`），或 `sourceDio` 傳錯：標記送到伺服器。
   - (b) `IOHttpClientAdapter(createHttpClient: () => 既有 client)` 回傳 inspector 建構前就建好的 client，或 adapter 子類覆寫 `fetch`，或 Dio 在 inspector 建構前就送過請求、快取了原生 client（`io_adapter.dart:57`、:241）：同樣外洩。
   - (c) Dio 三段 interceptor 同序（`dio_mixin.dart:534`、:564、:577），其他 interceptor 的 `onResponse`／`onError` 在 R12 移除前就看得到標記。經別的 Dio 重送時，非 IO adapter 會外洩；IO adapter 且未掛 inspector 時被**靜默略過**。
   - (a)(b) 只能靠文件；T12b 能偵測並記一筆「可能外洩」的 warning。(c) **待使用者裁決**（§9.2）。採 T12b 後仍有殘留：「連線失敗後經另一個 Dio 重送」，而連線失敗正是 retry 最主要的觸發情境。
2. **SDK 介面演進（R6）**：**待使用者裁決**（§9.1）。介面依 SDK 3.13.1 撰寫（`_http/http.dart:1257`、:1758、:1915），套件下限 `sdk: ^3.10.1`（`pubspec.yaml:14`）的介面差異未驗證；SDK 若修改既有成員的簽章，兩個選項都會編譯失敗。
3. **未被消費的 body 會一直停在 pending**：例如 `HEAD`，或拿到 response 後不讀 body。規格 7-3 禁止 inspector 自行讀取，所以列表會一直顯示 `no response · Ns` 並被標成 SLOW（`network_entry.dart:129-130`）。寫進 README。
4. **淘汰靠 `==` 找位置**（`ring_buffer.dart:47-54`）：完全相同的兩筆 entry 可能換錯；一次淘汰 k 筆會 bump k+1 次 revision。
5. **測試環境**：任何會改 `HttpOverrides` 的測試檔只要出現 `testWidgets`，binding 就會裝上 `_MockHttpOverrides`。
6. **基準數字已過時**：CLAUDE.md 與規格 9-1 寫 606，實測為 817。
7. **`_Tee` 上限會多出一個 chunk**：超過 5 MB 的圖片在完成前最多暫存約 5 MB 加一個 chunk。
8. **預覽只限寬度**：極端直長圖不會縮小，6-10 只算部分達成。
9. **Dio 的可見輸出會變**：圖片 `Uint8List` 的摘要改變；開關打開時，tagged pending entry 的 header 變成快照（兩者都寫進 CHANGELOG 的 Changed）。
10. **6-3 的放置位置**：預覽放在緊鄰的 `Response Preview` 區塊；驗收者若不接受，需改 `_bodySection`（約 +6 行）。
11. **T18a 的平台限制**：iOS 模擬器不支援 profile；`flutter run` 是互動式程序，需要背景執行並讀取 log；macOS 要補 network client entitlement。
12. **「先讀 `done` 再 `close()`」**（R2-2 的取捨）：`_inner.close()` 回傳的 future 不另外追蹤。dart:io 兩者是同一物件，沒有影響；不照慣例的自訂 client 若讓 close 的 future 單獨失敗，錯誤不會進 entry，也可能變成無人處理的錯誤。
13. **abort 的 microtask 競態**：底層回應已完成、但 `_track` 的 continuation 還沒跑時呼叫 `abort()`，entry 會被記成 aborted，實際回應卻照常抵達。視窗只有一個 microtask，可忽略。
14. **`addStream` 是先 tee 再轉出**：為了避開 R2-1 的 covariance 問題改用 `map`。chunk 物件、順序、時序都不變，tee 包在 `_guard` 內。若一定要先轉出，可改成 `.cast<List<int>>().transform(...)`（原型已驗證），代價是每個 chunk 多一次 cast。

（原風險 4「`close()` 依賴 dart:io 契約」已由第 1 輪的 `_track` 改寫消除，第 2 輪的 memo 取捨見第 12 項。）

---

## 8. 執行方式

1. **Subagent-Driven（建議）**：先取得 §9 兩項裁決，再依 §5 的 wave 派發。Wave 1 派 4 個 `[快/便宜]` subagent 並行；io 鏈（T7→T10）由同一個 `[標準]` subagent 依序完成；T12b、T13、T18a、T19 由主進程執行並交 verifier 驗收。每個 subagent 回報都要附 Red 與 Green 輸出。
2. **Parallel Session**：最多 3 個 session，各自使用 git worktree。分工為 io 鏈（T5→T7→T10）、資料與 Dio（T2→T3→T4→T11→T12）、UI（T1→T14→T15）；T6、T12b、T13、T16–T19 在合併後由主 session 序列完成。
3. **主進程原地序列**：照編號執行，總改動約 lib 950 行、test 1500 行，不建議。

---

## 9. 使用者裁決（2026-11-13 已定案：R6 採選項 2、5(c) 採選項 B）

### 9.1 R6：SDK 介面演進

| 選項 | 作法 | 好處 | 代價 |
|:---|:---|:---|:---|
| 1（目前預設，依先前指示） | 只寫 dart:io 介面要求的明確轉發 | 漏寫轉發在編譯期就會被抓到 | Dart SDK 只要替 `HttpClient`／`HttpClientRequest`／`HttpClientResponse` **新增**成員，**所有使用者都會編譯失敗，包括開關是 false 的人**，必須趕發 patch；SDK 3.10 下限的介面差異未驗證 |
| 2 | 三個代理各加一行 `@override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);` | SDK 新增成員不會編譯失敗；只有開關為 true、而且呼叫到新成員時，才在執行期拋 `NoSuchMethodError` | 漏寫既有成員不再編譯報錯，只能靠測試抓。修訂後的覆蓋：T7 測 client 全部成員（14 個 open 方法、6 個 setter、5 組 getter／setter 往返、3 個方法）；T8 測 request 的 IOSink 方法、6 組 set／get 往返與 5 個 getter；T9 測 response 的 11 個 getter、`detachSocket` 與 `redirect()`。這些測試抓得到「漏寫或轉錯對象」，抓不到 SDK 新增、我們不知道的成員，那正是選項 2 要兜底的部分。另外違背「只寫介面要求的轉發」的指示 |

兩個選項共同的限制：SDK 若**修改既有成員的簽章**，明確宣告的 override 會不相容，兩者都會編譯失敗。

**建議：選項 2**。選項 1 的影響範圍是所有使用者，包括沒開開關的人；選項 2 只影響有 opt-in、而且呼叫到 SDK 新成員的人。T8 的 request 成員往返表格測試**不論裁決結果都會加入**（本身就能抓漏轉發）。

### 9.2 5(c)：其他 interceptor 在 response 階段看得到標記

| 選項 | 作法 | 成本 | 殘留問題 |
|:---|:---|:---|:---|
| A（目前預設） | 只在 inspector 的 `onResponse`／`onError` 移除（R12） | 0 行 | 經別的 Dio 重送（retry、token refresh 的常見作法）時，非 IO adapter 會外洩；IO adapter 且未掛 inspector 時**整筆請求靜默消失**，鏈推斷斷裂 |
| B（**建議**，即 T12b） | 每個請求用一個 token，interceptor 在 registry 登記 live `options.headers`（值為 `WeakReference`，達 64 筆時剪枝）；重新標記前先移除舊 token；代理在 header 定案時，只有當 live map 裡仍是同一個 token 才把它拿掉，所以任何 response 或 error interceptor 都看不到標記 | lib 約 +34、test 約 +140；模組層級多一個 registry；規格 Q2 第 4 點從「固定值」改成「逐請求 token」；附帶 (a)(b) 的「可能外洩」偵測 warning | 只剩「連線失敗後經**另一個** Dio 重送」。**連線失敗正是 retry 最主要的觸發情境**，但常見作法經同一個 Dio 重送，會重新標記，不受影響 |
| C | 改要求 inspector interceptor 排第一 | 0 行 | 與 R3 衝突（後面的簽章 interceptor 會簽到標記），pending 紀錄也會缺後面 interceptor 加的 auth header。不建議 |
| D | 用 (method, uri) 查表取代 header 標記 | 中 | 是 C2 已否決的啟發式，同一 URL 並發時會誤判。不建議 |

**建議：B**。它消除 token refresh 這類「回應後換 Dio 重送」造成的整筆消失與外洩，也讓 (a)(b) 外洩至少留下一筆 warning；殘留限縮在「連線失敗後換 Dio 重送」。若使用者認為 registry 的狀態成本不值得，A 的代價必須寫進 README 的誠實邊界。
