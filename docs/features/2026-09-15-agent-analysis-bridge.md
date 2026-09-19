# §P27. Agent 分析橋接（Agent Analysis Bridge）— 設計文件

> **狀態**：🟡 **設計中、未排程、尚未動工**（2026-09-16）
>
> **本文件是 [`docs/brainstorm/2026-09-19-features-brainstorm.md`](../brainstorm/2026-09-19-features-brainstorm.md)
> §P27 的展開**，非已完成功能的紀錄（`docs/features/` 其餘檔案皆為落地後所寫）。
> 發想與裁決脈絡以 brainstorm 為主，本文件保存完整推導與理由。
>
> 三個**實質**問題已裁決（§5.4 / §6.1 / §6.2）；三個**機械**決定待定，集中於 §9。
>
> **前身**：§P26 Agent 交接提示（Issue #160 / PR #161 · 2026-09-12）。本項不取代 §P26，
> 而是把「單筆事件 → 人工貼給 agent」擴展為「LLM 主動查詢 → 分析結果回注」的雙向機制。

---

## 1. 痛點與場景

排查者手上有兩個時刻需要 AI 協助，而 §P26 只覆蓋了其中半個：

| 場景 | 誰在排查 | 何時 | §P26 是否覆蓋 |
|:---|:---|:---|:---|
| **A. 裝置上、當下** | QA 在手機上點一下，畫面直接顯示「這看起來像是 token 過期」 | 事發當下 | ❌ 完全沒有 |
| **B. 開發機、事後** | 開發者在電腦前，agent 能去問「那台機器剛剛發生什麼」 | 事後 | ⚠️ 僅限手動複製單筆 |

**關鍵洞察：A 與 B 不是兩個系統。** 兩者要的是同一份資料，差別只在「誰來讀」與「結果顯示在哪」。
把它們當成兩條路各自設計，會產生兩份真相——這正是不變式 #2 禁止的事。

---

## 2. 核心機制：雙向橋接

```
        ┌──────────────────────────────────────────────────┐
        │                       kit                        │
        │                                                  │
        │   ┌────────────────┐      ┌──────────────────┐   │
        │   │ (1) 查詢能力    │      │ (2) 結果接收介面   │   │
        │   │                │      │                  │   │
        │   │ query()        │      │ addAnalyses(List)│   │
        │   │ getDetail(id)  │      │  · 純 append      │   │
        │   │ traceFrom(id)  │      │  · 不可更新/撤回   │   │
        │   └───────┬────────┘      └─────────▲────────┘   │
        │           │                         │            │
        │           │      ┌──────────────────┴────────┐   │
        │           │      │  分析 tab（獨立，不進時間軸）│   │
        │           │      │  讀取時過濾：引用全失效則隱藏│   │
        │           │      └───────────────────────────┘   │
        └───────────┼─────────────────────────┼────────────┘
                    │                         │
             撈取（tool call）           注入分析結果
             回傳含 entry id             （結論 + 引用 id + 時間戳）
                    │                         │
        ┌───────────▼─────────────────────────┴────────────┐
        │                   Host App                        │
        │          （持有 API key，執行網路呼叫）             │
        └───────────┬─────────────────────────▲────────────┘
                    │                         │
                    └────────►  LLM  ─────────┘
```

> **引用關係的可信度來源**：host 回傳給 LLM 的 tool call 結果**本身就帶 entry id**，
> 因此 host 知道 LLM 實際撈過哪些 entry——引用列表是**事實**，不是模型的自述（§3.3）。

**(1) kit 開具名查詢能力**，host 把它們包成 tool schema 交給 LLM。
LLM 自行決定呼叫哪個、帶什麼參數；host 執行後把結果回傳給 LLM。

**(2) host 把 LLM 的分析結論注入回 kit**，kit 負責顯示。

### 2.1 這個形狀解掉的問題

| 問題 | 為何被解掉 |
|:---|:---|
| 開 port 的資安風險 | 方向是**由內而外**（host 主動打出去），kit 不監聽任何連線 |
| MCP 協定綁定 | host 自己決定怎麼包 schema，kit 不實作任何協定 |
| 套件純淨性（不變式 #5） | kit 只提供**純函式查詢** + 一個結果接收介面，零網路零依賴 |
| A/B 需要兩套機制 | 同一套機制的兩個位置：A 顯示在裝置上，B 由 host 轉送到開發機 |

---

## 3. 邊界裁決（已釘死）

### 3.1 API key 一律由 Host App 持有

**kit 永不內建網路呼叫。**

> **理由（非偏好，是 package 的責任）**：flutter_inspector_kit 是 package，會被裝進別人的 App。
> kit 內建網路呼叫，意味著**每個使用它的 App 都多一條把 log 與 response body 送往第三方的路徑**，
> 而那些 App 的開發者不一定知情。使用者可以為自己的專案決定資料能否離開裝置，
> 但套件不能代替所有下游使用者做這個決定。

連帶結果：不新增任何 pubspec 依賴，不引入 http client，不管理 API key。

### 3.2 分析結果走獨立 dashboard tab，不進 timeline

**推測不得混入事實流。**

> **理由**：分析結果來源是 LLM，不是 kit 的觀測。混進 timeline 會讓「kit 看到的事實」
> 與「模型的推測」長得一樣——而 `agent_prompt.dart` 的 `_kBoundaryNotice` 整段設計核心
> 就是不讓這兩者混淆（明寫 "The cause is unknown"）。推測混入事實流，
> 是這個套件最不該犯的錯。

連帶好處：獨立 tab 天然落在不變式 #3 的**即時查詢型**那一側（由 host 主動塞入、
不產生時序事件、不進時間軸），與 `Storage` 那類 browser source 同族，不觸發緩衝型的爭議。

### 3.3 分析結果必須可追溯（引用關係）

看到一條分析，要能點回去看它是根據**哪幾筆 entry** 講的，並跳回 timeline。

> **理由**：這是「鏈推斷」哲學在分析結果上的延伸。給一句斷言而不給依據，
> 等於退回成「點查詢」——那是本專案明確否決的形狀。

**引用關係必須可信**：它來自 **host 實際執行過的 tool call 回傳值**，
而非 LLM 的自述。模型未必誠實報告它引用了什麼，但 tool call 的結果是事實。

---

## 4. 查詢介面（乙案：三個具語義的查詢）

```dart
query({timeRange, sources, errorsOnly, route, limit})  // 撈時間軸
getDetail(id)                                          // 撈單筆完整內容
traceFrom(id)                                          // 同路由回溯
```

### 4.1 為何不是「一個萬用查詢」

考慮過甲案（單一 `query()` 打死）與丙案（先只開一個，不夠再加）。選乙案的理由：

> `_traceBack()` **已經寫好了**，而它正是這個套件區別於「一堆 log」的地方。
> 若 LLM 只能拿到扁平查詢，它會退化成在一堆 log 裡撈關鍵字，
> kit 的核心價值（鏈推斷）就進不到分析裡。

`traceFrom(id)` 直接暴露 §P26 已驗證的回溯演算法：同 `activeRoute` 且早於錨點、
走到路由進入點即停、觸頂時揭露。**演算法零修改。**

### 4.2 重用既有過濾維度

`query()` 的 `timeRange` / `sources` / `errorsOnly` 三個維度**直接取自
`diagnostic_report.dart`**，不發明新概念。`timeRange` 維持 `Duration?`
（`null` = 全部時間），沿用既有設計理由：「all 的情況否則會變成每個 switch 裡的特殊分支」。

### 4.3 回傳型別與收斂機制

**裁決一：回傳 JSON-safe `Map`，非 `List<TimestampedEntry>`。**

host 終究要把結果序列化餵給 LLM，kit 直接給 Map 省掉中間一層。

**裁決二：不實作分頁，靠 `limit` + `timeRange` 收斂。**

差別在**誰負責縮小範圍**：分頁是 kit 把大結果切片（LLM 翻頁），
收斂是 LLM 換條件重問（`query(timeRange: 30s, errorsOnly: true)`）。

> **三個理由**：
> 1. **LLM 本來就這樣用**——拿到 50 筆雜訊，自然的下一步是換條件重問，
>    而非要第 51–100 筆。翻頁是人類 UI 的習慣，不是 agent 的。
> 2. **🔴 游標會遇上 evict**——buffer 一直在變，翻到第 3 頁時第 1 頁可能已不存在。
>    要正確處理就得引入快照，而**快照撞不變式 #2**（§6.1 已為此否決過一次）。
> 3. **`traceFrom(id)` 已覆蓋「要看更多」的主要情境**——LLM 通常不是想看更多
>    *無關*事件，而是想看某錨點*周圍*的事件，那正是 `traceFrom` 做的事。

**裁決三：🔴 `limit` 截斷必須揭露。**

```dart
{
  'entries': [...],   // 實際回傳
  'total': 200,       // 符合條件的總數
  'truncated': true,  // limit 是否砍過
}
```

> 不揭露的話，LLM 會把 50 筆當成全部，推出「這段時間只有 50 個事件」的錯誤結論。
> 這與 `_traceBack()` 觸頂揭露（§P26）是同一個問題，沿用同一裁決。
>
> **這也正是回傳 Map 而非 List 的必然結果**——`List` 沒地方放 `total` 與 `truncated`。
> 兩個裁決相配，非巧合。

**`limit` 預設 50、上限 200。**

> buffer 才 500 筆，超過 200 已接近「全撈」，那是 `timeRange` 該處理的事，不是 `limit`。
> 此值非一錯即需重來的決定，實測不足再調。

---

## 5. Entry ID（丙案：掛在各 model，不進契約）

三個查詢裡有兩個靠它，引用關係也靠它。這是本設計唯一需要動既有 model 的地方。

### 5.1 為何不加進 `TimestampedEntry` 契約

`TimestampedEntry` 是 `abstract interface class`（只能 implements、不能 extends），
dartdoc 明寫「**存在的唯一理由**是讓 `mergedTimeline` 能用單一型別索取排序鍵」。

> 為了 id 去鬆動一個被刻意鎖死的窄契約，是拿架構不變式換一點型別便利。
> 且它是公開型別，host 若有自訂 entry 實作，新增 required member 屬 breaking change。

### 5.2 實際做法

四個 model（`LogEntry` / `NetworkEntry` / `NavigatorEntry` / `DatabaseEntry`）
各自加 `final String id`，建構時生成。契約不動。

查詢時以 `switch` 取 id——**這不是新發明**：`agent_prompt.dart` 的 `_routeOf()` /
`_stackTraceOf()` 已經是同一個模式（對四個型別 switch，其餘回 null）。

### 5.3 🔴 兩條不可違背的規則

**規則一：`copyWith` 必須繼承 id。**

`NetworkEntry` 的 pending → completed 走 `copyWith` → `RingBuffer.replace(old, new)`。
新 entry 帶**同一個 id**，代表「同一件事的新狀態」。

這讓引用關係與不變式 #2 天然一致：LLM 撈到 pending 狀態的那筆，
分析完成後 id 仍指向同一筆（此時已是 completed），**自動反映最新狀態，不存在第二份真相**。

**規則二：id 排除於 `operator ==` 與 `hashCode` 之外。**

有明確先例：`NetworkEntry.sourceDio` 的 dartdoc 明寫
「deliberately excluded from `operator ==`, `hashCode`」。id 同理——它是身份標籤，不是內容。

> **若把 id 納入 identity**：`copyWith` 一旦漏傳 id 就會生成新 id → `==` 不成立 →
> `RingBuffer.replace()` 找不到目標 → **pending 永遠不會變 completed**。
> 這是個埋在四個 `copyWith` 裡的靜默陷阱，而 `flutter test` 未必抓得到。
> 排除於 identity 之外，`copyWith` 就只需遵守「繼承 id」一條規則。

### 5.4 id 生成：全域遞增計數器 + 來源前綴

**格式**：`<source>_<seq>` — `log_47`、`network_12`、`nav_3`、`db_88`

前綴沿用既有 `TimelineSource` enum 的值（`log` / `network` / `nav` / `db`），
**不另外發明命名**——與 §P26 把路由標籤公式收斂成單一真相來源同個道理。

**序號來自 kit 內部一個全域 `int _seq`**，四個 model 共用，建構時遞增。

#### 為何不是 UUID

> UUID 解決的是「分散式系統中多節點生成不碰撞」——**這個問題在此不存在**。
> kit 是單進程、單來源，計數器完全夠用。
>
> 且 UUID 要嘛引入 `uuid` 套件（新依賴，違反不變式 #5），
> 要嘛自己寫生成邏輯（沒必要的程式碼）。字串還長、不可讀。
> 引入 UUID 等於為一個不存在的威脅付代價。

#### 🔴 為何淘汰所有「與位置有關」的方案

buffer 索引、陣列下標**全部出局**。

> 這些方案會**重用** id：buffer 滿了 evict 掉 `#3`，下一筆新事件又拿到 `#3`，
> 而某條分析仍引用著舊的 `#3` → **指向了完全不同的事件**。
>
> 這比懸空引用更糟——懸空是「看不到」，重用是**靜默的錯誤引用**，
> 使用者會看到一條分析指著無關的事件，卻沒有任何跡象顯示它錯了。

id 必須與「這個物件被創造出來」綁定，與它住在哪裡無關。計數器只增不減，天然滿足。

#### 🔴 兩條 dartdoc 必須鎖住的保證邊界

**其一：前綴是實作細節，host 不得 parse。**

> 前綴存在的唯一理由，是讓 kit 內部的 `getDetail(id)` 直接路由到正確 buffer，
> 而非四個都掃。它**不是**給 host 解析來源用的公開格式。
>
> 不明講的話，host 會開始從 `'log_47'` 推出「這是 log」，
> 那會把一個實作細節變成事實上的公開契約。
> 先例：`NetworkEntry.sourceDio` 的 dartdoc 同樣用文字鎖住意圖。

**其二：id 僅在單次 App 生命週期內有效。**

計數器跨重啟重置。

> kit 沒有永久儲存，重啟後 buffer 全空、分析全沒，舊引用連同分析一起消失——
> **kit 內部不可能出錯**。
>
> 但 host 拿得到 JSON，他要自己存 kit 攔不住；重啟後 `log_1` 會指向完全不同的事件。
> 既然攔不住，就明講保證邊界到哪為止——這與 `_traceBack()` 觸頂時揭露、
> `buildAgentPrompt` 不給推測原因是同一條紀律：
> **講清楚自己不保證什麼，比假裝保證更有用。**

---

## 6. 分析結果的生命週期與注入介面

### 6.1 分析結果的生命週期：綁引用，讀取時過濾

**前提（使用者裁決）**：kit **沒有永久儲存功能**，因此
> **「一條指向已消失事件的分析，沒有價值。」**

這句話解掉了整個「持久化」問題——它是個**假問題**。分析結果本來就該與 buffer 同生命週期。

**裁決一：分析結果的存活綁「它引用的事件」，不綁自己的數量上限。**

> 若分析結果只是自己進一個獨立 `RingBuffer`，會因兩者產生速率差太多而失效：
> 事件每秒數十筆，分析可能整場 QA 只有 3 條。分析 buffer 遠未滿時，
> 它引用的事件早被擠光——**懸空引用只是換個地方發生**。

**裁決二：不動 `RingBuffer`，改為讀取時過濾。**

```
讀分析 tab → 對每條分析，查它引用的 id 是否還在四個 buffer 裡
          → 全部都不在 → 不顯示（等同已移除）
```

> **為何不加 `onEvict` callback**（曾考慮並否決）：
> 那條路要改核心類別、四個 inspector 全受影響，且**新增一條 evict 通知通道
> 正面撞上不變式 #1**（`onMutate` → `revision` 是唯一變更通道）。
>
> 而讀取時過濾語義更正確：在**需要知道答案的那一刻**去問，
> 而不是維護一份可能不同步的狀態。這與 §P25 ImageCache 的裁決同一道理——
> 「在使用者主動查看的那一刻讀取，那個時點的值是真的」。
>
> 成本可忽略：500 筆 × 數條分析的掃描量級。

**裁決三：全部引用都不在時才隱藏（寬鬆策略）。**

部分失效（5 筆引用剩 3 筆）時分析結果**仍顯示**。

> 🔴 **連帶的 UI 義務（歸第 4 題）**：部分失效時，UI **必須誠實揭露**
> 「其中 N 筆已不在緩衝區」，不得讓已失效的引用看起來仍可點擊卻無反應。
> 同一條紀律貫穿本套件：`_traceBack()` 觸頂會揭露、`buildAgentPrompt` 不給推測原因。

### 6.2 注入介面：唯一 append 的批次介面

**裁決一：不可更新、不可撤回。純 append。**

> LLM 會改口（第一輪「像 token 過期」，追問後改成「refresh 打在錯的 endpoint」）。
> 處理方式是**再注入一條新的**，舊的留著。
>
> 「沒有永久儲存」這個前提同樣適用於此：整場 QA 結束就沒了，
> 累積幾條矛盾結論的成本，低於引入一套更新／撤回語義的成本。

**連帶結果：分析結果不需要自己的 id。** 沒有東西要被指定去修改。
（引用的 entry id 仍然需要，那是 §3.3 的可追溯要求。）

**裁決二：時間戳為必要欄位，非可選。**

> 由裁決一推出：不可更新意味著 tab 上會累積矛盾結論。
> 使用者分辨「哪條是後來的判斷」唯一的依據就是時間。
> 兩條矛盾結論並列而無法判斷先後，比沒有分析更糟。
>
> 注意：此時間戳**不是排序鍵意義上的 timestamp**——分析結果不進 timeline（§3.2），
> 不實作 `TimestampedEntry`。

**裁決三：只開批次介面，收列表。**

```dart
void addAnalyses(List<AgentAnalysis> analyses);
```

> **理由**：worst case 是一次 LLM 回應解析出多條獨立結論
> （「這個 401 是 token 過期」「另外那個 500 與它無關，是後端問題」）。
> 只開單筆會強迫 host 寫迴圈，把 N 次 UI 重建的成本推給他且無法避免。
> 單筆是批次的退化情形（傳單元素列表），反之不成立。

### 6.3 🔴 批次注入的實作約束

**批次必須只觸發一次 `_bump()`。**

> `RingBuffer.add()` 每次呼叫都 `onMutate?.call()`。批次若實作成 for 迴圈呼叫 `add`，
> 就退化回 N 次 revision，批次介面等於白開。
>
> 而**不能在迴圈外自行包一層 `onMutate`**——不變式 #1 明寫 `onMutate` 內嚴禁重入。

**解法：分析結果不使用 `RingBuffer`，改用普通 `List`。**

第 5 題已裁決分析結果**不綁自己的數量上限**（存活由引用決定），
因此它根本不需要 ring buffer 的容量語義——需要的只是一個 list + 一次變更通知。
批次 append 後呼叫一次 `_bump()` 即可。

> 與 §6.1 的「`RingBuffer` 零修改」結論一致：兩題都不碰核心 buffer。

### 6.4 記憶體：不需清理（500 上限天然壓制）

失效的分析結果**僅停止顯示，不從 list 移除**。曾考慮「讀取過濾時順手清」，判定不必要：

> 四個事件 buffer 各上限 500。能被引用的事件池子就這麼大，
> 因此**能顯示的分析數量天然被 500 卡住**——QA 跑再久都一樣。
> 積壓的死資料僅為純文字（幾百條約數十 KB），且整場結束即消失。

### 6.5 分析 tab 的 UI：全部重用既有元件

每條分析持有：結論文字、引用 id 列表、時間戳（§6.2）。呈現形式：

```
┌──────────────────────────────────────────────┐
│ 14:32:07                                     │
│ 這個 401 看起來是 token 過期，因為前面的        │
│ refresh 請求打在錯的 endpoint…                 │
│                                              │
│ ▸ 依據 5 筆事件                                │
│   14:31:55 [NET] GET /auth/refresh 404        │
│   14:32:01 [LOG/error] Token refresh failed   │
│   14:30:12 [LOG/info] …（灰）已不在緩衝區       │
└──────────────────────────────────────────────┘
```

**裁決一：🔴 tab 的隱藏條件是「從未注入過」，不是「目前沒有可顯示的」。**

host 未曾注入任何分析 → 隱藏該 tab。
（同 §P26「`inspector` 為 null 時隱藏選單項」的紀律：**沒有東西可給時，不要給一個空殼**。
絕大多數使用者不接 LLM，不該一直看到一個永遠空的 tab。）

> **但一旦注入過，該 tab 在此 App 生命週期內永久存在。**
>
> 若判準寫成「目前可顯示數 == 0」，則當引用陸續 evict、分析全部失效時，
> **tab 會憑空消失**——使用者剛剛還在看它。全部失效時應顯示空狀態，而非讓 tab 蒸發。

**裁決二：引用顯示事件摘要，重用 `_oneLiner()`。**

不顯示 `[network_12]` 這類 id chip——§5.4 才剛裁決前綴是實作細節、host 不得 parse，
給使用者看更無道理。

> `agent_prompt.dart` 的 `_oneLiner()` 已覆蓋四種型別且格式統一，**不重新發明**。
> ⚠️ **實作註記**：該函式目前為私有（`agent_prompt.dart:218`），需改為公開。
>
> 代價是佔空間（5 筆引用即 5 行）→ 預設折疊，點「依據 N 筆事件」展開。

**裁決三：點擊原地開 detail view，走 `pushInspectorRoute`。**

> §P26 已把 `LogDetailView` / `NetworkDetailView` 接好（皆收 `inspector` 參數）。
> 跳去 Console tab 再捲動需另做捲動定位，且 **§D6 的教訓**是 dashboard 內 push route
> 會污染 NavigatorTab——`pushInspectorRoute` 正是該案的成果，
> 已是 `console_tab` / `network_tab` / `database_tab` 三處的既有慣例，直接沿用。

**裁決四：失效的引用灰掉並標註，非整條加提示。**

使用者要知道的是「**哪一筆**沒了」，不是「有東西沒了」。
（履行 §6.1 裁決三的揭露義務：不得讓失效引用看起來仍可點擊卻無反應。）

### 6.6 通知：kit 於 `addAnalyses()` 自動發，點擊跳分析 tab

**裁決一：由 kit 自動發，非交給 host。**

`addAnalyses()` 被呼叫時即發通知。

**裁決二：預設 off，需 opt-in。**

`showNetworkNotification` 與 §P24 crash notification 皆為 opt-in，沿用同慣例。
裝本套件的人多數不接 LLM，預設彈通知是替他們做決定。

**裁決三：持有自己的 `AlertThrottler` 實例。**

> §P24 的紀律：crash 持有自己的實例，與 network 節流互不干擾。分析通知同理，**不共用**。

**裁決四：🔴 一批注入 = 一則通知，非 N 則。**

> §6.3 已裁決批次只 `_bump()` 一次，通知同理。一次 LLM 回應產出 5 條結論就彈 5 則通知，
> 是騷擾不是提示。
>
> **且不得依賴 `AlertThrottler` 來擋**——2 秒窗確實會吃掉同批的後 4 則，
> 但那是**副作用而非設計**。應在 `addAnalyses()` 層面就決定「一批一則」。

**裁決五：點擊跳分析 tab——既有機制已完全支援，無需擴充。**

```dart
NetworkNotifier.analysis(onTap: () => openDashboard(initialIndex: N));
```

> **實查結論（2026-09-16）**：`network_notifier_io.dart:149` 的
> `onDidReceiveNotificationResponse: (_) => onTap?.call()` **丟棄 payload**，
> 初看像是「無法區分通知來源」的缺陷——**實則不然**。
>
> 每個通知類型在建構時就綁好自己的 `onTap` closure
> （`flutter_inspector.dart:328` crash → `initialIndex: 0`；
> `:344` network → `initialIndex: 1`），哪則通知開哪個 tab 在那一行就決定了，
> payload 根本不需要。新增 `.analysis()` 照抄同一模式即可。
>
> **連帶：不變式 #4 的風險大幅降低**——新增建構式仍須 `_io` / `_web` 兩側同步，
> 但這是**照抄既有模式**，而非改動既有簽章（後者才是 §P24 記載的最大破壞風險）。

## 7. 破壞性分析

> **裁決後的整體結論**：本設計**不修改任何核心類別**——
> `RingBuffer`、`TimestampedEntry` 契約、四個 inspector 全部零修改。
>
> 動到既有程式碼的僅三處，且全為**加法或可見性調整**，無既有簽章變更：
> 1. 四個 model 各加 `final String id`（排除於 `==`/`hashCode`）
> 2. `agent_prompt.dart` 的 `_oneLiner()` 由私有改為公開（§6.5）
> 3. 新增 `NetworkNotifier.analysis()` 建構式（§6.6，**須 `_io`/`_web` 雙面同步**）

| 風險 | 嚴重度 | 處置 |
|:---|:---|:---|
| **id 重用 → 靜默錯誤引用** | 🔴 最高 | 全域遞增計數器只增不減（§5.4）；**嚴禁**任何與 buffer 位置相關的 id 方案。此風險比懸空更糟——懸空看得出來，錯誤引用不會 |
| `RingBuffer.replace()` 失效 | 🔴 高 | id 排除於 `==`/`hashCode`（§5.3 規則二）；**必須有測試覆蓋 pending → completed 全程** |
| `copyWith` 漏傳 id | 🟡 中 | §5.3 規則一；因 id 已排除於 identity 之外，漏傳不會破壞 `replace`，但會斷開引用 → 四個 `copyWith` 各需測試 |
| §P26 `buildAgentPrompt` 輸出漂移 | 🟡 中 | 簽章與逐字輸出不變，`agent_prompt_test.dart` 即回歸閘門 |
| `TimestampedEntry` 契約破壞 | 🟢 低 | 不觸碰；id 走各 model + switch（§5.1–5.2） |
| 不變式 #1（`onMutate` 通道） | 🟢 低 | 查詢全程唯讀；**`RingBuffer` 零修改**，未新增 evict 通知通道（§6.1）；批次注入只 `_bump()` 一次（§6.3） |
| 不變式 #2（指標語義） | 🟢 低 | `mergedTimeline()` 只讀不複製；id 繼承使引用自動反映最新狀態；**無快照**（§6.1） |
| 不變式 #3（緩衝型／即時查詢型分流） | 🟢 低 | 分析結果不進 timeline、由 host 主動塞入，天然落在即時查詢型一側（§3.2） |
| 不變式 #4（條件匯出雙向簽章） | 🔴 高 | ⚠️ **§6.6 通知裁決後已改變**：新增 `NetworkNotifier.analysis()` **確實觸及** `_io`/`_web` 雙面。屬照抄既有模式（非改動既有簽章），但 `flutter test` **抓不到**漂移——動工前須備妥 Web build harness（§9.1 第 2 點）。`share_text` 仍不觸碰 |
| 不變式 #5（套件純淨性） | 🟢 低 | 零新增依賴；`dart:convert` 已於 `diagnostic_report.dart` 使用 |

---

## 8. 刻意不做（附理由，避免日後重提）

| 項目 | 死因 |
|:---|:---|
| **MCP server** | 傳輸層需 stdio（App 無）或 HTTP（需在裝置開 port）。開 port 違反純淨性，且同場景被 VM Service 方案全面壓制——[flutter_agent_lens](https://github.com/dhruvanbhalara/flutter_agent_lens) 直接給 widget tree + memory + CPU profile，覆蓋面遠大於四個 buffer |
| **Android AppFunctions** | `@AppFunction` 需 Kotlin annotation + KSP codegen（Flutter 無路徑）；Android 16+ 專屬、iOS 無對應物；Gemini 整合為 private preview 僅限 trusted testers；呼叫端需 `EXECUTE_APP_FUNCTIONS` 權限且僅少數 app 被 allowlist |
| **嵌入 on-device model** | 最小 FunctionGemma 270M `.task` 檔 **284 MB**；且**模型在裝置上但 codebase 不在**——缺 codebase 的歸因就是 §P26 已裁決的「講錯的原因比不講更貴」。小模型會產出**有自信的錯誤原因**，親手違反 kit 自訂的誠實邊界 |
| **JSON 裡放「可能原因」欄位** | 同上：kit 有執行期事實但無 codebase |
| **手動多選匯出 UI** | 回溯邊界應由**導航行為**決定（§P26 已驗證），不是勾選出來的。且需新增選取模式 UI，是唯一要動 UI 狀態的方案 |

> **調研日期 2026-09-15**。上述三項若日後平台條件改變（例如 AppFunctions 開放公開存取、
> 或出現 <50MB 且具 codebase 感知的模型），可重新裁決——但**不得在條件未變時重提**。

---

## 9. ✅ 設計已完成（2026-09-16）

**六題全數裁決完畢，無未決項。**

| # | 問題 | 裁決 | 節次 |
|:---|:---|:---|:---|
| 1 | 懸空引用與持久化 | 綁引用、讀取時過濾、`RingBuffer` 零修改 | §6.1 |
| 2 | 注入介面形狀 | 純 append、批次、帶時間戳、無自身 id | §6.2 |
| 3 | Entry id 生成 | 全域計數器 + 來源前綴，嚴禁位置相關方案 | §5.4 |
| 4 | 查詢簽章 | JSON-safe Map、不分頁、截斷須揭露 | §4.3 |
| 5 | 分析 tab UI | 全部重用既有元件（`_oneLiner` / `pushInspectorRoute`） | §6.5 |
| 6 | 通知時機 | kit 自動發、opt-in、一批一則、跳分析 tab | §6.6 |

### 9.1 動工前的先決條件

本設計**尚未排程**。若要進入實作，建議先行確認：

1. **產出實作計畫**——依 repo 慣例寫入 `docs/plans/YYYY-MM-DD-<topic>.md`，
   拆解任務並定義驗收條件。
2. **🔴 Web build harness**——§P24 已記載：`_io`/`_web` 簽章漂移是最大破壞風險，
   而 `flutter test` **完全抓不到**（測試跑在 VM 上全程走 `_io`）。
   本設計新增 `NetworkNotifier.analysis()` 建構式，同樣需要最小 harness 跑
   `flutter build web` 把兩個建構式都納入編譯圖。**`example/` 不能當關卡**
   （依賴 ObjectBox，native-only，該目錄的 `flutter build web` 永遠失敗且與本功能無關）。
3. **四個 `copyWith` 的 id 繼承測試**——見 §7 風險表第三列。

---

## 10. 決策脈絡摘要（供未來 review 追溯）

本設計歷經數輪收斂，以下為關鍵轉折：

- **初始提問**：「能否導入 AI 或生成輔助 AI 的資訊幫助排查」——開放式，無預設方向。
- **調研結論**：GitHub 生態的 Flutter AI 除錯工具（marionette_mcp / mcp_flutter /
  flutter_agent_lens / 官方 Dart MCP）**全數依賴 Dart VM Service**，
  要求「開發者的機器 + debug build + 連線」。而 kit 的價值場景恰好相反：
  **QA 的手機上、release-ish build、開發者不在現場**。MCP 那條路對本套件是死路。
- **關鍵分歧點**：最初把 A（裝置上）與 B（開發機）當成互斥選項，
  並把「判斷住在哪」拆成三選一（規則層／遠端 LLM／本地 model）——
  **此框架是錯的**。三者是並存層級，A 與 B 要的是同一份資料。
- **資料政策裁決**：允許 log 與 response body 離開裝置 → 284MB 本地模型的問題消失，
  遠端 LLM 成為可行路徑。
- **形狀定案**：使用者提出「像 function call 一樣，讓 host app 撈取分析後注入結果」——
  這同時解掉開 port、MCP 綁定、套件純淨性三個問題，且讓 A/B 統一為同一套機制。
