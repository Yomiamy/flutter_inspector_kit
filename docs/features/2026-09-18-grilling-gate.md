# C4 · STAGE 0a 前插 grilling 關卡（需求盤問）

> **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §6 mattpocock/skills 比對 · C4
> （同源項：§5(A) A3「interview-me 一問一答需求探索」，兩份文件描述同一缺口）
> **狀態**：功能規格（What & Why）· 2026-09-18

---

## 1. 🔴 實查更正：原提案的前提有一半不成立

動工前實查 codebase，發現腦力激盪文件對本項的兩處描述與實況不符。**照原文字面實作會做出重複的東西**，故先更正前提再定義範圍。

### 1.1 文件說法

> §6.3.1：「他的四大失效模式第一條是 misalignment，解法是開發前一輪一輪盤問。
> 我們 STAGE 0a 是 **planner 直接產規格**，**誰來確保需求本身沒歪？**
> 目前只有暫停點給人看一眼。」

> §5(A) A3：「`brainstorming` 是**分析式的**——agent 自己想完再提出方案讓使用者確認。
> 對『使用者腦中只有模糊想法』的場景，**缺少漸進式引導**。」

### 1.2 實查結果

| 文件宣稱 | 實查 | 判定 |
|:---|:---|:---|
| `brainstorming` 是分析式、缺漸進引導 | `brainstorming/SKILL.md:169` 明寫 "ask questions one at a time"；`:171` 要求「只問一個問題」；其 Architectural path 的第 3 步即為逐項提問 | ❌ **證偽**——一問一答機制已完整存在 |
| STAGE 0a 是 planner 直接產規格 | `.claude/agents/planner.md:26` 的「使用的 Skills」明列 `brainstorming — 需求探索` | ⚠️ **部分證偽**——planner 契約上要用 brainstorming |
| （文件未提） | `grep -rn "brainstorming" .claude/skills/gen-dev-workflow/` = **0 命中** | 🔴 **真正的缺口在此** |

### 1.3 真正的缺口（重新定性）

**盤問能力不缺，缺的是「盤問一定會發生」的保證。**

三個事實串起來就是問題本身：

1. `brainstorming` 有完整的一問一答機制，且 frontmatter 寫著 `You MUST use this before any creative work`。
2. `planner.md` 契約上要用它。
3. 但 **`gen-dev-workflow` 全目錄 9 個 md 檔對 brainstorming 零引用**——STAGE 0a 的派發模板沒提它、`workflow-parallel.md` 的適用點 1 只說「雙線 context 收集 → 收斂後交給 planner 撰寫規格」，整條路徑上沒有任何一處要求先盤問。

於是 planner 用不用 brainstorming，**取決於它自己讀不讀 agent 定義、以及當下想不想**。這正是本 repo §8.1 自己下過的判準：

> **Guide 可以被忽略，Sensor 不行。**

`brainstorming` 的 `You MUST` 是 Guide。**本項要做的不是再寫一份盤問手冊（那是第二份 Guide），而是把既有的盤問變成 STAGE 0a 跳不過的一步。**

### 1.4 對範圍的影響

| 原提案 | 修正後 |
|:---|:---|
| 新建一個一問一答 skill（重寫盤問邏輯） | ❌ 不做——會與 `brainstorming` 重複，違反 YAGNI |
| 在 brainstorming 加 interview mode 分支 | ❌ 不做——該分支已存在 |
| — | ✅ **新建一個「盤問閘門」skill**，職責是**驅動既有 brainstorming 並判定需求是否收斂**，不重寫問法 |
| — | ✅ **把該閘門接進 STAGE 0a 的派發路徑**，讓它成為 planner 之前的必經步驟 |

---

## 2. 使用者故事

**主要場景（misalignment 防護）**

> 身為使用者，當我丟出一句「幫我做 X」時，我希望在 planner 花最強推論（opus/xhigh）寫出整份規格**之前**，先有人反問我幾個問題把需求釘清楚——而不是等規格產出後，在暫停點看著一份方向就歪掉的文件，再重跑一次 0a。

**次要場景（盤問的一致性）**

> 身為使用者，我不希望「這次有沒有被盤問」取決於 agent 當下的心情。同樣模糊的需求，這次被問了三題、下次直接產規格，我無從預期。

**反面場景（不可回歸的體驗）**

> 身為使用者，當我丟出的需求**本來就很清楚**（例如帶著完整 issue 內容、或是「把 §P4 照 Tier 4 表格做掉」這種已有文件背書的項目），我不希望還被強迫走完一輪盤問——那是純粹的摩擦。

---

## 3. 範圍邊界

### 3.1 做什麼（In Scope）

| # | 項目 | 說明 |
|:-:|:---|:---|
| 1 | 新建 `gen-grill` skill | 職責：判定需求是否收斂 → 未收斂則驅動 `brainstorming` 盤問 → 收斂後產出結構化 brief 交給 planner |
| 2 | 收斂判準 | 明文列出「需求算收斂」的檢查項（問題定義、使用者、約束、成功標準、範圍邊界），逐項可指認 |
| 3 | 短路條件 | 需求已充分時直接放行，不強迫盤問（對應 §2 反面場景） |
| 4 | 接進 STAGE 0a | 修改 `gen-dev-workflow/SKILL.md` 的 STAGE 0a 區塊與流程圖，把 grill 標為 planner 之前的必經步驟 |
| 5 | brief 交接格式 | 定義 grill 產出交給 planner 的形狀（讓 planner 拿到的是已收斂的需求，而非原始一句話） |

### 3.2 不做什麼（Out of Scope）

| 項目 | 理由 |
|:---|:---|
| **重寫一問一答的問法** | `brainstorming` 已有（`:169`、`:171`）。本項沿用其紀律，不重寫 |
| **改 `brainstorming/SKILL.md`** | 它是 superpowers 上游 skill，本 repo 不持有。改它會在上游更新時衝突。**只從外部呼叫，不修改** |
| **新增 wf-state.sh stage** | 使用者已裁決「不接狀態機」。轉移表維持 `0a→0b→1→2→3→4` 不變，grill 發生在 0a 內部、腳本無感 |
| **新增暫停點** | 盤問本身就是對話，不需要額外的 `stage-done` 棘輪。STAGE 0a 既有的規格確認暫停點不變 |
| **領域模型建構（`/grill-with-docs`）** | 上游那條是「對齊訪談 + 建領域模型」。本 repo 的領域詞彙表屬 C1（`CONTEXT.md`），是獨立項目，不在本項範圍 |
| **改 planner.md** | planner 的「使用的 Skills」已列 brainstorming，契約沒錯。錯的是 workflow 沒接線，修 workflow 即可 |

---

## 4. 驗收條件

### 4.1 功能面

| # | 條件 | 驗證方式 |
|:-:|:---|:---|
| AC-1 | `.claude/skills/gen-grill/SKILL.md` 存在，且有合法 frontmatter（`name` 與目錄名相符、`description` 齊備） | `head -4` 檢視；比照本 repo 61 個 skill 現況（實查：全數具備 frontmatter，本項不得成為第一個例外） |
| AC-2 | SKILL.md 明文列出收斂判準，且每一項可被逐條指認（非「大致清楚」這類不可證偽的敘述） | 人工讀；判準必須是「能指著說第 N 項沒答」的形狀 |
| AC-3 | SKILL.md 明文定義短路條件——需求已充分時直接放行 | 人工讀 |
| AC-4 | SKILL.md 明文要求呼叫既有 `brainstorming` skill 執行盤問，而非自帶問法 | `grep -c brainstorming` ≥ 1 |
| AC-5 | `gen-dev-workflow/SKILL.md` 的 STAGE 0a 區塊與流程圖，皆標示 grill 為 planner 之前的必經步驟 | `grep -n "grill" .claude/skills/gen-dev-workflow/SKILL.md` ≥ 2 處（流程圖 + 內文） |
| AC-6 | 定義 grill → planner 的 brief 交接格式 | 人工讀 |

### 4.2 不可回歸（Never break userspace）

| # | 條件 | 驗證方式 |
|:-:|:---|:---|
| AC-7 | `wf-state.sh` **零修改** | `git diff --stat` 不含 `scripts/wf-state.sh` |
| AC-8 | 轉移表維持 `0a→0b→1→2→3→4`，既有 state 檔可正常讀取 | `wf-state.sh get <現存檔>` 正常回傳 |
| AC-9 | `brainstorming/SKILL.md` **零修改** | `git diff --stat` 不含該檔 |
| AC-10 | 既有 7 個暫停點數量與位置不變 | 比對 SKILL.md「暫停點規則」表格，仍為 7 列 |
| AC-11 | `quick` 模式不受影響——小修正不應被強迫盤問 | SKILL.md 明文說明 grill 在 quick 模式的行為 |
| AC-12 | 測試與靜態分析無新增問題 | `flutter test`（基線 606 tests）+ `flutter analyze lib/ test/`（基線 7 個既有 info），**引述完整輸出**並逐一指認第 8 個以後的歸屬 |

> AC-12 的「引述」要求刻意對齊 §8.2 的 A2 建議：總數對但內容換掉仍會漏，故要求貼出實際輸出而非回報判斷。本項為純文件改動，理論上不應動到任何 Dart 程式碼，測試數與 info 數應**完全不變**。

---

## 5. 設計方向（2 案，供 STAGE 0b 收斂）

> 本節只列方向與 trade-off，**不含實作細節**——那是 0b 的工作。

### 方案 A：獨立 skill + workflow 接線（推薦）

`gen-grill` 是一個獨立 skill，`gen-dev-workflow` 的 STAGE 0a 在派發 planner 之前先呼叫它。

- ✅ 職責乾淨：盤問閘門與流程編排分離，可單獨叫用（使用者也能自己 `/gen-grill`）
- ✅ 符合使用者已裁決的形狀（獨立 skill、不接狀態機）
- ✅ 不動 `brainstorming`，上游更新無衝突
- ⚠️ 仍是 Guide 而非 Sensor——SKILL.md 寫「必經」，但沒有腳本擋。**這是使用者已接受的取捨**（裁決：不接狀態機）

### 方案 B：把收斂判準直接寫進 STAGE 0a 派發模板

不新建 skill，把判準塞進 `gen-dev-workflow/SKILL.md` 的 0a 區塊。

- ✅ 零新檔案，diff 最小
- ❌ 無法單獨叫用
- ❌ 讓已經 213 行的 SKILL.md 繼續長胖，與本 repo §6 C2「description 太長」的方向相反
- ❌ 與使用者裁決的「獨立 skill」形狀不符

**建議採 A。**

---

## 6. 已知風險與取捨

| 風險 | 說明 | 緩解 |
|:---|:---|:---|
| **Guide 而非 Sensor** | 本項產出的是文件約束，agent 理論上可跳過。本 repo §8.1 自承「Guide 可以被忽略」 | 使用者已裁決不接狀態機，接受此取捨。若日後發現實際被跳過，再議是否升級為 hook |
| **盤問摩擦** | 過度盤問會讓小改動變慢，重演 §2.1「人在迴路頻率過高」的老問題 | AC-3 的短路條件 + AC-11 的 quick 模式豁免，兩道防線 |
| **與 C1 的邊界** | 盤問時若牽涉領域詞彙（`mergedTimeline`、緩衝型 vs 即時查詢型），可能誘發「順手建 CONTEXT.md」 | 明確劃在 Out of Scope。C1 是獨立項目 |
| **negation 密度** | 本 repo §6 C7 指出 gen-dev-workflow 的 negation 已達 56 處/9 檔，新寫的 SKILL.md 若又是一堆「不要 X」會加劇 | 新 SKILL.md 以正面目標撰寫（「盤問到 N 項齊備」而非「不要跳過盤問」） |

---

## 7. 同源項處置

| 編號 | 出處 | 處置 |
|:---|:---|:---|
| **C4** | §6.5 順位 4 | ✅ 本規格 |
| **A3 / B19** | §5(A) 順位 3「interview-me」 | ✅ **併入本項**——同一缺口。其「方案 A：改 brainstorming 加 interview mode」因實查證偽（該分支已存在）而不採用 |

落地後應回寫兩處：`2026-09-17-workflow-brainstorm.md` 的 §5.7 順序表（A3 列）與 §6.5 表（C4 列），並在 §6.3.1 / §5(A)A3 補記本規格 §1 的實查更正。
