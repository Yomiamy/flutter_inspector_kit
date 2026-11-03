# 功能規格：gen-grill 預設同意問法與多題分隔規範 (Yes-Default Framing)

- **日期**：2026-11-03
- **來源**：`docs/brainstorm/2026-10-25-workflow-brainstorm.md` §6.5 C11（`grilling` 預設同意問法，源自上游 `mattpocock/skills` PR #917 `85f83d3` 與 PR #1193 `95249b0`）
- **Effort**：極低 ｜ **排查價值**：⭐⭐⭐

---

## 1. 使用者故事與動機 (What & Why)

### 痛點背景
在 `gen-dev-workflow` 的 STAGE 0·grill 階段，`gen-grill` skill 負責在 planner 撰寫規格之前，以決策樹逐輪（rounds）盤問使用者以對齊需求與邊界。

當一個回合（round）包含多個並行前沿（frontier）問題時：
1. **多題視覺黏連與混淆**：若題與題之間缺乏明確分隔，長篇選項與推薦理由容易混在一起，增加閱讀與批次回覆時的認知負擔。
2. **反向問法與確認歧義（Yes/No Inversion）**：若問題措辭未經嚴格防護，出現反向問法（例如：「是否避免使用 X 機制？（推薦：不，應保留 X）」），使用者若直覺回覆「是」或 `yes`，實際上卻反對了推薦選項，造成人機理解嚴重脫節（Misalignment）。

### 解決方案
對齊上游 `mattpocock/skills` 的最佳實踐（PR #917 與 PR #1193）：
1. **多題水平分隔線 (`---`)**：在每輪格式模板中，明確強制多題之間必須以 Markdown 水平分隔線 `---` 隔開。
2. **預設同意問法 (Yes-Default Framing)**：嚴格規範所有問題的措辭必須正向設計，確保使用者只要回覆「是」（或 `yes`）即代表直接採納推薦選項 `➡️`，**同意永遠不需要回答「否」**。
3. **回寫消除文件狀態漂移**：在 `docs/brainstorm/2026-10-25-workflow-brainstorm.md` 狀態表中回寫 C11 完成紀錄，終結本 repo 的狀態漂移現象。

---

## 2. 驗收條件 (Acceptance Criteria)

- [ ] **AC1 — 預設同意問法明文規範**：
  在 `.claude/skills/gen-grill/SKILL.md` 中，明文化要求每個問題必須以「回答是即接受推薦」的語氣設計，明確防守反向問法（例如「同意永遠不需要回答『否』」）。
- [ ] **AC2 — 多題分隔範本強化**：
  在 `.claude/skills/gen-grill/SKILL.md` 的每輪格式中，維持並強化 `---` 分隔線範例與多題區隔說明。
- [ ] **AC3 — 腦力激盪文件狀態回寫**：
  在 `docs/brainstorm/2026-10-25-workflow-brainstorm.md` §6.5 建議借鏡表之 C11 列，將狀態由「提案」更新為完成，並補註 `d8bd1b8` 與本次規範強化。
- [ ] **AC4 — 零代碼破壞與全套測試通過**：
  純工作流程與規範文件調整，不破壞任何既有 Dart 代碼，`flutter analyze` 與 `flutter test` 維持乾淨通過。

---

## 3. 範圍邊界 (Scope Boundaries)

### In Scope
- `.claude/skills/gen-grill/SKILL.md`（盤問方式章節與範本強化）
- `docs/brainstorm/2026-10-25-workflow-brainstorm.md`（狀態回寫）

### Out of Scope
- 修改 `gen-grill` 的 Q1–Q5 根節點架構或短路條件。
- 修改 `wf-state.sh` 狀態機或暫停點機制。
