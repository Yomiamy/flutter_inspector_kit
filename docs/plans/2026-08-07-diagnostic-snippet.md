# 實作計畫：快速複製 Diagnostic Snippet（§P4）

> 規格：[`docs/features/2026-08-07-diagnostic-snippet.md`](../features/2026-08-07-diagnostic-snippet.md)

## 資料流

無新資料模型。純粹是既有 `NetworkEntry` 的一種新輸出格式：

```
NetworkEntry ──► buildDiagnosticSnippet(entry, redact:) ──► String (Markdown)
                        │
                        ├─► buildCurl(entry, redact:)   （既有，不改）
                        └─► fencedBlock(...)            （提取自 diagnostic_report）
```

## 任務拆分

### Task 1：提取 `_fenced()` 為共用函式〔機械性 · 快/便宜〕

**為什麼先做**：Task 2 依賴它。這是純搬移，不改行為。

- 在 `lib/src/utils/markdown_fence.dart`（新檔）定義 `String fencedBlock(String body)`，
  內容從 `diagnostic_report.dart:183-200` 的 `_fenced()` 原樣搬移，含其 doc comment
  （那段註解記載了「fence 必須長於內容中最長 backtick run」的 CommonMark 理由，是資產）。
- `diagnostic_report.dart` 移除私有 `_fenced()`，改 import 並呼叫 `fencedBlock`。
- **驗收**：`flutter test test/utils/diagnostic_report_test.dart` 全數通過（行為不得改變）。

**寫入**：`lib/src/utils/markdown_fence.dart`（新）、`lib/src/utils/diagnostic_report.dart`

---

### Task 2：新增 `buildDiagnosticSnippet` formatter〔整合 · 標準〕

```dart
/// Assembles a one-shot diagnostic snippet for pasting into an issue tracker.
String buildDiagnosticSnippet(NetworkEntry entry, {bool redact = true})
```

輸出結構（欄位不存在時整行略去，不留空欄）：

```markdown
**[GET] https://api.example.com/cart** · 2026-08-07 14:32:05.123
Status: 500 · 1243ms
Error: DioExceptionType.badResponse — Http status error [500]

<fenced>curl -X GET ...</fenced>

Response:
<fenced>{"error": "..."}</fenced>
```

- 時間戳用 `entry.timestamp.toIso8601String()`（與既有 formatter 一致）。
- status / duration / error 各自 null-safe，缺就不輸出該行。
- cURL 段一律呼叫 `buildCurl(entry, redact: redact)`，不自行組裝。
- 所有 fenced 區塊走 Task 1 的 `fencedBlock`。

**驗收**：新增 `test/utils/network_formatters_test.dart` 的 group，涵蓋
①含 error 的失敗 entry ②成功 entry（無 error 行）③response body 內含 ``` （fence 加長）
④`redact: true/false` 差異。

**寫入**：`lib/src/utils/network_formatters.dart`、`test/utils/network_formatters_test.dart`

---

### Task 3：接上 UI 選單〔機械性 · 快/便宜〕

- `network_detail_view.dart:13` 的 `enum _ShareAction { curl, text, share }`
  → 加 `snippet`（放在 `curl` 之後，語意相近者相鄰）。
- 選單新增 `PopupMenuItem(value: _ShareAction.snippet, child: Text('Copy diagnostic snippet'))`。
- `_onShare` 的 switch 新增 case：`Clipboard.setData(ClipboardData(text: buildDiagnosticSnippet(entry, redact: redactSensitiveData)))`
  + 既有樣式的 SnackBar。
- ⚠️ **`redactSensitiveData` 必須傳入**——與既有 `curl` / `text` case 一致，不可漏。

**驗收**：`flutter test test/ui/tabs/network_detail_view_test.dart`，新增一個
widget test 確認選單有該項且點擊後剪貼簿內容含 `curl` 字樣。

**寫入**：`lib/src/ui/dashboard/tabs/network/network_detail_view.dart`、
`test/ui/tabs/network_detail_view_test.dart`

## 執行順序

序列：Task 1 → Task 2 → Task 3。**不可並行**——Task 2 依賴 Task 1 的 `fencedBlock`，
Task 3 依賴 Task 2 的 formatter。

## 風險

| 風險 | 對策 |
|---|---|
| 提取 `_fenced()` 改動既有 report 行為 | Task 1 驗收明訂既有 `diagnostic_report_test.dart` 須全過 |
| snippet 與 `buildPlainText` 職責重疊 | 兩者定位不同：plainText 是單筆完整轉錄、snippet 是可貼上的診斷摘要。不合併，但 snippet 不重複實作 cURL |
| 漏傳 redaction 旗標 | Task 3 驗收明列；review 時對照既有兩個 case |
