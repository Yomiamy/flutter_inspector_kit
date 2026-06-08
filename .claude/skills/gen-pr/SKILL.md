---
name: gen-pr
description: 當使用者想要針對合併至 origin/main 的變更撰寫、改寫、縮短或標準化 Pull Request (PR) 描述草稿時，請使用此技能。在審閱後可選擇發布 PR。此技能會產出精簡的 zh-tw Markdown，並保留必要的 en-us 技術術語。若未明確指定基準分支，預設與 origin/main 進行比較。若分支名稱開頭包含可解析的 YouTrack 議題編號，則會在 Summary 中自動加上議題資訊。
---

# PR Description Main ZH-TW

## Input Parsing

從觸發指令中解析 branch name（選填）。
- 輸入格式：`gen pr [branch-name]`
- 範例：`gen pr fix/202604/BUG-1691-product-gift-layout-issue`
- 若未提供 branch name，預設使用當前 HEAD 所在 branch。

將解析到的 branch name 記為 `$BRANCH`。

確認 branch 存在：
```bash
git branch -a | grep "$BRANCH"
```
若不存在，報錯並停止。

---

## Overview

Use this skill for PR descriptions that target `origin/main`.
This skill operates in two phases:
- **Phase 1**: Generate or revise the PR description draft for user review.
- **Phase 2**: After explicit user confirmation, push the branch (if needed) and create the GitHub PR using `gh pr create`.
When repository checklist items are available, this skill should also assess checklist items `1`, `3`, `4`, and `5` from the current changeset based on repository evidence, and reflect the result directly in the checklist lines inside the PR markdown. Item `2` should be explicitly left for the user to verify locally.

If the repository contains a PR template such as `.github/PULL_REQUEST_TEMPLATE.md`, preserve its required content at the top of the final PR body, remove placeholder prompt lines such as `Please explain the changes you made **HERE**.`, and place the generated summary content after the template heading section instead of replacing the template.

Produce copy-ready markdown with exactly two sections in this order, wrapped in a fenced `md` code block:

```md
### Summary
[{TICKET-ID}](ticket-url) Ticket title

**[修正問題]**

<描述這個 PR 解決了什麼問題，原本的行為是什麼，為何需要修正>

**[修正方式]**

<條列說明修正的具體方式，包含修改了哪些檔案/類別/方法、邏輯判斷的前後變化、關鍵的判斷順序或流程>
```

Only include the ticket line when a matching ticket can be resolved from the branch name.

## Workflow

1. Treat the PR as merging into `origin/main` unless the user explicitly says otherwise.
2. Use `$BRANCH` (resolved from input or current HEAD) as the source branch for all git operations. Default to `origin/main..$BRANCH` for commit range and `origin/main...$BRANCH` for diff summary.
3. Read the repository PR template when it exists, for example `.github/PULL_REQUEST_TEMPLATE.md`.
4. Preserve the template headings, checklist items, and any required instructional text at the top of the final PR body, but remove placeholder-only prompt lines that are meant to be replaced by actual content.
5. Place the generated PR description content after the template's description heading section, unless the user explicitly asks for a different layout.
6. Use `$BRANCH` as the branch name for ticket extraction and summary context.
7. Inspect the branch name near the start of the branch path and try to extract a resolvable YouTrack issue key from one of its early path or slug segments.
8. Do not require a fixed branch prefix or a fixed issue-key shape beyond what YouTrack can actually resolve.
9. Treat issue-key examples such as `APP-1234` or `Bug-4321` as examples only, not as restrictions.
10. Resolve ticket metadata before writing:
   - Always parse the ticket id from the branch name first when available.
   - If the current user-provided brief already includes a trustworthy ticket summary/title, use it directly and do not perform an extra ticket lookup just to re-fetch the same summary.
   - Otherwise, prefer YouTrack MCP tools to retrieve `idReadable`, `summary`, and URL metadata.
   - If MCP is unavailable or lookup fails, prefer the bundled branch ticket script when it exists, for example `bash ./.codex/skills/branch-ticket-solution-advisor/scripts/read_branch_ticket.sh`.
   - When using the bundled script, allow it to read `AUTH_HEADER` either from the current shell or from `[mcp_servers.youtrack.env]` in `~/.codex/config.toml`.
   - If script lookup also fails, fallback to any ticket brief the user already provided in the current context.
   - If lookup still fails, keep the ticket id and construct the standard YouTrack issue URL from that id instead of blocking the draft.
   - Only omit the ticket line entirely when no trustworthy ticket id can be determined.
11. Inspect the current diff, changed files, and relevant repository context to assess checklist items `1`, `3`, `4`, and `5` when the repository template includes them.
12. For checklist assessment, use evidence only:
   - `1`: whether the changes appear to follow repository conventions and do not obviously violate local patterns.
   - `3`: whether tests were added when the change looks like a bug fix or feature.
   - `4`: whether comments were added in hard-to-understand areas when such areas exist in the diff.
   - `5`: whether docs were updated when the change appears to require docs.
13. Update the template checklist lines directly:
   - use `[x]` for items with positive evidence
   - use `[ ]` for items that are not satisfied or must remain for user verification
   - do not use `[v]` or `[?]`
14. Explicitly exclude checklist item `2` from automated assessment and leave it as `[ ]` for local verification by the user.
15. When evidence is ambiguous, leave the checklist item as `[ ]` instead of guessing.
16. After the Checklist, write the description body using two fixed sections: `**[修正問題]**` and `**[修正方式]**`.
17. `**[修正問題]**`: describe the original (broken) behaviour and why it needs fixing. Focus on the gap between actual and expected behaviour.
18. `**[修正方式]**`: list the concrete fixes — which files/classes/methods were changed, how the logic changed, and any important ordering or flow changes. Be specific with class names and field names from the diff.
19. Keep the `### Summary` ticket line at the top of the description section when a ticket is resolved; place `**[修正問題]**` immediately after it.
20. Rewrite the result in `zh-tw`, keeping necessary `en-us` technical terms such as API names, branch names, package names, code identifiers, and the original YouTrack ticket id.
21. Keep the output compact, polished, and directly usable in a PR body without additional editing.
22. After presenting the draft, ask the user: **「草稿確認後，是否直接建立 PR？」**
23. If the user confirms (e.g. "yes", "對", "建立", "發送"), proceed to Phase 2:
   - Check if `$BRANCH` is already pushed to remote: `git ls-remote --heads origin $BRANCH`
   - If not pushed, push it first: `git push -u origin $BRANCH`
   - Extract the PR title from the ticket line or the first sentence of `**[修正問題]**`, and ensure it is in English (translate if necessary).
   - Run `gh pr create` with `--base main --head $BRANCH --title <title> --body <full PR body>`.
   - Pass the PR body via HEREDOC to preserve formatting.
   - Report the created PR URL to the user.

## Output Rules

- Always output markdown only in Phase 1.
- Always place the PR body draft in a fenced code block with the `md` info string so the user can copy it directly.
- Do not create or publish a GitHub PR until the user explicitly confirms after reviewing the draft.
- If a repository PR template exists, include it first in the final output before the generated `### Summary` section.
- Remove placeholder-only lines from the template, for example `Please explain the changes you made **HERE**.`, before composing the final output.
- When a repository PR template includes checklist items, return them already updated in the markdown body instead of describing checklist results in a separate prose section.
- Always use `### Summary` as the heading for the description section.
- If a YouTrack ticket id was resolved from the branch name or user brief, prepend a standalone line using this exact pattern: `[{TICKET-ID}](ticket-url) Ticket title`
- When only the ticket id is known but the lookup failed, still include the ticket line with the standard issue URL and use the best available title from user-provided context if one exists.
- After the ticket line (or directly under `### Summary` if no ticket), write `**[修正問題]**` followed by a paragraph describing the original broken behaviour and why it needs fixing.
- Then write `**[修正方式]**` followed by a numbered or bulleted list of concrete changes — class names, field names, logic flow changes, and important ordering.
- Avoid file-by-file listings unless the user explicitly asks for them.
- Avoid inventing details that are not supported by the provided diff, commits, or draft.
- If the branch appears to contain a candidate issue key and the lookup fails, do not block the draft:
  - reuse a user-provided ticket summary when available
  - otherwise keep the ticket id with the standard issue URL and omit only the unresolved title text
  - only drop the whole ticket line when even the ticket id is not trustworthy
- Do not delete or compress required checklist items from the repository PR template unless the user explicitly asks to rewrite the template itself.
- In template checklist lines, use `[x]` only when there is positive evidence and `[ ]` otherwise.
- Never output an additional `Checklist 確認` section unless the user explicitly asks for explanation outside the PR markdown.
- Do not add an extra note about item `2` outside the markdown body unless the user explicitly asks for checklist commentary.

## Style Rules

- Primary language: `zh-tw`
- PR Title: MUST be in `en-us` (English)
- Allowed exceptions: necessary `en-us` proper nouns and technical terms
- Preferred tone: concise, neutral, readable, ready to paste
- `**[修正問題]**` should describe the original broken behaviour and the expected behaviour in plain language — avoid vague phrases like "there was an issue".
- `**[修正方式]**` should be specific: use class names, field names, and describe the logic change precisely. Include key ordering or flow when relevant.
- When a ticket line is present, keep it as a standalone line before the problem/fix sections.
- If the user asks for a shorter version, compress wording but keep the `**[修正問題]**` / `**[修正方式]**` structure.
- If the user provides a draft, prefer reformatting and compressing it over fully rewriting from scratch.

## Example

```md
## 👾 Checklist before requesting a review

- [x] My code, git commit, table naming ...etc, follow the guidelines
- [ ] Lint and tests pass locally with my changes
- [ ] Tests for the changes have been added (for bug fixes / features)
- [x] I have commented on my code, particularly in hard-to-understand areas
- [x] Docs have been added/updated (if necessary)

## 👻 Describe your changes

### Summary
[APP-1234](https://<your-org>.youtrack.cloud/issue/APP-1234) 禮品商品版面異常

**[修正問題]**

禮品列表中，商品項目之間缺少間距，且當禮品圖片 URL 為 null 或空字串時，未做任何處理，導致版面排列錯誤。

**[修正方式]**

1. 在 `GiftItemWidget` 各項目之間新增 `SizedBox` 間距。
2. 在 `GiftItemWidget` 圖片載入前增加對 null 與空字串的判斷，改以 `placeholder_image.svg` 顯示。
3. 更新 `placeholder_image.svg` 為新版設計，簡化 SVG 結構。
```

## Defaults

- Base branch defaults to `origin/main`.
- Source branch (`$BRANCH`) defaults to current HEAD when not provided in input.
- Do not ask to confirm the base branch unless the user explicitly provides a conflicting branch.
- If information is incomplete, summarize only what can be supported from the available context.
- Branch ticket detection is based on whether an early branch segment appears to be a trustworthy YouTrack issue key, not on a fixed prefix list or a fixed example pattern.
- Ticket lookup failure must not block PR draft generation when the ticket id is already trustworthy from branch or user context.
- PR publication is a separate phase and requires an explicit user request after the draft is reviewed.
