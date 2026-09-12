# 實作計畫：Agent 交接 Prompt

**日期**：2026-09-12
**狀態**：待確認
**功能規格**：`docs/features/2026-09-12-agent-handoff-prompt.md`

> 本文件只談 **How**（資料結構、檔案異動、任務拆分）。
> What & Why、驗收條件、範圍邊界見功能規格。

---

## A. 路由錨點補齊

### A.1 現況

`_currentTopPageLabel()`（`flutter_inspector.dart:439`）已存在且已在跑，但**只餵給
`LogEntry`**（`:380`）。Network / DB 兩源飛盲——四源攤平後，只有 log 知道自己發生在哪一頁。

### A.2 改動範圍

| model | 動作 | 理由 |
|---|---|---|
| `NetworkEntry` | `+ String? activeRoute` | 發起頁面未知 |
| `DatabaseEntry` | `+ String? activeRoute` | 執行頁面未知 |
| `NavigatorEntry` | **不加**，改抽 getter | 見 A.3 |

### A.3 為何 Navigator 不加

`activeRoute` 問的是「這件事發生時使用者在哪一頁」。`NavigatorEntry` 記錄的事
**就是頁面本身**（`action` + `routeName`）——加了等於「在 /checkout 這頁，發生了
『進入 /checkout』」，同一事實講兩次。

邊界情況會立刻現形：`pop` 該填離開前還是離開後？**這問題難答正是因為它不該被問。**
消滅特殊情況優於新增判斷分支。

另：`_currentTopPageLabel()` 的資料源頭本就是 navigator 堆疊，讓 `NavigatorEntry`
帶一份從自己推導的值，是不必要的資料複製。

### A.4 採集時機（唯一需裁決的設計點）

`NetworkEntry` 有 pending→completed 非同步生命週期（`isComplete` + `copyWith`）。

**錨點記在發起時（`dio_interceptor.dart` 的 `onRequest`），`copyWith` 不覆寫。**

理由：排查問的是「誰發出了這個請求」，那是發起時的頁面。請求飛行中使用者可能已換頁，
完成時記錄會指向無辜頁面——**看似完整的答案比沒有答案更危險**。

`DatabaseEntry` 為同步，無此問題。

### A.5 `routeLabel` 收斂（順帶消滅漂移點）

`activeRoute` 存的是**組合字串** `'CheckoutPage (/checkout)'`（`displayName` +
`routeName`），而 `NavigatorEntry` 只有分開的欄位。C 的回溯需比對兩者，格式對不上。

解法不是新增欄位，而是**把公式收斂成一處**：

```dart
// navigator_entry.dart
String get routeLabel => (routeName == null || routeName!.isEmpty)
    ? displayName
    : '$displayName ($routeName)';
```

`_currentTopPageLabel()` 改為呼叫它。

> **這是 §P7 的教訓應用**：該案動工才發現「網路請求是否失敗」的判定在三處各手寫一份
> 且已漂移，最後收斂成 `NetworkEntry.isFailed`。本案**在動工前就避免新增第二個實作點**。

---

## B. `buildAgentPrompt()`

### B.1 落點

新檔 `lib/src/utils/agent_prompt.dart`，純函式、同步、不碰 `BuildContext`、不寫磁碟
（與 `buildDiagnosticReport` 同一份紀律）。

掛載點為兩個既有 detail view 的 `PopupMenuButton`：

| 檔案 | 既有 enum | 新增值 |
|---|---|---|
| `console/log_detail_view.dart` | `{copyConcise, copyRaw, shareConcise, shareRaw}` | `+ copyAgentPrompt` |
| `network/network_detail_view.dart` | `{curl, text, share}` | `+ agentPrompt` |

> 兩個 enum 為各自私有且形狀不同，**故 B 是兩個獨立呼叫點共用一個 formatter**，
> 不是一次共用的 UI 改動。此結構沿用既有設計，不重構。

§P4 原估 `trivial~low`（「既有選單多加一個 enum 值 + 一個組裝 formatter」），本案沿用該結構。

### B.2 輸出結構

```
## Runtime observation — flutter_inspector v{version}

{邊界宣告：2 行固定文字}

### Observed failure
{錨點 entry 全欄位展開 + Active Route}

### Where                          ← stackTrace 為 null 時整段省略
{normalizeStackTrace() 輸出}

### Earlier on this route ({route})
{截斷揭露行}                        ← 僅在觸發 C 出口 2/3 時出現
{同頁前序事件，每筆一行}

### Task
Investigate the cause in this codebase and propose a fix.
```

完整範例見 §E。

### B.3 鄰近事件的渲染

複用既有 one-liner formatter（`buildLogOneLiner` / `buildNetworkOneLiner`），
**但需剝除 log 行尾的 `(Active Route: ...)`**——該區塊內所有行同屬一個 route，
逐行重複是雜訊。

### B.4 body 截斷

複用既有 `NetworkEntry.truncateBody()`。一致性優先且已有先例。

---

## C. 回溯邊界

### C.1 為何不用時間窗

±5s 的假設是「時間近 ≈ 有因果」。此假設兩邊都塌：

* **會撈進無關的事**：背景 analytics、心跳輪詢、圖片預載、其他頁面未取消的請求全進來，
  而 agent 無從分辨哪些相干。
* **會漏掉相關的事**：使用者進頁後滑了 8 秒才觸發，元凶在窗外被切掉。

放寬 N 只會讓第一個問題更嚴重。**沒有一個 N 能同時解決兩邊，因為時間不是因果的載體。**

這正是 §D3 與 §P2 的共同死因（原文：「一個用固定時間窗猜、一個用固定維度猜」）。

### C.2 同頁為何不是猜

`activeRoute` 是**當下記錄的事實**，非事後推導的關聯。「同 route 且早於錨點」篩出的是
**確實發生在同一使用者情境、且在它之前**的事件——事實查詢，非相關性猜測。

「早於」單向取用（不取之後）：因在果之前，這是因果的必要條件。時間窗的 ± 連這點都沒守住。

### C.3 為何不算重蹈 §D3 覆轍

| | §D3 | 本案 |
|---|---|---|
| 形式 | 常駐側欄，改變主視圖資訊架構 | 按下才產生的一次性匯出 |
| 篩選依據 | 猜（時間窗） | 事實（已記錄的 route） |
| 前提 | 當年**無** `activeRoute`，只能用時間窗 | A 落地後才成立 |

**A 讓一個原本只能用猜的篩選，變成可以用事實。** 故 A 與 B 是咬合關係，非先後兩件事。

### C.4 邊界規則

```
邊界 action = {push, replace}
同 route 比對鍵 = NavigatorEntry.routeLabel（A.5）

從錨點往回掃同 route 的事件：
  出口 1：遇該 route 的 push/replace → 停（天然邊界，無需揭露）
  出口 2：掃滿 maxTraceBackEntries   → 停 + 揭露截斷
  出口 3：掃到 buffer 底              → 停 + 揭露「無進入點」
```

**三個出口，兩個需揭露。** 無特例分支——一個迴圈加三個終止條件。

> **實查修正**：`NavigatorAction` 實為 `{push, pop, replace, remove}`。
> **`replace` 也是進入頁面**（`pushReplacement`），原設計只認 `push` 會漏。

### C.5 出口 2／3 的揭露文字

```
出口 2：(showing the 50 most recent of 1,138 events on this route)
出口 3：(no route entry point in buffer; showing the 50 most recent of 1,138)
```

**揭露是必要的，不是裝飾。** 沉默地從「回溯到進入點」退化為「回溯 N 筆」，agent 會
以為看到了完整頁面歷程——即 §D4 的否決死因（*搜到 2 筆卻不知另有 800 筆未載入，
比沒有搜尋更危險*）。**截斷本身沒問題，沉默的截斷才有問題。**

### C.6 同 route 多次進入

`/room/4471` 可能 push → pop → push。回溯須停在**最近一次** push/replace，
否則會撈進前次造訪的事件（不同使用者情境）。實作即「從錨點往回掃，遇第一筆即停」，
天然滿足，無需額外邏輯。

### C.7 不處理的情況

tab 切換（IndexedStack，可能不產生 navigator 事件）、巢狀 Navigator——
**由出口 3 自然接住，不寫特例分支。**

### C.8 參數

比照 `slowRequestThreshold` 先例（宣告 → 文件 → 預設 → 驗證）：

```dart
final int maxTraceBackEntries;   // 預設 50，拒絕 <= 0
```

多數情況碰不到它（出口 1 先觸發）；它只是長駐頁面的保險絲。

---

## D. 任務拆分

> `pause_level=balanced`，故任務間不停，STAGE 2 整體完成後才暫停。

| # | 任務 | 寫入路徑 | 相依 | Effort |
|:--:|---|---|:--:|:--:|
| **T1** | `NavigatorEntry.routeLabel` getter + `_currentTopPageLabel()` 改呼叫它 | `navigator_entry.dart`、`flutter_inspector.dart` | — | trivial |
| **T2** | `NetworkEntry` / `DatabaseEntry` 加 `activeRoute`（含 `==`/`hashCode`/`copyWith`） | `network_entry.dart`、`database_entry.dart` | — | low |
| **T3** | 採集接線：`onRequest` + database inspector | `dio_interceptor.dart`、`database_inspector.dart` | T2 | low |
| **T4** | `agent_prompt.dart` + 測試 | `utils/agent_prompt.dart`（新）、`test/utils/agent_prompt_test.dart`（新） | T1, T2 | med |
| **T5** | 兩個 detail view 各加 enum 值與 case | `log_detail_view.dart`、`network_detail_view.dart` | T4 | low |
| **T6** | `maxTraceBackEntries` 參數化（含負值驗證） | `flutter_inspector.dart` | T4 | trivial |

**並行性**：T1 與 T2 寫入路徑不重疊，可並行。T3 依賴 T2；T4 依賴 T1+T2；T5、T6 依賴 T4。
故執行順序為 **`[T1 ‖ T2] → T3 → T4 → [T5 ‖ T6]`**。

> ⚠️ T1 觸碰 `flutter_inspector.dart`，T6 亦然——但兩者**時序上不重疊**（T1 在最前、
> T6 在最後），非同批並行，無衝突。

**T1 為純重構**：既有測試須全綠，確認 `routeLabel` 與原 `_currentTopPageLabel()` 公式等價。
此為後續任務的地基，失敗則整條停。

---

## E. 輸出範例

### E.1 網路超時（完整形狀，回溯出口 1）

````markdown
## Runtime observation — flutter_inspector v2.4.0

**This is an execution-time observation, not a static-analysis conclusion.
The cause is unknown. Do not assume the failing line is the faulty one.**

### Observed failure

[14:30:04.871] [LOG/error] Failed to load cart
Active Route: CheckoutPage (/checkout)

Data:
  cartId: 8842
  retryAttempt: 2

### Where

package:my_app/features/checkout/cart_controller.dart 88:7   CartController._load
  <-- async gap -->
package:my_app/data/api_client.dart 142:3                    ApiClient.get
  [... 14 frames of framework internals]
package:my_app/features/checkout/checkout_page.dart 61:5     _CheckoutPageState.initState

### Earlier on this route (CheckoutPage (/checkout))

[14:30:04.870] [NET] GET /api/cart ✗ connectionTimeout
[14:30:02.118] [DB]  read cart_items (12 rows)
[14:30:01.940] [LOG/info] Cart cache miss, fetching remote
[14:30:01.902] [NET] GET /api/promo → 200 (81ms)
[14:30:01.310] [LOG/debug] Restoring checkout draft
[14:30:00.884] [NAV] push CheckoutPage (/checkout)

### Task

Investigate the cause in this codebase and propose a fix.
````

**讀法**：`✗ connectionTimeout`（04.870）→ error log（04.871），相隔 1ms，
**因果自時間軸浮出，非由工具宣告**。末行 push 即回溯出口 1，無揭露行。

### E.2 500 錯誤（無 stackTrace，`### Where` 整段消失）

````markdown
### Observed failure

[09:12:44.201] [NET] POST /api/orders → 500 (1204ms)
Active Route: ConfirmPage (/checkout/confirm)

Request headers:
  content-type: application/json
  authorization: ***REDACTED***

Request body:
  {"cartId":8842,"couponCode":"SUMMER26","addressId":17}

Response body:
  {"error":"coupon_expired","detail":"SUMMER26 expired 2026-09-01"}

### Earlier on this route (ConfirmPage (/checkout/confirm))

[09:12:43.980] [LOG/debug] Submitting order, cart=8842
[09:12:41.677] [NET] GET /api/coupons/SUMMER26 → 200 (94ms)
[09:12:41.550] [NAV] push ConfirmPage (/checkout/confirm)

### Task

Investigate the cause in this codebase and propose a fix.
````

**線索在 response body 的 `coupon_expired`，而 2 秒前查詢回 200**——
兩筆並陳讓矛盾自己現形，**工具一句結論都沒下**。

### E.3 長駐頁面（回溯出口 2）

````markdown
### Earlier on this route (RoomPage (/room/4471))

(showing the 50 most recent of 1,138 events on this route)

[16:48:02.330] [LOG/debug] Rendering 84 messages
[16:48:02.101] [NET] GET /api/rooms/4471/messages → 200 (142ms)
[16:48:01.998] [DB]  write messages (1 row)
...
[16:45:12.003] [LOG/info] Socket reconnected
````

---

## F. 破壞性分析

**零破壞。**

* 新增 nullable 欄位，預設 `null`
* `RingBuffer.onMutate` → `revision` 單一變更通道**不動**
* `mergedTimeline()` **不動**
* **不新增 `TimelineSource`**（Anti-Feature #6）
* 不新增 tab、不新增相依

⚠️ **`NetworkEntry` 的 `==` / `hashCode` 為手寫**（`:162` / `:183`），新欄位漏改會
**靜默失效**。`DatabaseEntry` 同須檢查。

---

## G. 測試策略

`test/utils/agent_prompt_test.dart`（新）：

| 案例 | 驗證 | 對應 AC |
|---|---|:--:|
| 邊界宣告 | 任何 entry 型別皆存在 | INV-1 |
| `stackTrace == null` | `### Where` 整段不存在，且不含 `(none)` | INV-2 |
| redact 生效 | `authorization` 遮罩 | INV-3 |
| 回溯出口 1 | 停在 push/replace，無揭露行 | AC-4 |
| 回溯出口 2 | 揭露行含正確總數 | INV-5 |
| 回溯出口 3 | 揭露「無進入點」 | INV-5 |
| 同 route 多次進入 | 只回溯到最近一次 push | AC-5 |
| `replace` 作為邊界 | 與 push 同等對待 | AC-4 |
| 前序事件單向性 | 不含晚於錨點的事件 | AC-3 |
| one-liner 去重 | 鄰近事件行不含 `(Active Route: ...)` | B.3 |

model 層：`NetworkEntry` / `DatabaseEntry` 的 `==`、`hashCode`、`copyWith`
各補 `activeRoute` case；`NavigatorEntry.routeLabel` 的 null / empty routeName 分支。

`_currentTopPageLabel()` 改用 `routeLabel` 後，既有測試須全綠（確認公式等價）。

**基準**：`flutter test` 現為 610 tests；`flutter analyze lib/ test/` 既有 7 個 info，
**唯有超出這 7 個才是本次引入**。

---

## H. 相依假設（動工前必讀）

`normalizeStackTrace()`（`log_formatters.dart:95`）目前只折疊 `package:flutter/`
與 `dart:` 兩類幀，故 **`package:dio/` 的幀會被保留**——對網路類失敗恰好是關鍵定位。

⚠️ **若日後擴大折疊規則至「所有 `package:`」，本案產出的 prompt 會失去該定位。**
修改 `normalizeStackTrace()` 時須一併評估對 `buildAgentPrompt()` 的影響。
