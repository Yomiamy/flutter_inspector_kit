# 功能規格：retro skill（環境回顧與 mechanical/judgement 二分）

- **日期**：2026-10-23
- **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.4 與 §5 項目 C5
- **Effort**：中 ｜ **價值**：⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在完成開發 session、PR 建立或 worktree 收尾的工程師／AI agent，
> 我希望**透過 `/retro` skill 系統性回顧開發過程中遇到的阻礙、測試退回、違規與反覆修改，並由 retro skill 嚴格依據「Mechanical vs Judgement」二分法將問題拆解為可落地的環境改進**，
> 這樣所有**機械性違規**都能被轉化為確定性的自動化檢查（linter / hook / Bash 斷言 / 測試），絕不塞進 prompt/rules 造成 context 膨脹與記憶漂移；而**判斷型問題**才提煉為規則指引，使開發環境持續自我強化。

### 為什麼需要這項改進

目前團隊或 AI agent 在遇到違規（如：檔案位置放錯、import 格式不符、使用了已淘汰 API、缺少特定檔案註解）時，最常見的本能反模式是「在 prompt、CLAUDE.md 或 rules 裡加上一條條『禁止...』『必須...』的文字」。
這會帶來兩大致命問題：
1. **Context Load 爆炸**：常駐 context 隨每次違規不斷膨脹，每輪對話都在燒 token，稀釋 LLM 對核心任務的注意力。
2. **否定式規則失效**：LLM 存在 _don't think of an elephant_ 效應，「禁止 X」常導致模型更容易犯 X，且散文式的「禁止」沒有任何程式強制力。

依據 Pilotfish §3.4 洞見，根本解決方案是**回顧環境而非指責 agent**，並且實施嚴格的 **Mechanical vs Judgement 二分法**：
- **預設是建檢查，不是寫規則**。
- 機械性違規（可由程式碼特徵判定者）一律做成 deterministic check（linter / pre-commit / PostToolUse hook / Bash test 斷言）。
- 只有真正的 Judgement call（架構權衡、跨檔一致性、周邊風格契合）才寫進 guidelines。

---

## 2. 範圍邊界

### ✅ 做

1. **建立獨立 `retro` skill**：
   - 位於 `.claude/skills/retro/SKILL.md`（因 `.agents/skills` 為軟連結，同步生效）。
   - Frontmatter 定義名稱 `retro` 與精確 description（支援 `retro`, `/retro`, `環境回顧` 等觸發詞）。
   - 清楚定義回顧輸入來源：
     1. 分支相對於 base branch 的 `git diff` 與 commit log。
     2. 最近發生的失敗紀錄（測試失敗、linter 報錯、review 被打回）。
     3. 使用者額外口頭描述的摩擦點。
   - 定義二分法決策樹：
     - **Mechanical 判準**：語法格式、禁止 API、檔案放置路徑、命名結構、import 規則等。**明確禁止寫入 prompt 或 rules**，產出對應的自動化檢查腳本草稿（Hook / Linter / CI / Bash assertion）。
     - **Judgement 判準**：架構分層、邊界職責、過度工程簡化、周邊風格契合度。產出對應的文字規範草稿（如 `.claude/rules/`）。
   - 提供標準化的回顧輸出範本與具體範例（包含事件診斷、二分表格、行動待辦 Action Items）。

2. **整合 `gen-dev-workflow` 收尾引導**：
   - 在 `.claude/skills/gen-dev-workflow/SKILL.md` 的 STAGE 6（Worktree 清理）完成指引中，加入推薦使用者執行 `/retro` 進行環境回顧的提示說明。

3. **同步知識庫與決策記錄**：
   - 更新 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`：
     - §3.4 補充 retro skill 的落地成果。
     - §5 項目 C5 的狀態更新為「✅ 已完成（2026-10-23）」。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 自動靜默覆寫專案的 hook 腳本或 rules | 保留工程師與維持者的最終審核與裁量權，避免 agent 產生自毀式或有瑕疵的自動化腳本 |
| 引入額外第三方依賴或重度 CI 平台綁定 | 維持本機輕量與零相依性，聚焦於 Git / Bash / Flutter 原生工具鏈 |
| 在 STAGE 4 強制阻擋暫停進行 retro | retro 應為按需觸發的建設性回顧，非每次都要強制阻擋交付流程的阻塞關卡 |

---

## 3. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | 建立 `.claude/skills/retro/SKILL.md`，frontmatter 符合規範，結構包含輸入收集、二分診斷樹、產出範本與範例 | 檔案檢查與靜態驗證 |
| 2 | Skill 內容明訂 Mechanical 違規「一律產出自動化檢查腳本，嚴禁塞進 prompt/rules」，Judgement 項目才產出規範條款 | 文本審查與準則確認 |
| 3 | `gen-dev-workflow/SKILL.md` STAGE 6 結尾包含推薦執行 `/retro` 的引導說明 | 文本審查與 workflow 對齊驗證 |
| 4 | `docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.4 與 §5 C5 正確標記為完成 | 文本審查與 git diff 確認 |
| 5 | 全案測試與靜態分析無破壞（`flutter test` 750 tests 通過，`flutter analyze` 7-info baseline） | 指令執行驗證 |
