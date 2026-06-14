---
name: branch-diff-code-review
description: 當使用者想要對當前 branch 自從與其 base branch 分歧以來的所有變更進行一般性 code review，且不要把審查範圍預設為 origin/main 時，使用此 skill。它應判定 branch fork point、檢視完整的 branch diff、優先處理 bugs 與 regression 風險，並以 zh-tw 呈現審查發現，同時遵循 repository 的 .gemini/styleguide.md code review persona 與收尾儀式。
---

# Branch Diff Code Review

當使用者想要的是 branch 自其 base 分岔後整條 branch 的 code review，而非只審查最新 commit 或固定與 `origin/main` 比較時，使用此 skill。

## 必讀 Style Guide

撰寫審查前，先閱讀位於以下路徑的 repository style guide：

[`../../../.gemini/styleguide.md`](../../../.gemini/styleguide.md)

將其 `Code Review Feedback Persona: The Versatile Poet` 章節視為強制要求。

來自 style guide 的最低要求：

- 以 `zh-tw` 撰寫審查
- 必要的 `en-us` 技術術語保留英文
- 每份完成的審查都以一種隨機選擇的文學收尾風格結尾：
  - 五言/七言絕句
  - 新詩
  - 俏皮話
  - 順口溜

即使發現項目很短，也不要略過收尾儀式。

## 審查目標

從實際的 branch 分歧點審查 branch diff。
聚焦於找出：

- 正確性 bug
- 行為回歸
- 邊界情況處理問題
- 狀態或資料流風險
- API contract 不一致
- 缺失或薄弱的測試覆蓋
- 可能藏匿 bug 的可維護性問題

不要為了讚美開頭的摘要而優化。
發現項目優先。

## 工作流程

1. 解析審查目標：
   - 預設為當前 checkout 的 branch
   - 若使用者指名某 branch 或 base reference，改用該項
2. 在不假設 `origin/main` 的前提下，判定最可信的審查 base：
   - 優先使用使用者提供的 base reference
   - 否則檢查 branch upstream（若存在）
   - 否則從本地 git 脈絡與可達 refs 推斷最可能的 parent branch
3. 判定 fork point：
   - 當 `git merge-base --fork-point` 回傳有效祖先時優先使用
   - 當缺少 fork-point metadata 時，回退至 `git merge-base`
4. 蒐集 diff 與 commit 資料：
   - 執行 `git diff <fork_point>...HEAD` 與 `git log --oneline <fork_point>..HEAD`
   - 蒐集 `git diff --stat` 作為檔案概覽
5. 在判斷行為之前，檢視變更檔案並在需要處閱讀周邊程式碼。
6. **agy 優先策略**：收集完 diff 與程式碼觀察後，優先委派 antigravity-cli（`agy`）生成審查報告本文：
   - 透過 Bash 以 stdin 管道委派（`printf '%s' "<填入下方 prompt>" | agy -p --print-timeout 180s`），prompt 如下（以實際資料填入；務必在結尾要求「只輸出報告本文，不要任何開場白或人設評論」）：
     ```
     你是一位資深 Flutter 工程師，同時也是嚴格的 Code Reviewer。
     請根據以下 branch diff 與 commit 紀錄，用繁體中文撰寫一份代碼審查報告（保留英文技術術語）。

     Branch: $BRANCH
     Fork point: $FORK_POINT

     Commits:
     <git log --oneline 結果>

     Diff stat:
     <git diff --stat 結果>

     Diff:
     <git diff <fork_point>...HEAD 結果>

     程式碼觀察補充（已讀取的相關邏輯、測試、呼叫點）：
     <Claude 的 rg / file read 觀察摘要>

     審查重點（全部必須涵蓋）：
     - 正確性 bug 與行為回歸
     - 邊界情況處理問題
     - 狀態與資料流風險
     - API contract 不一致
     - 測試覆蓋缺失或薄弱
     - 可維護性問題（可能藏 bug）

     輸出格式（嚴格遵守）：
     ### Findings
     按嚴重程度排序，每條包含：
     - 嚴重程度（P0-P3）
     - 檔案與行數（可支援時）
     - 具體風險說明

     ### Open Questions / Assumptions
     - 依賴未見 runtime 行為的疑慮標注為 risk 或 open question

     ### Summary
     - 一段簡短總結

     ### 結尾創作
     隨機選擇一種文學體裁（五言/七言絕句、新詩、俏皮話、順口溜），根據此次審查內容創作結尾。

     Findings 優先，不以讚美開頭。
     ```
   - 若 `agy` 成功回傳包含 `### Findings` 的結構化審查報告，採用其內容。
   - **後處理（必做）**：`agy` 會讀取全域 CLAUDE.md 而附加 Linus 人設框架，且可能在生成時順手建立暫存檔。採用前須剝除人設包裝、只取 `### Findings` 起的報告本文（注意：本 skill 結尾的文學創作 ritual 為刻意保留，不可剝除）；並確認 `agy` 未在工作區誤建檔案（如有則刪除）。
   - 若 `agy` 不在 PATH、呼叫失敗或回傳格式不合法，回退至步驟 7 自行撰寫審查報告。
7. （Fallback）自行依 diff 與程式碼觀察撰寫審查報告，遵循 Output Rules 格式。
8. 偏好來自 repository 的證據，而非臆測。
9. 當某個疑似問題依賴未見的 runtime 行為時，將其標為 risk 或 open question，而非誇大確定性。
10. 當 branch 改變行為時，檢查是否新增或更新了 tests。
11. 將審查範圍限定在 branch diff，除非使用者明確要求更廣的架構分析。

## 調查指引

先使用快速的本地檢視：

- `git branch --show-current`
- `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`
- `git merge-base --fork-point <base> HEAD`
- `git merge-base <base> HEAD`
- `git diff <fork_point>...HEAD --stat`
- `git diff <fork_point>...HEAD -- <path>`
- `git log --oneline <fork_point>..HEAD`
- 以 `rg` 搜尋受影響的 symbols、call sites、tests、routes、providers、services 與 models

當 branch base 模糊時，說明所選的 base 與原因。
若無法推斷出安全的 base，停止並回報審查範圍無法可靠判定。

## 輸出規則

發現項目優先呈現，依嚴重度排序。

偏好結構：

1. `Findings`
2. `Open Questions / Assumptions`
3. `Summary`
4. 從 style guide 選出的文學收尾

每條發現：

- 有助益時附上嚴重度，例如 `P0` 到 `P3`
- 在能佐證時附上檔案與行號參照
- 解釋具體風險、可能行為，以及為何重要
- 當缺少 tests 屬於風險的一部分時，提及之

若沒有發現：

- 明確說明
- 仍提及任何殘留風險或測試缺口
- 仍包含文學收尾

## 語氣規則

- 主要語言：`zh-tw`
- 保留 `en-us` 專有名詞與技術術語
- 語氣：直接、冷靜、以證據為本
- 避免模糊回饋，例如 `建議再確認`
- 偏好具體陳述，例如 `這裡在 empty state 會提前 return，導致 loading flag 無法復原`

## 範圍邊界

- 預設只審查屬於所請求 diff 範圍的已 commit 與未 commit branch 變更
- 不要只因為 `origin/main` 可用就默默切換成與它比較
- 不要只審查 `HEAD`，除非使用者明確要求 latest-commit 審查
- 不要改寫程式碼，除非使用者要求處理發現項目
