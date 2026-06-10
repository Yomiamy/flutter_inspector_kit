# 功能規格：Network Inspector 強化（對齊 alice）

- **日期**：2026-06-10
- **Workflow ID**：wf-1781023458-df59
- **參考**：[jhomlala/alice](https://github.com/jhomlala/alice)
- **狀態**：STAGE 0a — 待確認

---

## 1. 背景與動機（Why）

目前的 Network Inspector（`network_tab.dart`）相當陽春：

- 列表只顯示 `[method] url` 與 `statusCode • durationms`。
- 展開後用 `ExpansionTile` 直接把 headers / body 以 `toString()` 塞進 `ListTile.subtitle`，沒有結構化呈現、沒有 JSON 美化、沒有複製。
- 沒有搜尋／篩選，呼叫一多就無法定位。
- 沒有任何「進行中呼叫」的提示。
- 無法把呼叫分享給後端同事 debug。

對標 alice 的五大能力（Request、Response、Notification、Sharing、Keyword Search），把 Network Inspector 從「看得到」提升到「查得到、看得懂、帶得走」。

## 2. 範圍（Scope）

本次一次交付五項（已與使用者確認「全部五項一起做」）：

1. **Request 詳情強化**
2. **Response 詳情強化**
3. **Notification（系統通知列）**
4. **Sharing（cURL / 純文字 / 系統分享）**
5. **Keyword Search（關鍵字搜尋 + 篩選）**

### 明確不在範圍內（Non-goals）

- 不支援 Dio 以外的 HTTP client（http、chopper 等）攔截器——維持現有 Dio-only。
- 不做「Shake to open」（搖動開啟）。
- 不做請求重送（replay / resend）。
- 不做跨 session 的呼叫持久化（維持 RingBuffer 記憶體內）。
- 不改動 Console / Navigator / Database 三個 tab。

## 3. 使用者故事與驗收條件

### US-1：Request 詳情強化

> 身為開發者，我要在展開一筆呼叫時看到結構化的 Request 資訊，而不是一坨 toString。

對齊 alice `AliceHttpRequest` 的欄位，呈現：method、完整 URL、**query parameters（拆解顯示）**、headers（鍵值表格）、body（JSON 自動美化）、**content type**、**request size（bytes，人類可讀）**、發起時間。

**驗收條件：**
- [ ] 展開呼叫後，Request 區塊以分段卡片呈現：General（method/url/time/size/contentType）、Query Parameters、Headers、Body。
- [ ] URL 含 query string 時，自動拆解為 key-value 列表顯示。
- [ ] Request body 若為合法 JSON → 縮排美化顯示；否則原樣顯示。
- [ ] Headers 以鍵值對列表呈現，不再是 `Map.toString()`。
- [ ] 顯示 request body 大小（如 `1.2 KB`）；無 body 時顯示 `0 B` 或隱藏。
- [ ] 既有截斷機制（`kNetworkBodyMaxLength`）行為不變，截斷標記仍可見。

### US-2：Response 詳情強化

> 身為開發者，我要清楚看到 Response 的狀態、耗時、大小與美化後的 body。

對齊 alice `AliceHttpResponse`：status code（含顏色語意）、duration、**response size**、headers、body（JSON 美化）、error（失敗時）。

**驗收條件：**
- [ ] Response 區塊分段：General（status/duration/size）、Headers、Body。
- [ ] status code 依區間著色：2xx 綠、3xx 藍、4xx 橘、5xx/error 紅。
- [ ] Response body 為 JSON → 美化顯示；否則原樣。
- [ ] 顯示 response size（人類可讀）。
- [ ] 進行中（`isComplete == false`）的呼叫顯示「Pending / Loading」狀態，不顯示空白。
- [ ] 失敗呼叫的 error 區塊以紅色明確標示。

### US-3：Notification（系統通知列）

> 身為開發者，即使 App 在前景、我沒打開 dashboard，也要能從系統通知列得知有 HTTP 呼叫發生與最新狀態。

對齊 alice「Notification on HTTP call」——以 `flutter_local_notifications` 在系統通知列顯示一則**可更新的常駐通知**，顯示最近一筆呼叫與累計統計。

**驗收條件：**
- [ ] 提供開關 API（如 `FlutterInspector(showNotification: true)` 或 `enableNetworkNotification()`），**預設關閉**（不打擾未啟用者，且避免未授權崩潰）。
- [ ] 啟用後，每筆新呼叫更新同一則通知（不洗版），顯示：最新 `[method] endpoint`、status、累計呼叫數。
- [ ] 點擊通知可開啟 dashboard 的 Network tab（需 navigator / context 可用時；不可用則僅顯示）。
- [ ] 未授權通知權限時，安全降級（不崩潰，靜默略過），並可透過 log 提示。
- [ ] 此功能為可選依賴策略：未啟用時不要求 App 端設定通知權限。

### US-4：Sharing（匯出）

> 身為開發者，我要把某一筆呼叫帶出去（貼到 issue、丟給後端、存檔），用最省事的方式重現。

支援三種匯出（已確認全做）：

1. **複製為 cURL**：把 method / url / headers / body 組成可執行的 `curl` 指令，複製到剪貼簿。
2. **複製為純文字**：完整 Request + Response 詳情格式化為文字，複製到剪貼簿。
3. **系統分享 / 存檔**：透過 `share_plus` 叫出系統分享面板（可選存檔）。

**驗收條件：**
- [ ] 呼叫詳情頁有「分享」入口（icon / menu）。
- [ ] 「複製為 cURL」產生語法正確的 curl：含 `-X <method>`、每個 header `-H`、body `--data`（有 body 時）、URL 最後。
- [ ] 「複製為純文字」包含 General / Request / Response / Error 全段，格式清晰。
- [ ] 「系統分享」透過 share_plus 帶出格式化文字。
- [ ] 複製成功給予 SnackBar 之類的回饋。

### US-5：Keyword Search（搜尋與篩選）

> 身為開發者，呼叫列表很長時，我要用關鍵字快速定位某一筆，並能依方法/狀態篩選。

對齊 alice「HTTP calls search」。

**驗收條件：**
- [ ] Network tab 頂部有搜尋框，輸入即時過濾列表。
- [ ] 搜尋比對範圍：URL、method、status code（字串比對）。
- [ ] 搜尋大小寫不敏感。
- [ ] 提供方法/狀態快速篩選（至少：method chip 或 status 區間 chip 二擇一，作為基礎篩選）。
- [ ] 清空搜尋恢復完整列表。
- [ ] 搜尋與既有 refresh / clear 按鈕並存，不互相干擾。

## 4. 跨領域驗收（全項共用）

- [ ] `flutter analyze` 零 issue。
- [ ] 既有 Network 相關測試不退化；新增資料模型 / util 有單元測試（size 格式化、curl 生成、JSON 美化、搜尋過濾）。
- [ ] 對外公開 API 變更（若有）在 `lib/flutter_inspector.dart` 正確 export，並更新 example。
- [ ] 新增的第三方依賴（`flutter_local_notifications`、`share_plus`）加入 `pubspec.yaml` 並能在 example 編譯通過。

## 5. 風險與待解

- **Notification 平台設定**：`flutter_local_notifications` 在 Android 需 channel、iOS/macOS 需權限請求。預設關閉可降低對使用者既有 App 的侵入；啟用流程的平台設定需在 README 說明。
- **依賴體積**：新增兩個第三方套件。若團隊在意，後續可評估把 notification / sharing 拆成可選的 feature flag（本次先內建，預設關閉 notification）。
- **size 計算**：body 已是字串（且可能被截斷），size 以字串 byte 長度估算，截斷後的 size 為截斷值——需在 UI 標註「截斷」避免誤導。

---

## 確認

請確認以上功能規格（使用者故事、驗收條件、範圍邊界）。確認後我會進入 **STAGE 0b** 產出實作計畫（資料結構、檔案異動、任務拆分）。
