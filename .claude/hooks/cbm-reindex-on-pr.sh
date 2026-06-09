#!/bin/bash
# PostToolUse(Bash) hook: re-index the codebase on PR creation or git sync.
# Fires after every Bash call; only acts on `gh pr create`, `git push`, or `git pull`.
# Indexing runs in the background (fast mode) so it never blocks the agent.

input=$(cat)

# Tokenize the command (shlex) and decide whether to act, all in one Python pass.
# Parsing into a token list — instead of regex-matching the raw string — kills the
# false positives: `git commit -m "add push button"` has subcommand `commit`, so the
# "push" inside the quoted message never counts. Exits 0 (skip) unless the command is:
#   - `gh pr create`                  → PR creation
#   - `git [global-opts] push|pull`   → repo sync (git's first non-option token)
should_act=$(printf '%s' "$input" | python3 -c '
import json, shlex, sys
try:
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    toks = shlex.split(cmd)
except Exception:
    sys.exit(0)
# gh pr create
if toks[:3] == ["gh", "pr", "create"]:
    print(1); sys.exit(0)
# git <global opts> <subcommand> ...  — find first token that is not an option.
# git global opts that take a value: -C <path>, -c <name=val>, --git-dir <path>, etc.
if toks[:1] == ["git"]:
    i, takes_val = 1, {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
    while i < len(toks):
        t = toks[i]
        if t in takes_val:
            i += 2; continue          # skip the option and its value
        if t.startswith("-"):
            i += 1; continue          # skip a standalone/inline-value option
        if t in ("push", "pull"):
            print(1)
        break                          # first non-option token = the subcommand
' 2>/dev/null)

[ -n "$should_act" ] || exit 0

repo="${CLAUDE_PROJECT_DIR:-$PWD}"
cli="$HOME/.local/bin/codebase-memory-mcp"
[ -x "$cli" ] || exit 0

# Background re-index; detached so the hook returns immediately.
nohup "$cli" cli index_repository "{\"repo_path\":\"$repo\",\"mode\":\"fast\"}" \
  >/dev/null 2>&1 &

echo "[cbm] repo sync detected → re-indexing $repo in background (fast mode)."
exit 0
