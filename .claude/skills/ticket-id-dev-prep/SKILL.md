---
name: ticket-id-dev-prep
description: Use this skill when the user provides a YouTrack ticket id together with a parsed ticket brief and wants Codex to create a new git branch and worktree from a safe base, keeping the existing naming rules and completing the minimal development setup without relying on the current branch name.
---

# Ticket Id Dev Prep

Use this skill when the user gives a specific YouTrack ticket id such as `BUG-2351` together with a parsed ticket brief and wants branch/worktree preparation, not a fresh end-to-end ticket investigation.

## Goal

Turn a pasted parsed ticket brief into a safe, ready-to-start workspace:

1. start from the parsed ticket brief
2. condense the ticket into one short English slug for naming
3. create a new worktree
4. create a new branch
5. complete practical setup checks so development can start immediately

## Workflow

1. Read the ticket id from the user message.
2. Prefer using a parsed ticket brief pasted by the user in the current conversation.
3. If a reliable parsed brief already exists earlier in the same conversation, you may reuse it.
4. If no reliable parsed brief is available yet, first run or request the equivalent investigation flow from `ticket-code-investigator` before doing any naming or git write work.
5. Base all naming and setup decisions on the parsed result, especially:
   - the problem or goal
   - the likely implementation area
   - whether the work is a bug fix, feature, or maintenance task
   - any ambiguity that could make naming unreliable
6. Condense that parsed result into one short implementation brief in `zh-tw`.
7. Produce one concise English naming phrase that works as both:
   - branch slug
   - worktree suffix
8. Choose the branch prefix from the parsed ticket intent:
   - `fix/` for bug, regression, error, mismatch, or validator issues
   - `feature/` for new capability or user-facing expansion
   - `chore/` for refactor, maintenance, internal tooling, or non-user-facing cleanup
9. Default the base branch to `origin/main` unless the user explicitly requests another base.
10. Create the worktree from that base and create the new branch at the same time.
11. Run the minimal setup checks needed to confirm the new workspace is ready:
   - confirm branch and path
   - inspect repo status
   - sync local-only config files needed for real development and local builds when they exist in the source worktree, such as `.env`, Android signing / Firebase config, and iOS Firebase / fastlane signing config
   - verify `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` are copied when they exist in the source worktree; if either is missing, report that explicitly before bootstrap
   - run dependency bootstrap for this repo with `flutter pub get` after local config sync
12. Report the result with the parsed ticket brief, chosen slug, branch name, worktree path, and any follow-up notes.

## Parsed Brief Rules

The pasted parsed ticket brief is the source of truth for:

- implementation brief
- branch prefix choice
- slug generation
- uncertainty that should remain visible in the prep result

If the pasted brief conflicts with current conversation context, mention the mismatch and ask whether to refresh the investigation before any git write work.

## Parsed Input Rules

Treat the parsed ticket brief as the source of truth for setup decisions.

Always distinguish:

- fact from the parsed result
- naming inference made during prep
- open ambiguity that still needs confirmation

The brief should capture:

- problem or goal
- user-facing impact
- explicit requirements already identified during parsing
- technical clues already observed during parsing
- risks or missing details

Do not invent acceptance criteria that are not present.

If the parsed result says the issue may not exist or still needs verification, keep that uncertainty visible in the prep output instead of hiding it behind a confident slug.

## Slug Rules

The English naming phrase should be short, concrete, and reusable.

Requirements:

- based on the parsed ticket brief, not just the issue key
- prefer 2 to 6 English words
- lowercase kebab-case in final slug form
- keep it implementation-relevant, not overly broad
- avoid filler words such as `handle`, `update`, `improve`, `fix-issue`, `ticket-work`
- prefer the smallest phrase that still identifies the work clearly

Good examples:

- `password-fields-validator-error`
- `member-card-expired-state`
- `checkout-delivery-note`
- `apple-login-token-refresh`

Avoid:

- `bug-2351`
- `misc-fix`
- `update-something`
- `temporary-change`

## Branch And Worktree Rules

Construct names in this order:

1. branch name: `<prefix><TICKET-ID>-<slug>`
2. worktree directory name: `<repo-name>-<TICKET-ID-lowercase>-<slug>`

Example:

- branch: `fix/BUG-2351-password-fields-validator-error`
- worktree: `../ai-chat-bug-2351-password-fields-validator-error`

Additional rules:

- preserve the ticket id casing in the branch name
- use lowercase ticket id in the worktree directory suffix
- prefer creating the new worktree beside the current repo unless the user asks for another location
- if the target branch already exists locally, stop and report it instead of silently reusing it
- if the target worktree path already exists, stop and report it instead of overwriting anything

## Git Execution Rules

Prefer the bundled script for deterministic setup:

[`scripts/prepare_ticket_dev_workspace.sh`](./scripts/prepare_ticket_dev_workspace.sh)

Usage:

```bash
./scripts/prepare_ticket_dev_workspace.sh \
  --ticket-id "BUG-2351" \
  --prefix "fix/" \
  --slug "password-fields-validator-error"

./scripts/prepare_ticket_dev_workspace.sh \
  --ticket-id "APP-412" \
  --prefix "feature/" \
  --slug "member-card-expired-state" \
  --base "origin/main"
```

Behavior:

- validates required inputs before any git write
- defaults base branch to `origin/main`
- defaults worktree parent to the current repo parent directory
- fetches the base ref when it points to `origin/*`
- stops if the target branch already exists locally
- stops if the target worktree path already exists
- copies common local-only config files from the source worktree into the new worktree by default
- falls back to sibling git worktrees that already have local config files when the current worktree is missing them
- prints normalized JSON describing the created or intended workspace

Local config sync includes the repo's common development-only files when present, for example:

- any `.env` or `.env.*` files
- `android/key.properties`
- `android/app/google-services.json`
- Android signing files such as `*.keystore` and `*.jks`
- `ios/Runner/GoogleService-Info.plist`
- iOS / Android `fastlane` private signing or credential files such as `*.json`, `*.plist`, `*.p8`, `*.p12`, and `*.mobileprovision`

If you explicitly want a clean worktree without copied local secrets, run the script with `--skip-local-config-sync`.

Manual fallback flow:

```bash
git fetch origin main --prune
git worktree add -b "<branch-name>" "<worktree-path>" "origin/main"
```

If the user requested a different base branch, replace `origin/main` accordingly.

After creating the worktree:

1. verify `git branch --show-current`
2. verify `git status --short`
3. run `flutter pub get`

Do not create the branch inside the already-dirty current worktree when the goal is isolated ticket development.

## Setup Completion Rules

The skill should finish with a usable development workspace, not only a naming suggestion.

Default completion checklist:

1. new worktree exists
2. new branch exists and is checked out there
3. repo status in the new worktree is clean before new edits
4. required local config files are copied into the new worktree when they exist in the source worktree
5. `flutter pub get` has completed successfully
6. note any required next command if setup cannot be completed automatically

When useful for this repo, also do one or more of:

- inspect package or workspace dependency files
- confirm whether code generation or other bootstrap steps are required

For this repo, prefer the concrete initialization flow below unless the user explicitly asks to skip it:

1. sync local-only config into the new worktree
2. run `flutter pub get` at the repo root

Prefer the smallest safe setup that unblocks development quickly.

## Safety Rules

- Never infer a ticket id from the current branch in this skill; the user must provide it.
- If there is no reliable parsed brief yet, stop before any git write operation and run or request investigation first.
- If the ticket summary is too vague to create a reliable slug, produce the best concise slug you can and say it is a naming inference.
- If the current repo has unrelated dirty changes, do not modify them; creating a separate worktree is still preferred.
- If `git fetch` or other network-dependent git commands fail because of environment restrictions, report that clearly.
- Do not overwrite existing directories or force-create branches.

## Output Rules

Keep the response concise and execution-oriented.

Preferred output shape:

1. `Ticket`: issue key and summary
2. `Ticket 摘要`: short implementation brief
3. `English Slug`: the naming phrase
4. `Branch`: final branch name
5. `Worktree`: final worktree path
6. `Setup`: what was created or what blocked creation
7. `待確認`: only when meaningful ambiguity remains

## Style Rules

- Primary language: `zh-tw`
- Allowed exceptions: necessary `en-us` proper nouns and technical terms such as `YouTrack`, `State`, `branch`, `worktree`, `slug`, `API`, `UI`, `Backend`, and issue keys
- Preferred tone: concise, reliable, and directly actionable
