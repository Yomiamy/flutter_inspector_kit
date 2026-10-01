# 功能規格：B2 活化 STAGE 3 total_tasks 任務完成度閘門 (Activate Total Tasks Gate)

> **建立日期**：2026-10-01  
> **關聯 Issue / 提案**：[`docs/brainstorm/2026-09-17-workflow-brainstorm.md`](../brainstorm/2026-09-17-workflow-brainstorm.md) §8.2 B2  
> **狀態**：草案 (Draft)  
> **模式**：Sequence (Batch item 1/3)  

---

## 1. 背景與痛點 (Why)

在 `gen-dev-workflow` 狀態機實作中，[`scripts/wf-state.sh:325`](../../.claude/skills/gen-dev-workflow/scripts/wf-state.sh#L325) 內建了進入 STAGE 3（審查階段）的完成度檢查邏輯：

```bash
if [ "$next" = "3" ] && [ "$mode" = "sequence" ]; then
  total="$(jq -r '.total_tasks' "$f")"
  if [ "$total" != "null" ]; then
    completed_count="$(jq -r '.completed_tasks | length' "$f")"
    if [ "$completed_count" -lt "$total" ]; then
      die "實作尚未全部完成（已完成 $completed_count / 共 $total 任務），拒絕推進至 STAGE 3"
    fi
  fi
fi
```

### 現存缺陷
1. **假安全防線**：`init` 預設寫入 `total_tasks: null`。全 repo 僅有 `wf-state.sh` 本體與 `state-machine.md` 的 JSON 範例提及此欄位，**完全沒有任何流程步驟指示模型去設定 `total_tasks`**。
2. **實務從未觸發**：因為永遠是 `null`，所以 `[ "$total" != "null" ]` 永遠不成立，當 STAGE 2 漏做、少做或 hallucinate「全部完成」時，`advance 3` 靜默放行，失去了作業系統級（Sensor）的防禦價值。
3. **消除偽安全**：依據 Birgitta Böckeler 的 Harness Engineering 與 Linus 模式實用主義哲學，既然腳本已備妥 Sensor 邏輯，就必須接上實際訊號（Guides/操作指示），使防線真實生效，而非留存假保護說謊。

---

## 2. 功能定義與使用者故事 (What)

### 使用者故事
* **身為流程編排者（Orchestrator）**：在 STAGE 2 開始執行實作時，我能從 STAGE 0b 確認的實作計畫中讀取任務清單總數 $N$，並透過 `wf-state.sh set <state_file> total_tasks=<N>` 寫入狀態檔。
* **身為開發者 / 驗收審查者**：當子任務尚未全數呼叫 `task-done`（已完成任務數小於 $N$）時，若流程嘗試提前推進到 STAGE 3，狀態機腳本必須直接 `die` 阻擋，拒絕未完工代碼混入審查階段；唯有所有任務完成時才允許推進。

---

## 3. 範圍邊界 (Scope & Boundaries)

### 包含 (In Scope)
1. **流程規範更新**：
   - 在 [`gen-dev-workflow/SKILL.md`](../../.claude/skills/gen-dev-workflow/SKILL.md) 的 STAGE 2 起手步驟明確加入：解析計畫任務數 $N$，執行 `wf-state.sh set <檔> total_tasks=<N>`。
   - 在 [`references/state-machine.md`](../../.claude/skills/gen-dev-workflow/references/state-machine.md) 生命週期表中加入 `total_tasks` 設定的標準指令與說明。
   - 在 [`references/command-cheatsheet.md`](../../.claude/skills/gen-dev-workflow/references/command-cheatsheet.md) 流程速查表中補上該步驟。
2. **狀態機腳本驗證與防護**：
   - 驗證 `wf-state.sh set <檔> total_tasks=<N>` 的型別校驗（必須為正整數）。
   - 確保 `advance 3` 在未達成時阻斷、達成時順利放行。
3. **回寫 Brainstorm 與架構文件**：
   - 回寫 [`docs/brainstorm/2026-09-17-workflow-brainstorm.md`](../brainstorm/2026-09-17-workflow-brainstorm.md) §8.2 B2 與 §8.5 表格，將 B2 標記為已完成。

### 不包含 (Out of Scope)
1. **不影響 Quick 模式**：Quick 模式無 Task 概念，不設定 `total_tasks`，維持 `null` 且不觸發檢查。
2. **不影響 Jump 模式手動跳段**：若使用者手動 `--mode jump --stage 3`，轉移表不套用，維持自由調度。

---

## 4. 驗收條件 (Acceptance Criteria)

1. **AC-1 指令設定生效**：
   - 執行 `wf-state.sh set <檔> total_tasks=3` 後，`wf-state.sh get <檔>` 輸出的 `.total_tasks` 必須為數值 `3`。
2. **AC-2 提前推進阻斷**：
   - 當 `total_tasks=3`，但 `completed_tasks` 僅有 `[1, 2]` 時，執行 `wf-state.sh advance <檔> 3 --confirmed` 必須 exit 1，並輸出 `實作尚未全部完成（已完成 2 / 共 3 任務），拒絕推進至 STAGE 3`。
3. **AC-3 全數完成放行**：
   - 當 `completed_tasks` 達到 `[1, 2, 3]` 時，執行 `wf-state.sh advance <檔> 3 --confirmed` 必須成功 exit 0，且狀態變更為 `stage: "3"`。
4. **AC-4 文件鏈路閉環**：
   - `gen-dev-workflow/SKILL.md`、`state-machine.md`、`command-cheatsheet.md` 皆已正確標註設定步驟與範例。
