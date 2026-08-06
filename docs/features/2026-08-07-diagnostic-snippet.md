# 快速複製 Diagnostic Snippet（§P4）

> 來源：`docs/brainstorm/2026-08-05-features-brainstorm.md` §P4（Tier 4，effort trivial~low）

## 問題

開發者看到 API 失敗後，要湊出一份可貼到 GitHub Issue / Slack 的 bug report，
目前得在 `NetworkDetailView` 裡分三次操作：複製 cURL、往下捲找 error body 複製、
再手動拼接並補上 status / 時間戳。步驟多且容易漏掉欄位。

## 使用者故事

> 作為排查 API 失敗的開發者，我想在 detail view 一鍵複製一份**完整的診斷片段**
> （cURL + 狀態 + 錯誤 payload + 時間戳），直接貼進 issue 就是可讀的 Markdown，
> 不必自己拼接。

## 驗收條件

1. `NetworkDetailView` 的既有分享選單新增一個項目「Copy diagnostic snippet」。
2. 選取後複製到剪貼簿的內容為單一 Markdown 區塊，依序包含：
   - 標題行：method + URL
   - 時間戳（entry 的 timestamp）
   - status code（若有）與 duration（若有）
   - errorType / error 訊息（若有）
   - cURL 指令（fenced）
   - response body（若有，fenced）
3. **遵守 redaction 旗標**：`redactSensitiveData` 為 true 時，敏感 header 需遮罩，
   行為與既有 `buildCurl` / `buildPlainText` 一致。
4. **fence 安全**：內容自身含 ``` 時不可打斷區塊——沿用既有的動態長度 fence 邏輯，
   不重寫一份。
5. 複製後顯示既有樣式的 SnackBar 回饋。
6. 新增單元測試涵蓋：含 error 的 entry、無 error 的成功 entry、
   內容含 backtick 的 entry（fence 加長）、redact on/off。

## 範圍邊界

**做：**
- `network_formatters.dart` 新增一個組裝 formatter
- `network_detail_view.dart` 既有 `_ShareAction` enum 加一個值 + 選單項 + 分支
- 將 `diagnostic_report.dart` 的私有 `_fenced()` 提取為共用函式（見下）

**不做：**
- 不新增按鈕或 UI 元件（沿用既有 `PopupMenuButton`）
- 不改 `buildCurl` / `buildPlainText` 的既有簽章與行為
- 不加入 request headers 全文（cURL 已含）
- 不做批次匯出多筆 entry（那是 diagnostic report 的職責）

## 實查發現（影響 effort 的關鍵）

| 項目 | 現況 |
|---|---|
| `buildCurl(entry, {redact})` | ✅ `network_formatters.dart:105`，已接 redaction |
| `buildPlainText(entry, {redact})` | ✅ 同檔 `:136` |
| `_ShareAction` enum + 選單 | ✅ `network_detail_view.dart:13` / `:38-52`，加一個值即可 |
| `_onShare` switch | ✅ 同檔 `:230`，加一個 case |
| **`_fenced()`** | ⚠️ **私有**於 `diagnostic_report.dart:190`，需提取為共用 |

⚠️ 最後一項是文件原估計未涵蓋的：brainstorm 只寫「沿用該處的處理方式」，
但它是私有函式，跨檔使用必須先提取。這正是「trivial 項目低估既有判定份數」的
同一類成本——提取時要確認 `diagnostic_report.dart` 的既有呼叫端行為不變。
