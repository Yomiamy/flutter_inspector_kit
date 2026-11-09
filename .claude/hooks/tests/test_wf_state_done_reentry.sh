#!/usr/bin/env bash
set -euo pipefail

# STAGE 5/6 are standalone entries after the PR is published, so a sequence
# workflow that already reached `done` must still be able to re-enter them.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WF_STATE="$REPO_ROOT/.claude/skills/gen-dev-workflow/scripts/wf-state.sh"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
export WF_STATE_DIR="$TEMP_DIR"

# Drive a fresh sequence workflow to `done` via 0a→0b→1→2→3→4→done.
new_done_state() {
  local branch="$1" pending state
  pending="$("$WF_STATE" init --mode sequence --stage 0a)"
  "$WF_STATE" advance "$pending" 0b --confirmed >/dev/null
  "$WF_STATE" advance "$pending" 1 --confirmed >/dev/null
  state="$("$WF_STATE" promote "$pending" --branch "$branch" --dest "$TEMP_DIR")"
  for s in 2 3 4 done; do
    "$WF_STATE" advance "$state" "$s" --confirmed >/dev/null
  done
  echo "$state"
}

stage_of() { "$WF_STATE" get "$1" | jq -r '.stage'; }

echo "=== Test 1: done -> 5 is allowed (PR review after publish) ==="
F1="$(new_done_state test/done-to-5)"
"$WF_STATE" advance "$F1" 5 --confirmed
[ "$(stage_of "$F1")" = "5" ] || { echo "FAIL: expected stage 5" >&2; exit 1; }
echo "PASS"

echo "=== Test 2: done -> 6 is allowed (cleanup after merge) ==="
F2="$(new_done_state test/done-to-6)"
"$WF_STATE" advance "$F2" 6 --confirmed
[ "$(stage_of "$F2")" = "6" ] || { echo "FAIL: expected stage 6" >&2; exit 1; }
echo "PASS"

echo "=== Test 3: done -> 2 is still illegal ==="
F3="$(new_done_state test/done-to-2)"
set +e
ERR="$("$WF_STATE" advance "$F3" 2 --confirmed 2>&1)"
CODE=$?
set -e
if [ "$CODE" -eq 0 ] || ! grep -q "非法 stage 轉移" <<<"$ERR"; then
  echo "FAIL: done -> 2 should be rejected (exit=$CODE): $ERR" >&2
  exit 1
fi
echo "PASS"

echo "All done-reentry tests passed."
