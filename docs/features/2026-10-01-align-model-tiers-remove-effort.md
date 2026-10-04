# 功能規格：B5 effort 分層表說謊問題（確認 effort 覆蓋機制）

- **日期**：2026-10-01
- **狀態**：STAGE 0a — 規劃中
- **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §8.3 / §8.5（B5 提案）
- **類型**：流程規範重構與文件去假存真（eliminate aspirational documentation）
- **批次項目**：第 2 項 / 共 3 項

---

## 1. 問題陳述（What & Why）

### 一句話本質
修正「推論等級表」中的描述，確立各 Agent frontmatter 中配置的 `effort` 會明確覆蓋 session 預設設定，以確保不同階層的 Agent 能擁有正確的思考預算。

### 現況行為 vs 期望行為

| 維度 | 現況（文件與實作矛盾） | 期望（修復後：真實 Model 與 Effort 綁定） |
|---|---|---|
| **分層維度** | 宣稱 effort 由 session 全域掌握，但 frontmatter 實際上已恢復設定 | **明確的推論分層**：最強推論 (`model: opus`, `effort: max`/`xhigh`)、標準/輕量 (`model: sonnet`)、快/便宜 (fast model) |
| **Effort 生效方式** | 文件宣稱「子 Agent 天然繼承主對話 session」 | **Frontmatter 覆蓋機制**：各 Agent 依其任務重要性在 frontmatter 中明確設定 `effort`（例如 `effort: max` 或 `effort: xhigh`），這將覆蓋主對話 session 的全域設定 |
| **防禦與例外噪音** | 文件中對於 thinking 關閉時的 API 錯誤處理描述混亂 | **明確的環境要求**：在綁定高 effort 的 Agent 中，明確要求必須在支援 thinking 的環境下執行，避免 API 組合錯誤 |
| **文件真實度** | 文件所寫與 codebase 實況（`.claude/agents/*.md` 實際有 `effort` 綁定）存在認知脫節 | **程式碼 = 文件**：文件精確描述真實運作的機制，確立 frontmatter 中的 effort 設定為權威來源 |

### 根因分析
1. Commit `a6fcd29`（2026-07-15）曾一度移除了所有 Agent frontmatter 中的 `effort:` 設定。
2. 但後續為了確保特定 Agent (如 planner, reviewer) 能有足夠的推論深度，我們已在 frontmatter 中恢復了 `effort: xhigh` 與 `effort: max` 等設定。
3. 然而相關文件（如 `delegation-and-parallel.md` 與計畫書）並未同步更新，仍停留在「完全由 session 繼承」的舊假設，導致實作與文件矛盾。
4. CodeRabbit 在 PR #189 審查中指出了此矛盾，因此需要將所有相關文件更新，以承認並規範 frontmatter 覆蓋 session effort 的機制。

---

## 2. 使用者故事

### US-1：流程編排者與開發者看到真實架構
> 身為流程編排者（AI 或人類），我閱讀 `delegation-and-parallel.md` 時能清楚知道各 Agent 需要的 effort 已被妥善設定在 frontmatter 中，並且知道這會覆蓋當下的 session 設定。

### US-2：確保核心任務具備足夠思考深度
> 身為終端使用者，我不需要在發起工作流時手動調高 session effort，因為系統已經在最需要深度思考的環節（如 planner 與 reviewer）自動透過 frontmatter 綁定了最高等級的推論預算。

---

## 3. 驗收條件

### AC-1：推論等級表反映真實 Model 與 Effort 設定
- [ ] `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` 中的「推論等級表」保留並更新 `effort` 欄位。
- [ ] 內文清楚說明：各 Agent 的 Model 別名與 effort 綁定在 frontmatter，且 frontmatter 中的 effort 會覆蓋呼叫端 session 的設定。

### AC-2：修正錯誤的 session 繼承宣稱
- [ ] `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` 範例與說明更新為「依賴 frontmatter 中的 effort 設定」。
- [ ] `SKILL.md` 等流程文件正確標示獨立 Agent 啟動時所挾帶的 effort 等級。

### AC-3：Brainstorm 文件狀態核實回寫
- [ ] `docs/brainstorm/2026-09-17-workflow-brainstorm.md` 的 B5 條目更新，說明我們選擇了保留並規範 frontmatter 的 effort 覆蓋機制。
- [ ] §8.5 建議動工順序表中，B5 狀態標記為完成。

---

## 4. 範圍邊界

- **In Scope**：
  - 更新 `references/delegation-and-parallel.md`。
  - 更新 `references/workflow-parallel.md`。
  - 更新 `docs/features/2026-10-01-align-model-tiers-remove-effort.md`。
  - 更新 `docs/plans/2026-10-01-align-model-tiers-remove-effort.md`。
  - 更新 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`。
- **Out of Scope**：
  - 不修改 `wf-state.sh` 狀態機腳本。
  - 不修改 Claude Code 或其他外部工具的 session effort 機制。
