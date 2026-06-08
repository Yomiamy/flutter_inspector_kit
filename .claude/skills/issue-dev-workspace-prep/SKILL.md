---
name: issue-dev-workspace-prep
description: Use after context-collector has produced issue context and the user wants to prepare a development branch or worktree. Uses .agent-output/context/* as the source for issue id, slug, work type, and blockers; when creating a new worktree, it must copy the current context output into the new worktree before any issue-doc-writer or issue-spec-writer runs.
---

# Issue Dev Workspace Prep

Use this skill to prepare a development workspace from context output.

## Can modify

- Git branch / worktree state.
- Local copied context files under `.agent-output/context/*` in the target worktree.

## Cannot modify

- Production code.
- Tests.
- `docs/issues/*`.
- `docs/issues/specs/*`.
- PRs.
- YouTrack comments or State.

## Required Input

- A current `context-collector` output file under `.agent-output/context/*`.

If missing, route to `context-collector`.

## Workflow

1. Read the context file.
2. Confirm `Handoff` is `workspace-prep-ready`.
3. Resolve issue id if present, work type, slug, and blockers.
4. Inspect current branch/status and existing worktrees.
5. Choose `current-branch`, `current-worktree-new-branch`, `new-worktree`, or `no-prep`.
6. Execute the selected workspace strategy.
7. If creating `new-worktree`, copy the current context file into the target worktree.
8. Verify the copied context file exists in the target worktree.
9. Report workspace result and next skill.

## New Worktree Script

Prefer the bundled script when creating a new worktree:

```bash
scripts/prepare_ticket_dev_workspace.sh --ticket-id "<ISSUE-ID>" --prefix "<fix/|feature/|chore/>" --slug "<slug>"
```

Omit `--ticket-id` for no-ticket issues:

```bash
scripts/prepare_ticket_dev_workspace.sh --prefix "<fix/|feature/|chore/>" --slug "<slug>"
```

The script also syncs local-only development config into the target worktree, including:

- root `.env` and `.env.*`
- `android/key.properties`
- `android/app/google-services.json`
- Android signing files such as `*.keystore` and `*.jks`
- `ios/Runner/GoogleService-Info.plist`
- iOS / Android `fastlane` private signing or credential files

Use `--skip-local-config-sync` only when the user explicitly wants no local config copy.

## Mandatory Context Handoff

If strategy is `new-worktree`:

```text
copy .agent-output/context/<subject>.md from source workspace to target worktree
verify target .agent-output/context/<subject>.md exists
stop if copy or verification fails
```

Do this before running `issue-doc-writer` or `issue-spec-writer`.

## Naming

Use issue id when present. Otherwise use slug.

Branch examples:

- `fix/<ISSUE-ID>-<slug>`
- `feature/<ISSUE-ID>-<slug>`
- `chore/<ISSUE-ID>-<slug>`
- Without issue id: `<type>/<slug>`

## Output Rules

Report:

- context file used.
- strategy.
- branch.
- worktree.
- context copy result.
- blockers.
- next skill: usually `issue-doc-writer`.

Primary language: `zh-tw`.
