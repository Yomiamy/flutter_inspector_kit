# 功能規格：D2 STAGE 2「派發煞車」硬門檻 (Dispatch Brake)

- **日期**：2026-10-01
- **狀態**：STAGE 0a — 規劃中
- **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.2 / §5（D2 提案）
- **類型**：工作流程調度優化與派發煞車規範 (Dispatch Brake)
- **批次項目**：第 3 項 / 共 3 項

---

## 1. 問題陳述（What & Why）

### 一句話本質
在 STAGE 2 引入「派發煞車（Dispatch Brake）」硬門檻：明定「單檔 ≤ 20 行且無公共 API 變更」之微任務強制由主進程原地修改，嚴禁盲目派發 subagent，消除子進程冷啟動延遲與 context 調度浪費。

### 現況行為 vs 期望行為

| 維度 | 現況（無硬煞車門檻） | 期望（修復後：Dispatch Brake 硬門檻） |
|---|---|---|
| **STAGE 2 派發流程** | `SKILL.md` 寫死「→ 呼叫 implementer agent」，所有任務默認啟動 subagent | 實作起手先過「派發煞車」閘門；命中微任務門檻強制主進程原地修改 |
| **微任務標準** | `delegation-and-parallel.md` 僅模糊提及「單一檔案 < 50 行的小修正」，未定義微任務特徵 | 明確量化指標：**單檔、預期變更 ≤ 20 行、無公共 API 變更** |
| **Model 分級矩陣** | 分級表第一級為「觸及 1–2 檔、規格完整、機械性 → 快/便宜」，仍需派發子進程 | 頂層優先分支為「微任務 → 原地修改（派發煞車，禁止派發 subagent）」 |
| **調度開銷與延遲** | 即使改 2 行常數或補 1 個 assert 也啟動 subagent，付出 30–60 秒冷啟動與數萬 token | 微任務原地毫秒級完成並直接執行測試，顯著提升執行吞吐量 |

### 根因分析
1. **LLM 具備 Subagent 能力後的「神經質/懶惰化派發」現象**：調度者模型在有子進程可用時，容易忽視微小改動的調度成本，甚至對 2-3 行的 typo 或常量調整也開 subagent。
2. **流程文檔指示過於死板**：`SKILL.md` 在 STAGE 2 流程中未設計前置的 guard clause，直接指示「呼叫 implementer agent」，促使模型機械式派發。
3. **門檻定義模糊且脫節**：既有的「< 50 行」散落在「不委派硬規則」末尾，既無明確的公共 API 防禦限制，也未整合至 STAGE 2 任務分級決策樹中。

---

## 2. 使用者故事

### US-1：流程編排者具備清晰的調度煞車判準
> 身為流程編排者（AI 或人類），我在 STAGE 2 拆解實作任務時，能依據客觀指標（單檔、≤ 20 行、無 public API 變更）果斷判定原地修改，避免不必要的子進程調度開銷。

### US-2：開發者享受低延遲且流暢的微任務交付
> 身為開發者，在執行小型修正或補充邏輯時，不需要等待子 Agent 的冷啟動與 context 傳遞，能在主對話中快速看見代碼與測試結果，節省寶貴的等待時間。

---

## 3. 驗收條件

### AC-1：STAGE 2 流程引入 Dispatch Brake 判斷
- [ ] `.claude/skills/gen-dev-workflow/SKILL.md` 的 STAGE 2 流程步驟加入「派發煞車 (Dispatch Brake)」門檻。
- [ ] 明定微任務（單檔 ≤ 20 行且無公共 API 變更）原地修改，不派發 implementer，且並行模式僅限未命中煞車之非微任務。

### AC-2：標準化 Dispatch Brake 硬門檻與分級表
- [ ] `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` 的「STAGE 2 implementer 內部的 model 分級」表加入首優先行：
  - 微任務（單檔 ≤ 20 行且無公共 API 變更）→ 原地修改（派發煞車，禁止派發 subagent）。
- [ ] 重構「不委派的硬規則」章節，將「派發煞車 (Dispatch Brake)」列為核心硬門檻並闡明設計動機（消除調度延遲與 context 開銷）。
- [ ] 明確微任務驗收方式：主進程原地執行測試，不需派發獨立 verifier subagent；並行契約同步排除微任務。

### AC-3：速查指引同步更新
- [ ] `.claude/skills/gen-dev-workflow/references/command-cheatsheet.md` 在 STAGE 2 與 STAGE 3 審查不通過修正流程中，補充 Dispatch Brake 的判準與原地執行原則。

### AC-4：Brainstorm 狀態回寫
- [ ] `docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.2 補充 D2 落地說明。
- [ ] §5 待優化項目表中將 D2 標記為 ✅ 已完成。

---

## 4. 範圍邊界

- **In Scope**：
  - 更新 `SKILL.md` STAGE 2 流程步驟。
  - 更新 `references/delegation-and-parallel.md` 分級表與不委派硬規則。
  - 更新 `references/command-cheatsheet.md` 速查說明。
  - 回寫 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`。
- **Out of Scope**：
  - 不實作額外的 benchmark 測試套件（如 `benchmarks/dispatch-brake/`），遵循實用主義避免過度工程。
  - 不更動 PreToolUse 攔截腳本（Bash hook 無法事前準確預測子任務修改行數）。
  - 不影響 Quick 模式（Quick 本就強制全走原地修改）。
  - 不更動現有跨檔與中大型任務的 model 分級邏輯。
