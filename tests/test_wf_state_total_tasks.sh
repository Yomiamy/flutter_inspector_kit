#!/usr/bin/env bash
set -euo pipefail

# Locate repo root and wf-state.sh
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF_STATE="$REPO_ROOT/.claude/skills/gen-dev-workflow/scripts/wf-state.sh"

if [ ! -f "$WF_STATE" ]; then
  echo "Error: wf-state.sh not found at $WF_STATE" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

export STATE_DIR="$TEMP_DIR"

echo "=== Test 1: set total_tasks=3 stores numeric 3 ==="
INIT_OUTPUT="$("$WF_STATE" init --mode sequence --stage 0a)"
PENDING_FILE="$INIT_OUTPUT"
"$WF_STATE" advance "$PENDING_FILE" 0b --confirmed
"$WF_STATE" advance "$PENDING_FILE" 1 --confirmed
BRANCH="test/test-branch"
STATE_FILE="$("$WF_STATE" promote "$PENDING_FILE" --branch "$BRANCH" --dest "$TEMP_DIR")"
"$WF_STATE" advance "$STATE_FILE" 2 --confirmed

"$WF_STATE" set "$STATE_FILE" total_tasks=3
TOTAL="$("$WF_STATE" get "$STATE_FILE" | jq -r '.total_tasks')"
if [ "$TOTAL" != "3" ]; then
  echo "FAIL: Expected total_tasks to be 3, got $TOTAL" >&2
  exit 1
fi
echo "PASS: total_tasks is 3"

echo "=== Test 2: advance to 3 blocked when completed_tasks < total_tasks ==="
"$WF_STATE" task-done "$STATE_FILE" 1
"$WF_STATE" task-done "$STATE_FILE" 2

set +e
ERR_OUTPUT="$("$WF_STATE" advance "$STATE_FILE" 3 --confirmed 2>&1)"
STATUS=$?
set -e

if [ $STATUS -eq 0 ]; then
  echo "FAIL: Expected advance 3 to fail when completed < total, but it succeeded!" >&2
  exit 1
fi

if [[ "$ERR_OUTPUT" != *"實作尚未全部完成（已完成 2 / 共 3 任務）"* ]]; then
  echo "FAIL: Unexpected error message: $ERR_OUTPUT" >&2
  exit 1
fi
echo "PASS: Blocked with expected message: $ERR_OUTPUT"

echo "=== Test 3: advance to 3 succeeds when completed_tasks == total_tasks ==="
"$WF_STATE" task-done "$STATE_FILE" 3
"$WF_STATE" advance "$STATE_FILE" 3 --confirmed
CUR_STAGE="$("$WF_STATE" get "$STATE_FILE" | jq -r '.stage')"
if [ "$CUR_STAGE" != "3" ]; then
  echo "FAIL: Expected stage 3, got $CUR_STAGE" >&2
  exit 1
fi
echo "PASS: Advanced to stage 3 successfully"

echo "=== Test 4: total_tasks=null backward compatibility ==="
TEMP_DIR2="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR" "$TEMP_DIR2"' EXIT
export STATE_DIR="$TEMP_DIR2"

INIT_OUTPUT2="$("$WF_STATE" init --mode sequence --stage 0a)"
"$WF_STATE" advance "$INIT_OUTPUT2" 0b --confirmed
"$WF_STATE" advance "$INIT_OUTPUT2" 1 --confirmed
STATE_FILE2="$("$WF_STATE" promote "$INIT_OUTPUT2" --branch "test/test-null" --dest "$TEMP_DIR2")"
"$WF_STATE" advance "$STATE_FILE2" 2 --confirmed

"$WF_STATE" task-done "$STATE_FILE2" 1
"$WF_STATE" advance "$STATE_FILE2" 3 --confirmed
CUR_STAGE2="$("$WF_STATE" get "$STATE_FILE2" | jq -r '.stage')"
if [ "$CUR_STAGE2" != "3" ]; then
  echo "FAIL: Expected stage 3 with total_tasks=null, got $CUR_STAGE2" >&2
  exit 1
fi
echo "PASS: null total_tasks passes backward-compatibly"

echo "=== Test 5: advance to 3 blocked when completed_tasks > total_tasks ==="
TEMP_DIR3="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR" "$TEMP_DIR2" "$TEMP_DIR3"' EXIT
export STATE_DIR="$TEMP_DIR3"

INIT_OUTPUT3="$("$WF_STATE" init --mode sequence --stage 0a)"
"$WF_STATE" advance "$INIT_OUTPUT3" 0b --confirmed
"$WF_STATE" advance "$INIT_OUTPUT3" 1 --confirmed
STATE_FILE3="$("$WF_STATE" promote "$INIT_OUTPUT3" --branch "test/test-overflow" --dest "$TEMP_DIR3")"
"$WF_STATE" advance "$STATE_FILE3" 2 --confirmed

"$WF_STATE" set "$STATE_FILE3" total_tasks=2
"$WF_STATE" task-done "$STATE_FILE3" 1
"$WF_STATE" task-done "$STATE_FILE3" 2
"$WF_STATE" task-done "$STATE_FILE3" 3

set +e
ERR_OUTPUT3="$("$WF_STATE" advance "$STATE_FILE3" 3 --confirmed 2>&1)"
STATUS3=$?
set -e

if [ $STATUS3 -eq 0 ]; then
  echo "FAIL: Expected advance 3 to fail when completed > total, but it succeeded!" >&2
  exit 1
fi

if [[ "$ERR_OUTPUT3" != *"任務狀態異常：已完成數 (3) 超出宣告總數 (2)"* ]]; then
  echo "FAIL: Unexpected error message: $ERR_OUTPUT3" >&2
  exit 1
fi
echo "PASS: Blocked with expected message: $ERR_OUTPUT3"

echo "ALL TESTS PASSED!"
