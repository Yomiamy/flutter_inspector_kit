---
name: gen-dev-workflow
description: |
  完整開發流程編排器。使用者說「幫我做 X 功能」時觸發，自動依序驅動所有 agent 直到 PR 建立，只在關鍵決策點暫停確認。
  觸發條件：dev workflow, 開始開發, 新功能開發, 幫我做 X 功能, 繼續, 繼續上次, 繼續開發, /gen-dev-workflow
---

# Dev Workflow（自動編排模式）

你是整個開發流程的**總指揮**。使用者給你一個需求，你自動驅動所有 agent 跑完整個週期，只在必要時暫停。

> **委派後端：antigravity-cli (`agy`)。** brancher、implementer、publisher 透過 Bash 呼叫 `agy -p` 委派（stdin 管道傳 prompt + `--print-timeout`）。
> 需求：`agy` 須在 PATH（預設於 `~/.local/bin/agy`）。
> `agy` 不在 PATH 時各 agent 會自動退回 Fallback 模式，功能仍可運作但不會委派給 `agy`。

> **多 workflow 並行：** 同一 repo 可同時跑多個獨立 workflow（多個終端 / 多個 session）。隔離 key 是 **git branch**——每個 workflow 跑在自己的 branch 上，寫自己 branch 對應的 state 檔，彼此天然零衝突，不需要任何鎖或中央索引。唯一需要額外處理的窗口是「兩個流程都還在 STAGE 0a/0b（尚無 branch）」，靠 **workflow-id** 持久化區分（見「狀態追蹤」章節）。

> **Claude Workflow 編排（可選加速層）。** 本流程內**特定的並行、唯讀或路徑不重疊、且該段落內部不需要問使用者**的環節，可改用 Claude `Workflow` 工具（JS 腳本 fan-out 多 subagent）執行，取代逐個 `Task(...)` 串接。適用點只有三處：**STAGE 0a 雙線 context 收集**、**STAGE 2 同批獨立任務**、**STAGE 3 多 angle 對抗式審查**（各章節有專節說明）。
>
> **硬性邊界（違反即破壞流程，絕不可越界）：**
> - **絕不**把整條 orchestrator 包成單一 Workflow 腳本——Workflow 背景執行、跑完才回，中途無法暫停問人，會直接摧毀本流程 7 個人在迴圈中的暫停確認點。
> - Workflow 只用於**單一段落內部**的 fan-out，**暫停點永遠由主指揮（主對話）掌控**，落在任何 Workflow 呼叫的外面。一個 Workflow 呼叫 = 一段不可中斷的並行，跑完回到主對話才暫停。
> - **前置條件：** 使用者需明確 opt-in 多 agent 編排（說「ultracode」、「用 workflow」、「多 agent」或類似）。未 opt-in 時，這三處一律退回原本的 `Task(...)` / 序列作法，功能完全相同，只是不 fan-out。
> - state 檔、model 策略、委派規則**完全不變**——Workflow 只換「並行執行的載體」，不換流程語意。

## 編排流程

```text
    使用者：「幫我做 X 功能」
           │
           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 0a：功能規格            [Model: Opus (xHigh effort)] │
    │  → 呼叫 planner agent                           │
    │  → 🟢 並行 2 條（已 opt-in → 可用 Workflow）：   │
    │     A. 專案 context 收集（讀檔 / git log）       │
    │     B. 相似功能代碼調查（既有實作參考）          │
    │     → planner 收斂兩者後撰寫規格                 │
    │  → 產出 docs/features/YYYY-MM-DD-<feature>.md   │
    │    （What & Why：使用者故事、驗收條件、範圍邊界） │
    │  ⏸ 暫停：展示功能規格，等使用者確認              │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 0b：實作計畫            [Model: Opus (xHigh effort)] │
    │  → 呼叫 planner agent（依據已確認的功能規格）    │
    │  → 產出 docs/plans/YYYY-MM-DD-<feature>.md      │
    │    （How：資料結構、檔案異動、任務拆分）          │
    │  ⏸ 暫停：展示實作計畫，等使用者確認              │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 1：建立分支            [Model: Sonnet (Max effort)] │
    │  → 呼叫 brancher agent 產出草稿                  │
    │  ⏸ 暫停：展示 Issue 標題/內容 + 分支名稱         │
    │          等使用者確認或修改                       │
    │  → agy 執行 gh issue create + git checkout   │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 2：實作      [Model: 逐任務動態分級]       │
    │  → 呼叫 implementer agent                       │
    │  → 解析計畫，判斷並行模式：                       │
    │     • ≥2 個獨立任務、寫入路徑不重疊 → 🟢 並行    │
    │       （已 opt-in → 同批可用 Workflow fan-out）  │
    │     • 否則 → 🔴 序列逐任務                        │
    │  → 逐任務選 model：機械性→快/便宜｜整合→標準     │
    │     ｜設計判斷/跨層→最強（見 Model 策略章節）    │
    │  → agy 實作任務，Claude 兩階段驗收            │
    │  ⏸ 每個任務（或每批並行）完成後暫停：            │
    │      展示變更檔案 + 測試結果摘要                  │
    │      問「確認繼續下一個任務嗎？」                  │
    │  ⏸ 遇到模糊需求：問使用者後繼續                  │
    └──────────────────────┬──────────────────────────┘
                           │ 所有任務確認完成
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 3：審查        [Model: Opus (xHigh effort)] │
    │  → 呼叫 reviewer agent（不委派 agy，親自判斷）  │
    │  → 已 opt-in → 多 angle 對抗式審查（Workflow    │
    │    平行 verifier 找 bug，reviewer 收斂判斷）     │
    │  ⏸ 暫停：展示審查報告，問「確認繼續嗎？」         │
    │  ┌─ 使用者確認（通過）                      ─┐   │
    │  └─ 不通過 / 使用者要求修正                   │   │
    │       → 退回 STAGE 2 修正 → 再回 STAGE 3 ───┘   │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認通過
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 4：發布        [Model: Sonnet (Max effort)] │
    │  → 呼叫 publisher agent                         │
    │  → agy 分析 Diff，Claude 校對草稿             │
    │  ⏸ 暫停：展示 PR 草稿，等使用者確認發布          │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
                      PR 建立完成 ✦
                      流程結束，Claude 停止。
                      （本地 branch 一律保留，不自動刪除）

    ──────────────────────────────────────────────────
    [Model: ...] = 該 stage 委派時選用的基準 model。
    主對話（總指揮）全程不換 model；切換發生在委派出去的
    agy 子進程。STAGE 2 為逐任務動態分級。
    詳見下方「Model 與委派策略」章節。

    ──────────────────────────────────────────────────
    STAGE 5：回覆 PR Review（獨立入口，由你手動觸發）
    ──────────────────────────────────────────────────
    觸發方式：你說「PR #42 有新的 review 意見」
    → 呼叫 responder agent 處理每條意見      [Model: Sonnet (Max effort)]
    → 處理完畢 → 呼叫 reviewer agent 重新審查 [Model: Opus (xHigh effort)]
    → 審查通過 → 呼叫 publisher agent 更新 PR [Model: Sonnet (Max effort)]
    → 完成後流程再次結束，Claude 停止等待。
```

---

## 暫停點規則（只有三種）

| 暫停時機 | 你要做什麼 | 繼續條件 |
|---------|-----------|---------|
| 功能規格完成後 | 展示功能規格（使用者故事、驗收條件、範圍），問「確認嗎？」 | 使用者確認 |
| 實作計畫完成後 | 展示實作計畫（任務清單、檔案異動），問「確認開始實作嗎？」 | 使用者確認 |
| Issue + 分支建立前 | 展示 Issue 標題、描述內容、分支名稱，問「確認建立嗎？」 | 使用者確認或修改後確認 |
| 每個實作任務完成後 | 展示變更檔案清單 + 測試結果，問「確認繼續下一個任務嗎？」 | 使用者確認 |
| 審查報告完成後 | 展示完整審查報告，問「確認繼續發布嗎？或需要修正？」 | 使用者確認 → STAGE 4，或退回 STAGE 2 |
| 遇到模糊需求 | 問最小必要問題（≤ 2 個），不要問多 | 使用者回答後自動繼續 |
| PR 草稿完成後 | 展示草稿，問「確認發布嗎？」 | 使用者確認 |

**不應該暫停的情況：** 分支建立、任務間自動切換、STAGE 2 內部失敗 retry、STAGE 3 審查失敗退回 STAGE 2、測試執行、並行單元間的協調。這些全部自動處理（失敗 retry 與退回路徑見「並行執行契約」章節）。

**主動中斷（非暫停）：** context > 150k 時依 Token Budget Gate 主動保存並切 session，這不是暫停點，是保護性中斷。

---

## 執行方式

### 啟動完整流程
```
使用者：幫我做 <需求描述>

你：好，開始執行開發流程。
    Task("planner", "規劃 <需求描述>，產出 plan 文件")
    → [等 planner 完成] → 展示計畫摘要 → 暫停確認
    → Task("brancher", "執行 <plan 路徑>")
    → Task("implementer", "執行 <plan 路徑>")
    → Task("reviewer", "審查 <branch-name>")
    → [若不通過] Task("implementer", "修正以下問題：<reviewer 回報>")
    → Task("publisher", "發布 <branch-name>")
    → 暫停確認 → 完成
```

### 從特定階段繼續
```
使用者：從審查繼續 / 繼續發布 / 重新規劃

你：根據當前狀態跳入對應 stage，其餘流程照常自動執行。
```

---

## 狀態追蹤

每個 stage 開始前，輸出一行進度提示。**前綴帶流程識別**（pending 階段帶 `<wf-id>`，已建 branch 後帶 branch slug），讓多個並行 workflow 的輸出能一眼分辨：

```
[wf-1717400000-3f9a] [0a/5] 撰寫功能規格中...   ← 尚無 branch，帶 wf-id
[feature-202605-42-cart] [1/5] 建立分支中...     ← 已建 branch，帶 slug
[feature-202605-42-cart] [2/5] 實作中（共 N 個任務）...
[feature-202605-42-cart] [3/5] 審查中...
[feature-202605-42-cart] [4/5] 發布準備中...
[feature-202605-42-cart] [5/5] 完成 ✦ PR: <URL>
```

### 狀態檔：每個 workflow 一個檔，用 branch 命名

**多 workflow 並行的隔離 key 是 git branch。** 同一 repo 上兩個並行 workflow 一旦各自建了 branch，就寫各自 branch 對應的 state 檔，彼此天然零衝突——不需要任何鎖、不需要中央索引。

**檔案路徑規則：**

```
.claude/workflow-state/<branch-slug>.json      ← 已建 branch 的 workflow（STAGE 1 之後）
.claude/workflow-state/.pending-<wf-id>.json   ← 尚無 branch 時的暫存（STAGE 0a / 0b）
```

- `<branch-slug>`：當前 branch 名稱把 `/` 換成 `-`。
  例：`feature/202605/42-cart` → `feature-202605-42-cart.json`
- `<wf-id>`：**workflow-id**，流程啟動當下產生的唯一識別碼，格式 `wf-<epoch>-<rand4>`
  （`echo "wf-$(date +%s)-$(head -c2 /dev/urandom | xxd -p)"`，例 `wf-1717400000-3f9a`）。
  即使兩個流程在「同一秒、同一 base branch」上同時啟動，`<rand4>` 也保證檔名不撞。

**workflow-id 是 pending 階段的隔離 key（取代舊的「靠 context 記住路徑」）：**

舊設計把「本 session 對應哪個 pending 檔」只存在對話 context 裡——session 一中斷，pending 檔就成了無主孤兒，新 session 因為還沒 branch 而推導不到它。改用 workflow-id 後，這個識別碼**同時寫進 state 檔內容、並由 session 在每次進度回報行帶上**，所以續接時能精準認領自己的 pending 檔，不會誤撿別人的。

```json
// .pending-<wf-id>.json 內容（STAGE 0a/0b 階段）
{
  "workflow_id": "wf-1717400000-3f9a",
  "stage": "0a",
  "mode": "sequence",
  "branch": null,
  "spec": null,
  "plan": null
}
```

進度回報行格式（每次 stage 切換、每個任務完成時輸出）：
```
[wf-1717400000-3f9a] [1/5] 建立分支中...
```
branch 建立後改帶 branch slug，不再需要 workflow-id：
```
[feature-202605-42-cart] [2/5] 實作中（共 5 個任務）...
```

**state 檔生命週期（解決「尚無 branch」這個唯一邊界）：**

| 時機 | 動作 |
|------|------|
| STAGE 0a 啟動（流程剛開始，還沒 branch） | 產生 `<wf-id>` → 建 `.pending-<wf-id>.json`（內含 `workflow_id`）→ 之後進度行都帶 `[<wf-id>]` |
| STAGE 1 建好 branch 後 | `mv .claude/workflow-state/.pending-<wf-id>.json .claude/workflow-state/<branch-slug>.json`，補上 `branch` 欄位（`workflow_id` 保留，便於追溯） |
| STAGE 1 之後每次寫入 | 寫 `<branch-slug>.json`，零衝突 |
| 直接 jump 進 STAGE 1+（已知 branch） | 略過 pending，直接寫 `<branch-slug>.json` |

> 關鍵：每個 session 只寫**自己**那一個檔——pending 階段靠 `<wf-id>` 認領、STAGE 1 之後靠當前 branch 推導，絕不掃別人的檔來寫，所以任意數量的並行 workflow 都不會互踩。

**每個 stage 完成後寫入對應 state 檔**，讓新 session 可以從中斷點繼續：

**sequence 模式**（正常流程跑到這裡）：
```json
{
  "workflow_id": "wf-1717400000-3f9a",
  "stage": 2,
  "mode": "sequence",
  "spec": "docs/features/2026-05-03-cart.md",
  "plan": "docs/plans/2026-05-03-cart.md",
  "branch": "feature/202605/42-cart",
  "issue": 42,
  "pr": null,
  "completed_tasks": [1, 2],
  "total_tasks": 5,
  "interrupted_by": "context_budget"
}
```

`interrupted_by` 欄位（可選）：記錄上次為何中斷，續接時用來決定第一句話。
- `"context_budget"` → 因 context 超標主動切 session（見下方 Token Budget Gate）
- `null` 或不存在 → 正常暫停（使用者主動離開）

**jump 模式**（直接指定特定 stage 執行）：
```json
{
  "workflow_id": "wf-1717400500-b21c",
  "stage": 5,
  "mode": "jump",
  "pr": 42,
  "spec": null,
  "plan": null,
  "branch": null,
  "issue": null,
  "completed_tasks": [],
  "total_tasks": null
}
```

`mode` 的用途：
- `sequence` → 前面所有 stage 都有完整 context（spec、plan、branch），可以回頭參照
- `jump` → 只有當前 stage 的資訊，不應假設前面的 context 存在

**狀態檔檢查時機（三種觸發）：**

**三種觸發點，發現狀態檔時走同一套邏輯：**

| 觸發 | 關鍵字 |
|------|--------|
| A | `/gen-dev-workflow` |
| B | 「幫我做 X 功能」/ 「開始開發」/ 「新功能開發」 |
| C | 「繼續」/ 「繼續上次」/ 「繼續開發」 |

**先定位「本 session 對應的 state 檔」（A / B / C 共用）：**
```
→ 若本 session context 已持有 <wf-id>（這個流程在本 session 啟動過 STAGE 0a/0b）
   → 直接認領 .pending-<wf-id>.json，走「狀態檔存在時」（不必看 branch）

→ 否則 slug = 當前 branch（git branch --show-current）把 / 換成 -
→ 候選檔 = .claude/workflow-state/<slug>.json
→ 若候選檔存在 → 它就是本 session 的 state，走「狀態檔存在時」
→ 若候選檔不存在：
   ├─ 列出 .claude/workflow-state/*.json（已建 branch 的流程，排除 .pending-*）
   │   ├─ 0 個 → 再看有沒有 pending：
   │   │         列出 .claude/workflow-state/.pending-*.json
   │   │         ├─ 0 個 → 走「狀態檔不存在時」
   │   │         ├─ 1 個 → 提示「找到 1 個尚未建 branch 的流程 <wf-id>（STAGE <N>），要接續它嗎？」
   │   │         └─ ≥2 個 → 列出全部 <wf-id> + stage 讓使用者選，或開新流程
   │   ├─ 1 個 → 提示「當前 branch 無對應流程，但找到 1 個其他流程 <slug>，要接續它嗎？」
   │   └─ ≥2 個 → 列出全部讓使用者選，或開新流程
   └─（並行情境下，每個 session 都待在自己的 branch，候選檔通常一擊命中；
       多個流程同時卡在 STAGE 0a/0b 時，靠各自 context 的 <wf-id> 一擊命中，不會誤撿別人的 pending 檔）
```

> **絕不**用 `git branch --show-current` 推導去認領 pending 檔——pending 階段可能多個流程共用同一 base branch，branch 推不出唯一的 pending 檔。pending 階段的唯一識別永遠是 `<wf-id>`。

**狀態檔存在時（即上面定位到的 `<slug>.json`）：**
```
→ 讀取該檔
→ 若 pr 欄位有值 → gh pr view <pr> --json state --jq '.state'
   ├─ MERGED → 自動刪除該檔，告知「PR 已合併，開發週期完成 ✦」
   ├─ CLOSED → 問使用者「PR 已關閉，要重新開 PR 還是放棄？」
   └─ OPEN   → 展示目前狀態（STAGE <N>），問「繼續還是開新流程？」
→ 若 pr 欄位為 null → 展示目前狀態（STAGE <N>），問「繼續還是開新流程？」
```

**狀態檔不存在時：**
```
→ 觸發 A → 問「要開始新的開發流程嗎？請描述需求」
→ 觸發 B → 直接用使用者描述的需求啟動新流程
→ 觸發 C → 告知「當前 branch 找不到未完成的流程，要開始新的嗎？」
```

**狀態檔刪除時機：**
- PR 狀態為 `MERGED` → 自動刪除該 branch 的 state 檔
- 使用者說「放棄這個功能」→ 自動刪除該 branch 的 state 檔
- 其他情況一律保留，直到明確完成

> 上述刪除只針對 **state 檔（JSON）**，**git branch 本身一律保留**——流程任何階段（含 PR MERGED 後）都不自動執行 `git branch -d/-D`，branch 由使用者自行決定何時刪除。

> 刪除只動「本 session 對應的那一個」state 檔，絕不清整個 `.claude/workflow-state/` 目錄——別的 session 的進度不可被波及。

---

## Token Budget Gate（context 用量控管）

這是長流程（6 stages + 每任務暫停）的存活機制。**每個 stage 切換前、以及 STAGE 2 每個任務完成後**，評估主對話 context 用量並依下表行動：

| Context 用量 | 行為 |
|---|---|
| < 60k | 正常流程，不做任何事 |
| 60–100k | ⚠️ 提示使用者「context 已 <用量>，建議精簡」。委派 agent 時要求只回報摘要，不回貼完整 diff / 檔案內容 |
| 100–150k | ⚠️ 強制走委派路徑：implementer / publisher 一律走 agy 委派（即使 fallback 條件成立也不自行讀大檔），主對話只保留高層判斷 |
| > 150k | ⛔ **強制 checkpoint，主動切 session** — 走下方「context 超標切 session 閉環」 |

### context 超標切 session 閉環

這是本 skill 相對其他 workflow 的關鍵優勢：**已有 per-branch state 檔，所以 Token Gate 撞牆時不會丟失進度**。

`> 150k` 觸發時，**不是只丟一句「建議切 session」**，而是執行完整交接：

```
1. 完成當前正在進行的最小單元（如 STAGE 2 的當前任務），不要切在半途
2. 寫入本 workflow 的 state 檔，並設 "interrupted_by": "context_budget"
   ├─ 已建 branch → <branch-slug>.json（記錄 stage / mode / spec / plan / branch / completed_tasks）
   └─ 尚無 branch（STAGE 0a/0b）→ .pending-<wf-id>.json（務必含 workflow_id，否則新 session 認不回）
3. 若有未 commit 的變更 → 先 commit（避免 session 切換後遺失）
4. 明確告知使用者，並把識別碼一起給出去（讓使用者知道續接的是哪個流程）：
   「[<wf-id 或 branch-slug>] context 已達 <用量>，為避免品質下降已保存進度至 STAGE <N>。
     請開新 session 後輸入『繼續』或 /gen-dev-workflow，會自動從 STAGE <N> 接續。」
5. 停止，不再繼續任何 stage
```

續接時（新 session 讀到 `"interrupted_by": "context_budget"`）：
```
→ 定位本 workflow 的 state 檔（已建 branch 靠當前 branch；尚無 branch 靠使用者帶回的 <wf-id>，
   或在只有單一 pending 檔時直接認領）
→ 開場白改為：「[<wf-id 或 branch-slug>] 偵測到上次因 context 超標而保存（STAGE <N>），現在 context 乾淨，直接續接。」
→ 不問「繼續還是開新流程」（因為這不是使用者主動離開，是系統保護性中斷，意圖明確）
→ 直接從 state 記錄的 stage 接續
```

**為什麼這是閉環：** Token Gate 偵測危險 → state 持久化保存全部進度 → 切 session 清空 context → 續接時 state 還原 → 不需重講 spec/plan/branch。沒有 state 的 workflow 在 150k 那一行只能撞牆，本 skill 在這裡反而最強。

---

## Model 與委派策略

Model 不綁死在 agent 身上，而是**依工作性質動態選擇**。這是降低成本與延遲的核心。

### Opus 優先原則（最高推論等級的選模規則）

所有需要**最高推論等級**的環節（planner、reviewer、STAGE 2 的「最強 model」分級）一律**使用 Opus 並指定 xHigh effort**（`model: "opus", effort: "xHigh"`）：

```
派發需要最強推論的 Task / agent 呼叫
  → 帶 model: "opus", effort: "xHigh"
```

下表與流程圖中標註 `Opus (xHigh effort)` 與 `Sonnet (Max effort)` 的位置皆使用該設定；「快/便宜」的位置**不受影響**，維持原樣。對於所有 Sonnet 的派發，皆帶 `model: "sonnet", effort: "max"`。

### Stage 層級的基準分配

| Stage | Agent | 基準 Model | agy 委派 | 不委派的原因 |
|-------|-------|-----------|------------|------------|
| 0a/0b 規劃 | planner | Opus (xHigh effort) | — | 設計與計畫拆解是最高槓桿推論，錯了後面全錯 |
| 1 建立分支 | brancher | Sonnet (Max effort) | ✦ gh issue create, git checkout | 純 IO |
| 2 實作 | implementer | **見下方分級** | ✦ 代碼+測試+commit（Claude 驗收）| — |
| 3 審查 | reviewer | Opus (xHigh effort) | — | 根因判斷需最強推論，且不該讓產出代碼的同源 model 自審 |
| 4 發布 | publisher | Sonnet (Max effort) | ✦ Diff 分析 → PR 草稿（Claude 校對）| — |
| 5 回覆 PR Review | responder | Sonnet (Max effort) | — | 逐條意見處理，短文判斷 |

### STAGE 2 implementer 內部的 model 分級

implementer 不該對所有任務一律用同一 model。讀取實作計畫後，**逐任務依複雜度分級**（對齊 `subagent-driven-development` 的 Model Selection）：

| 任務複雜度信號 | 委派 model | 範例 |
|---|---|---|
| 觸及 1–2 檔、規格完整、機械性 | 快/便宜 model | 新增一個 DTO 欄位、補一個 util function |
| 觸及多檔、需整合協調 | 標準 model | 跨 service 串接、改既有流程 |
| 需設計判斷或廣泛 codebase 理解 | 最強 model（Opus, xHigh effort） | 重構狀態機、新增跨層架構 |

planner 在實作計畫中**應為每個任務標註複雜度等級**，implementer 直接據此分派；未標註時 implementer 自行依上表判定。

### 不委派 agy 的硬規則

以下情況即使 agy 可用也**不委派**（短文直生反而更省一次 context 來回）：
- commit message 生成（Sonnet (Max effort)/實作 model 依 diff 直生）
- 單一檔案 < 50 行的小修正
- STAGE 3 審查報告（reviewer 親自判斷，不可委派 agy。註：可選的「多 angle 對抗式審查」用 Claude Workflow 的 verifier 平行找 bug 作為輸入，reviewer 仍親自收斂判斷並產出報告，兩者不衝突——見「用 Claude Workflow 執行並行」章節）

---

## 並行執行契約

並行只在兩處發生：**STAGE 0a 的 context 收集（雙線）** 與 **STAGE 2 的獨立任務並行**。

宣告並行的地方都必須遵守以下契約——光標 🟢 不算數，沒有契約的並行會在衝突時靜默壞掉。

### 何時可並行（判斷條件）

```
                  待處理工作
                       │
          ┌────────────┴────────────┐
          │ ≥2 個工作單元，且彼此    │
          │ 無資料依賴、寫入路徑     │
          │ 互不重疊？               │
          └────────────┬────────────┘
              是 ↓            ↓ 否
        ┌───────────┐   ┌──────────┐
        │ 🟢 並行    │   │ 🔴 序列   │
        └───────────┘   └──────────┘
```

### 並行三規則（缺一不可）

1. **明確 scope**：每個並行單元派發時給定**明確的寫入檔案清單**。STAGE 0a 的兩條是唯讀（只收集，不寫），天然安全；STAGE 2 的並行任務由 planner 在計畫中標好各自的檔案 scope。
2. **共享資源指定唯一 owner**：`pubspec.yaml`、DI 註冊、generated files 等共享檔案，只能指定**一個**並行單元修改。若多個任務都需動到同一共享檔 → 不可並行，退回序列。
3. **結果聚合與失敗短路**（這是契約核心）：

| 情境 | 行為 |
|---|---|
| 全部並行單元成功 | 收斂所有結果 → 統一在暫停點展示 → 問使用者確認 |
| 部分失敗，失敗單元與成功單元**無依賴** | 不中止其他單元（讓它們跑完）→ 聚合時明確標出哪些成功哪些失敗 → 失敗者進入 retry（見下方退回路徑） |
| 部分失敗，且有其他單元**依賴失敗單元的產出** | 立即短路：停止依賴鏈下游，已完成的保留，回報使用者「X 失敗，已暫停依賴它的 Y、Z」 |
| context 在並行中途超標 | 等當前所有並行單元跑完（不切在半途）→ 才執行 Token Gate 的切 session 閉環 |

### 退回路徑（失敗 retry 迴圈）

並行單元失敗時，**不可無限重試**：
```
失敗單元 → 分析原因
  ├─ context 不足  → 補 context，重派同 model（最多 1 次）
  ├─ 任務過大      → 拆成更小單元，重新並行/序列
  ├─ 計畫本身有誤  → 退回 planner（STAGE 0b），不在 STAGE 2 硬修
  └─ 重派仍失敗 2 次 → 停止，回報使用者，等決策（不自動繼續）
```

**與 STAGE 3 退回的關係：** STAGE 2 內部失敗在 STAGE 2 內 retry；STAGE 3 審查不通過才退回 STAGE 2 整體重做。兩者是不同層級的迴圈，不可混用。

---

## 用 Claude Workflow 執行並行（可選加速層）

**僅在使用者已 opt-in 多 agent 編排時啟用**（見開頭「Claude Workflow 編排」總則）。未 opt-in → 三處全部退回原本的 `Task(...)` / 序列作法。

共通鐵則（與「並行三規則」一致，違反即退回序列）：
- 一個 `Workflow` 呼叫 = **一段不可中斷的 fan-out**，跑完才回到主對話。**暫停點永遠在 Workflow 呼叫之外**，由主指揮掌控。
- Workflow 回傳結構化結果後，主指揮負責**聚合、套用 model 策略、寫 state 檔、在既有暫停點展示**。Workflow 內部不碰 state 檔、不問使用者。
- 用 `pipeline()` 為預設；只有「下一步需要前一步全部結果」時才用 `parallel()` barrier。
- 共享檔（`pubspec.yaml`、DI 註冊、generated files）只能有唯一 owner；多任務搶同一檔 → 不可並行，退回序列。

### 適用點 1：STAGE 0a 雙線 context 收集

兩條唯讀調查（A. 專案 context 讀檔/git log｜B. 相似功能代碼調查），無依賴、不寫檔 → 天然安全的 `parallel()` barrier，收斂後才交給 planner 撰寫規格。

```js
// meta 省略；agentType 用 Explore（唯讀搜尋）
const [projCtx, similarCode] = await parallel([
  () => agent('收集專案 context：讀 README / pubspec / 近期 git log，回報架構與慣例', {agentType: 'Explore', schema: CTX_SCHEMA}),
  () => agent('調查與「<需求>」相似的既有實作，回報可參考的檔案與模式', {agentType: 'Explore', schema: CTX_SCHEMA}),
])
// 回到主對話：planner 收斂 projCtx + similarCode → 撰寫 docs/features/...md → 暫停確認（不在 Workflow 內）
```

### 適用點 2：STAGE 2 同批獨立任務

planner 已在計畫中標好各任務的**寫入檔案 scope** 與**複雜度等級**。同一批內「寫入路徑不重疊」的任務 → `pipeline()` 並行，**每個任務沿用原本的逐任務 model 分級**（`opts.model` 帶入計畫標註的等級）。

```js
// batch = 當前批次中路徑不重疊的任務；model 來自計畫的複雜度標註
const results = await pipeline(
  batch,
  task => agent(task.prompt, {label: task.id, model: task.model, isolation: 'worktree', schema: TASK_SCHEMA}),
  (impl, task) => agent(`驗收任務 ${task.id}：跑測試、檢查 diff`, {label: `verify:${task.id}`, schema: VERIFY_SCHEMA}),
)
// 回到主對話：聚合 results → 寫 state（completed_tasks）→ 在「每批完成」暫停點展示 → 問使用者確認下一批
```

> 邊界：**批與批之間的暫停由主指揮控制**，不可把多批塞進同一個 Workflow 連續跑完（那會跳過暫停點）。並行任務改檔時用 `isolation: 'worktree'` 避免互踩工作區。

### 適用點 3：STAGE 3 多 angle 對抗式審查

**reviewer 仍是主導者、最終判斷者**（不違反「審查報告 reviewer 親自判斷」）。Workflow 的 verifier 只是平行找 bug 的助手：每個 verifier 帶**不同 lens**（correctness / security / 回歸風險 / 測試覆蓋），對抗式地嘗試挑出問題，reviewer 收斂所有 verdict 後親自寫審查報告。

```js
const LENSES = ['correctness', 'security', '回歸風險', '測試覆蓋']
const findings = (await parallel(LENSES.map(lens => () =>
  agent(`以 ${lens} 視角審查 <branch> 的 diff，盡力挑出真實問題`, {label: `review:${lens}`, schema: FINDING_SCHEMA})
))).filter(Boolean).flatMap(r => r.findings)
// 回到主對話：reviewer 親自收斂 findings、去重、判定真偽 → 寫審查報告 → 暫停展示（不委派 agy）
```

> 不變式：審查報告由 reviewer（Opus, xHigh effort）親自產出，**不委派 agy**。多 angle 只是提高召回率的輸入，不取代 reviewer 的最終判斷。退回 STAGE 2 的條件與層級不變。

---

## Quick Commands

| Command | Stage | Action |
|---------|-------|--------|
| `/gen-dev-workflow` | — | 查看目前流程狀態 / 開始新流程 |
| `/gen-dev-workflow spec <description>` | 0a | 撰寫功能規格 |
| `/gen-dev-workflow plan <spec-path>` | 0b | 產出實作計畫 |
| `/gen-dev-workflow branch <issue>` | 1 | 建立 Issue + 分支 |
| `/gen-dev-workflow implement <plan-path>` | 2 | 執行實作 |
| `/gen-dev-workflow code-review <branch>` | 3 | 執行代碼審查 |
| `/gen-dev-workflow publish <branch>` | 4 | 建立 PR |
| `/gen-dev-workflow review #<PR>` | 5 | 處理 PR review 意見 |

---

## 跳入特定階段

所有跳入指令都以 `mode: "jump"` 寫入狀態檔。

```
# 重新規劃功能規格（STAGE 0a）
/gen-dev-workflow spec <需求描述>
→ 寫入狀態檔 { stage: "0a", mode: "jump" }
→ 呼叫 planner agent 產出功能規格

# 重新產出實作計畫（STAGE 0b）
/gen-dev-workflow plan <spec 路徑>
→ 寫入狀態檔 { stage: "0b", mode: "jump", spec: "<spec 路徑>" }
→ 呼叫 planner agent 依規格產出實作計畫

# 只需要建分支（STAGE 1）
/gen-dev-workflow branch <ISSUE-NUMBER>
→ 寫入狀態檔 { stage: 1, mode: "jump", issue: <ISSUE-NUMBER> }
→ 呼叫 brancher agent

# 繼續實作（STAGE 2）
/gen-dev-workflow implement <plan 路徑>
→ 寫入狀態檔 { stage: 2, mode: "jump", plan: "<plan 路徑>" }
→ 呼叫 implementer agent

# 只需要審查（STAGE 3）
/gen-dev-workflow code-review <branch-name>
→ 寫入狀態檔 { stage: 3, mode: "jump", branch: "<branch-name>" }
→ 呼叫 reviewer agent

# 只需要發 PR（STAGE 4）
/gen-dev-workflow publish <branch-name>
→ 寫入狀態檔 { stage: 4, mode: "jump", branch: "<branch-name>" }
→ 呼叫 publisher agent

# 處理 PR review 意見（STAGE 5）
/gen-dev-workflow review #<PR>
→ 寫入狀態檔 { stage: 5, mode: "jump", pr: <PR> }
→ 呼叫 responder agent 處理所有 review 意見
→ 處理完畢後呼叫 reviewer agent 重新審查
→ 審查通過後呼叫 publisher agent 更新 PR
```
