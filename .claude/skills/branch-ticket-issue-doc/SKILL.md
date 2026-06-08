---
name: branch-ticket-issue-doc
description: Use this skill after ticket-id-dev-prep has selected or prepared the development workspace and Codex needs to create or update docs/issues/<ticket-id>.md from the advisor parsed brief, YouTrack ticket details, and current workspace code context; focus on documenting the problem only, not writing specs or code.
---

# Branch Ticket Issue Doc

Use this skill in the development workspace selected by `ticket-id-dev-prep`.

Goal: create or update `docs/issues/<ticket-id>.md` as the canonical problem document for the branch.

Do not create specs here. Do not change product code here.

## Preconditions

1. Confirm the current directory is the intended development workspace.
2. Confirm the current branch contains the ticket id or the user explicitly provides the ticket id.
3. Prefer using the parsed brief from `branch-ticket-solution-advisor`.
4. If no parsed brief exists, read the YouTrack ticket and inspect only enough code context to document the problem.
5. Create `docs/issues/` if missing.

If `ticket-id-dev-prep` selected a different workspace, switch there before writing. If the selected strategy is `current-branch` or `current-worktree-new-branch`, writing in the current workspace is allowed.

## Workflow

1. Resolve the ticket id.
2. Read existing `docs/issues/<ticket-id>.md` if present.
3. Read `docs/issues/template.md` when present and preserve local documentation style.
4. Gather source material:
   - advisor parsed brief
   - YouTrack title and description
   - relevant fields such as `State`, `Type`, `Priority`, `Subsystem`
   - current worktree code observations from targeted inspection
5. **agy 優先策略**：收集完所有資料後，優先委派 antigravity-cli（`agy`）生成 issue doc 本文：
   - 透過 Bash 以 stdin 管道委派（`printf '%s' "<填入下方 prompt>" | agy -p --print-timeout 180s`），prompt 如下（以實際資料填入；務必在結尾要求「只輸出文件本文，不要任何開場白或人設評論」）：
     ```
     你是一位資深 Flutter 工程師，請根據以下 ticket 資料與程式碼觀察，用繁體中文撰寫一份問題文件（保留英文技術術語與 issue key）。

     Ticket: <ticket-id> - <ticket summary>
     State: <state>
     Type: <type>
     Priority: <priority>

     Ticket 描述摘要：
     <ticket description 摘要>

     Advisor 解析摘要（如有）：
     <branch-ticket-solution-advisor parsed brief，若無則填「無」>

     程式碼觀察（已檢視的相關模組、邏輯路徑）：
     <Claude 的 rg / file read 觀察摘要>

     請嚴格按照以下 markdown 結構輸出：

     # <TICKET-ID> <title>

     ## Ticket

     - URL:
     - State:
     - Type:
     - Priority:

     ## 問題描述

     ## 影響範圍

     ## 重現步驟

     1.

     ## 預期結果

     ## 實際結果

     ## 環境

     - App 版本：
     - 裝置：
     - OS 版本：
     - 測試帳號：

     ## 程式碼現況

     ## 已知事實

     ## 推論

     ## 待確認

     ## 截圖 / 錄影

     ## 備註

     規則：
     - 不要發明 ticket 中未提及的資訊
     - 無法確認的項目一律填入「待確認」
     - 保留原始錯誤訊息、欄位名稱、使用者可見字串
     - 若程式碼觀察與 ticket 敘述有矛盾，在「備註」中記錄不一致之處
     只輸出文件內容，不要其他說明。
     ```
   - 若 `agy` 成功回傳包含 `## 問題描述` 與 `## 已知事實` 的結構，採用其內容。
   - **後處理（必做）**：`agy` 會讀取全域 CLAUDE.md 而附加 Linus 人設框架，且可能在生成時順手建立暫存檔。採用前須剝除人設包裝、只取目標 markdown 結構；並確認 `agy` 未在工作區誤建檔案（如有則刪除）。`docs/issues/<ticket-id>.md` 一律由 Claude 自行 Write 寫入，不依賴 `agy` 落檔。
   - 若 `agy` 不在 PATH、呼叫失敗或回傳格式不合法，回退至步驟 6 自行撰寫 issue doc。
6. （Fallback）自行 write or update `docs/issues/<ticket-id>.md`，依照 Issue Doc Template。
7. Distinguish facts, inference, and open questions.
8. Keep the issue doc focused on the problem and current behavior.
9. Do not add implementation strategy beyond short code-context observations.

## File Naming

Use:

`docs/issues/<TICKET-ID>-<description-suffix>.md`

Where `<description-suffix>` is derived from the last path segment of the current branch name, with the leading ticket id portion removed.

Example:

- Branch: `fix/202605/BUG-2362-some-feature-fix`
- Last segment: `BUG-2362-some-feature-fix`
- Description suffix: `some-feature-fix`
- File: `docs/issues/BUG-2362-some-feature-fix.md`

Resolve the suffix by running:
```bash
git rev-parse --abbrev-ref HEAD | sed 's|.*/||' | sed 's/^[A-Z][A-Z]*-[0-9]*-//'
```

Preserve ticket id casing.

## Issue Doc Template

Use this structure unless local template requires a tighter fit:

```markdown
# <TICKET-ID> <title>

## Ticket

- URL:
- State:
- Type:
- Priority:

## 問題描述

## 影響範圍

## 重現步驟

1.

## 預期結果

## 實際結果

## 環境

- App 版本：
- 裝置：
- OS 版本：
- 測試帳號：

## 程式碼現況

## 已知事實

## 推論

## 待確認

## 截圖 / 錄影

## 備註
```

Omit empty sections only when they truly do not apply. Prefer `待確認` over invented details.

## Quality Rules

- Problem doc must be understandable without reading the full ticket.
- Do not copy long ticket text verbatim.
- Preserve exact error messages, labels, field names, and user-visible strings when relevant.
- Note missing reproduction data explicitly.
- If code context contradicts the ticket, record the mismatch.

## Output Rules

Preferred output:

1. `Issue Doc`: path created or updated
2. `來源`: advisor brief, YouTrack, code inspection
3. `重點`: one short problem summary
4. `待確認`: only if present
5. `Next`: run `issue-spec-prep`

## Style Rules

- Primary language: `zh-tw`
- Keep necessary `en-us` technical terms such as `YouTrack`, `State`, `API`, `UI`, `Backend`, `QA`
- Be concise and documentation-focused
