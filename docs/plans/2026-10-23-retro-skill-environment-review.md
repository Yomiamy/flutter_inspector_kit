# 實作計畫：retro skill（環境回顧與 mechanical/judgement 二分）

- **日期**：2026-10-23
- **規格**：[`docs/features/2026-10-23-retro-skill-environment-review.md`](../features/2026-10-23-retro-skill-environment-review.md)
- **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.4 與 §5 C5
- **Effort**：中

---

## 1. 資料結構與設計方向 Trade-off

### 核心哲學
1. **環境回顧而非指責 Agent**：
   - 失敗與摩擦通常源於環境反饋遲緩、缺乏確定性約束、或規範不明確。
   - 拒絕在 prompt/rules 中堆砌「禁止 X」等散文式禁令。
2. **預設是建檢查，不是寫規則**（Mechanical vs Judgement 嚴格二分）：
   - **Mechanical 違規**：凡能透過 AST、正則、檔案路徑、退出碼、Git diff 或特定靜態分析判定的特徵，一律視為機械性違規。
     → **產出**：自動化檢查草稿（PostToolUse/PreToolUse hook、Bash test 斷言、linter 規則、CI 檢查）。
     → **嚴禁**：直接塞進 `.claude/rules/` 或 prompt。
   - **Judgement 項目**：涉及主觀架構權衡、複雜邊界劃分、過度工程簡化判斷、風格語境契合度。
     → **產出**：規範與指引修訂建議（如 `.claude/rules/`、`CODING_STANDARDS.md`、`docs/architecture/`）。
3. **保留使用者裁量權**：
   - Skill 只負責診斷與輸出具體、可複製或執行的方案草稿，不靜默自動修改專案配置。

---

## 2. 檔案異動清單

| 檔案 | 動作 | 說明 |
|:---|:---:|:---|
| `.claude/skills/retro/SKILL.md` | 新增 | 建立 `retro` skill 主文件（二分診斷樹、輸入收集、產出範本、範例） |
| `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 | 在 STAGE 6 清理 Worktree 收尾引導中加入推薦執行 `/retro` 的說明 |
| `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | §3.4 補充 retro skill 落地成果，§5 C5 狀態更新為已完成 |
| `.claude/hooks/tests/test_retro_skill.sh` | 新增 | 自動化驗證腳本：檢驗 retro skill 格式、二分法規範關鍵詞、符號連結與 STAGE 6 連結 |

---

## 3. 任務拆分

**總任務數：2**

### Task 1 `[快/便宜]`：建立 `test_retro_skill.sh` 驗證腳本與新增 `retro` skill
- **寫入路徑**：
  - `.claude/hooks/tests/test_retro_skill.sh`
  - `.claude/skills/retro/SKILL.md`
- **實作重點**：
  1. 建立 `.claude/hooks/tests/test_retro_skill.sh` 測試腳本，驗證：
     - `.claude/skills/retro/SKILL.md` 存在且 `.agents/skills/retro/SKILL.md` 同步可存取。
     - YAML frontmatter 正確（`name: retro`，包含 description 與觸發條件）。
     - 具備核心章節：輸入來源、Mechanical vs Judgement 判定矩陣、輸出範本、正反案例。
     - 包含關鍵準則：「嚴禁將機械性違規寫入 prompt/rules」、「預設建檢查而非寫規則」。
  2. 撰寫 `.claude/skills/retro/SKILL.md`，提供完整清晰的操作指導。
  3. 執行 `bash .claude/hooks/tests/test_retro_skill.sh` 驗證通過。

### Task 2 `[快/便宜]`：更新 `gen-dev-workflow` STAGE 6 引導與 `brainstorm` 知識庫
- **寫入路徑**：
  - `.claude/skills/gen-dev-workflow/SKILL.md`
  - `docs/brainstorm/2026-09-17-workflow-brainstorm.md`
- **實作重點**：
  1. 在 `.claude/skills/gen-dev-workflow/SKILL.md` STAGE 6 加入環境回顧引導提示。
  2. 更新 `docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.4 與 §5 C5（更新為完成並記錄決策）。
  3. 再次執行 `bash .claude/hooks/tests/test_retro_skill.sh` 確保全項目通過。
  4. 執行 `flutter test` 與 `flutter analyze` 確保專案基線零破壞。

---

## 4. 驗收與驗證標準
1. `bash .claude/hooks/tests/test_retro_skill.sh` 5 項測試全部綠燈通過。
2. `flutter test` 750 個測試全部通過。
3. `flutter analyze` 維持 7-info baseline，無任何 error 或 warning。
