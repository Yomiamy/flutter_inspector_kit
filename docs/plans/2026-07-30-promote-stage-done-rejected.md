# 實作計畫：修復 promote 後 stage-done 1 恆遭拒

- **日期**：2026-07-30
- **狀態**：STAGE 0b — 已完成（實作已於 branch 上）
- **規格來源**：`docs/features/2026-07-30-promote-stage-done-rejected.md`
- **類型**：bug fix，純文件修改，最小 diff

---

## 1. 技術決策（Decisions）

### D1. 修復策略：Workaround in SKILL.md（不動腳本）

**選擇**：修改 SKILL.md 的操作指引，而非修改 `wf-state.sh` 腳本。

**理由**：
1. **「Never break userspace」原則**：`wf-state.sh` 的狀態機是整體流程心臟。動核心腳本就必須對另外三種啟動模式（`quick`、`jump`、`upgrade`）做全面性回歸測試，牽一髮而動全身。
2. **實用主義**：底層轉移表（0a→0b→1）邏輯嚴謹且正確。修改 SKILL.md 讓 AI 遵守嚴格的腳本規則，成本極低、零副作用且絕對安全。
3. **已否決的替代方案**：曾提議讓 `promote` 一併設定 `stage=1`，但經 PR review 發現 promote 也服務 quick→sequence 升級路徑（upgrade 後 stage 為 `2`），無條件寫死 `stage=1` 會打回 `2`。

### D2. SKILL.md 修改位置：兩處精準插入

| 位置 | 修改內容 |
|---|---|
| 狀態機腳本表格（promote 行） | 加入括號註記：sequence 模式下 promote 後須依序 advance |
| State 檔生命週期表（STAGE 1 建好 worktree 後） | 加入 `🔴 STAGE 1 收尾必讀 (Bug 1.6 Workaround)` 完整三步操作指引 |

### D3. Brainstorm 文件更新策略

- §6 Bug 1.6 區段標記 `✅ 已修`。
- 記錄完整的誤判過程（避免重蹈）。
- 記錄被否決的錯誤修復方向及其原因。
- 追加 rationale 段落解釋為何選 workaround 而非改腳本。

### D4. 文件重命名對齊日期

- `docs/architecture/2026-07-21-gen-dev-workflow-analysis.md` → `2026-07-30-gen-dev-workflow-analysis.md`
- `docs/brainstorm/2026-07-17-workflow-brainstorm.md` → `2026-07-30-workflow-brainstorm.md`

---

## 2. 檔案異動總覽

| 檔案 | 動作 | 淨變更規模 |
|---|---|---|
| `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 | 2 行（兩處 promote 相關行加入 workaround 註記） |
| `docs/brainstorm/2026-07-30-workflow-brainstorm.md` | 重命名+修改 | +39 行（Bug 1.6 已修標記 + 完整根因分析 + 決策記錄 + rationale） |
| `docs/architecture/2026-07-30-gen-dev-workflow-analysis.md` | 重命名+修改 | +9 行（同步更新） |

**新增檔案數：0。無程式碼變更、無新增依賴。**

---

## 3. 任務拆分

所有任務為序列執行（檔案間有引用關係），複雜度皆為 `快/便宜`。

### T1｜SKILL.md 新增 Bug 1.6 Workaround 註記

- **複雜度**：`快/便宜`
- **寫入 scope**：`.claude/skills/gen-dev-workflow/SKILL.md`
- **內容**：
  - 狀態機腳本表格的 promote 行：加括號說明 sequence 模式下需依序 advance
  - State 檔生命週期表的 STAGE 1 行：加 `🔴` 醒目 Workaround 區塊
- **驗收**：SKILL.md 語法正確、兩處修改一致不矛盾

### T2｜Brainstorm 文件更新 Bug 1.6 修復記錄

- **複雜度**：`快/便宜`
- **寫入 scope**：`docs/brainstorm/2026-07-30-workflow-brainstorm.md`
- **內容**：
  - §6 Bug 1.6 標記 `✅ 已修`
  - 記錄誤判過程（`&&` 鏈中斷的錯誤診斷）
  - 記錄被否決的修復方向（promote 寫死 stage=1）
  - 追加 workaround 選擇 rationale
- **驗收**：Markdown 格式正確、結論與 SKILL.md 的 workaround 一致

### T3｜Architecture 文件同步與日期對齊

- **複雜度**：`快/便宜`
- **寫入 scope**：`docs/architecture/2026-07-30-gen-dev-workflow-analysis.md`
- **內容**：重命名 + 同步 Bug 1.6 相關段落
- **驗收**：檔案存在、內容引用正確

---

## 4. 出口檢查（對照規格 AC）

| AC | 由哪個任務保證 |
|---|---|
| AC-1 sequence STAGE 1 promote 後能正確收尾 | T1（SKILL.md workaround 指引）+ 人工驗證紀錄（已成功執行 advance 0b, advance 1, stage-done 1 並驗證通過） |
| AC-2 其他模式不受影響 | T1（不動腳本，零影響） |
| AC-3 SKILL.md 清楚可執行 | T1（兩處醒目標記） |
| AC-4 Brainstorm 文件如實記錄 | T2 + T3 |

## 5. 明確不做（Out-of-scope）

不修改 `wf-state.sh`、不新增自動化測試、不修改任何 Dart/Flutter 程式碼。
