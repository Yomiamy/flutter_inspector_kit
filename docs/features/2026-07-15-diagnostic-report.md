# 功能規格：一鍵診斷報告（Diagnostic Report）

> **來源**：[brainstorm #3](../brainstorm/2026-07-12-features-brainstorm.md) §3「一鍵診斷報告（Diagnostic Report）」
> **日期**：2026-07-15
> **狀態**：Approved — 開放問題已於暫停點全數裁決（見「已定案設計取捨」D-1 ~ D-4）
> **版本基準**：v1.4.0（branch `main`）

---

## 問題

QA 重現 bug 後要帶走證據，今天的流程是：

1. 開 dashboard → 切 Console tab → 找到那筆 error log → 點開 `LogDetailView` → 按分享
2. 切 Network tab → 找到那筆失敗請求 → 點開 `NetworkDetailView` → 按分享
3. 切 Navigator tab → 看當前堆疊 → **沒有分享按鈕，只能截圖**
4. 切 Database tab → **沒有分享按鈕，只能截圖**
5. 手打 device / OS / app 版本資訊到 issue 裡

**codebase 證據（缺口就在這裡）**：

| 現況 | 位置 | 缺口 |
|------|------|------|
| 單筆 network 匯出已完備 | `network_formatters.dart:106` `buildPlainText(entry, {redact})` | **只吃一個 `NetworkEntry`**，沒有任何「多筆打包」的呼叫者 |
| 單筆 log 匯出已完備 | `log_formatters.dart:8` `buildLogPlainText(entry)` | 同上，`entry` 是單數 |
| 跨層時序軸已完備 | `inspector_registry.dart:38` `mergedTimeline({sources})` | 已按 `TimestampedEntry.timestamp` 降序合併四個 buffer——**唯一的消費者是 `ConsoleTab` 的畫面渲染，沒有任何序列化出口** |
| 當前路由堆疊已完備 | `navigator_stack_resolver.dart:21` `NavigatorStackResolver().resolve(entries)` | 純 Dart、可直接取用——**唯一的消費者是 `NavigatorTab` 的畫面渲染** |
| Log 等級過濾已完備 | `log_inspector.dart:21` `entriesAtLevel(LogLevel)` | **寫好了，但整個 codebase 從未呼叫過**（brainstorm #5 已點名此事） |
| 平台自適應分享已完備 | `share_text.dart` → `shareText(String)` | 只有 `NetworkDetailView`、`LogDetailView` 兩個單筆呼叫點 |
| Dashboard AppBar | `dashboard_modal.dart:47` | **`actions:` 是空的**——title + leading(close) + bottom(TabBar)，沒有任何 dashboard 級別的全域動作 |
| Navigator / Database tab | `navigator_tab.dart`、`database_tab.dart` | **零匯出能力** |

**核心矛盾**：序列化零件（`buildPlainText` / `buildLogPlainText`）、資料聚合零件（`mergedTimeline`）、過濾零件（`entriesAtLevel`）、輸出零件（`shareText`）**全部就緒**——其中三個已在生產路徑上驗證過，一個（`entriesAtLevel`）寫好了卻沒人用。缺的只是把它們串起來的那條線，以及 dashboard 上那顆按鈕。這不是新功能開發，是把既有零件接上。

---

## 解決方案（一句話）

Dashboard AppBar 新增一個 **Export** action → 開啟選單（勾選區段 + 時間範圍 + errors-only）→ 產生一份 **Markdown 報告**（app/device 表頭 + 當前路由堆疊 + 選定條件下的 log / network / nav / db 各區段）→ 直接送進系統分享，**不落盤**。

---

## 使用者故事

### US-1：QA 一鍵帶走證據
> 身為 QA，
> 我在 app 裡重現了 bug 之後，
> 我希望打開 dashboard 按一個按鈕，就得到一份可直接貼進 Jira / GitHub issue 的報告，
> 好讓我不必切四個 tab、逐筆截圖，也不必手打 device 資訊。

### US-2：只帶走相關的部分
> 身為 QA，
> 當我知道 bug 只跟網路有關、且發生在最近 5 分鐘內時，
> 我希望能勾選「只要 Network」+「最近 5 分鐘」，
> 好讓報告不被 500 筆無關的 log 稀釋，收報告的工程師一眼看到重點。

### US-3：開發者拿到報告能還原現場
> 身為接到 issue 的 Flutter 開發者，
> 我打開 QA 貼上來的報告，
> 我希望看到「當時的路由堆疊」「失敗請求的 status / errorType / stack trace」「錯誤前後發生的事件」，
> 好讓我不用回頭問 QA「你當時在哪個畫面」。

### US-4：報告不能洩漏 secret
> 身為導入這個套件的開發者，
> 當我的 QA 把診斷報告貼到公司的 issue tracker（甚至外部群組）時，
> 我希望 `Authorization` / `Cookie` 這類敏感 header 已經被遮蔽，遮蔽行為跟我設定的 `redactSensitiveData` 完全一致，
> 好讓「一鍵匯出」不會變成「一鍵洩密」。

### US-5：沒注入 device info 也不能崩
> 身為導入這個套件的開發者，
> 當我沒有提供任何 device / app 版本資訊時，
> 我希望報告的表頭優雅地顯示 `N/A`，
> 好讓這個功能不會強迫我為了一個 debug 工具去背新的原生相依。

### US-6：只帶走錯誤，不帶走噪音
> 身為 QA，
> 當我知道問題就是那幾筆 error 時，
> 我希望能勾選「只包含 error / warning」，
> 好讓報告不被幾百筆 info log 淹沒——但這個選項**預設關閉**，因為多數時候「錯誤發生前做了什麼」才是關鍵線索。

---

## 功能範圍

### In scope

- **報告產生器**：純函式，吃 entries + 選項，吐 Markdown 字串。零 Flutter 相依、可獨立 unit test（沿用 `network_formatters.dart` / `log_formatters.dart` 的 "pure formatting helpers" 慣例）。
- **報告內容**：
  - **表頭**：產生時間、**套件版本（單一真相來源，見前置項 P-1）**、`Redaction: enabled/disabled`、app / device 資訊（host 注入；缺值一律 `N/A`）
  - **當前路由堆疊**：直接複用 `NavigatorStackResolver().resolve(navigatorEntries)`（top-first）
  - **各區段**：使用者選定的 source（log / network / nav / db），每段列出符合條件的 entries
- **三個過濾維度**（互相獨立、可組合）：
  1. **時間窗**：last 5m / last 1h / all
  2. **區段選擇**：四個 source 可獨立勾選
  3. **errors-only**：只包含 `LogLevel.error` / `LogLevel.warning` 的 log（**預設關閉**）——只影響 **log 區段**，不影響 network / nav / db
- **Device / app info 注入介面**：抽象介面 + host 註冊實作，package 對 `device_info_plus` / `package_info_plus` **零相依**（沿用 `DatabaseBrowserSource` 先例）
- **UI 入口**：`DashboardModal` 的 AppBar `actions:` 新增一顆 export icon → 開啟選項 sheet/dialog → 確認後 `shareText(report)`
- **Redaction 繼承**：報告的 network 區段必須透過 `buildPlainText(entry, redact: inspector.redactSensitiveData)` 產生，**不得**繞過既有 redaction 路徑
- **空狀態**：選定條件下無資料時，該區段顯示 `(none)`，不產生空白區塊或崩潰

### Out of scope（明確排除）

| 排除項 | 理由 |
|--------|------|
| **落盤 / 持久化 / 報告歷史** | brainstorm anti-feature #2 已明確拒絕。報告是「當下產生、立刻帶走」，只走 `shareText` 的純文字路徑，不寫檔案 |
| **JSON 格式輸出** | **使用者裁決（D-3）**：只做 Markdown。目前沒有任何 JSON 消費者——HAR 已被 anti-feature #3 砍掉、持久化已被 anti-feature #2 砍掉。唯一使用者是「QA 貼進 Jira / GitHub issue」，那是 Markdown 的主場。JSON 是投機性需求，等真有消費者再加（屆時非破壞性變更） |
| **擴大 redaction 到 body / query / log data** | **使用者裁決（D-2）**：本次 out of scope，列為**獨立後續項目（值得單開一個 issue）**。理由與完整風險留痕見「🔴 敏感資料外洩」專節——body redaction 是遞迴 JSON 走訪 + 敏感 key 啟發式，屬獨立功能份量，且會改變既有單筆分享行為（破壞性風險） |
| **`device_info_plus` / `package_info_plus` 硬相依** | **使用者裁決（D-1）**：改用 host 注入。相依數維持 4 個不變 |
| **ConsoleTab 的搜尋欄 / LogLevel FilterChip** | brainstorm #5 的 UI 部分**仍維持 out of scope**。本功能只在**報告的匯出選單**提供 errors-only，**不動 ConsoleTab 的 UI** |
| **HAR / 效能 timing** | brainstorm anti-feature #3。不偽造 DNS/TLS/TTFB 分段 |
| **報告內容編輯 / 預覽畫面** | 選項 sheet 已足夠。做可編輯預覽器等於重造 markdown editor |
| **截圖 / 畫面錄製附加** | 需要額外原生相依與權限，且 share sheet 的多檔附件是完全不同的問題 |
| **自訂 template / 使用者自定義區段** | YAGNI。三個過濾維度已覆蓋 brainstorm 描述的痛點 |
| **自訂 buffer 之外的資料源** | 報告只讀四個既有 buffer，不新增資料收集 |

---

## 前置項

### P-1：修正 `FlutterInspector.version` 的單一真相來源 🔴

```
lib/src/core/flutter_inspector.dart:24   →   static const String version = '1.1.0';
pubspec.yaml:3                           →   version: 1.4.0
```

這個常數**已經過期三個版本**，而且過去沒人發現——因為**整個 codebase 沒有任何程式碼讀取它**。

診斷報告的表頭要印「套件版本」，這會讓這個常數**第一次有真實消費者**。若直接沿用，**報告會對收件人說謊**（宣稱 1.1.0，實際 1.4.0）——而收件人正是那個要靠版本號判斷「這個 bug 是不是已知問題」的工程師。

**要求**：實作報告表頭之前，必須先確立版本的**單一真相來源**（同步修正常數，或改用不會漂移的來源）。這是**前置項**，不是「順便做」。對應 AC-3。

---

## 驗收條件

| # | 條件 | 驗證方式 |
|---|------|---------|
| **AC-1** | 報告產生器是**純函式**，不依賴 Flutter widget / BuildContext，可獨立 unit test | unit test（無 widget binding） |
| **AC-2** | 報告表頭包含：產生時間（ISO8601）、套件版本、redaction 狀態、app 版本、device / OS 資訊 | unit test 比對輸出字串 |
| **AC-3** | **版本單一真相**：報告表頭印出的套件版本與 `pubspec.yaml` 一致（前置項 P-1） | unit test |
| **AC-4** | device / app 資訊**未注入**時，對應欄位顯示 `N/A`，**不拋例外、不回傳 null**，報告仍完整產生 | unit test（不提供 provider） |
| **AC-5** | device / app 資訊**已注入**時，表頭顯示 host 提供的值 | unit test（注入 fake provider） |
| **AC-6** | **零新增 pub 相依**：`pubspec.yaml` 仍為 4 個相依（`dio` / `share_plus` / `flutter_local_notifications` / `web`） | `pubspec.yaml` 對比 |
| **AC-7** | 報告包含「當前路由堆疊」區段，內容等同 `NavigatorStackResolver().resolve(navigatorEntries)`（top-first） | unit test |
| **AC-8** | **時間窗**：`last 5m` / `last 1h` 只納入 `timestamp` 落在窗內的 entries；`all` 納入全部 | unit test（構造跨時間窗 entries） |
| **AC-9** | **區段選擇**：未勾選的 source 完全不出現在報告中（不留空標題） | unit test |
| **AC-10** | **errors-only 勾選時**：報告的 log 區段只含 `LogLevel.error` 與 `LogLevel.warning` 的 entries | unit test |
| **AC-11** | **errors-only 未勾選時（預設）**：報告的 log 區段包含所有等級的 entries；且預設值為 `false` | unit test |
| **AC-12** | **errors-only 不影響其他區段**：勾選後 network / nav / db 區段內容與未勾選時完全相同 | unit test |
| **AC-13** | errors-only 的過濾**複用 `LogInspector.entriesAtLevel()`**，不重寫等級過濾邏輯 | code review |
| **AC-14** | 選定條件下某 source 無資料時，該區段顯示 `(none)`，不崩潰 | unit test |
| **AC-15** | 🔴 **`redactSensitiveData: true`（預設）時，報告中的 `Authorization` / `Cookie` / `Set-Cookie` / `X-Api-Key` header 值全部為 `••••`** | unit test（構造帶 secret header 的 entry，斷言報告字串**不含**明文 secret） |
| **AC-16** | 🔴 **`redactSensitiveData: false` 時，報告中上述 header 為明文**（opt-out 行為與 `NetworkDetailView` 一致，見 `network_detail_view_test.dart:106`） | unit test |
| **AC-17** | 🔴 **報告表頭明示 redaction 狀態**（`Redaction: enabled` / `disabled`），讓收報告的人知道這份文件有沒有被遮蔽 | unit test |
| **AC-18** | 報告的 network 區段透過 `buildPlainText(entry, redact: ...)` 產生，**不繞過**既有 redaction 路徑 | code review |
| **AC-19** | Dashboard AppBar 出現 export action；點擊開啟選項 UI | widget test |
| **AC-20** | 選項 UI 提供三個維度：四個 source 勾選、三種時間範圍、errors-only 勾選（預設關閉）；確認後呼叫 `shareText` 一次 | widget test |
| **AC-21** | 報告**不寫入任何檔案**（無 `dart:io` File 寫入、無 `path_provider`） | code review + import 檢查 |
| **AC-22** | 既有公開 API 行為零變更：`FlutterInspector` 現有 getter / method 簽章與行為不變 | 既有測試全綠 |
| **AC-23** | **ConsoleTab UI 零變更**（errors-only 只在匯出選單，不加搜尋欄 / LogLevel FilterChip） | 既有 `console_tab_test.dart` 全綠 |
| **AC-24** | Web 平台可用（報告產生器不得引入 `dart:io`） | 檢查 import graph |

---

## 已定案設計取捨

### D-1：device / app info → **Host 注入**（原 Q1，使用者裁決 A）

**調查發現（與 brainstorm 原始構想牴觸）**：brainstorm 寫「用 `package_info_plus` + `device_info_plus`（**可選相依**，未安裝時降級為 N/A）」。但 **Dart / pub 沒有 optional dependency 機制**——conditional import（`import 'a.dart' if (dart.library.io) 'b.dart'`）的條件只能是 **Dart core library 是否存在**，不能是「某個第三方 package 是否被安裝」。原構想**無法照字面實現**。

**決策**：抽象介面 + host 註冊實作。package 對 `device_info_plus` / `package_info_plus` **零相依**，由宿主 app 決定要不要裝、並把資訊餵進來。未注入 → 該區段全部 `N/A`，不崩（AC-4）。

**理由**：本專案已有一模一樣的先例——`DatabaseBrowserSource`（`lib/src/models/database_browser_source.dart`）就是「抽象介面 + host 註冊具體實作」，package 本身對 ObjectBox / sqflite 零相依，只有 `example/pubspec.yaml` 才裝那些套件。device info 是完全相同的形狀。相依數維持 4 個不變（對 pub score 與導入成本都友善），且用的是本專案**已驗證過**的 IoC 模式。

---

### D-2：redaction → **繼承現狀 + 表頭明示**（原 Q2，使用者裁決 A）

**決策**：報告一律走 `buildPlainText(entry, redact: inspector.redactSensitiveData)`，維持不變式——

> **報告的遮蔽行為 == 單筆分享的遮蔽行為**

不製造第二套語意、不產生行為分歧。報告表頭必須印 `Redaction: enabled/disabled`（AC-17），誠實告知收件人這份文件有沒有被遮蔽。

**擴大 redaction 到 body / query / log data → 本次 out of scope，列為獨立後續項目（值得單開一個 issue）。** 完整的風險留痕見下方「🔴 敏感資料外洩」專節。

---

### D-3：報告格式 → **只做 Markdown**（原 Q3，使用者裁決 A）

**決策**：只輸出 Markdown。JSON 移入 Out of scope。

**理由**：問一句「JSON 給誰吃？」——brainstorm 自己已經砍掉了所有可能的 JSON 消費者：HAR 匯出（anti-feature #3）、落盤 / 持久化（anti-feature #2）。剩下的唯一使用者是「QA 貼進 Jira / GitHub issue」，那是 Markdown 的主場。做兩套序列化 = 兩倍測試成本換零使用者。

---

### D-4：errors-only 過濾 → **第三個維度，預設關閉**（使用者於暫停點主動追加）

**決策**：匯出選單在既有兩個維度（時間窗、來源區段）之外，新增第三個維度——「只包含 error / warning 等級」勾選框，**預設關閉（全收）**。

**正面理由（使用者提出）**：
- 報告更短、訊噪比更高——QA 知道問題就是那幾筆 error 時，不必讓幾百筆 info log 稀釋重點
- **順帶緩解「報告過大」風險**（見 D-5）——一個過濾維度換兩個好處
- **複用已存在但從未被呼叫的 `LogInspector.entriesAtLevel()`**（`log_inspector.dart:21`）。brainstorm #5 已點名這段死代碼，本功能讓它第一次有消費者。零新邏輯。

**反面風險（故預設關閉）**：
使用者可能匯出一份**缺了上下文跟路**的報告——排查最關鍵的線索往往不是 error 本身，而是「error 發生前那幾筆 info log 做了什麼」。若預設開啟，會系統性地把最有價值的上下文從報告中剃掉，而 QA **不會知道自己剃掉了什麼**。**因此預設關閉：讓「完整上下文」成為預設路徑，errors-only 是使用者明確做出的取捨。**

**範圍界線**：
- **只影響報告的 log 區段**。network / nav / db 區段完全不受影響（AC-12）——network 的錯誤過濾已有 `NetworkStatusGroup` / Error Summary 負責，不在此重複。
- **不動 ConsoleTab 的 UI**（AC-23）。brainstorm #5 的搜尋欄 / LogLevel FilterChip 仍維持 out of scope。

**實作注意（留給 STAGE 0b）**：`entriesAtLevel(LogLevel)` 是**精確等級比對**（`e.level == level`），不是「最低等級以上」過濾。要同時取 error + warning，需呼叫兩次後合併，並重新按 `timestamp` 降序排序以維持 newest-first 慣例。（`LogLevel` enum 的宣告順序 `verbose < debug < info < warning < error` 也支援 index-based 的最低等級過濾——選哪種寫法由 STAGE 0b 決定；AC-13 只要求不重寫等級過濾邏輯。）

---

### D-5：報告大小 → 靠預設值緩解，不做硬性截斷

500 筆 network entries × 完整 request/response body 可能產生數 MB 的字串。`shareText` 走 `SharePlus.instance.share(ShareParams(text: ...))`（io）與 Web Share API（web），兩者對超長純文字的行為都**未經本專案驗證**。

**緩解**（具體數值留給 STAGE 0b）：時間窗預設 `last 5m`（而非 `all`）+ errors-only 選項（D-4）。**規格層級的要求**：報告不得因為過大而讓 app 無回應或崩潰。

---

### D-6：資料來源 → 分區段，不用混合時序

`InspectorRegistry.mergedTimeline({sources})` 已經做完聚合（按 source 過濾 → 合併四 buffer → 按 timestamp 降序）。但 brainstorm 描述的是「**各區段**」，且分區段對閱讀者更友善（工程師會先跳到 Network 段）。

**決策**：報告**分區段**呈現，每段內部沿用 buffer 的 newest-first 順序。`mergedTimeline` 的 source 過濾能力仍可複用。

**型別分派**：若走 `mergedTimeline`，回傳的 `List<TimestampedEntry>` 需按具體型別分派序列化——**這個 pattern 已有生產先例**：`console_tab.dart` 的 `_EntryRowDispatcher` 就在做同一件事（依 entry 型別選 row widget）。報告只是把「選 widget」換成「選 formatter」。

---

### D-7：Builder 簽章 → 純函式，不吃 `FlutterInspector`

brainstorm 寫的是 `buildDiagnosticReport(inspector, {...})`。但既有慣例（`network_formatters.dart` 檔頭）明文寫著：

> Pure formatting helpers for the Network inspector. **No Flutter dependencies**, so everything here is unit-testable in isolation.

`FlutterInspector` import 了 `package:flutter/widgets.dart`。讓 formatter 吃它會把 Flutter 相依拖進 `utils/`，破壞既有純度慣例，且讓 unit test 被迫建構整個 inspector。

**決策**：核心 builder 吃**原始資料**（entry lists + 選項 + redact flag + device info），保持純函式（AC-1）；UI 層負責把 inspector 的欄位拆開餵進去。

---

### D-8：公開 API 面 → **不 export 到 barrel**（device info 介面除外）

`lib/flutter_inspector_kit.dart` 只 export 7 個檔；`TimelineSource` / `LogEntry` / `NavigatorEntry` / `DatabaseEntry` **都沒有被 export**。若把 report builder 設為公開 API，其參數型別必須一併 export = 擴大公開 API 面。

**先例**：error-aggregation（v1.3.0）的 `aggregateNetworkErrors()` 明確決定「放在 `src/utils/`，**不從 barrel file 匯出**」。

**決策**：report builder **不 export**。這個功能的使用者是「按 dashboard 上那顆按鈕的 QA」，不是「programmatic 呼叫 builder 的開發者」——沒有已知的 programmatic 消費者，YAGNI。

**例外**：D-1 的 device info 注入介面**必須 export**（host 要 implement 它），比照 `DatabaseBrowserSource` 已在 barrel 中的處理。

---

## 風險與破壞性評估

| 面向 | 風險 | 評估 |
|------|------|------|
| **既有公開 API** | 🟢 零破壞 | 純新增：`DashboardModal` 的 AppBar `actions:` 目前是空的（`dashboard_modal.dart:47`），新增 action 不動任何既有簽章。`FlutterInspector` 既有 getter/method 全部不動。D-1 會新增一個**可選**建構參數（default null）——與 `redactSensitiveData` / `captureUncaughtErrors` / `databaseSources` 的既有擴充模式一致，不破壞既有呼叫端 |
| **既有序列化路徑** | 🟢 零破壞 | 報告**呼叫** `buildPlainText` / `buildLogPlainText` / `entriesAtLevel`，不修改它們 |
| **ConsoleTab** | 🟢 零破壞 | errors-only 只在匯出選單，ConsoleTab UI 完全不動（AC-23） |
| **敏感資料外洩** | 🔴 **最高風險** | 見下方專節 |
| **報告過大** | 🟡 中等 | 見 D-5。緩解：預設時間窗 5m + errors-only 選項 |
| **新增 pub 相依** | 🟢 零新增 | D-1 裁決為 host 注入，相依維持 4 個（AC-6） |
| **Web 相容性** | 🟢 已有先例 | `shareText` 已有 io/web 條件匯出（`share_text.dart:8`）。報告 builder 不引入 `dart:io`（AC-24） |
| **效能** | 🟢 可忽略 | O(N) 遍歷 + 字串串接，N ≤ 500（`RingBuffer.capacity`）。使用者按下按鈕時才執行，不在 build path 上 |
| **版本說謊** | 🟡 已納管 | 前置項 P-1 + AC-3 |

---

### 🔴 敏感資料外洩：既有 redaction 的實際覆蓋範圍（誠實留痕）

> **這一節記錄 STAGE 0a 的 codebase 調查結果，不得在後續修訂中被刪除或淡化。**

`redaction.dart` 的 `redactHeaders()` **只遮 4 個 header key**（`authorization` / `cookie` / `set-cookie` / `x-api-key`）。它**不遮**：

| 未遮蔽的資料 | 證據 | 具體洩漏樣態 |
|---|---|---|
| **query parameters** | `network_formatters.dart:117-121` 原文輸出 | `?api_key=xxx` 明文出現在報告中 |
| **request / response body** | `network_formatters.dart:125-143` 原文輸出 | `{"access_token": "..."}` 明文出現在報告中 |
| **log entry 的 message / data** | `log_formatters.dart:8` `buildLogPlainText()` **連 `redact` 參數都沒有** | `LogEntry.data` 整包明文印出 |

**這不是本功能引入的漏洞。** 今天單筆分享一個 network entry，body 裡的 token 就**已經**是明文外送了。

**但本功能會放大它的爆炸半徑**：

| | 洩漏面 |
|---|---|
| **現況（單筆分享）** | 1 筆 → 剪貼簿 / share sheet，通常是開發者自己看 |
| **本功能（診斷報告）** | 最多 500 筆 → share sheet → **貼進 issue tracker / 聊天群組**。接收面更廣、更持久，且 QA 不會逐筆檢查內容 |

**使用者已裁決（D-2）**：本次維持現狀遮蔽範圍（不擴大），並以表頭 `Redaction: enabled/disabled`（AC-17）誠實告知收件人。

**後續項目（建議單開 issue）**：擴大 redaction 到 request / response body、query parameters、`LogEntry.data`。這是獨立功能的份量——body redaction 是遞迴 JSON 走訪 + 敏感 key 啟發式，不是 4 個 header key 的 set lookup；且它會**改變既有單筆分享的行為**，屬於需要獨立評估的破壞性變更。

---

## 核心判斷

✅ **值得做。**

理由：排查鏈條的最後一環（「帶走證據」）目前是紅燈——Navigator / Database tab 連分享按鈕都沒有，QA 只能截圖。而所需的零件**全部已經存在**：`mergedTimeline`（聚合）、`buildPlainText` / `buildLogPlainText`（序列化）、`NavigatorStackResolver`（堆疊快照）、`entriesAtLevel`（等級過濾，**寫好了從沒被呼叫過**）、`shareText`（平台自適應輸出）。這是組裝，不是發明。

原本需要動腦的兩件事已由使用者裁決：device info 相依策略走 IoC（brainstorm 的「可選相依」在 Dart 根本不存在）、redaction 維持現狀範圍並誠實明示。唯一的前置債是 `FlutterInspector.version` 這個過期常數——本功能會讓它第一次有消費者，必須先修。

---

## 相關文件

- Brainstorm 原始描述：[2026-07-12-features-brainstorm.md](../brainstorm/2026-07-12-features-brainstorm.md) §3（另 §5 為 errors-only 所複用的 `entriesAtLevel` 出處）
- 敏感資料遮蔽（redaction 現況）：[2026-06-27-sensitive-data-redaction.md](./2026-06-27-sensitive-data-redaction.md)
- 當前路由堆疊（可複用的 `NavigatorStackResolver`）：[2026-07-01-navigator-active-stack.md](./2026-07-01-navigator-active-stack.md)
- 混合時序軸（可複用的 `mergedTimeline`）：[2026-06-26-console-merged-timeline.md](./2026-06-26-console-merged-timeline.md)
- 「不 export 到 barrel」的先例：[2026-07-10-error-aggregation-summary.md](./2026-07-10-error-aggregation-summary.md)
- 可複用的序列化：[network_formatters.dart](../../lib/src/utils/network_formatters.dart)、[log_formatters.dart](../../lib/src/utils/log_formatters.dart)
- 可複用的等級過濾：[log_inspector.dart](../../lib/src/inspectors/log_inspector.dart)
- 可複用的分享：[share_text.dart](../../lib/src/utils/share_text.dart)
- IoC 相依注入先例：[database_browser_source.dart](../../lib/src/models/database_browser_source.dart)
- AppBar 擴充點：[dashboard_modal.dart](../../lib/src/ui/dashboard/dashboard_modal.dart)
