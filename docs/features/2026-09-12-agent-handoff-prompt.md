# 功能規格：Agent 交接 Prompt

**日期**：2026-09-12
**狀態**：待確認
**實作計畫**：`docs/plans/2026-09-12-agent-handoff-prompt-plan.md`
**相關**：§P4（快速複製 Diagnostic Snippet）、§P9（JSON 輸出）、§P19（StackTrace 正規化，已完成）
**否決參照**：§D3（±5s 側欄）、§P2（錯誤上下文快照）、§D4（表內資料搜尋）

---

## 1. 問題陳述

排查鏈條的八個環節已全綠（見 features-brainstorm 現況盤點），四源已由
`mergedTimeline()` 攤平。**剩餘瓶頸不在採集，在判讀**——資料都在了，但要靠人腦逐筆掃。

同時存在一個能力互補的缺口：

| | flutter_inspector | coding agent |
|---|---|---|
| 執行期事實（實際發生了什麼） | ✅ 有 | ❌ 沒有 |
| codebase（為什麼會這樣） | ❌ 沒有 | ✅ 有 |

**兩邊補的正好是對方的盲區。** 目前缺的是把前者交接給後者的動作。

現況下使用者的動線是：匯出 Markdown 報告 → 手動貼給 AI → 問「這裡出了什麼事」。
這條路已經通，但**匯出的報告是為人眼設計的，不是為 agent 消費設計的**——
它是一份扁平的全域時間軸，agent 拿到後無從判斷哪些事件與問題相關。

## 2. 使用者故事

> 身為開發者／QA，當我在 Console 或 Network tab 看到一筆可疑的錯誤，
> 我希望能一鍵複製一段**已經聚焦、且誠實標明邊界**的交接文字，
> 直接貼給 coding agent，讓它帶著執行期事實去 codebase 裡查原因，
> 而不必由我手動摘錄前後文、也不必擔心它把工具的猜測當成事實。

## 3. 核心判斷

✅ **值得做**。但形狀必須是「**產出 agent 能吃的東西**」，不是「**內建 AI 面板**」。

內建 LLM 呼叫會撞上三條既有約束，均為明文否決：

| 既有約束 | 出處 |
|---|---|
| 資料不出裝置 | Anti-Feature #1 附帶結論（明文否決 sentry/crashlytics「方向相反」） |
| 不引重量級相依 | CLAUDE.md §2.5 |
| 不落盤、不當資料庫 | Anti-Feature #2（API key 存放問題） |

**第四條未成文但更致命**：本 kit 為 debug-only 工具。Anti-Feature #1 否決掉幀偵測的
死因是「debug build 誤判不是邊緣情況，是唯一情況」。同一把刀砍向 LLM 因果推論——
**產出看似篤定的推測，比不給結論更危險**（同 §D4 判準：部分覆蓋比零覆蓋更危險）。

### 3.1 與 §P9 的關係

§P9 原描述為「JSON 結構直接映射既有 section，不引入新 schema」，服務 CI／Slack bot，
評級 ⭐⭐。**本案不是 §P9**：那是機械式 Markdown→JSON 轉寫，給 LLM 的是同一份扁平
資料換標點符號，理解度零改善。本案的價值在**路由錨點**與**回溯邊界**（見實作計畫）。

### 3.2 與 CodeRabbit 模式的差異

參照 CodeRabbit 的 "Prompt for AI Agents"（每則 review comment 下的可折疊區塊，
內容為寫給 coding agent 的祈使句）。其四個特徵與本 kit 的對應：

| CodeRabbit 特徵 | inspector 有嗎 | 本案產出 |
|---|---|---|
| 定位（file:line） | 部分有（`stackTrace` + §P19 已正規化） | 折疊後呼叫點 |
| 觀測事實 | 完全有 | entry 全欄位 + 同頁前序事件 |
| **要做什麼** | **沒有** | **誠實留白** |
| 邊界 | 可以有 | 「執行期觀測，非靜態分析結論」 |

CodeRabbit 能寫祈使句是因為它做過 review、有結論；inspector 只有觀測。
**照抄祈使句形狀會踩 §D4 的雷**。故第三格留白，由結尾 Task 交給 agent 自行調查。

---

## 4. 驗收條件

### 4.1 功能面

| # | 條件 |
|---|---|
| AC-1 | Console tab 的 log detail view 選單可複製 agent prompt |
| AC-2 | Network tab 的 network detail view 選單可複製 agent prompt |
| AC-3 | Prompt 含邊界宣告、錨點事實、定位（若有）、同頁前序事件、Task 結語 |
| AC-4 | 前序事件回溯至該 route 的進入點（`push`／`replace`）為止 |
| AC-5 | 同 route 多次進入時，只回溯到**最近一次**進入點 |
| AC-6 | 回溯遭截斷或找不到進入點時，**必須揭露** |

### 4.2 不變式（任一違反即不通過）

| # | 不變式 | 說明 |
|---|---|---|
| INV-1 | 邊界宣告必存 | 固定文字，任何情況不省略 |
| INV-2 | 空段落不輸出 | 無 stackTrace 時整段消失，**不印 `(none)`**（空段落對 agent 是雜訊） |
| INV-3 | 一律套 redact | 沿用 `FlutterInspector.redactSensitiveData`，與既有分享路徑同一份判定 |
| INV-4 | **零猜測** | 無「可能是」「建議檢查」；錯誤型別僅原樣轉述 enum 名 |
| INV-5 | 截斷必揭露 | 沉默的截斷會讓 agent 誤以為看到全部（§D4 死因） |
| INV-6 | 結尾固定 | Task 一句，不隨 entry 型別變化 |

### 4.3 品質面

| # | 條件 |
|---|---|
| AC-7 | `flutter test` 全綠（基準 610 tests） |
| AC-8 | `flutter analyze lib/ test/` 不超出既有 7 個 info |
| AC-9 | 零破壞：不動 `RingBuffer.onMutate` → `revision` 通道、不動 `mergedTimeline()`、不新增 `TimelineSource` |

---

## 5. 範圍邊界

### 5.1 範圍內

* 三源（`LogEntry` 已有／`NetworkEntry`／`DatabaseEntry`）的路由錨點補齊
* 單筆錨點的 agent prompt 產生器
* 兩個既有 detail view 的選單掛載

### 5.2 範圍外（已否決，記錄以免重提）

| 變體 | 否決理由 |
|---|---|
| 內建 LLM 分析面板 | 撞四條約束（§3），且 debug build 下產出自信的錯誤結論 |
| prompt 含「建議怎麼修」 | inspector 只有觀測無結論，猜錯成本由使用者承擔（§D4 判準） |
| 往後取 N 筆事件 | 會讓「因在果之前」長出例外，且目前無證據說需要 |
| 範圍框選（多筆錨點） | YAGNI；形狀與成本皆大幅不同，待實際需求出現再議 |
| `NavigatorEntry` 加 `activeRoute` | 自我指涉；`pop` 無法填；值可從自身算出 |
| §P9 式 Markdown→JSON 轉寫 | 同一份扁平資料換標點，理解度零改善（§3.1） |

---

## 6. 階段性價值

實作計畫的 A 部分（路由錨點）**獨立有價值**：時間軸按頁分段後，
人眼直接受益（看得出「這批請求都發生在結帳頁」），**即使 B'（prompt 產生器）不做也站得住**。

故本案不是一個全有全無的賭注——A 落地即有回報，B' 是其上的加值。
