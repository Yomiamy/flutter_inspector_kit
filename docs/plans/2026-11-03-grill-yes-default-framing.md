# 實作計畫：gen-grill 預設同意問法與多題分隔規範 (Yes-Default Framing)

> 規格：[`docs/features/2026-11-03-grill-yes-default-framing.md`](../features/2026-11-03-grill-yes-default-framing.md)

---

## 1. 動工前必查結論與資料流向

1. **上游對齊查證 (Q5 既有覆蓋實查)**
   - 上游 `mattpocock/skills` PR #917 (`85f83d3`) 引入以 `---` 分隔多題範本。
   - 上游 PR #1193 (`95249b0`) 引入 Yes-default framing：「Word each question so "yes" accepts your recommended answer.」確保同意永遠不需要回答「否」。
   - 本 repo 於 2026-10-15 之 `d8bd1b8` 實驗性 commit 中已初步移植了 `---` 分隔線與「措辭讓『是』等於接受你的推薦答案」。
   - **本次強化重點**：
     - 正式確立並加強正面問法防禦（避免雙重否定或反向提問造成「說是的實質意圖是反對」）。
     - 更新 `docs/brainstorm/2026-10-25-workflow-brainstorm.md` §6.5 C11 狀態列，杜絕文檔漂移。
2. **零代碼侵入性與 Never break userspace**
   - 本次改動僅限於 Skill 規範文件與 Brainstorm 狀態記錄，完全不牽涉 Dart 原始碼、狀態機 `wf-state.sh` 或專案依賴。

---

## 2. 異動檔案清單 (File Changes)

| 檔案 | 變更類型 | 說明 |
|:---|:---:|:---|
| `.claude/skills/gen-grill/SKILL.md` | 修改 | 明確補充 Yes-default framing 核心規則（正面問法、同意永不答否）與多題 `---` 分隔 |
| `docs/brainstorm/2026-10-25-workflow-brainstorm.md` | 修改 | 更新 §6.5 建議借鏡表 C11 為完成狀態，記錄對齊細節 |

---

## 3. 實作任務拆分 (Tasks)

### Task 1: 強化 `gen-grill` 規範與問法防護 (AC1, AC2)
- **路徑**：`.claude/skills/gen-grill/SKILL.md`
- **內容**：
  - 在「每輪格式」下方，明確闡明：
    - **預設同意問法 (Yes-default framing)**：每個問題的措辭必須正向設計，使使用者回覆「是」（或 `yes`）即代表直接採納推薦選項 `➡️`。設計問句時**絕不可出現反向問法**（即「同意推薦選項時反而必須回答『否』」）。
    - **多題分隔線 (`---`)**：在同一輪內提出多個前沿問題時，題與題之間必須以 `---` 水平線嚴格分隔，避免長篇選項與推薦理由視覺黏連。

### Task 2: 更新 Brainstorm 借鏡狀態表記錄 (AC3)
- **路徑**：`docs/brainstorm/2026-10-25-workflow-brainstorm.md`
- **內容**：
  - 更新 §6.5 表中第 11 項 C11 之狀態為完成，並補註上游 commit 與落地 PR。

---

## 4. 驗收與回滾指引 (Verification & Rollback)

### 驗收步驟
1. 靜態分析與單元測試：
   ```bash
   flutter analyze lib/ test/
   flutter test
   ```
   確保純文件與 Skill 調整完全不影響 Dart 代碼庫。
2. 文本查核：
   檢查 `.claude/skills/gen-grill/SKILL.md` 與 `docs/brainstorm/2026-10-25-workflow-brainstorm.md` 內容。

### 回滾指引
純文字調整，若需回滾直接 `git revert <commit-sha>` 即可乾淨復原。
