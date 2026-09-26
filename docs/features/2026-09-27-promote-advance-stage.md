# 功能規格：B1 promote 推進 stage（消滅 Bug 1.6 Workaround）

- **日期**：2026-09-27
- **狀態**：STAGE 0a — 規劃中
- **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §8.5（B1 P0 提案）
- **類型**：**開發流程狀態機缺陷修復（bug fix / good taste polish）**
- **批次項目**：第 1 項 / 共 3 項

---

## 1. 問題陳述（What & Why）

### 一句話本質
將 `wf-state.sh promote` 晉升 worktree 狀態檔時補上 `.stage = "1"`，徹底廢除逼迫 AI 自行假簽 `--confirmed` 的 Bug 1.6 Workaround，守住人機確認閘門的確定性語意。

### 現況行為 vs 期望行為

| 維度 | 現況（Bug 1.6 遺留補丁） | 期望（B1 修復後） |
|---|---|---|
| `promote` 後的 `stage` 欄位 | 維持 `"0a"`（卡在原 repo 初始階段） | 自動推進至 `"1"`（與物理進入 worktree 一致） |
| STAGE 1 收尾動作 | 強迫手動 `advance 0b --confirmed` → `advance 1 --confirmed` → `stage-done 1` | 直接 `stage-done 1`，流暢自然 |
| `--confirmed` 旗標語意 | 被 AI 假報兩次，破壞「人類使用者親自確認過」的安全契約 | 嚴格維持「只在使用者真正確認時由主對話帶入」 |
| `state-machine.md` 說明 | 充斥 6 行「STAGE 1 收尾必讀 (Bug 1.6 Workaround)」補丁文字 | 移除該 Workaround，維持乾淨極簡的生命週期表 |

### 根因分析
1. `wf-state.sh:240` 的 `promote` 只做了 `.branch = $b`，未更新 `.stage`，導致 state 仍為 `"0a"`。
2. 歷史上（2026-07-30）曾顧慮 quick 模式升級而選擇不碰腳本、改用文件 workaround。但後續（2026-08-25）架構演進已廢除「就地升級」（改為收工重來重新規劃），`promote` 唯一定位即是「從無 worktree 的 pending 階段晉升為 STAGE 1 worktree」。
3. 當時的 workaround 要求模型在無使用者介入的狀態下，自行帶 `--confirmed` 執行兩次 `advance`。這嚴重腐蝕了安全棘輪：模型學會了假造確認，使 `strict` / `balanced` 模式的人機閘門面臨被無聲繞過的風險。

---

## 2. 使用者故事

### US-1：開發流程總指揮（AI）在 STAGE 1 自然收尾
> 身為 `gen-dev-workflow` 的總指揮，我在 STAGE 1 建立好 worktree 並執行 `promote` 後，能直接呼叫 `stage-done 1`，無需練習假簽 `--confirmed`。

### US-2：使用者享受不被假報腐蝕的安全閘門
> 身為開發者，我希望 `--confirmed` 永遠代表我本人的真實授權，狀態機腳本不得依賴偽造的 `--confirmed` 來維持正常 sequence 運轉。

---

## 3. 驗收條件

### AC-1：`promote` 自動將 `stage` 設為 `"1"`
- [ ] 執行 `wf-state.sh init` 產出 pending 檔（`stage: "0a"`）。
- [ ] 執行 `wf-state.sh promote <pending-file> --branch <branch> --dest <dest>` 後，產出的 state 檔中 `.stage` 必為 `"1"`，`.branch` 為指定分支名。

### AC-2：STAGE 1 happy path 無需任何多餘 advance
- [ ] 在 `promote` 後直接執行 `wf-state.sh stage-done <state-file> 1`，順利成功，不被 sequence guard 擋下（回傳退出碼 0）。
- [ ] 在 `strict` 模式下 `awaiting_confirmation` 成為 `true`；在 `balanced` 模式下 `awaiting_confirmation` 成為 `false`。

### AC-3：文件清理乾淨
- [ ] `.claude/skills/gen-dev-workflow/references/state-machine.md` 內所有關於 Bug 1.6 Workaround 的指示與說明均已移除。
- [ ] 生命週期表格與說明回歸直截了當的 `promote` → `stage-done 1`。

---

## 4. 範圍邊界

- **In Scope**：
  - 修改 `.claude/skills/gen-dev-workflow/scripts/wf-state.sh` 中的 `promote` 指令（改 1 行）。
  - 清理 `.claude/skills/gen-dev-workflow/references/state-machine.md` 中的 workaround 指示。
  - 編寫/執行驗證指令確認 AC-1 與 AC-2。
- **Out of Scope**：
  - 不修改 `advance`、`stage-done` 或 `legal_transition` 的轉移規則。
  - 不修改 `quick` 模式的相關行為。
