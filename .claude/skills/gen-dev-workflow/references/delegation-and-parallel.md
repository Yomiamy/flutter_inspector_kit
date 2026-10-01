# Model 委派與並行契約（gen-dev-workflow 參考）

> 本檔是 `gen-dev-workflow` 主 skill 的委派與並行參考。主檔（`../SKILL.md`）在派發子 agent、決定並行、或處理失敗 retry 時指向這裡。
> 本檔收錄「推論等級表」（唯一定義處）、完整綁定原則、風險註記、Stage 分配、implementer 分級、派發煞車 (Dispatch Brake) 與不委派硬規則，以及並行契約全文。

## Model 與委派策略

Model 別名綁在各 agent 檔的 frontmatter（`.claude/agents/*.md`），主文件只寫**角色名**與**推論等級名**——這是降低 model 換代維護成本的核心，換代時只動 agent 檔一行（甚至因為用別名而完全免改）。

> **effort 由 Session 全域掌握與繼承。** 各 agent 的 frontmatter 僅綁定 `model`；子 agent 預設完全繼承主對話 session 目前的 effort 與 thinking 設定。不逐 agent 或逐 stage 人工指派 effort，消滅虛假分層與派發時必須顯式帶參的維護負擔。

### Model 等級表（等級 → 綁定，全文唯一定義處）

| 等級 | model（frontmatter 綁定） | 綁定的 agent |
|------|-----------------|-------------|
| 最強推論 | `model: opus` | planner、reviewer、verifier、plan-verifier |
| 標準 | `model: sonnet` | implementer |
| 輕量 | `model: sonnet` | brancher、responder、publisher |
| 快/便宜 | 委派後端內部 fast model（不在 Claude 側綁定） | STAGE 2 機械性任務 |

**綁定原則：**
- model 一律用**別名**（`opus`/`sonnet`），不綁版本 ID——CLI 自動解析到當代 model。
- effort **由主對話 session 統一繼承**：子 agent 自動跟隨 session 的思考強度（low / medium / high / xhigh），派發時無需顯式指定 `effort` 參數。
- 要調整某角色的等級 → 改該 agent 檔的 `model` 一行即可，無需在呼叫端散落硬編碼。

> 註：在未啟用 thinking 的環境下若底層嘗試使用不相容的 effort 曾有 400 報錯前例；由主對話 session 統一繼承 effort 可避免因子 agent 寫死或指定不支援的參數而撞 API 約束。

### Stage 層級的基準分配

| Stage | Agent | 推論等級 | MCP 委派 | 不委派的原因 |
|-------|-------|-----------|------------|------------|
| 0a/0b 規劃與初審 | planner、plan-verifier | 最強推論 | — | 設計與計畫拆解是最高槓桿推論；plan-verifier 以全新獨立 Opus 扮演對抗挑刺初審，輸出 READY/REVISE 二值契約，瓦解盲審 |
| 1 建立 Issue + Worktree | gen-gh-issue skill + brancher | 輕量 | ✦ gh issue create/view, git worktree add, flutter pub get | Issue body 由 gen-gh-issue 產（五區段 zh-tw，或 issue-id 路徑由 brancher 解析既有 issue），brancher 依 gen-dev-worktree 規則建立 worktree + branch，皆純 IO |
| 2 實作 | implementer | 標準（逐任務再分級，**見下方分級**） | ✦ 代碼+測試+commit（驗收委派 verifier：最強推論）| — |
| 3 審查 | reviewer | 最強推論 | — | 根因判斷需最強推論，且不該讓產出代碼的同源 model 自審 |
| 4 發布 | publisher（內部用 gen-pr skill） | 輕量 | ✦ Diff 分析 → PR 草稿（Claude 校對）| PR 描述由 gen-pr 產（Summary + 修正問題/修正方式），publisher 負責 push + gh pr create；重活已委派，且發布前有暫停點人肉把關 |
| 5 回覆 PR Review | responder（→ reviewer → publisher） | responder: 輕量；reviewer: 最強推論；publisher: 輕量 | — | responder 逐條意見判斷用輕量即可；中間 reviewer 是交叉驗證的把關點，吃重推論不降級 |
| 6 清理 Worktree | gen-sync-docs-by-branchs → gen-commit → worktree-close-cleanup skill | —（skill 於主對話執行） | — | 先同步文件再 commit，確保 docs 反映分支最終狀態；之後由主對話親自執行 `git worktree remove`（不委派 MCP），事後驗證 `git worktree list` / `git branch --list` |

### STAGE 2 任務分級與「派發煞車 (Dispatch Brake)」

實作任務不該盲目派發子進程。讀取實作計畫後，**逐任務先過「派發煞車」門檻，其餘依複雜度分級**（對齊 `subagent-driven-development` 的 Model Selection）：

| 任務複雜度信號 | 委派等級 | 範例 |
|---|---|---|
| **單檔 ≤ 20 行且無公共 API 變更（微任務）** | **🛑 原地修改（派發煞車，禁止派發 subagent）** | 改常數、修 typo、補單行防禦/assert、修文件註解 |
| 觸及 1–2 檔、規格完整、機械性 | 快/便宜 | 新增一個 DTO 欄位、補一個 util function |
| 觸及多檔、需整合協調 | 標準 | 跨 service 串接、改既有流程 |
| 需設計判斷或廣泛 codebase 理解 | 最強推論 | 重構狀態機、新增跨層架構 |

planner 在實作計畫中**應為每個任務標註複雜度等級**，若為微任務則標記 `[原地修改]`，編排者直接據此分派；未標註時編排者自行依上表判定。

### STAGE 2 驗收的 model（與實作 model 分離）

驗收（spec compliance → code quality 兩階段）**不沿用主對話當前 model**，而是**委派 verifier agent** 執行——其 frontmatter 綁定 `model: opus`，opus 取不到時由 CLI fallback 鏈自動落到可用的最強 model。

這麼設計的原因與 STAGE 3 相同——**產出代碼的委派後端可能用便宜/快 model，驗收刻意用最強推論交叉檢查**，不讓同源 model 自審，維持「驗收等級 ≥ 實作等級」的把關強度。

> 落地方式：`Task("verifier", ...)` 或 Workflow 的 `agent('驗收任務...', {agentType: 'verifier', ...})` 執行（見 `references/workflow-parallel.md` 適用點 2 的 verify 階段）。這是 STAGE 2 唯一會脫離「主對話 model」的環節。

> **微任務驗收例外（派發煞車配套）**：命中派發煞車之微任務（單檔 ≤ 20 行且無公共 API 變更），由主進程在原地執行相關測試（如 `flutter test`），**不派發獨立 verifier subagent**，避免 5 行改動卻付出獨立 Opus 驗收的來回延遲；非微任務之一般實作任務仍嚴格維持上述 verifier 獨立驗收契約。

### STAGE 2 派發煞車 (Dispatch Brake) 與不委派硬規則

以下情況即使 MCP 或 Subagent 可用也**不委派**（短文直生與原地修改反而更省一次 context 來回與冷啟動延遲）：

1. **STAGE 2 派發煞車 (Dispatch Brake) 硬門檻**：
   - **條件（三要素缺一不可）**：
     1. 僅觸及單一檔案。
     2. 預期變更行數 ≤ 20 行。
     3. 無任何公共 API（公開 class / method / signature / export）變更。
   - **行為**：主進程原地修改代碼，並在原地執行測試。**嚴禁派發 implementer subagent**。
   - **動機**：啟動子 Agent 需複製 context、初始化工具鏈與進程 IPC，耗時 30–60 秒與數萬 token。微任務原地完成可消滅神經質派發與不必要的調度延遲。
2. **commit message 生成**（實作 model 依 diff 直生）。
3. **STAGE 3 審查報告**（reviewer 親自判斷，不可委派。註：可選的「多 angle 對抗式審查」用 Claude Workflow 的 verifier 平行找 bug 作為輸入，reviewer 仍親自收斂判斷並產出報告，兩者不衝突——見 `references/workflow-parallel.md` 適用點 3）。
4. **對外動作一律自己執行**：`gh pr create`、`git push` 不委派子進程動手，且須先通過對應暫停點

---

## 並行執行契約

並行的固定發生處有兩個：**STAGE 0a 的 context 收集（雙線）** 與 **STAGE 2 中未命中派發煞車的獨立任務並行**。另有第三處**僅在使用者 opt-in 多 agent 編排時**成立：**STAGE 3 的多 angle 對抗式審查**（平行 verifier 只是輸入，reviewer 仍親自收斂判斷並產出報告——定義見 [`workflow-parallel.md`](workflow-parallel.md)，該檔為唯一來源）。

宣告並行的地方都必須遵守以下契約——光標 🟢 不算數，沒有契約的並行會在衝突時靜默壞掉。

### 何時可並行（判斷條件）

```text
                  待處理工作
                       │
          ┌────────────┴────────────┐
          │ ≥2 個非微任務，且彼此    │
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

並行單元（或單一任務）失敗時，**不可無限重試**。
針對實作/邏輯錯誤，採用「同 tier 重派失敗 2 次 → 升一級 tier 再試 1 次」的漸進升級策略（硬性限制最多升級一次）：

```text
失敗單元 → 分析原因
  ├─ 基礎設施錯誤  → **不計入失敗次數**（見下方「為什麼要分類」）
  │                   400 參數/thinking 不支援 → 先確認環境 thinking 設定，非原樣重派
  │                   429 / 5xx / 連線中斷 → 同 tier 重派 1 次，再依重派結果分流：
  │                     · 仍是基礎設施錯誤 → 停止並回報使用者，不升級 tier（升級對基礎設施錯誤無效）
  │                     · 變成其他失敗類型 → 回本表重新分類，走該類型自己的分支
  ├─ context 不足  → 補 context，重派同 model（最多 1 次）
  ├─ 任務過大      → 拆成更小單元，重新並行/序列
  ├─ 計畫本身有誤  → 退回 planner（STAGE 0b），不在 STAGE 2 硬修
  └─ 邏輯/實作失敗（重試與升級機制）：
       1. 同 tier (當下 model) 重派，最多失敗 2 次。
       2. 失敗 2 次後，判斷是否已為最高 tier (Opus)：
          - 若是 → 停止，回報使用者，等決策（不自動繼續）。
          - 若否 → 將該任務升級一級 tier（例：快/便宜 → 標準，或標準 → 最強），再試 1 次。
       3. 升級後若仍失敗 → 停止，回報使用者，等決策（不自動繼續）。
```

> **Tier Upgrade 紀錄：** 當觸發 tier 升級時，必須在進度回報行中明確註記（例如：`[任務 N 升級至 標準 model]`），讓使用者知悉該任務正動用更高成本嘗試解決。

> **為什麼基礎設施錯誤要與能力不足分開算：** 升級 tier 的前提是「這個執行者不夠強」。基礎設施錯誤（參數不被支援、限流、服務端錯誤、連線中斷）與 model 強弱無關，**換更強的 model 對它零幫助**。若混為一談，一次參數不相容的 400 會吃掉兩次同 tier 重試（必然重現）再觸發升級，而最高 tier 無處可升，最終走到「停止並等使用者決策」——三次派發全部注定失敗，且給出錯誤診斷。
>
> 清單刻意維持極小，**只列實際觀測到或判斷無歧義的**：`400` 參數/thinking 不支援、`429` 限流、`5xx`、連線中斷。**不要**擴寫成一份投機的暫時性錯誤分類學——字串比對錯誤訊息終究會誤判，而誤判的代價（多一次同 tier 重試）必須小於它要解決的問題。

**與 STAGE 3 退回的關係：** STAGE 2 內部失敗在 STAGE 2 內 retry；STAGE 3 審查不通過才退回 STAGE 2 整體重做。兩者是不同層級的迴圈，不可混用。
