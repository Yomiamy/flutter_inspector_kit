---
name: issue-spec-prep
description: Use this skill after branch-ticket-issue-doc has created docs/issues/<ticket-id>.md in the selected development workspace and Codex needs to create or update docs/issues/specs/<ticket-id>.md as the implementation spec for that issue; read the issue doc first, inspect code only as needed, and do not implement code changes.
---

# Issue Spec Prep

Use this skill after `branch-ticket-issue-doc`.

Goal: create or update `docs/issues/specs/<ticket-id>.md` from the issue document and current worktree code context.

Do not change product code here. Do not run implementation refactors here.

## Preconditions

1. Confirm current directory is the development workspace selected by `ticket-id-dev-prep`.
2. Resolve ticket id from user input, branch name, or existing issue docs.
3. Read `docs/issues/<ticket-id>.md` first.
4. If the issue doc is missing, stop and run `branch-ticket-issue-doc` first.
5. Create `docs/issues/specs/` if missing.

## Workflow

1. Read `docs/issues/<ticket-id>.md`.
2. Extract:
   - problem statement
   - expected and actual behavior
   - affected flows
   - known facts, inference, and open questions
3. Inspect code only enough to make the spec actionable:
   - likely files or modules
   - current logic boundaries
   - existing tests or missing test surfaces
   - shared utilities or duplicated flows
4. **agy 優先策略**：收集完 issue doc 內容與程式碼觀察後，優先委派 antigravity-cli（`agy`）生成 spec 文件本文：
   - 透過 Bash 以 stdin 管道委派（`printf '%s' "<填入下方 prompt>" | agy -p --print-timeout 180s`），prompt 如下（以實際資料填入；務必在結尾要求「只輸出 spec 本文，不要任何開場白或人設評論」）：
     ```
     你是一位資深 Flutter 工程師，請根據以下問題描述與程式碼觀察，用繁體中文撰寫一份實作規格文件（保留英文技術術語）。

     Ticket: <ticket-id> - <ticket summary>

     Issue 文件內容：
     <docs/issues/<ticket-id>.md 完整內容>

     程式碼觀察（已檢視的相關模組、邏輯邊界、測試缺口）：
     <Claude 的 rg / file read 觀察摘要>

     請嚴格按照以下 markdown 結構輸出，每個段落用簡潔的條列式說明：

     # <TICKET-ID> Spec

     ## 背景

     ## 目標

     ## 非目標

     ## 目前行為

     ## 目標行為

     ## 修正策略

     ## 影響範圍

     ### Affected Files / Modules

     ## Acceptance Criteria

     ## Test Plan

     ### Automated

     ### Manual

     ## Regression Risk

     ## Open Questions

     規則：
     - Acceptance Criteria 必須描述可觀察的行為
     - Test Plan 需具體指出 unit / widget / bloc / integration / manual 類型
     - 若有未知項目會阻塞實作，在 Open Questions 中清楚標記
     - 不要發明 issue 文件中未提及的需求
     只輸出 spec 文件內容，不要其他說明。
     ```
   - 若 `agy` 成功回傳包含 `## 背景` 與 `## Acceptance Criteria` 的 spec 結構，採用其內容。
   - **後處理（必做）**：`agy` 會讀取全域 CLAUDE.md 而附加 Linus 人設框架，且可能在生成時順手建立暫存檔。採用前須剝除人設包裝、只取目標 spec 結構；並確認 `agy` 未在工作區誤建檔案（如有則刪除）。`docs/issues/specs/<ticket-id>.md` 一律由 Claude 自行 Write 寫入，不依賴 `agy` 落檔。
   - 若 `agy` 不在 PATH、呼叫失敗或回傳格式不合法，回退至步驟 5 自行撰寫 spec。
5. （Fallback）自行撰寫並 create or update `docs/issues/specs/<ticket-id>.md`，依照 Spec Template。
6. Keep acceptance criteria testable.
7. Keep open questions visible; do not convert unknowns into requirements.
8. Stop before implementation.

## File Naming

Use:

`docs/issues/specs/<TICKET-ID>-<description-suffix>.md`

Where `<description-suffix>` is derived from the last path segment of the current branch name, with the leading ticket id portion removed.

Example:

- Branch: `fix/202605/BUG-2362-some-feature-fix`
- Last segment: `BUG-2362-some-feature-fix`
- Description suffix: `some-feature-fix`
- File: `docs/issues/specs/BUG-2362-some-feature-fix.md`

Resolve the suffix by running:
```bash
git rev-parse --abbrev-ref HEAD | sed 's|.*/||' | sed 's/^[A-Z][A-Z]*-[0-9]*-//'
```

Preserve ticket id casing.

## Spec Template

Use this structure:

```markdown
# <TICKET-ID> Spec

## 背景

## 目標

## 非目標

## 目前行為

## 目標行為

## 修正策略

## 影響範圍

### Affected Files / Modules

## Acceptance Criteria

## Test Plan

### Automated

### Manual

## Regression Risk

## Open Questions
```

Prefer short, concrete bullets.

## Spec Rules

- Base requirements on the issue doc.
- Use code inspection to improve feasibility, not to invent product intent.
- Mention exact files only when inspected or strongly indicated.
- Acceptance criteria must describe observable behavior.
- Test plan should name likely unit, widget, bloc, integration, or manual checks.
- If an open question blocks implementation, say so clearly.

## Output Rules

Preferred output:

1. `Spec`: path created or updated
2. `依據`: issue doc path and inspected code context
3. `修正方向`: short summary
4. `測試重點`
5. `阻塞`: only if open questions block implementation
6. `Next`: implementation can start only if no blocking questions remain

## Style Rules

- Primary language: `zh-tw`
- Keep necessary `en-us` technical terms such as `Acceptance Criteria`, `Test Plan`, `API`, `UI`, `Widget`, `Bloc`
- Be concise and spec-focused
