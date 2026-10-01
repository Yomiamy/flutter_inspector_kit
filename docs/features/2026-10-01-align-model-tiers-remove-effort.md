# 功能規格：B5 effort 分層表說謊問題（回歸真實 Model 綁定）

- **日期**：2026-10-01
- **狀態**：STAGE 0a — 規劃中
- **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §8.3 / §8.5（B5 提案）
- **類型**：流程規範重構與文件去假存真（eliminate aspirational documentation）
- **批次項目**：第 2 項 / 共 3 項

---

## 1. 問題陳述（What & Why）

### 一句話本質
砍掉「推論等級表」中徒有其名、從未在實際流程中生效且容易引發 400 警告的 `effort` 欄位與虛假分層宣稱，改為純粹以各 Agent frontmatter 真實綁定的 `model` 為唯一劃分依據，並確立「effort 一律由 session 全域繼承」的單一事實。

### 現況行為 vs 期望行為

| 維度 | 現況（說謊的 effort 分層） | 期望（修復後：真實 Model 分層） |
|---|---|---|
| **分層維度** | 宣稱為「Model + effort 二維分層」（表列 xhigh / max / high / —） | **純 Model 一維分層**：最強推論 (`model: opus`)、標準/輕量 (`model: sonnet`)、快/便宜 (fast model) |
| **Effort 生效方式** | 文件宣稱「呼叫時必須明確帶入」，但實務上除了單一範例或註解外從未帶入，STAGE 2/3 的差異化未曾自動發生 | **Session 自然繼承**：effort 是執行階段由使用者/環境設定的思考強度，子 Agent 天然繼承主對話 session，不在架構層偽裝分層 |
| **防禦與例外噪音** | 文件充斥 40 行關於 `effort: 'xhigh'` / `'max'` 撞 400 錯誤、thinking 被關閉時排查、版本歷史的繁複警告 | **消滅邊界情況**：既然流程派發不再指定 `effort` 參數，不相容的組合與 400 邊界直接在流程層消失，大幅減少認知負擔 |
| **文件真實度** | 文件所寫（推論等級表）與 codebase 實況（`.claude/agents/*.md` 只有 `model` 綁定）存在認知脫節 | **程式碼 > 文件**：文件精確描述真實運作的機制，符合「premature catalog entries become aspirational documentation」的去假原則 |

### 根因分析
1. Commit `a6fcd29`（2026-07-15）移除了所有 Agent frontmatter 中的 `effort:` 設定，原因在於讓 subagent 統一跟隨 session 的思考預算。
2. 然而後續文件維護未將「effort 概念自架構分層中剔除」，反而在 `delegation-and-parallel.md` 建立了「推論等級表」，並要求調度者在派發時「顯式帶入 effort」。
3. 實務上主流程（`SKILL.md` 的各 STAGE）、`command-cheatsheet.md` 等均未遵循該「顯式帶入」要求，所有 Stage 實際上均使用同一個 session effort 執行。
4. 該表格與相關章節成了典型的「心願式文檔 (aspirational documentation)」，徒增閱讀與維護負擔。

---

## 2. 使用者故事

### US-1：流程編排者與開發者看到真實架構
> 身為流程編排者（AI 或人類），我閱讀 `delegation-and-parallel.md` 時能看到與 `.claude/agents/*.md` 一一對應的真實 Model 分級，不被虛構的 effort 表格誤導，也不需要閱讀過時的 400 報錯排查。

### US-2：使用者自主掌握整體思考預算
> 身為終端使用者，我能透過主對話的 session 設定統一控制整條 workflow 的思考深度（low / medium / high / xhigh），而 subagent 自然繼承，不會因流程寫死或強制覆蓋 effort 而撞 API 組合錯誤。

---

## 3. 驗收條件

### AC-1：推論等級表收斂為真實 Model 等級表
- [ ] `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` 中的「推論等級表」移除 `effort` 欄位。
- [ ] 表格明確改為以 `model`（別名 `opus` / `sonnet` / 內部 fast model）為劃分標準。
- [ ] 內文清楚說明：各 Agent 的 Model 別名綁定在 frontmatter，effort 則統一繼承自呼叫端 session，不另行逐 Agent/逐 Stage 做假分層。

### AC-2：清理殘留的虛假 effort 參數與噪音
- [ ] 移除 `delegation-and-parallel.md` 中關於 `effort: 'xhigh'` / `'max'` 撞 400 的長篇歷史背景說明，若保留提示，僅留 1 行極簡說明。
- [ ] `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` 範例代碼中清理多餘的 `effort:` 覆蓋參數，註解同步校正。
- [ ] `SKILL.md` 中 STAGE 0b 呼叫說明去除 `effort: "xhigh"`，回歸單純的「獨立 Opus」。

### AC-3：Brainstorm 文件狀態核實回寫
- [ ] `docs/brainstorm/2026-09-17-workflow-brainstorm.md` 的 B5 條目更新為已完成說明。
- [ ] §8.5 建議動工順序表中，B5 狀態標記為完成。

---

## 4. 範圍邊界

- **In Scope**：
  - 更新 `references/delegation-and-parallel.md`。
  - 更新 `references/workflow-parallel.md`。
  - 更新 `SKILL.md`。
  - 更新 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`。
- **Out of Scope**：
  - 不更動各 Agent 的 `model` 綁定（`planner.md`、`reviewer.md`、`verifier.md` 仍維持 `model: opus`；`implementer.md`、`brancher.md` 等維持 `model: sonnet`）。
  - 不修改 `wf-state.sh` 狀態機腳本。
  - 不修改 Claude Code 或其他外部工具的 session effort 機制。
