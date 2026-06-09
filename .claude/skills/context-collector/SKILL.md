---
name: context-collector
description: Use when Codex needs canonical issue context collection from YouTrack tickets, user briefs, QA reports, branch context, or focused repository evidence before issue docs, specs, workspace prep, implementation, or workflow routing. Produces or refreshes .agent-output/context/<issue-id-or-slug>.md as the main facts/inference/open-questions source without modifying source, tests, specs, PRs, or YouTrack state.
---

# Context Collector

Use this skill as the canonical issue context source.

## Role

- Role: issue context collector.
- Strategy: collect facts once, make downstream skills read the same source.

## Can modify

- `.agent-output/context/*`.

## Cannot modify

- Production code.
- Tests.
- `docs/issues/*`.
- `docs/issues/specs/*`.
- PRs.
- YouTrack comments or State.

## Inputs

Accept any issue source:

- YouTrack issue id.
- User-provided issue brief.
- QA report.
- Feature request.
- Current branch context.
- Existing issue doc or spec refresh request.

## Workflow

1. Resolve the subject.
2. Read source facts from YouTrack, user brief, branch context, QA evidence, and focused repo inspection as applicable.
3. Distinguish facts, inference, and open questions.
4. Inspect only code needed to understand likely affected areas.
5. Write or refresh `.agent-output/context/<subject>.md`.
6. Keep a concise `History` table in the same file.
7. Report the context file path and whether it is ready for issue doc, workspace prep, or blocked.

## Path Rules

Use one canonical file per subject:

- With issue id: `.agent-output/context/<ISSUE-ID>.md`
- Without issue id: `.agent-output/context/<slug>.md`

Do not add `-context` to the filename because the folder already defines artifact type.

If refreshing the same subject, overwrite the same file and update `History`. Do not create a `history/` folder.

## Required Sections

Use this structure:

```markdown
# <Subject> Context

## Source

## Summary

## Facts

## Code Observations

## Inference

## Open Questions

## Suggested Slug

## Handoff

## History

| Time | Change | Source | Notes |
| --- | --- | --- | --- |
```

`Handoff` must say:

- `issue-doc-ready`
- `workspace-prep-ready`
- `blocked`

Include blocker reason when blocked.

## History Rules

- Add one table row per context refresh.
- Summarize the change, source, and caveat.
- Do not paste full old content or full source text.

## Output Rules

- Primary language: `zh-tw`.
- Keep necessary `en-us` technical terms.
- Report only the context path, readiness, blockers, and suggested next skill.
