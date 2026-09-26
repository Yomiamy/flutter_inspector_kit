# D1 · STAGE 0b Plan 機器對抗初審（Plan-Verifier Adversarial Review）

> **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §5 D1
> **狀態**：功能規格（What & Why）· 2026-09-27

---

## 1. 🔴 痛點與設計批判（Linus-Style Critique）

### 1.1 現況痛點：人類橡皮圖章盲審 (Rubber-Stamping)

在目前的 `gen-dev-workflow` 中，STAGE 0b 產出實作計畫（`docs/plans/YYYY-MM-DD-<feature>.md`）後，流程便直接暫停等待人類開發者確認。
然而在實務開發場景中：
1. **心智疲勞與信任慣性**：
   人類開發者在面對長篇技術計畫時，往往僅快速掃過標題，未細究底層資料結構是否最小化、邊界條件是否已被消除、任務拆分是否有寫入路徑衝突或計畫外加料，便習慣性按下 Enter 放行。
2. **缺陷延遲發現成本高昂**：
   若實作計畫存在架構缺陷或隱藏破壞性（例如違反「Never break userspace」原則或引入不必要的複雜度），一旦放行至 STAGE 2 實作，將導致 implementer 走偏、寫出大量無用抽象代碼、測試失敗，最終在 STAGE 3 審查時被退回重做。
   > 「在 STAGE 0b 攔截一個設計錯誤，成本是 1 次 Plan 重寫；在 STAGE 2 攔截，成本是整組子進程代碼與測試作廢。」

### 1.2 設計原則：以機器對抗初審瓦解盲審

借鏡 Nanako0129/pilotfish 的 `plan-verifier` 機制，引入**獨立於 Planner 的對抗審查者**：
* **全新上下文的獨立推論**：
  不讓 Planner「球員兼裁判」自審。派發獨立的 `plan-verifier`（綁定最強推論 `model: opus` / `effort: xhigh`），站在「預設計畫有重大漏洞」的挑刺視角審閱。
* **四大對抗審查維度 (Linus Mindset)**：
  1. **資料結構最小化**：核心資料結構是什麼？是否有不必要的資料複製或過度轉換？職責歸屬是否簡潔？
  2. **邊界情況消滅（好品味）**：是否能重新設計結構以消滅特殊情況分支，而非打滿 if/else 補丁？
  3. **任務邊界與 YAGNI**：任務拆分是否清晰？寫入檔案是否嚴格隔離？是否有計畫外的額外抽象或依賴（計畫外加料）？
  4. **破壞性與回滾措施**：是否遵循 Never break userspace？既有 public API 是否受損？是否有清楚的驗證與回歸檢查？
* **強制二值化輸出契約**：
  結論只能是 `READY` 或 `REVISE`。
  - `READY`：通過機器初審，放行至 ⏸ 暫停點展示給人類審核。
  - `REVISE`：初審不通過，打回給 Planner 修改計畫，附具體缺陷條目與修改方向。
* **有限重試防禦**：
  REVISE 迴圈最多 2 次。若 2 次修正後仍為 REVISE，自動短路停止並將歧見列出由人類決策，杜絕無窮循環與 Token 爆炸。

---

## 2. 規格細節（What）

### 2.1 Agent 定義：`plan-verifier`
新增專職的計畫驗證 Agent：
* `.claude/agents/plan-verifier.md`
* `.agents/agents/plan-verifier.yaml`
* **屬性**：
  - `model: opus`
  - `tools`: `[Read, Glob, Grep]`（只讀不寫，嚴禁修改代碼或計畫檔案）
  - 任務：對 STAGE 0b 剛產出的實作計畫進行對抗式初審，嚴格驗證資料結構、邊界消滅、任務拆分與破壞性。
  - 輸出契約：結尾必須明確輸出 `READY` 或 `REVISE`。若為 `REVISE`，必須列出【致命缺陷】與【修改方向】。

### 2.2 工作流程整合：STAGE 0b
在 `gen-dev-workflow` 主流程的 STAGE 0b 中：
```text
STAGE 0b：實作計畫
  → 呼叫 planner agent（依據已確認的功能規格）
  → 產出 docs/plans/YYYY-MM-DD-<feature>.md
  → 呼叫 plan-verifier agent（獨立 Opus，對抗初審）
     ├─ REVISE → 退回 planner 修正計畫（最多 2 次）
     └─ READY  → 展示實作計畫 + plan-verifier 審查摘要
  ⏸ 暫停：等使用者確認（balanced / strict 均停）
```

### 2.3 派發與推論契約
* 在 `references/delegation-and-parallel.md` 的「推論等級表」中，將 `plan-verifier` 明確列入「最強推論」（`model: opus`, `effort: xhigh`）。
* 在「Stage 層級的基準分配」中載明 STAGE 0b 由 planner 撰寫，由 plan-verifier 對抗初審。

---

## 3. 影響範圍（Where）

1. `.claude/agents/plan-verifier.md`（新增）
2. `.agents/agents/plan-verifier.yaml`（新增）
3. `.claude/skills/gen-dev-workflow/SKILL.md`（更新流程圖與 STAGE 0b 描述）
4. `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`（更新推論等級表與 Stage 分配）
5. `docs/brainstorm/2026-09-17-workflow-brainstorm.md`（更新 §5 D1 為已完成）
6. `docs/features/2026-09-27-plan-verifier-adversarial-review.md`（本規格文件）
7. `docs/plans/2026-09-27-plan-verifier-adversarial-review.md`（實作計畫文件）

---

## 4. 驗收條件（Acceptance Criteria）

* [ ] `.claude/agents/plan-verifier.md` 與 `.agents/agents/plan-verifier.yaml` 均建立，內容精確對齊，具備四大審查維度與 `READY`/`REVISE` 二值契約。
* [ ] `gen-dev-workflow/SKILL.md` 流程明確定義 STAGE 0b 執行 `plan-verifier` 初審與最多 2 次 REVISE 迴圈。
* [ ] `references/delegation-and-parallel.md` 載明 `plan-verifier` 最強推論與 opus/xhigh 契約。
* [ ] `docs/brainstorm/2026-09-17-workflow-brainstorm.md` §5 D1 狀態更新為已完成。
* [ ] 全套 645 tests 通過，`flutter analyze lib/ test/` 維持既有 7-info 基線。
