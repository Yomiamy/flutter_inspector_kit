---
name: gen-commit
description: Analyze unstaged/staged git changes, group files by functional relevance, and create multiple semantic unit commits. Use when the user says "commit", "gen-commit", "依功能 commit", "幫我 commit", "進行功能單元 commit", or any variant requesting intelligent grouping and committing of current changes. Also use when the user wants to commit changed files with meaningful, well-structured messages organized by feature area.
---

# gen-commit

Analyze current git changes, group files by functional relevance, and execute multiple semantic commits — one per logical unit.

## Workflow

### 1. Inspect Changes

```bash
git status
git diff --stat
```

Include both staged and unstaged changes. Also check untracked files that belong to the work.

### 2. Group Files by Functional Unit

Examine `git diff` content for each file to understand what changed, then cluster into groups where **all files in a group serve the same logical purpose**.

**Grouping heuristics:**

| Group type | Typical file patterns |
|---|---|
| `feat` | New feature files + their direct tests |
| `refactor` | Style/constant/naming changes across related files |
| `test` | Test files only (when decoupled from implementation) |
| `fix` | Bug fix files, often narrow scope |
| `chore` | Config, tooling, Makefile, CI, lock files |
| `build` / `ci` | Build scripts, pubspec, package.json, pipelines |
| `docs` | Documentation-only changes |

**Key rule:** One commit = one reason to change. If two files could be explained by the same sentence, they belong together.

### 3. Order Commits

Commit in dependency order — foundational changes first (e.g., config before generated files, constants before UI that uses them).

### 4. Execute Commits

For each group, stage only those files and commit:

```bash
git add <file1> <file2> ...
git commit -m "$(cat <<'EOF'
<type>(<optional scope>): <short imperative summary>

<optional body explaining why, not what>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

**Message rules:**
- Type: `feat` / `fix` / `refactor` / `test` / `chore` / `build` / `ci` / `docs`
- Subject line ≤ 72 chars, imperative mood ("add", "fix", "remove" — not "added", "fixes")
- Body: explain *why* or *what changed*, not line-by-line summary
- Always append the `Co-Authored-By` trailer

### 5. Confirm

After all commits, run `git log --oneline -N` (N = number of commits made) and show the user the result.

## Edge Cases

- **Untracked files**: Include if clearly part of a logical unit; skip generated or binary files unless they're the point of the commit.
- **Single logical change**: One commit is correct — don't split artificially.
- **Generated files** (e.g., `*.gen.dart`, `pubspec.lock`): Group with the config/source that triggered their generation, not separately.
- **Ambiguous grouping**: Prefer fewer, broader commits over many micro-commits that are hard to reason about.
