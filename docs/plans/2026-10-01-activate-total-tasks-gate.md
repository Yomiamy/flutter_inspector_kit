# 實作計畫：B2 活化 STAGE 3 total_tasks 任務完成度閘門 (Activate Total Tasks Gate)

> **建立日期**：2026-10-01  
> **關聯規格**：[`docs/features/2026-10-01-activate-total-tasks-gate.md`](../features/2026-10-01-activate-total-tasks-gate.md)  
> **複雜度**：低 (Low)  
> **模式**：Sequence (Batch item 1/3)  

---

## 1. 資料結構與設計分析 (Linus-Style Decomposition)

### 核心資料流
* **資料本體**：`.claude/workflow-state/<branch-slug>.json` 中的 `total_tasks` (型別：`number | null`) 與 `completed_tasks` (型別：`number[]`)。
* **修改者與時機**：
  1. `init`：初始化為 `null`。
  2. STAGE 2 起手：Orchestrator 解析 STAGE 0b 實作計畫的任務總數 $N$，執行 `wf-state.sh set <檔> total_tasks=<N>`。
  3. STAGE 2 執行：每個任務完成時執行 `wf-state.sh task-done <檔> <n>`，將任務編號加入 `completed_tasks` 並經 `unique` 去重。
  4. STAGE 2 結束推進至 3：`wf-state.sh advance <檔> 3 --confirmed`，觸發完成度 Sensor 判定：`completed_count < total` 則中斷退出，`completed_count >= total` 則順利晉升。

### 消除特殊情況
* 既有 `wf-state.sh` 已有防護邏輯，但因缺了操作引導，使其常態為 `null` 淪為假防線。本計畫不發明新指令，直接利用既有白名單的 `set total_tasks=<N>`，以最小 diff 閉環。

---

## 2. 異動檔案清單 (File Changes)

1. [`.claude/skills/gen-dev-workflow/SKILL.md`](../../.claude/skills/gen-dev-workflow/SKILL.md)
   - STAGE 2 實作段落加入解析計畫任務總數並呼叫 `wf-state.sh set <檔> total_tasks=<N>` 的明確指示。
2. [`.claude/skills/gen-dev-workflow/references/state-machine.md`](../../.claude/skills/gen-dev-workflow/references/state-machine.md)
   - 生命週期表加入 STAGE 2 起手設定 `total_tasks` 的指示與範例說明。
3. [`.claude/skills/gen-dev-workflow/references/command-cheatsheet.md`](../../.claude/skills/gen-dev-workflow/references/command-cheatsheet.md)
   - 典型 Sequence 流程中補上 `wf-state.sh set <檔> total_tasks=<N>`。
4. [`tests/test_wf_state_total_tasks.sh`](../../tests/test_wf_state_total_tasks.sh) (新建立驗證腳本)
   - 包含正向（全數完成放行）、負向（未完成阻擋）、null 兼容（Quick/Jump 模式無任務時不阻擋）的自動化驗證。
5. [`docs/brainstorm/2026-09-17-workflow-brainstorm.md`](../brainstorm/2026-09-17-workflow-brainstorm.md)
   - 回寫 §8.2 B2 與 §8.5 表格，將 B2 標記為 ✅ 已完成。

---

## 3. 任務拆分 (Tasks)

### Task 1: 建立自動化驗證測試腳本 (TDD / Verification First)
- **路徑**：`tests/test_wf_state_total_tasks.sh`
- **內容**：
  - 測試 `set total_tasks=3` 能正確寫入數值。
  - 測試 `completed_tasks=[1, 2]` 時 `advance 3 --confirmed` 必須 exit 1 並印出錯誤訊息。
  - 測試 `task-done 3` 後 `completed_tasks=[1, 2, 3]` 時 `advance 3 --confirmed` 必須成功進入 stage 3。
  - 測試 `total_tasks=null` 時相容舊行為直接放行。
- **等級**：輕量 (sonnet / effort: high)

### Task 2: 更新 `gen-dev-workflow/SKILL.md` 指示
- **路徑**：`.claude/skills/gen-dev-workflow/SKILL.md`
- **內容**：
  - 在 STAGE 2 流程圖與步驟說明中，明定進入 STAGE 2 的第一動為：「解析計畫中的任務清單，取得總數 $N$，執行 `wf-state.sh set <檔> total_tasks=<N>`」。
- **等級**：標準 (sonnet / effort: max)

### Task 3: 更新參考文件 (`state-machine.md` & `command-cheatsheet.md`)
- **路徑**：
  - `.claude/skills/gen-dev-workflow/references/state-machine.md`
  - `.claude/skills/gen-dev-workflow/references/command-cheatsheet.md`
- **內容**：
  - 在生命週期表格中加入 STAGE 2 起手設定指令。
  - 在速查表中補齊指令呼叫位置。
- **等級**：輕量 (sonnet / effort: high)

### Task 4: 回寫 Brainstorm 記錄
- **路徑**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md`
- **內容**：
  - 更新 §8.2 B2 段落標記為已完成。
  - 更新 §8.5 表格將 B2 標為 ✅ 已完成。
- **等級**：輕量 (sonnet / effort: high)
