# 實作計畫：D2 STAGE 2「派發煞車」硬門檻 (Dispatch Brake)

- **日期**：2026-10-01
- **狀態**：STAGE 0b — 待確認
- **規格參考**：[`docs/features/2026-10-01-stage-2-dispatch-brake.md`](../features/2026-10-01-stage-2-dispatch-brake.md)
- **模式**：Sequence（Batch Item 3）

---

## 1. 摘要與架構設計

### 背景
現行 STAGE 2 開發流程中，編排者（Orchestrator）在面對微小改動任務（如單檔改動 2-3 行常數、修復 typo、新增單行 assert / guard clause、補充文檔註解）時，由於流程定義缺乏具體前置衛語句，容易盲目派發子進程（implementer subagent）。這引發了「神經質/懶惰化派發」現象，造成 30–60 秒的冷啟動延遲與數萬 token 的調度浪費。既有文檔僅有模糊的「< 50 行小修正」，未與 STAGE 2 流程對位，亦缺乏公共 API 不變的安全性限制。

### 核心改動
- **引入 Dispatch Brake 硬門檻**：明確量化判準——**單檔、預期變更 ≤ 20 行、且無公共 API 變更**。
- **STAGE 2 流程加入前置衛語句**：在 `SKILL.md` 的 STAGE 2 實作起手處，明定先過「派發煞車」判準，命中者強制由主進程原地修改代碼並原地執行測試，嚴禁派發 subagent。
- **重構 implementer model 分級表與不委派契約**：在 `delegation-and-parallel.md` 中將「微任務原地修改」列為最高優先級；同時重構「不委派硬規則」，將 Dispatch Brake 獨立成章並闡明設計動機。
- **更新速查表與 Brainstorm**：同步 `command-cheatsheet.md`，並回寫 `docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.2 與 §5。

---

## 2. 檔案異動清單

| 檔案 | 變更性質 | 說明 |
|---|---|---|
| `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 | STAGE 2 流程步驟加入「派發煞車 (Dispatch Brake)」門檻判斷 |
| `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改 | 分級表新增微任務原地修改分支；重構不委派章節為 Dispatch Brake 硬門檻 |
| `.claude/skills/gen-dev-workflow/references/command-cheatsheet.md` | 修改 | 速查表中 STAGE 2 補充 Dispatch Brake 操作原則 |
| `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新 §3.2 與 §5，將 D2 標記為 ✅ 已完成 |

---

## 3. 具體任務拆分 (Tasks)

### Task 1: 在 `SKILL.md` 的 STAGE 2 流程加入 Dispatch Brake 閘門
- **檔案**：`.claude/skills/gen-dev-workflow/SKILL.md`
- **操作**：
  - 在 STAGE 2 的 ASCII 流程圖中，明確加入「派發煞車 (Dispatch Brake)」前置衛語句：
    - 微任務（單檔 ≤ 20 行且無公共 API 變更）→ 🛑 煞車：主進程原地修改，不派發 subagent，原地跑測試。
    - 其餘任務 → 判斷並行模式（≥2 個獨立非微任務可並行）並委派實作。
- **驗收**：STAGE 2 流程步驟清楚呈現煞車分支，避免無條件呼叫 implementer，且並行限制在非微任務。

### Task 2: 重構 `delegation-and-parallel.md` 的 model 分級與不委派硬規則
- **檔案**：`.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`
- **操作**：
  1. 在「STAGE 2 implementer 內部的 model 分級」表格頂部加入優先行：
     - `單檔 ≤ 20 行且無公共 API 變更（微任務）`｜`原地修改（派發煞車，禁止派發 subagent）`｜`改常數、修 typo、補單行防禦/assert、修文件註解`。
  2. 將「不委派的硬規則」章節重構為「STAGE 2 派發煞車 (Dispatch Brake) 與不委派硬規則」：
     - 定義 Dispatch Brake 三要素：單一檔案、變更 ≤ 20 行、無公共 API 變更。
     - 闡述核心哲學：消除調度延遲與 context 膨脹。
     - 明定驗收規則：微任務由主進程直接執行相關測試（如 `flutter test`），不派發 verifier subagent。
  3. 更新「並行執行契約」，明確指出並行條件僅適用於未命中派發煞車之獨立非微任務。
- **驗收**：分級表、不委派規則與並行契約完全吻合，定義精準無歧義。

### Task 3: 更新 `command-cheatsheet.md` 的 STAGE 2 速查指引
- **檔案**：`.claude/skills/gen-dev-workflow/references/command-cheatsheet.md`
- **操作**：
  - 在 STAGE 2 與 STAGE 3 審查不通過退回修正流程中，補充 Dispatch Brake 的判斷速查：
    - 提醒編排者遇單檔 ≤ 20 行微任務直接在主對話編輯與跑測試，不派發子 agent；審查修正亦同。
- **驗收**：速查手冊與核心規範保持一致。

### Task 4: 更新 Brainstorm 文件狀態追蹤
- **檔案**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md`
- **操作**：
  1. 在 §3.2 `Dispatch Brake` 標題補充「— ✅ 已完成（2026-10-01 · Issue #...）」。
  2. 在 §5 待優化項目表中，將 D2 的狀態標記為 ✅ 已完成。
- **驗收**：文件精確反映最新落地成果。

### Task 5: 驗證與全域一致性檢查
- **操作**：
  - 檢視 `git diff`，確認文字修改精簡扼要，無冗餘樣板代碼。
  - 確認 `.agents/skills` 符號連結與 `.claude/skills` 完全一致。
- **驗收**：無語意衝突，文檔嚴謹。

---

## 4. 風險評估與防禦

- **向後相容性（Never break userspace）**：
  - 既有中大型任務的 implementer 派發機制完全不受影響。
  - Quick 模式與批次模式行為維持不變。
- **消除邊界情況（Good Taste）**：
  - 藉由明確的三要素（單檔、≤ 20 行、無公共 API 變更），消滅了「要不要開 subagent」的模糊地帶，直接以衛語句阻斷濫用。
