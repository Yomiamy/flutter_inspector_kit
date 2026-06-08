---
name: branch-diff-code-review
description: Use this skill when the user wants a general code review of all changes made on the current branch since it diverged from its base branch, without defaulting the review scope to origin/main. It should determine the branch fork point, inspect the full branch diff, prioritize bugs and regression risks, and present review findings in zh-tw while following the repository's .gemini/styleguide.md code review persona and closing ritual.
---

# Branch Diff Code Review

Use this skill when the user wants a code review for the whole branch after it split from its base, rather than a review of only the latest commit or a fixed comparison against `origin/main`.

## Required Style Guide

Before writing the review, read the repository style guide at:

[`../../../.gemini/styleguide.md`](../../../.gemini/styleguide.md)

Treat its `Code Review Feedback Persona: The Versatile Poet` section as mandatory.

Minimum requirements from the style guide:

- write the review in `zh-tw`
- keep necessary `en-us` technical terms in English
- end every completed review with one randomly chosen literary closing style:
  - 五言/七言絕句
  - 新詩
  - 俏皮話
  - 順口溜

Do not skip the closing ritual, even when the findings are short.

## Review Goal

Review the branch diff from the actual branch divergence point.
Focus on finding:

- correctness bugs
- behavior regressions
- edge-case handling problems
- state or data flow risks
- API contract mismatches
- missing or weak test coverage
- maintainability issues that are likely to hide bugs

Do not optimize for praise-first summaries.
Findings come first.

## Workflow

1. Resolve the review target:
   - default to the current checked-out branch
   - if the user names a branch or base reference, use that instead
2. Determine the most credible review base without assuming `origin/main`:
   - first prefer a user-provided base reference
   - otherwise check the branch upstream when it exists
   - otherwise infer the most likely parent branch from local git context and reachable refs
3. Determine the fork point:
   - prefer `git merge-base --fork-point` when it returns a valid ancestor
   - fall back to `git merge-base` when fork-point metadata is unavailable
4. Collect diff and commit data:
   - run `git diff <fork_point>...HEAD` and `git log --oneline <fork_point>..HEAD`
   - collect `git diff --stat` for a file overview
5. Inspect changed files and read surrounding code where needed before judging behavior.
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
8. Prefer evidence from the repository over speculation.
9. When a suspected issue depends on unseen runtime behavior, mark it as a risk or open question instead of overstating certainty.
10. Check whether tests were added or updated when the branch changes behavior.
11. Keep the review scoped to the branch diff unless the user explicitly asks for wider architectural analysis.

## Investigation Guidance

Use fast local inspection first:

- `git branch --show-current`
- `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`
- `git merge-base --fork-point <base> HEAD`
- `git merge-base <base> HEAD`
- `git diff <fork_point>...HEAD --stat`
- `git diff <fork_point>...HEAD -- <path>`
- `git log --oneline <fork_point>..HEAD`
- `rg` for impacted symbols, call sites, tests, routes, providers, services, and models

When the branch base is ambiguous, state the chosen base and why.
If no safe base can be inferred, stop and report that the review scope could not be determined reliably.

## Output Rules

Present findings first, ordered by severity.

Preferred structure:

1. `Findings`
2. `Open Questions / Assumptions`
3. `Summary`
4. Literary closing selected from the style guide

For each finding:

- include severity such as `P0` to `P3` when useful
- include file and line references when you can support them
- explain the concrete risk, likely behavior, and why it matters
- mention missing tests when that is part of the risk

If there are no findings:

- say so explicitly
- still mention any residual risk or testing gap
- still include the literary closing

## Tone Rules

- primary language: `zh-tw`
- preserve `en-us` proper nouns and technical terms
- tone: direct, calm, evidence-based
- avoid vague feedback such as `建議再確認`
- prefer concrete statements such as `這裡在 empty state 會提前 return，導致 loading flag 無法復原`

## Scope Boundaries

- default to review only committed and uncommitted branch changes that are part of the requested diff scope
- do not silently switch to `origin/main` comparison just because it is available
- do not review only `HEAD` unless the user explicitly asks for latest-commit review
- do not rewrite code unless the user asks to address findings
