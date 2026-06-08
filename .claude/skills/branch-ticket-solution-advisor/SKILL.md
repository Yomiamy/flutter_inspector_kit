---
name: branch-ticket-solution-advisor
description: Use this skill when the user wants to analyze the current branch slug, inspect the relevant code paths in the current repo, condense the task into a clear implementation brief, and propose practical development, bug-fix, or improvement approaches without inventing missing requirements.
---

# Branch Solution Advisor

Use this skill when the task is to read the current git branch, parse the slug to understand the intent, inspect the repository for the most relevant implementation context, summarize the task into a concise working brief, and propose actionable implementation directions.

## Workflow

1. Read the current git branch name unless the user explicitly provides a branch name.
2. Parse the branch slug to infer the task type and scope:
   - `fix/` prefix → bug fix or regression
   - `feature/` prefix → new capability
   - `chore/` prefix → refactor, maintenance, or non-user-facing cleanup
   - slug words describe the affected area (e.g., `chat-message-scroll`, `firebase-auth-token`)
3. Inspect the repository before recommending implementation work:
   - find likely modules, screens, routes, services, tests, or shared utilities related to the slug
   - prefer fast local discovery such as `rg`, targeted file reads, and existing project conventions
   - compare slug intent with the current implementation and note mismatches
   - if multiple flows are mentioned, check whether they share logic or duplicate it
4. Condense the task into a working brief:
   - problem or goal inferred from slug and code inspection
   - user-facing impact
   - explicit constraints or edge cases found in code
   - open ambiguities
5. Distinguish facts from inference. If the slug is too vague to drive a safe recommendation, say what is missing.
6. **agy 優先策略**：收集完程式碼觀察後，優先委派 antigravity-cli（`agy`）生成「建議方向」段落：
   - 透過 Bash 以 stdin 管道委派（`printf '%s' "<填入下方 prompt>" | agy -p --print-timeout 180s`），prompt 如下（以實際資料填入；務必在結尾要求「只輸出建議內容本文，不要任何開場白或人設評論」）：
     ```
     你是一位資深 Flutter 工程師，請根據以下 branch slug 與程式碼觀察，用繁體中文提出 1 至 3 個具體的實作方向建議（保留英文技術術語）。

     Branch: <branch-name>
     推斷任務類型: <開發 / 修正 / 改善>
     推斷影響範圍: <slug 解析結果>

     程式碼觀察（已檢視的相關模組、現有邏輯、潛在衝突點）：
     <Claude 的 rg / file read 觀察摘要>

     每個建議方向請依照以下格式輸出：

     ### [類型]（開發 / 修正 / 改善 擇一）

     **判斷依據**：為何這個類型符合此任務

     **建議做法**：具體的實作方向，需提及影響的層級（Data / Domain / BLoC / UI）、可複用的現有邏輯、潛在風險

     **驗證方式**：測試方式、手動驗證步驟、或上線後確認項目

     **風險與待確認**：缺少的 context、潛在副作用、不明確的需求

     規則：
     - 只輸出建議方向，不要重複任務摘要
     - 建議必須有根據（來自 slug 解析或程式碼觀察），不要憑空推測
     - 若有不確定的地方，在「風險與待確認」中說明
     ```
   - 若 `agy` 成功回傳包含 `**判斷依據**` 與 `**建議做法**` 的建議內容，採用作為「建議方向」段落。
   - **後處理（必做）**：`agy` 會讀取全域 CLAUDE.md 而附加 Linus 人設框架（如「【Linus 式方案】」），且可能在生成時順手建立暫存檔。採用前須剝除人設包裝、只取目標結構內容；並確認 `agy` 未在工作區誤建檔案（如有則刪除）。檔案一律由 Claude 自行寫入正式路徑，不依賴 `agy` 落檔。
   - 若 `agy` 不在 PATH、呼叫失敗或回傳格式不合法，回退至步驟 7 自行生成建議方向。
7. （Fallback）自行 propose one or more solution directions under the most suitable category:
   - `開發` for new capability or workflow expansion
   - `修正` for bug, regression, mismatch, or broken behavior
   - `改善` for refactor, UX polish, performance, maintainability, or process optimization
8. If the best category is unclear, state the likely category and why.
9. Keep recommendations concrete: mention affected layers, validation ideas, likely risks, and whether the current implementation already has reusable logic.
10. If the slug is too vague to produce a safe recommendation, stop and ask the user to clarify the task intent.

## Branch Detection

- Default source: `git branch --show-current`
- If the user supplies a branch name, use that instead.
- Parse the prefix (`fix/`, `feature/`, `chore/`) and slug words to infer task type and scope.
- If an issue-key-like pattern (e.g. `ABC-1234`) is present in the slug, surface it as context but do not attempt to fetch it from any external system.

## Summarization Rules

Summaries should help implementation, not restate the branch name verbatim.

Always capture:

- branch name and inferred task type
- condensed task description in plain `zh-tw` based on slug and code inspection
- current-code observations when repository inspection was possible
- explicit constraints found in the codebase
- dependencies, assumptions, or unanswered questions

When the slug is short and unambiguous, produce a concise one-paragraph brief.

## Recommendation Rules

Recommendations must be practical and bounded by slug inference and code observation.
Prefer repo-aware recommendations over slug-only speculation when the codebase is available.

For each proposed direction, prefer this structure:

- `類型`: `開發` / `修正` / `改善`
- `判斷依據`: why this category fits the task
- `建議做法`: concrete implementation direction
- `驗證方式`: tests, manual checks, or rollout checks
- `風險與待確認`: missing context, side-effect risk, or unclear requirement

Good recommendation patterns:

- identify likely modules or app layers
- point out existing validators, shared helpers, duplicated logic, or missing abstraction
- note data flow, API, state management, UI, analytics, or localization impact when relevant
- mention regression surfaces and test focus
- call out when a staged delivery is safer than a single large change

Avoid:

- pretending the branch slug already contains full technical design when it does not
- offering only vague advice such as `check logic` or `optimize code`
- converting unknowns into false requirements

## Output Rules

Keep the response concise but decision-useful.

Preferred output shape:

1. `Branch`: detected branch name and inferred task type
2. `程式碼現況`: only when repository inspection was possible and relevant
3. `任務摘要`: condensed problem statement and key constraints
4. `建議方向`: one to three concrete options, each labeled `開發` / `修正` / `改善`
5. `待確認`: only when meaningful gaps remain

## Style Rules

- Primary language: `zh-tw`
- Allowed exceptions: necessary `en-us` proper nouns and technical terms such as `State`, `API`, `UI`, `Backend`, `QA`, branch names, and issue keys
- Preferred tone: concise, analytical, and implementation-oriented
