# D1 · STAGE 0b Plan 機器對抗初審（plan-verifier）— 實作計畫

> **規格**：[`docs/features/2026-09-27-plan-verifier-adversarial-review.md`](../features/2026-09-27-plan-verifier-adversarial-review.md)
> **日期**：2026-09-27 ｜ **優先序**：P1 ｜ **預估 Effort**：低（Agent 定義與 Workflow 規範整合，零核心代碼改動）

---

## 1. 核心判斷與設計原則 (Linus-Style Mindset)

**消滅人類盲審，在實作之前用獨立對抗推論擋下架構缺陷。**

* **消滅邊界情況與盲審（Good Taste）**：
  人類在 STAGE 0b 容易因為心智疲勞產生橡皮圖章盲審。引進獨立對抗角色 `plan-verifier`，以全新上下文的 Opus 對實作計畫進行挑刺，專注於「資料結構最小化」、「邊界情況消滅」、「任務邊界與 YAGNI」及「破壞性與回滾措施」。
* **極簡二值契約（Pragmatism）**：
  結論不給模糊的「大致可行」，強制只有兩種：`READY`（放行給人類）或 `REVISE`（打回重改）。打回時必須明確指出致命缺陷與改進方向。
* **迴圈防護機制（Simplicity）**：
  Planner 與 Plan-Verifier 的重審迴圈嚴格限制最多 2 次。超過 2 次仍未通過則自動停止並交由人類決策，杜絕無窮循環與 Token 浪費。
* **零執行時代碼開銷（Never break userspace）**：
  純工作流程與 Agent 定義增訂，完全不碰 Flutter 套件核心業務邏輯，維持既有測試全綠與 analyze 7-info 基線。

---

## 2. 流程架構與資料流向

```text
       STAGE 0a 功能規格完成
                 │
                 ▼
       STAGE 0b：Planner 產出實作計畫
                 │
                 ▼
    ┌───────────────────────────────────────────────┐
    │ 派發獨立 plan-verifier (Opus / xhigh effort)  │
    │                                               │
    │ 四大對抗審查維度：                             │
    │ 1. 資料結構最小化（無多餘複製、責任歸屬清晰）  │
    │ 2. 邊界情況消滅（好品味：消除分支而非補丁）    │
    │ 3. 任務邊界與 YAGNI（路徑互斥、無計畫外加料）  │
    │ 4. 破壞性與回滾措施（Never break userspace）  │
    │                                               │
    │ 輸出契約：強制 READY / REVISE 二值            │
    └──────────────────────┬────────────────────────┘
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
          REVISE                       READY
     打回 Planner 修正             放行至 ⏸ 暫停點
   （附缺陷條目，最多 2 次）     展示實作計畫 + 審查摘要
             │                           │
             └────────► 人類介入 ◄───────┘
```

---

## 3. 檔案異動清單

| # | 檔案 | 動作 | 說明 |
|:-:|:---|:---|:---|
| 1 | `.claude/agents/plan-verifier.md` | 新增 | 建立 Markdown 格式的 plan-verifier agent，綁定 `model: opus`，設定 tools 為 `[Read, Glob, Grep]`，定義對抗職責與四大維度及 READY/REVISE 輸出契約 |
| 2 | `.agents/agents/plan-verifier.yaml` | 新增 | 建立 YAML 格式的 plan-verifier agent，保持與 plan-verifier.md 內容完全一致 |
| 3 | `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 | 更新 STAGE 0b 流程圖與步驟說明，加入 plan-verifier 對抗初審與有限重試迴圈 |
| 4 | `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改 | 推論等級表加入 plan-verifier（最強推論，opus / xhigh），Stage 層級基準分配加入 STAGE 0b 初審說明 |
| 5 | `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新 §5 表格與段落中的 D1 狀態為 ✅ 已完成（2026-09-27） |

---

## 4. 任務拆分與執行規劃

### Task 1: 建立 `plan-verifier` Agent 規範檔
- **目標檔案**：
  - `.claude/agents/plan-verifier.md`
  - `.agents/agents/plan-verifier.yaml`
- **實作內容**：
  1. 建立 `.claude/agents/plan-verifier.md`：
     - frontmatter: `name: plan-verifier`, `description: STAGE 0b 實作計畫產出後的獨立對抗初審 subagent。`, `category: quality`, `model: opus`, `tools: [Read, Glob, Grep]`
     - 定義對抗初審角色、四大審查維度（資料結構、邊界消滅、任務拆分/YAGNI、破壞性/回滾）。
     - 定義結論輸出格式（開頭或結尾必須明確為 `READY` 或 `REVISE`）。
  2. 建立 `.agents/agents/plan-verifier.yaml`：
     - 同步更新屬性（`enable_write_tools: false`, `enable_mcp_tools: true`），`system_prompt` 完整對齊 Markdown 定義。

### Task 2: 整合 `gen-dev-workflow` 主流程與推論契約
- **目標檔案**：
  - `.claude/skills/gen-dev-workflow/SKILL.md`
  - `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`
- **實作內容**：
  1. 在 `SKILL.md` 中：
     - 更新 STAGE 0b 區塊：Planner 產出計畫後，派發 `plan-verifier` 執行對抗初審；若 REVISE 則退回 Planner 修正（最多 2 次）；READY 則展示計畫與審查摘要進入 ⏸ 暫停點。
  2. 在 `references/delegation-and-parallel.md` 中：
     - 推論等級表：最強推論等級的綁定 agent 清單補上 `plan-verifier`。
     - Stage 基準分配表：0a/0b 規劃階段加入 plan-verifier 對抗初審之角色與職責。

### Task 3: 更新 Brainstorm 文件追蹤狀態
- **目標檔案**：
  - `docs/brainstorm/2026-09-17-workflow-brainstorm.md`
- **實作內容**：
  1. 將 §5 借鏡項表格中的 D1 狀態由 `提案` 改為 `✅ 已完成（2026-09-27）`。
  2. 在 §3.1 與 §5 相關段落標註落地資訊。

### Task 4: 驗證與基準回歸檢查
- **執行驗證**：
  1. 執行 `flutter test`，確認全套 645 tests 100% 通過。
  2. 執行 `flutter analyze lib/ test/`，確認既有 7-info 基線保持不變。
  3. 核對所有檔案格式與連結完整性。

---

## 5. 複雜度與推論等級標註

* **Task 1**：`快/便宜`（依標準範本精確新增 2 個 agent 定義檔）
* **Task 2**：`標準`（工作流程文件修改，精確嵌入 STAGE 0b）
* **Task 3**：`快/便宜`（文件狀態回寫）
* **Task 4**：`最強推論`（驗證全套測試與基準對齊）
