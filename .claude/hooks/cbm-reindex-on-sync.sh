#!/bin/bash
# AfterTool(run_command) hook for Antigravity (agy).
# Re-indexes codebase-memory after `git push`, `git pull`, or `gh pr create`.
#
# Adapted from .claude/hooks/cbm-reindex-on-pr.sh but uses agy's stdin schema:
#   - Claude:       .tool_input.command
#   - Antigravity:  .toolCall.args.CommandLine
#
# Fires after every run_command call; only acts on repo-sync commands.
# Indexing runs in background (fast mode) so it never blocks the agent.

input=$(cat)

# Parse the command from agy's JSON schema and decide whether to act.
# Uses shlex tokenization to avoid false positives (e.g. "git commit -m 'push button'").
should_act=$(printf '%s' "$input" | python3 -c '
import json, shlex, sys
try:
    data = json.load(sys.stdin)
    # Antigravity schema: .toolCall.args.CommandLine
    cmd = ""
    tc = data.get("toolCall", {})
    args = tc.get("args", tc.get("Arguments", {}))
    cmd = args.get("CommandLine", args.get("command", ""))
    # Fallback: try Claude schema for compatibility
    if not cmd:
        cmd = data.get("tool_input", {}).get("command", "")
    if not cmd:
        sys.exit(0)
    toks = shlex.split(cmd)
except Exception:
    sys.exit(0)

# gh pr create
if toks[:3] == ["gh", "pr", "create"]:
    print(1); sys.exit(0)

# git <global opts> <subcommand> — find first non-option token
if toks[:1] == ["git"]:
    i = 1
    takes_val = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
    while i < len(toks):
        t = toks[i]
        if t in takes_val:
            i += 2; continue
        if t.startswith("-"):
            i += 1; continue
        if t in ("push", "pull"):
            print(1)
        break
' 2>/dev/null)

[ -n "$should_act" ] || exit 0

repo="$(cd "$(dirname "$0")/../.." && pwd)"
cli="$HOME/.local/bin/codebase-memory-mcp"
[ -x "$cli" ] || exit 0

# Background re-index; detached so the hook returns immediately.
nohup "$cli" cli index_repository "{\"repo_path\":\"$repo\",\"mode\":\"fast\"}" \
  >/dev/null 2>&1 &

echo "[cbm] repo sync detected → re-indexing $repo in background (fast mode)." >&2
exit 0
