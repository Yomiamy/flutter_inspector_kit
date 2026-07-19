# WebView Inline Debugging 實作計畫（STAGE 0b）

> **For Claude:** REQUIRED: 使用 superpowers:subagent-driven-development（若有 subagent）或 superpowers:executing-plans 執行本計畫。步驟以 checkbox（`- [x]`）追蹤。
>
> **語言**：繁體中文；程式碼、識別字、指令保留原文。遵守 `flutter-styles.md`（const 正確性、尾隨逗號、named parameter 規範、widget 提取為獨立 class）。

- **日期**：2026-07-18
- **對應規格**：`docs/features/2026-07-18-webview-inline-debugging.md`（STAGE 0a 已確認）
- **需求主來源**：`docs/brainstorm/2026-07-17-features-brainstorm.md`「第三部分 · #10」
- **範圍**：Phase 1 + 2 + 3（完整 bridge + 雙套件接線文檔 + example 示範頁）。**不含** Phase 0（Eruda 食譜）。

---

## 0. 目標與架構一句話

**Goal**：把 WebView 內的 `console.*` / JS error / `fetch` / `XHR` 翻譯成既有 `LogEntry` / `NetworkEntry`，經既有 registry 進入同一條 timeline——**多一個事件來源，不是多一個系統**。

**Architecture**：三個零件、零新相依、schema 僅向後相容擴充（`NetworkEntry.origin`/`pageUrl`，見 §1.3 修訂）、`FlutterInspector` 建構子零改動。

```text
[WebView 頁內 JS]                         [Native / Dart]
  inspectorWebViewBridgeJs   ──postMessage(JSON String)──▶  JavaScriptChannel
   ├ hook console.*                                          / addJavaScriptHandler
   ├ hook window.onerror / unhandledrejection                       │
   ├ hook fetch / XMLHttpRequest                                    ▼
   └ JS 端截斷 + 統一 JSON envelope             WebViewBridgeAdapter.handleMessage(String)
                                                                    │ decode + route
                                              ┌─────────────────────┼─────────────────────┐
                                              ▼                                             ▼
                                   inspector.log(...)                        inspector.logNetwork(NetworkEntry(...))
                                              │                                             │
                                              ▼                                             ▼
                                   registry.log  (RingBuffer)                 registry.network (RingBuffer)
                                              └───────────────── 既有 mergedTimeline / Console tab /
                                                                 Network tab / #7 aggregation /
                                                                 #9 診斷報告 Timeline（全部免費受益）
```

**元件職責與邊界**：

| 元件 | 職責 | 明確不做 |
|---|---|---|
| `inspectorWebViewBridgeJs`（Dart 常數字串） | 頁內 hook、序列化、**JS 端截斷**、偵測傳輸層 post 給 native | 不持有狀態、不畫 UI（那是 Eruda 的地盤，本次不做） |
| `WebViewBridgeAdapter`（Dart） | decode JSON → 建 `LogEntry`/`NetworkEntry` → 呼叫既有 `inspector.log`/`inspector.logNetwork` | **不持有 buffer、不做 redaction、不做 UI、不引入第二份真相** |
| 既有 registry / UI / 報告 | 照舊 | 零改動 |

---

## 1. 讀 codebase 後的關鍵技術事實（設計地基）

實作前先內化這些逐檔核對過的事實，計畫的每個決策都由它們推導：

1. **事件入口是公開 API，adapter 鏡像 Dio interceptor 的關係**
   - Log：`FlutterInspector.log(String message, {LogLevel level = info, String? stackTrace, Map<String,dynamic>? data})`（`flutter_inspector.dart:196`）→ 內部 `_registry.log.add(LogEntry(...))`。**`log()` 不接受 `timestamp`**，一律 `DateTime.now()`。
   - Network：`FlutterInspector.logNetwork(NetworkEntry entry, {NetworkEntry? replaces})`（`flutter_inspector.dart:228`）→ `_registry.network.add(...)`；`NetworkEntry` **可帶 `timestamp`**。
   - `FlutterInspectorDioInterceptor(this._inspector, {this.sourceDio})`（`dio_interceptor.dart:12`）就是「外部物件持有 inspector 參照、用公開 API 推事件進去」的既有範式。**`WebViewBridgeAdapter` 完全鏡像此形狀**——`WebViewBridgeAdapter(this._inspector)`。
   - ⇒ **`FlutterInspector` 建構子與公開 API 完全不動**（比 `DiagnosticInfoSource`/`DatabaseBrowserSource` 還乾淨：那兩者需要新增可選建構參數，本 adapter 連建構參數都不用加，因為它是「事件來源」不是「被 inspector 拉取的資料源」）。這是 US-6 的最強保證。

2. **redaction 在「匯出/顯示邊界」，不在 ingest**（決定 US-3 的正確做法，見 §5）
   - `redaction.dart` 只有 `redactHeaders(Map)` + `kRedactedValue = '••••'` + `kSensitiveHeaderKeys`。**沒有 body redaction 函式**。
   - Dio interceptor（`dio_interceptor.dart`）建 `NetworkEntry` 時存的是**原始** headers/body，**完全不 redact**。
   - redaction 只發生在匯出/分享/顯示路徑，且都吃 `redactSensitiveData` 旗標：`buildCurl(redact:)`、`buildPlainText(redact:)`（`network_formatters.dart`）、`diagnostic_report.dart`（對 headers data 呼叫 `redactHeaders`）、`network_detail_view.dart` 的 copy/share action。
   - **on-screen detail view 的 header 表格是原始未遮罩的**（`network_detail_view.dart:66` `KeyValueTable(data: entry.requestHeaders)`）——native 就這行為。
   - ⇒ WebView `NetworkEntry` 走**同一個 buffer、同一組 formatter**，redaction 對它**自動生效且與 native 逐字節一致、且尊重 `redactSensitiveData` opt-out**。adapter **不該**在 ingest 時 redact（會與 native 分歧、且忽略 opt-out）。

3. **schema 對應**（逐欄確認；`LogEntry` 零變更，`NetworkEntry` 後經修訂擴充——見本節末修訂條目）
   - `LogEntry`：`message`/`level`(`LogLevel`)/`stackTrace`(`String?`)/`data`(`Map?`)/`timestamp`。provenance → `data: {'origin':'webview','pageUrl':...}`。
   - `LogLevel` enum：`verbose, debug, info, warning, error`（`log_level.dart`）。
   - `NetworkEntry`：`method`/`url`/`statusCode`(`int?`)/`duration`(`Duration?`)/`requestHeaders`/`requestBody`/`responseHeaders`/`responseBody`/`error`(`String?`)/`errorType`(`DioExceptionType?`)/`errorStackTrace`/`isComplete`/`isReplay`/`sourceDio`(`WeakReference<Dio>?`)。WebView 填 `errorType: null`、`sourceDio: null`。
   - **NetworkEntry 沒有 `data` 欄位**，故 network 事件**不帶** origin 標記——US-2 驗收未要求 network provenance，且 `sourceDio==null` 已足以在 UI 做 presentation 判斷。**不新增欄位**（YAGNI + 零 schema）。
   - **（2026-07-18 使用者修訂，取代上一條）**：network provenance 升級為第一級欄位——`NetworkEntry.origin`（`NetworkOrigin.dio | .webview`，預設 `dio`）與 `pageUrl`（`String?`）。理由：`sourceDio` 是 `WeakReference`，Dio 被 GC 後 native 與 WebView 請求無法區分，顯式欄位修掉此歧義。JS envelope 的 `t:"net"` 增送 `page`（`location.href`）；`NetworkDetailView` General 區顯示 Origin / Page URL；example 的 `loadHtmlString` 帶 `baseUrl` 使 pageUrl 有真實值。預設 `dio` 保證 Dio interceptor / Replay 零改動。規格決策紀錄 #6 同步。

4. **截斷雙保險**
   - `NetworkInspector.add` 會把 request/response body 再截到 `kNetworkBodyMaxLength = 10*1024`（`network_entry.dart:10`）。
   - **但 log 訊息在 Dart 端無任何截斷上限**——所以 JS 端截斷是 console 訊息唯一的源頭護欄（US-4）。

5. **CRLF / malformed-URL 已在 formatter 邊界加固**（#9 / PR #87）
   - `buildLogOneLiner` 用 `replaceAll(RegExp(r'\r\n?|\n'), ' ')` 壓平訊息（`log_formatters.dart:22`）。
   - `buildNetworkOneLiner` 對 malformed URL 於首個 `?`/`#` 截斷、避免 query secret 外洩（`network_formatters.dart:85`）。
   - 這兩個 formatter 是**型別無關**（吃 `LogEntry`/`NetworkEntry`，不管來源）。⇒ WebView 事件流經 timeline 自動獲得此加固，**adapter 不需預先清洗**（存原始，邊界清洗，與全套件哲學一致）。US-4/風險④ 只需補一個「WebView 來源」的確認測試。

6. **public API 出口**：`lib/flutter_inspector_kit.dart` barrel，新符號在此 export。

7. **test 結構鏡像 lib**：`test/webview/` 尚不存在，需新建。既有 `test/interceptors/dio_interceptor_test.dart` 是 adapter 測試的最佳範本。

8. **example 慣例**：`demos/network_demo.dart` 是「一個 class 持有 inspector、內部建 client + 掛 interceptor」的範本；`main.dart` 以 `late final XxxDemo` 初始化並綁按鈕。webview 套件加在 `example/pubspec.yaml`（**不污染 `lib/` 相依**，US-6）。

---

## 2. JS bridge 訊息協定（統一 JSON schema）

adapter 與 JS 之間的唯一契約。**先凍結此協定，Chunk 1（JS）與 Chunk 2（adapter log）即可平行開發。**

### 2.1 Envelope

每則訊息是一個 JSON 物件字串，經 `postMessage` 送出。頂層 `t` 決定路由：

```jsonc
// t === "log"：console.* / window.onerror / unhandledrejection 皆走此型
{
  "t": "log",
  "method": "error",              // 原始 console 方法名：log|info|warn|error|debug；onerror/rejection 送 "error"
  "message": "Uncaught TypeError…", // 已由 JS 把多個 args 序列化並 join(' ')
  "stack": "at foo (app.js:10)",  // 可選；onerror/rejection/console.error 帶
  "page": "https://m.example.com/pay", // 可選；location.href，作 provenance
  "truncated": false              // 可選；message 是否被 JS 截斷
}

// t === "net"：fetch / XMLHttpRequest 皆走此型
{
  "t": "net",
  "method": "POST",
  "url": "https://m.example.com/api/pay",
  "status": 502,                  // 可選；傳輸層失敗時 absent/null
  "durationMs": 1234,             // 可選
  "reqHeaders": { "Content-Type": "application/json" }, // 可選；原始（不在 JS 端 redact）
  "reqBody": "{\"amount\":100}",  // 可選；JS 端截斷
  "resHeaders": { "Content-Type": "application/json" }, // 可選
  "resBody": "{\"ok\":false}",    // 可選；JS 端截斷
  "error": "NetworkError: Failed to fetch", // 可選；傳輸失敗時帶
  "truncated": true,              // 可選；任一 body 被 JS 截斷
  "ts": 1752800000000             // 可選；request 開始的 epoch ms（對齊 native 的「timestamp = 起始時間」語義）
}
```

**設計取捨（好品味）**：`window.onerror` 與 `unhandledrejection` **不另立訊息型別**——它們就是「一筆帶 stack 的 `console.error`」，統一為 `t:"log", method:"error"`。fetch 與 XHR 同理統一為 `t:"net"`。型別只有兩種，adapter 的 switch 只有兩個 case，消滅特殊情況。

### 2.2 JS 端 hook 實作要點

| Hook | 要點 |
|---|---|
| `console.log/info/warn/error/debug` | 逐一包裝：**先呼叫原方法**（不吞頁面自己的 log），再 `post`。args 以 `a => typeof a === 'object' ? safeStringify(a) : String(a)` 序列化後 `join(' ')`。`safeStringify` 用 try/catch 防循環參照（iOS 遞迴 logging bug 的教訓）。 |
| `window.onerror` | chain 既有 handler（先存 `var prev = window.onerror`，post 後 `if (prev) return prev.apply(this, arguments)`），`message` 取第 1 參數，`stack` 取第 5 參數（error 物件）的 `.stack`。 |
| `unhandledrejection` | `window.addEventListener('unhandledrejection', e => post({t:'log',method:'error',message:String(e.reason),stack:e.reason && e.reason.stack}))`。 |
| `fetch` | 包裝 `window.fetch`：記 `start = Date.now()`，`await` 原 fetch，`res.clone().text()` 取 body（**必 clone**，否則吃掉頁面的 body stream），post `t:"net"`；`.catch` 分支 post 帶 `error`、無 `status`。 |
| `XMLHttpRequest` | 包裝 `open`（記 method/url）與 `send`（記 start、掛 `loadend` 收 `status`/`responseText`/`getAllResponseHeaders()`）。 |

**傳輸層偵測（單一 JS payload 支援雙套件的關鍵）**：

```js
function post(msg) {
  var s = JSON.stringify(msg);
  // webview_flutter：JavaScriptChannel 注入 window.<name>.postMessage
  if (window.FlutterInspectorBridge && window.FlutterInspectorBridge.postMessage) {
    window.FlutterInspectorBridge.postMessage(s);
  // flutter_inappwebview：callHandler
  } else if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
    window.flutter_inappwebview.callHandler('FlutterInspectorBridge', s);
  }
}
```

⇒ **一份 JS payload 兩套件通用**；兩邊最終都把一個 **String** 交給 `adapter.handleMessage(String)`。channel 名以常數 `kWebViewBridgeChannelName = 'FlutterInspectorBridge'` 對齊，JS 與 host 引用同一個名字。

### 2.3 JS 端截斷（US-4，上限為具名常數）

```js
var MAX_CHARS = 32768; // 對齊 brainstorm 的 32KB；具名常數，非魔術數字
function truncate(s) {
  if (typeof s !== 'string' || s.length <= MAX_CHARS) return { v: s, cut: false };
  return { v: s.slice(0, MAX_CHARS) + '…[truncated]', cut: true };
}
```

- body 與 message 皆過 `truncate`，被截斷時 envelope 帶 `truncated: true`。
- **上限在源頭**（與 `RingBuffer` 同哲學），非 Dart 端事後補救。
- 註：Dart 端 `NetworkInspector.add` 之後還會把 body 再截到 `kNetworkBodyMaxLength`(10KB)；32KB 是 bridge 吞吐護欄，10KB 是最終儲存上限，兩者並存不衝突。console 訊息 Dart 端無上限，故 32KB 截斷是其唯一護欄。

---

## 3. adapter 的 Dart 設計

### 3.1 進入點 API 形狀

```dart
// lib/src/webview/webview_bridge_adapter.dart
import 'dart:convert';

import '../core/flutter_inspector.dart';
import '../models/log_level.dart';
import '../models/network_entry.dart';
import '../models/network_origin.dart';

/// 把 decode 後的 WebView bridge 訊息翻成既有 [LogEntry] / [NetworkEntry]，
/// 交給既有 registry。翻譯器不是系統：不持有 buffer、不做 redaction、不做 UI。
///
/// 用法比照 [FlutterInspectorDioInterceptor]：host 建立一個 adapter、持有
/// inspector 參照，從自己的 JavaScriptChannel / addJavaScriptHandler 把原始
/// 訊息字串轉交 [handleMessage]。
class WebViewBridgeAdapter {
  WebViewBridgeAdapter(this._inspector);

  final FlutterInspector _inspector;

  /// 餵入一則原始 bridge 訊息（host 的 channel 交來的 JSON String）。
  ///
  /// **永不 throw**：malformed / 未知型別一律靜默丟棄——敵意頁面不得
  /// 透過畸形訊息炸掉 host 的 channel callback（US-5 優雅降級）。
  void handleMessage(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return; // malformed JSON — graceful drop
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['t']) {
      case 'log':
        _handleLog(decoded);
      case 'net':
        _handleNet(decoded);
      default:
        return; // 未知型別忽略
    }
  }

  void _handleLog(Map<String, dynamic> msg) {
    _inspector.log(
      msg['message']?.toString() ?? '',
      level: _levelFor(msg['method']?.toString()),
      stackTrace: msg['stack']?.toString(),
      data: {
        'origin': 'webview',
        if (msg['page'] != null) 'pageUrl': msg['page'],
      },
    );
  }

  void _handleNet(Map<String, dynamic> msg) {
    _inspector.logNetwork(
      NetworkEntry(
        method: msg['method']?.toString() ?? 'GET',
        url: msg['url']?.toString() ?? '',
        statusCode: _asInt(msg['status']),
        duration: _asDuration(msg['durationMs']),
        requestHeaders: _asHeaders(msg['reqHeaders']),
        requestBody: msg['reqBody']?.toString(),
        responseHeaders: _asHeaders(msg['resHeaders']),
        responseBody: msg['resBody']?.toString(),
        error: msg['error']?.toString(),
        // errorType / sourceDio 刻意留 null：這不是 Dio 請求。
        // Replay 因 sourceDio == null 正確地不可用（沿用既有 null 檢查）。
        isComplete: true,
        origin: NetworkOrigin.webview,
        pageUrl: msg['page']?.toString(),
        timestamp: _tsOf(msg['ts']),
      ),
    );
  }

  /// console method → LogLevel。未知/缺省 → info（安全的通用級）。
  static LogLevel _levelFor(String? method) {
    switch (method) {
      case 'error':
        return LogLevel.error;
      case 'warn':
        return LogLevel.warning;
      case 'debug':
        return LogLevel.debug;
      case 'info':
      case 'log':
      default:
        return LogLevel.info;
    }
  }

  static int? _asInt(Object? v) => v is num ? v.toInt() : null;

  static Duration? _asDuration(Object? v) =>
      v is num ? Duration(milliseconds: v.toInt()) : null;

  static DateTime? _tsOf(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  static Map<String, dynamic>? _asHeaders(Object? v) {
    if (v is! Map) return null;
    return v.map((key, value) => MapEntry(key.toString(), value));
  }
}
```

### 3.2 console method → LogLevel 對應表

| console / event | envelope `method` | `LogLevel` |
|---|---|---|
| `console.error` / `window.onerror` / `unhandledrejection` | `error` | `error` |
| `console.warn` | `warn` | `warning` |
| `console.debug` | `debug` | `debug` |
| `console.info` | `info` | `info` |
| `console.log`（通用） | `log` | `info` |
| 未知 / 缺省 | — | `info` |

（`LogLevel.verbose` 不對應任何 console 方法——JS 無 verbose 概念，不硬湊。）

### 3.3 provenance 與 timestamp

- **Log provenance**：`data: {'origin':'webview','pageUrl': page}`（US-1）。UI 是否據此加小圖示是 presentation 層的可選判斷，資料層無感。
- **Log timestamp**：走公開 `inspector.log()`，一律 `DateTime.now()`（receipt-time）。log 事件近乎瞬時，bridge 延遲 <1ms（同機時鐘），可接受。
- **Network timestamp**：`NetworkEntry` 可帶 `timestamp`，用 JS 送的 `ts`（request 起始）以對齊 native 的「timestamp = 起始時間」語義；缺省 → `null` → `NetworkEntry` 內部 fallback `DateTime.now()`。
- **不 reach into internals**：adapter 只用公開 `inspector.log` / `inspector.logNetwork`，不碰 `registry`（test-only）。

### 3.4 redaction 接線點 —— 決策見 §5（結論：無 ingest 接線點，靠共用邊界繼承）

---

## 4. 逐檔異動清單

`FlutterInspector`（`lib/src/core/flutter_inspector.dart`）**不在清單內——零改動**（§1.1）。

### 新增（4 檔）

| 檔案 | 性質 | 內容 |
|---|---|---|
| `lib/src/webview/webview_bridge_js.dart` | 新增 | `kWebViewBridgeChannelName` 常數、`inspectorWebViewBridgeJs`（JS payload raw string）、JS 端截斷上限（在 JS 字串內為具名 `MAX_CHARS`） |
| `lib/src/webview/webview_bridge_adapter.dart` | 新增 | `WebViewBridgeAdapter`（§3） |
| `test/webview/webview_bridge_adapter_test.dart` | 新增 | adapter 全部單元測試（§6） |
| `example/lib/demos/webview_demo.dart` | 新增 | Phase 3 示範頁（對齊 `network_demo.dart`） |

### 修改（4 檔）

| 檔案 | 性質 | 內容 |
|---|---|---|
| `lib/flutter_inspector_kit.dart` | export 增列 | export `webview/webview_bridge_adapter.dart` 與 `webview/webview_bridge_js.dart` |
| `README.md` | 新增章節 | webview_flutter / flutter_inappwebview 雙段接線 + 注入時機誠實說明 + iframe/SW 註記 + redaction 說明 |
| `example/pubspec.yaml` | 相依增列 | 加 `webview_flutter`（示範用；**僅 example**） |
| `example/lib/main.dart` | 接線 | `late final WebViewDemo`、初始化、加一顆按鈕開示範頁 |

---

## 5. redaction 決策（US-3）——關鍵設計判斷

規格 US-3 字面寫「headers/body 在**成為 NetworkEntry 前**必經 redaction 管線」。但逐檔核對後（§1.2）發現 codebase 的 redaction **在匯出/顯示邊界**，native `NetworkEntry` 存的是原始資料。兩種落地方式：

**方案 A（字面 ingest-redact）**：adapter 建 `NetworkEntry` 前呼叫 `redactHeaders`。
- 🔴 **與 native 分歧**：native 的 on-screen detail view 顯示原始 header，WebView 卻顯示遮罩——違反 US-3 驗收的「遮罩行為與 native 一致」。
- 🔴 **忽略 opt-out**：ingest 時遮罩是**永久**的，`redactSensitiveData=false` 也拆不開——違反風險②的「不得繞過 opt-out 行為」。
- 🔴 **重複邏輯**：redaction 邏輯出現在第二個地點，且 body redaction 函式**根本不存在**（§1.2），得為 WebView 新造，波及 native。

**方案 B（共用邊界繼承）✅ 採用**：adapter 建**原始** `NetworkEntry`（與 native 逐欄一致），redaction 由**同一組匯出/顯示 formatter**（已吃 `redactSensitiveData`）自動施加。
- ✅ **零 WebView 專屬 redaction 程式碼**——「不開後門」正因為**只有一條路**：WebView entry 是 buffer 裡與 native 無異的 `NetworkEntry`，`buildCurl`/`buildPlainText`/`diagnostic_report` 對它遮罩與 native 逐字節相同。
- ✅ **尊重 opt-out**：`redactSensitiveData=false` 時 WebView 與 native 一起顯示原始（一致）。
- ✅ 滿足決策紀錄 #4「不得繞過遮罩管線」——用的就是那條管線、那個接線點。

> **落地校正註記**：US-3 的「在成為 NetworkEntry 前」是規格層的意向措辭；其**可測試意向**（不繞過、與 native 一致、尊重 opt-out）由方案 B **更忠實**達成。TDD 用「WebView 來源的 `NetworkEntry` 過 `buildPlainText(redact:true)` 後 `Authorization` 被遮成 `••••`、且與 native 同一 code path」證明之（§6 Chunk 3）。
>
> **向 reviewer 誠實揭露的落差**：codebase 的 redaction 是 **header-only**（無 body redaction 函式）；native 不遮 body。故 WebView body 亦不遮 header，僅 JS 端截斷——**parity 成立**。若要真正遮 body，那是一個影響 native 的**新橫切功能**，超出 #10 範圍，不在本計畫。

---

## 6. Chunk 拆分、複雜度與 TDD

複雜度等級：**機械性** / **標準整合** / **需設計判斷**。write-scope 供 STAGE 2 判斷並行（路徑不重疊者可並行）。

### 依賴圖與並行建議

```text
Chunk 1 (JS payload)        ─┐   （協定已於 §2 凍結）
Chunk 2 (adapter · log)     ─┼─ 可並行（不同檔）
                             │
Chunk 3 (adapter · net)     ─┘   ← 依賴 Chunk 2（同一個 adapter 檔）
Chunk 4 (barrel export)          ← 依賴 1,2,3 的符號存在
Chunk 5 (README)  ┐
                  ├─ 可並行（不同路徑；皆依賴公開 API 凍結，即 Chunk 4 後）
Chunk 6 (example) ┘
```

| Chunk | write-scope（路徑） | 可與誰並行 |
|---|---|---|
| 1 JS payload | `lib/src/webview/webview_bridge_js.dart` | Chunk 2 |
| 2 adapter·log | `lib/src/webview/webview_bridge_adapter.dart`、`test/webview/webview_bridge_adapter_test.dart` | Chunk 1 |
| 3 adapter·net | 同 Chunk 2 檔（**路徑重疊 → 不可與 2 並行**） | — |
| 4 barrel | `lib/flutter_inspector_kit.dart` | — |
| 5 README | `README.md` | Chunk 6 |
| 6 example | `example/lib/demos/webview_demo.dart`、`example/pubspec.yaml`、`example/lib/main.dart` | Chunk 5 |

> **Phase 1（console/error）＝ Chunk 2；Phase 2（fetch/XHR）＝ Chunk 3。** 兩者同屬一條資料管線、寫入同一個 adapter 檔，**併入同一個 PR**，但拆成兩個獨立 TDD 任務循序落地（2 → 3）。

---

### Chunk 1：JS bridge payload 與協定常數

**複雜度：需設計判斷**（JS 正確性、雙傳輸偵測、hook 排序、截斷、防循環序列化）。
**Files**：Create `lib/src/webview/webview_bridge_js.dart`。

> **TDD 誠實說明**：JS payload 是**資料常數字串**，Dart 端無 JS 引擎可執行它。單元測試只能做**結構斷言**（契約護欄）；JS 的實際行為由 Chunk 6 example app 手動驗證（真機/模擬器看事件是否進 dashboard）。不為此建 JS 測試框架（YAGNI）。

- [x] **Step 1：寫 failing 結構測試（契約護欄）**

```dart
// test/webview/webview_bridge_js_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/webview/webview_bridge_js.dart';

void main() {
  test('JS payload 與 host 引用同一個 channel 名', () {
    expect(inspectorWebViewBridgeJs, contains(kWebViewBridgeChannelName));
  });
  test('JS payload 涵蓋 console/error/fetch/xhr 四類 hook 與雙傳輸', () {
    for (final needle in [
      'console', 'onerror', 'unhandledrejection', 'fetch',
      'XMLHttpRequest', 'flutter_inappwebview', 'postMessage',
    ]) {
      expect(inspectorWebViewBridgeJs, contains(needle), reason: needle);
    }
  });
  test('JS 端截斷上限為具名常數且存在截斷標記', () {
    expect(inspectorWebViewBridgeJs, contains('MAX_CHARS'));
    expect(inspectorWebViewBridgeJs, contains('truncated'));
  });
}
```

- [x] **Step 2：跑測試確認 FAIL**（`flutter test test/webview/webview_bridge_js_test.dart`，Undefined name）
- [x] **Step 3：實作** `webview_bridge_js.dart`——`const String kWebViewBridgeChannelName = 'FlutterInspectorBridge';` + `const String inspectorWebViewBridgeJs = r'''(function(){ ... })();''';`，內含 §2.2 的 hook、§2.2 傳輸偵測、§2.3 截斷。JS 以 IIFE 包裹，並在頂部加 `if (window.__inspectorBridgeInstalled) return; window.__inspectorBridgeInstalled = true;` 防重複注入（同頁多次 `runJavaScript` 不重覆 hook）。
- [x] **Step 4：跑測試確認 PASS**
- [x] **Step 5：commit**（`feat(webview): add injectable JS bridge payload and protocol constant`）

---

### Chunk 2：adapter — log 路徑（Phase 1）

**複雜度：標準整合**。
**Files**：Create `lib/src/webview/webview_bridge_adapter.dart`、Create `test/webview/webview_bridge_adapter_test.dart`。

- [x] **Step 1：寫 failing 測試**（測資放同檔 `_Data` class；範本參考 `test/interceptors/dio_interceptor_test.dart`）

涵蓋：
1. `console.error` 訊息 → `LogLevel.error` 的 `LogEntry` 進 `inspector.logEntries`。
2. 五種 method（log/info/warn/error/debug）→ 正確 `LogLevel`（表 §3.2）；未知 method → `info`。
3. `window.onerror`（`method:"error"` + `stack`）→ error 級 entry，`stackTrace` 帶 JS stack。
4. provenance：entry.data == `{'origin':'webview','pageUrl':'https://…'}`。
5. **優雅降級**：`handleMessage('not json{')`、`handleMessage('{"t":"log"')`（截斷 JSON）、`handleMessage('{"t":"weird"}')`（未知型別）→ **不 throw、不新增 entry**。

```dart
test('console.error 成為 error 級 LogEntry 並帶 webview provenance', () {
  final inspector = FlutterInspector();
  final adapter = WebViewBridgeAdapter(inspector);
  adapter.handleMessage(_Data.consoleError);
  final e = inspector.logEntries.single;
  expect(e.level, LogLevel.error);
  expect(e.message, 'boom');
  expect(e.data, {'origin': 'webview', 'pageUrl': 'https://m.example.com'});
});

test('malformed / unknown 訊息靜默丟棄不 throw', () {
  final inspector = FlutterInspector();
  final adapter = WebViewBridgeAdapter(inspector);
  for (final raw in ['not json{', '{"t":"log"', '{"t":"weird"}']) {
    expect(() => adapter.handleMessage(raw), returnsNormally);
  }
  expect(inspector.logEntries, isEmpty);
});
```

- [x] **Step 2：跑測試確認 FAIL**
- [x] **Step 3：實作** `WebViewBridgeAdapter`——**只先實作 `_handleLog` 與 `handleMessage` 的 `case 'log'`**（`case 'net'` 留給 Chunk 3；此時 `_handleNet` 可先不存在，`net` 落入 default 忽略）。含 `_levelFor` 對應表。
- [x] **Step 4：跑測試確認 PASS**
- [x] **Step 5：commit**（`feat(webview): translate WebView console/error into LogEntry (Phase 1)`）

---

### Chunk 3：adapter — network 路徑（Phase 2）

**複雜度：標準整合**。
**Files**：Modify `lib/src/webview/webview_bridge_adapter.dart`、Modify `test/webview/webview_bridge_adapter_test.dart`。（與 Chunk 2 路徑重疊 → 循序，不並行。）

- [x] **Step 1：寫 failing 測試**

涵蓋：
1. `t:"net"` fetch → `NetworkEntry` 進 `inspector.networkEntries`，`method`/`url`/`statusCode`/`duration`/headers/body 正確對應（US-2）。
2. `errorType == null && sourceDio == null`（US-2 / US-5：非 Dio、Replay 自然不可用）。
3. 傳輸失敗（無 `status`、帶 `error`）→ `statusCode == null` 且 `error` 保留（供 #7 aggregation 與 detail view 分流）。
4. **redaction parity（US-3 · §5 方案 B）**：帶 `Authorization` header 的 WebView `NetworkEntry` 過 `buildPlainText(entry, redact: true)` 後含 `••••`；`redact: false` 時保留原值——證明與 native 同一 code path、尊重 opt-out。
5. **CRLF / malformed-URL 加固確認（風險④）**：`message` 含 `\r\n` 的 WebView log 過 `buildLogOneLiner` 被壓平；malformed URL 的 WebView net 過 `buildNetworkOneLiner` 不外洩 query。（複用既有 formatter，僅補「WebView 來源」確認案例。）

```dart
test('WebView fetch 成為非 Dio NetworkEntry：errorType/sourceDio 皆 null', () {
  final inspector = FlutterInspector();
  WebViewBridgeAdapter(inspector).handleMessage(_Data.fetch502);
  final e = inspector.networkEntries.single;
  expect(e.method, 'POST');
  expect(e.statusCode, 502);
  expect(e.errorType, isNull);
  expect(e.sourceDio, isNull); // Replay 正確地不可用
});

test('WebView 網路事件過既有 redaction 邊界，行為與 native 一致', () {
  final inspector = FlutterInspector();
  WebViewBridgeAdapter(inspector).handleMessage(_Data.fetchWithAuth);
  final e = inspector.networkEntries.single;
  expect(buildPlainText(e, redact: true), contains('••••'));
  expect(buildPlainText(e, redact: false), contains('Bearer secret'));
});
```

- [x] **Step 2：跑測試確認 FAIL**
- [x] **Step 3：實作** `_handleNet` + `handleMessage` 的 `case 'net'` + `_asInt`/`_asDuration`/`_tsOf`/`_asHeaders`（§3.1）。
- [x] **Step 4：跑測試確認 PASS**
- [x] **Step 5：commit**（`feat(webview): translate WebView fetch/XHR into NetworkEntry (Phase 2)`）

---

### Chunk 4：public API export

**複雜度：機械性**。
**Files**：Modify `lib/flutter_inspector_kit.dart`。

- [x] **Step 1**：增列 export：

```dart
export 'src/webview/webview_bridge_adapter.dart';
export 'src/webview/webview_bridge_js.dart';
```

- [x] **Step 2**：`flutter analyze` 無 error/warning。
- [x] **Step 3**：（可選）在 `test/webview/webview_bridge_adapter_test.dart` 改用 `package:flutter_inspector_kit/flutter_inspector_kit.dart` import，確認公開出口可用。
- [x] **Step 4：commit**（`feat(webview): export WebViewBridgeAdapter and JS bridge payload`）

---

### Chunk 5：README 雙套件接線文檔

**複雜度：標準整合**（技術須精確）。
**Files**：Modify `README.md`。

新增「WebView Inline Debugging」章節，內容須含：

- [x] **共用步驟**：建 `WebViewBridgeAdapter(inspector)` →（各套件）建 channel/handler，名字用 `FlutterInspectorBridge` → `onMessage` 把字串交 `adapter.handleMessage(...)` → 頁面載入時注入 `inspectorWebViewBridgeJs`。
- [x] **webview_flutter 段**（約五行）：
  ```dart
  final adapter = WebViewBridgeAdapter(inspector);
  controller
    ..addJavaScriptChannel(
      kWebViewBridgeChannelName, // 'FlutterInspectorBridge'
      onMessageReceived: (m) => adapter.handleMessage(m.message),
    )
    ..setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) => controller.runJavaScript(inspectorWebViewBridgeJs),
    ));
  ```
- [x] **flutter_inappwebview 段**（約五行）：
  ```dart
  final adapter = WebViewBridgeAdapter(inspector);
  // documentStart 注入，吃得到早期 log
  controller.addUserScript(userScript: UserScript(
    source: inspectorWebViewBridgeJs,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  ));
  controller.addJavaScriptHandler(
    handlerName: kWebViewBridgeChannelName,
    callback: (args) => adapter.handleMessage(args.first as String),
  );
  ```
- [x] **注入時機誠實說明**（§5 規格 / US-7 驗收）：`flutter_inappwebview` 的 `UserScript` 可於 `AT_DOCUMENT_START` 注入、吃得到早期 log；`webview_flutter` 的 `runJavaScript` 於 `onPageStarted` 後執行，**會漏頁面初始化最早期的 log**——明示各自能與不能，不假裝等價。
- [x] **限制註記**：iframe / Service Worker 不支援（僅 main frame）；`setOnConsoleMessage` 只能當 console 的降級備援，非 fetch/error 主路徑；WebView 網路事件的 Replay 因非 Dio 而不可用（正確降級）。
- [x] **redaction 說明**：WebView 網路事件與 native 一樣受 `redactSensitiveData` 遮罩（走同一匯出/顯示邊界）。
- [x] **commit**（`docs(webview): dual-package wiring guide with injection-timing caveats`）

---

### Chunk 6：example 示範頁

**複雜度：標準整合**。
**Files**：Create `example/lib/demos/webview_demo.dart`、Modify `example/pubspec.yaml`、Modify `example/lib/main.dart`。

- [x] **Step 1**：`example/pubspec.yaml` 加 `webview_flutter: ^4.x`（僅 example；不碰 `lib/` 相依，US-6）。跑 `flutter pub get`（於 `example/`）。
- [x] **Step 2**：`webview_demo.dart`——對齊 `network_demo.dart` 慣例：一個 `WebViewDemo` class 持有 `inspector`，內建 `WebViewController` 掛 channel + adapter + 注入 JS，載入一個內嵌 HTML（`loadHtmlString`）含幾顆按鈕觸發 `console.log`/`console.error`/`fetch`，證明事件進 dashboard。UI 若需頁面，提取為獨立 `class WebViewDemoPage extends StatelessWidget`（**禁 `_build...()` helper**，遵 flutter-styles）。
- [x] **Step 3**：`main.dart` 加 `late final WebViewDemo`、初始化、一顆「Open WebView Demo」按鈕。
- [x] **Step 4**：`flutter analyze`（於 `example/`）無 error；手動於模擬器驗證 WebView 的 console/error/fetch 出現在 Console/Network tab 與 mergedTimeline。
- [x] **Step 5：commit**（`docs(example): add WebView demo page wiring the bridge adapter`）

---

## 7. 破壞性分析（US-6 · Never break userspace）

| 保證 | 如何在實作中確保 |
|---|---|
| **零新相依** | `lib/src/webview/*` 只 import 既有 `core/`、`models/`；webview 套件僅入 `example/pubspec.yaml`。CI/`flutter pub deps` 檢查 `lib/` 相依不變。 |
| **schema 僅向後相容擴充**（2026-07-18 修訂，§1.3） | `LogEntry` 零變更（provenance 塞既有 `data`）；`NetworkEntry` 新增 `origin`（預設 `NetworkOrigin.dio`）與 `pageUrl`（預設 `null`）兩個帶預設值欄位——既有建構呼叫、Dio interceptor、Replay 零改動。既有 `*_entry_test.dart` 全綠 + provenance 新測試即證。 |
| **既有公開 API 不變** | **`FlutterInspector` 建構子與方法零改動**——adapter 是外部物件，鏡像 Dio interceptor 的關係（§1.1）。既有 `flutter_inspector_test.dart` 全綠即證。 |
| **既有 UI / 報告零改動即受益** | 不改 `console_tab` / `network_tab` / `mergedTimeline` / `diagnostic_report` / #7 aggregation；WebView entry 是同型別、進同 buffer，自動流經全鏈路。 |
| **redaction 不開後門** | §5 方案 B：無 ingest redaction，靠共用邊界；parity 測試（Chunk 3）證明與 native 同 code path、尊重 opt-out。 |
| **敵意輸入不崩** | `handleMessage` 全程 try/catch + 型別守衛，malformed/未知一律靜默丟棄（Chunk 2 測試）。 |

**回歸驗證**：全套件 `flutter test`（依 MEMORY：STAGE 3 不重跑已驗證測試；`magical_tap_test` 有既有 10 分鐘 timeout，全套測試前先排除）。

---

## 8. 執行方式（供選擇）

本計畫的 write-scope 已明確標註路徑重疊關係，兩種執行方式皆可：

### 方式 A：subagent-driven（推薦）
- 一個 orchestrator 依 §6 依賴圖派工。
- **第一波並行**：Chunk 1（JS）+ Chunk 2（adapter·log）——不同檔、協定已凍結。
- **序列**：Chunk 3（依賴 2，同檔）→ Chunk 4（barrel）。
- **第二波並行**：Chunk 5（README）+ Chunk 6（example）——不同路徑、皆依賴 Chunk 4 凍結的公開 API。
- 每個 Chunk 一個 subagent，TDD 紅→綠→commit 後回報，orchestrator 驗收再放下一波。

### 方式 B：parallel session（人工分工）
- Session 1：Chunk 1 → 4（核心 bridge，同一人維持 adapter 檔一致性最穩）。
- Session 2：待 Chunk 4 API 凍結後，接手 Chunk 5 + 6（文檔 + example），與 Session 1 收尾不衝突（路徑不重疊）。

> 兩種方式的臨界同步點都是 **Chunk 4（public API 凍結）**——README 與 example 引用的公開符號必須先定案。
</content>
</invoke>
