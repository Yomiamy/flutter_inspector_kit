# 實作計畫：Qodo Merge 設定支援

- **日期**：2026-06-17
- **Workflow ID**：wf-1781708822-2be9
- **Stage**：0b（實作計畫 — How）
- **對應規格**：`docs/features/2026-06-17-qodo-merge-config-support.md`
- **狀態**：待使用者確認

---

## 1. 核心判斷（Linus 式）

**這不是新功能，是把兩個已存在的檔補完整 + 標註。** 資料結構就是兩個純文字檔，沒有狀態、沒有流程、沒有共享資源。複雜度的本質為零——所有「特殊情況」都來自規格揪出的 4 個缺口，逐一填掉即可，不需要任何抽象。

證據驅動的範圍收斂（STAGE 0b 調查結果）：
- **G-2 已排除**：章節對照確認 `best_practices.md` 涵蓋 `styleguide.md` 全部 8 大章 + X/Y 章的**規範判準**，精簡掉的只是子小節範例程式碼。對 LLM 審查基準而言判準完整 → **G-2 不需處理**。
- 真正要動的只有 **G-1**（補範例詩句）與 **G-3**（v1/v2 書面標註）。**G-4**（README）依規格列為可選。

---

## 2. 資料結構與檔案異動

| 檔案 | 動作 | 對應缺口 |
|------|------|---------|
| `.pr_agent.toml` | 修改：在 `[pr_reviewer].extra_instructions` 補回 4 段文學體裁**範例詩句**；補一段 v1/v2 路線說明註解 | G-1、G-3 |
| `best_practices.md` | 不動（涵蓋度已足，G-2 排除）。*若任務 1 改採「範例放這裡」方案則動此檔* | — |
| `README.md` | 可選：補一行指向 Qodo / Gemini 設定（依使用者決定） | G-4 |

> 既有 `.gemini/config.yaml`、`.gemini/styleguide.md` **零異動**（AC-6，Never break userspace）。

---

## 3. 任務拆分

### 任務 T-1：補回文學體裁範例詩句（G-1）｜複雜度：機械性（快/便宜 model）

- **寫入 scope**：`.pr_agent.toml`（單檔）
- **做什麼**：把 `styleguide.md` 第 21–37 行的 4 段範例（五言絕句「變數命名亂如麻…」、新詩「變數在黑暗中交會…」、俏皮話、順口溜）原文補進 `[pr_reviewer].extra_instructions` 的「結尾創作規範」段，作為 AI 可模仿的 few-shot 樣本。
- **驗收**：`extra_instructions` 含 4 段範例；TOML 仍可被解析（三引號字串內含中文與換行無誤）。→ 滿足 AC-5。

### 任務 T-2：補 v1/v2 路線書面說明（G-3）｜複雜度：機械性（快/便宜 model）

- **寫入 scope**：`.pr_agent.toml`（單檔，與 T-1 同檔 → 兩任務**不可並行，序列執行**）
- **做什麼**：在檔案頂部註解區補一段說明：本設定走 **Qodo v1 (Qodo Merge / PR-Agent)** 路線，讀 repo 內 `.pr_agent.toml` + `best_practices.md`；Qodo **v2 (Qodo Review)** 改用 web dashboard 的 Rule System，repo 檔案是否生效需視所裝 GitHub App 版本而定。
- **驗收**：檔頭含此說明，措辭與規格 §5 G-3 一致。→ 滿足 AC-7。

### 任務 T-3（可選）：README 提及 code review 設定（G-4）｜複雜度：機械性

- **寫入 scope**：`README.md`（單檔）
- **做什麼**：補一小段「Code Review」說明，指向 `.gemini/` 與 `.pr_agent.toml` 兩套設定並存。
- **預設**：**不做**，除非使用者在暫停點明確要求（避免 scope creep / YAGNI）。

### 驗證任務 V：TOML 語法 + 欄位有效性 + .gemini 零異動

- 跑 TOML 解析（python `tomllib` 或等價）確認 `.pr_agent.toml` 可載入。
- `git diff .gemini/` 應為空（AC-6）。
- 對照 AC-1～AC-7 逐條打勾。

---

## 4. 並行判斷

- T-1 與 T-2 **寫同一檔** `.pr_agent.toml` → 違反「共享資源唯一 owner」→ **不可並行，序列執行**（T-1 → T-2）。
- 因屬同檔小修，STAGE 2 實作時**合併為一次編輯**最乾淨（避免兩次 diff 來回）。
- 無多檔獨立任務 → STAGE 2 不啟用 Workflow fan-out，序列即可。

---

## 5. Model 分級（STAGE 2 用）

| 任務 | 複雜度信號 | Model |
|------|-----------|-------|
| T-1 + T-2（同檔小修，規格完整、機械性） | 觸及 1 檔、機械性 | 快/便宜 model（或主對話直接編輯，不委派 agy — 符合「單一檔 < 50 行小修正不委派」硬規則） |
| V（驗證） | 跑解析指令 | 主對話直接執行 |

> 依 skill「不委派 agy 的硬規則」：單一檔小修正直接由主對話編輯 + 驗證，比委派更省一次 context 來回。

---

## 6. 風險與破壞性分析

- **唯一風險**：TOML 三引號字串內補入多段含中文/換行的詩句，可能踩到解析邊界 → V 任務的 `tomllib` 解析即可攔截。
- **破壞性**：零。不動既有 `.gemini`、不動程式碼、不動 CI。兩檔皆為新增/未追蹤狀態，commit 前不影響任何現有行為。
- **回滾**：兩檔尚未 commit，最壞情況 `git checkout -- .pr_agent.toml` 或刪檔即還原。

---

## 7. 完成定義（DoD）

- [ ] T-1：4 段範例詩句已補入 `.pr_agent.toml`
- [ ] T-2：v1/v2 路線說明已補入檔頭
- [ ] V：`.pr_agent.toml` 通過 TOML 解析；`git diff .gemini/` 為空；AC-1～AC-7 全綠
- [ ] （可選）T-3 依使用者決定

---

**下一步**：使用者確認本計畫 → STAGE 1 建立 Issue + 分支（brancher agent）。
