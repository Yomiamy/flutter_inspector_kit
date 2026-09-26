# 實作計畫：B1 promote 推進 stage（消滅 Bug 1.6 Workaround）

- **日期**：2026-09-27
- **狀態**：STAGE 0b — 待確認
- **規格參考**：[`docs/features/2026-09-27-promote-advance-stage.md`](../features/2026-09-27-promote-advance-stage.md)
- **模式**：Sequence（Batch Item 1）

---

## 1. 摘要與架構設計

### 背景
`gen-dev-workflow` 在 STAGE 1 建立分支與 worktree 後，使用 `wf-state.sh promote` 將 pending 狀態檔轉移至 worktree 中。目前 `promote` 僅寫入 `.branch = $b`，未修改 `.stage`，導致狀態仍留在 `"0a"`，隨後呼叫 `stage-done 1` 時被 sequence 狀態校驗拒絕。歷史補丁要求模型手動執行兩次 `advance --confirmed`，腐蝕了 `--confirmed` 旗標「使用者親自確認」的安全語意。

### 核心改動
- 實作「Good Taste」極簡修正：`promote` 的本質就是推進至 STAGE 1，直接在 jq 管道加入 `.stage = "1"`。
- 清理 `state-machine.md` 中的所有 Bug 1.6 Workaround 文字與範例，消除 AI 假報 `--confirmed` 的後門。

---

## 2. 檔案異動清單

| 檔案 | 變更性質 | 說明 |
|---|---|---|
| `.claude/skills/gen-dev-workflow/scripts/wf-state.sh` | 修改 | `promote` 指令補上 `.stage = "1"`（改 1 行） |
| `.claude/skills/gen-dev-workflow/references/state-machine.md` | 修改 | 清理 Bug 1.6 Workaround 相關敘述與指令序列（刪除冗餘補丁） |

---

## 3. 具體任務拆分 (Tasks)

### Task 1: 修正 `wf-state.sh` 的 `promote` 指令
- **檔案**：`.claude/skills/gen-dev-workflow/scripts/wf-state.sh:240`
- **操作**：
  將：
  ```bash
  jq --arg b "$branch" '.branch = $b' "$src" | atomic_write "$f"
  ```
  改為：
  ```bash
  jq --arg b "$branch" '.branch = $b | .stage = "1"' "$src" | atomic_write "$f"
  ```
- **驗收**：`bash -n .claude/skills/gen-dev-workflow/scripts/wf-state.sh` 語法檢查通過。

### Task 2: 清理 `state-machine.md` 中的 Bug 1.6 Workaround
- **檔案**：`.claude/skills/gen-dev-workflow/references/state-machine.md`
- **操作**：
  1. 第 29 行生命週期簡表：移除 `（注意：sequence 模式下 promote 後須依序執行 advance 0b --confirmed → advance 1 --confirmed ...）`。
  2. 第 96 行生命週期詳表：移除 `🔴 STAGE 1 收尾必讀 (Bug 1.6 Workaround)` 警告區塊與手動 advance 指令，更新為標準的 `promote` → `stage-done 1`。
- **驗收**：確認檔案內已無任何 Bug 1.6 或假報 `--confirmed` 的遺留指引。

### Task 3: 狀態機轉移驗證與回歸測試
- **驗證項目**：
  1. 建立測試 pending 狀態檔：`wf-state.sh init`。
  2. 執行 `wf-state.sh promote`：驗證輸出狀態檔之 `.stage` 為 `"1"`，`.branch` 正確寫入。
  3. 執行 `wf-state.sh stage-done <檔> 1`：確認順利成功（退出碼 0），無任何 guard 報錯。
  4. 驗證 `advance 2 --confirmed` 正常推進至 STAGE 2。
  5. 清理測試產物。

---

## 4. 風險評估與防禦

- **向後相容**：`promote` 僅在 STAGE 1 建立 worktree 時調用，設置為 `"1"` 正好與後續的 `stage-done 1` 契約完全吻合。
- **無人值守 / balanced 模式相容**：`balanced` 模式下 `stage-done 1` 自動將 `awaiting_confirmation` 設為 `false`，後續 `advance 2` 無需 `--confirmed` 即可順利推進，更加乾淨。
