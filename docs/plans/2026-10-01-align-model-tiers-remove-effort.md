# 實作計畫：B5 effort 分層表說謊問題（回歸真實 Model 綁定）

- **日期**：2026-10-01
- **狀態**：STAGE 0b — 待確認
- **規格參考**：[`docs/features/2026-10-01-align-model-tiers-remove-effort.md`](../features/2026-10-01-align-model-tiers-remove-effort.md)
- **模式**：Sequence（Batch Item 2）

---

## 1. 摘要與架構設計

### 背景
`delegation-and-parallel.md` 收錄的「推論等級表」宣稱具備 4 級 `effort` 分層（最強 xhigh、標準 max、輕量 high、快/便宜 —）。自 commit `a6fcd29`（2026-07-15）將 `effort:` 自所有 Agent 的 frontmatter 移除後，該分層機制在實務上從未生效；實際工作流派發時均未帶 `effort` 參數，所有子 Agent 實質上繼承主對話 session 的 effort。這份表格成了典型「心願式文檔（aspirational documentation）」，且附帶的大量 400 報錯排查也增加了維護噪音。

### 核心改動
- 依 Ponytail 刪減原則與 Linus 實用主義，**砍掉推論等級表中的 `effort` 欄位與說謊的分層宣稱**。
- 回歸真實單一事實：各 Agent frontmatter 唯一真實綁定的是 `model`（別名 `opus` / `sonnet` / 內部 fast model），`effort` 由使用者主對話 session 全域掌握與繼承。
- 清理 `delegation-and-parallel.md`、`workflow-parallel.md` 與 `SKILL.md` 中殘留的虛假 effort 參數與過時報錯防禦。
- 回寫 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`，記錄 B5 已完成。

---

## 2. 檔案異動清單

| 檔案 | 變更性質 | 說明 |
|---|---|---|
| `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改 | 推論等級表砍掉 effort 欄位，改為純 Model 等級表；精簡 400 說明為極簡註記；驗收說明移除 explicit effort 要求 |
| `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` | 修改 | 清理範例程式碼中多餘的 `effort:` 覆蓋參數 |
| `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 | STAGE 0b 呼叫 `plan-verifier` 移除冗餘的 `effort: "xhigh"` |
| `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新 B5 條目與 §8.5 表格，標記為已完成 |

---

## 3. 具體任務拆分 (Tasks)

### Task 1: 重構 `delegation-and-parallel.md`（Model 等級表與消滅假分層）
- **檔案**：`.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`
- **操作**：
  1. 將「推論等級表」重構為「Model 等級表」：
     - 表格欄位：`等級`、`model（frontmatter 綁定）`、`綁定的 agent`。
     - 移除 `effort（呼叫時明確帶入...）` 欄位。
  2. 內文確立單一事實：
     - 各 Agent 依其職責於 frontmatter 綁定 `model`（`opus` / `sonnet` / 外部 fast model）。
     - `effort` 由使用者 session 統一管理，所有子 agent 自然繼承主對話設定，不再於呼叫時做假分層。
  3. 精簡 400 錯誤與 thinking 相關的 40 行長篇排查，收斂為 2-3 行務實註記（提示若在未開啟 thinking 的環境強制使用 xhigh 會觸發 API 限制）。
  4. 更新 STAGE 2 驗收與 Stage 層級分配等章節，刪除「需明確帶入 `effort: xhigh`」之描述。
- **驗收**：檔案內不再宣稱「派發時必須顯式帶入 effort」，表格真實反映 frontmatter 與 session 繼承關係。

### Task 2: 清理 `workflow-parallel.md` 與 `SKILL.md` 的殘留參數
- **檔案**：
  - `.claude/skills/gen-dev-workflow/references/workflow-parallel.md`
  - `.claude/skills/gen-dev-workflow/SKILL.md`
- **操作**：
  1. 在 `workflow-parallel.md` 範例代碼中，移除 `effort: 'high'`、`effort: task.effort`、`effort: 'xhigh'`。註解同步說明「effort 繼承 session」。
  2. 在 `SKILL.md` 第 67 行，將 `呼叫 plan-verifier agent（獨立 Opus，effort: "xhigh"）` 簡化為 `呼叫 plan-verifier agent（獨立 Opus）`。
- **驗收**：`git diff` 確認範例代碼與流程描述一致。

### Task 3: 更新 Brainstorm 文件追蹤狀態
- **檔案**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md`
- **操作**：
  1. 更新 B5 條目：標記為已修復，說明採二選一之「砍掉分層表只留 model 欄，回歸 session 繼承」，消除心願式文件。
  2. 更新 §8.5 建議動工順序表：將 B5 的狀態改為完成（待 PR 合併補上 PR 編號）。
- **驗收**：核對 B5 描述與前次 B2/B1/B6 的記錄風格一致。

### Task 4: 全域一致性實查驗證
- **操作**：
  - 執行 `grep -rn "effort" .claude/skills/gen-dev-workflow/`，確認除了對 session 繼承的正確說明外，無任何要求模型「手動顯式帶入 effort 達成 stage 間差異化」的遺留語句。
- **驗收**：Grep 結果乾淨且符合預期。

---

## 4. 風險評估與防禦

- **向後相容性（Never break userspace）**：
  - 各 Agent frontmatter 的 `model:` 綁定維持不變，執行時所使用的模型不變。
  - Subagent 繼承 session effort 是 Claude Code 目前的既定行為，此改動只是將文件與實況對齊，不改變任何執行時期行為。
- **消滅邊界情況**：
  - 停止在文件要求模型顯式傳遞 `effort: xhigh`，從根本上避免了在 thinking 未開啟時撞 400 錯誤的潛在風險。
