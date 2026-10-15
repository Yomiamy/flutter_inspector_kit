#!/usr/bin/env bash
set -euo pipefail

# 鎖住「流程守衛掛載在進版控的 .claude/settings.json」。
# 刻意不讀 settings.local.json：它不進版控，clone 環境裡不存在。
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS=".claude/settings.json"
# shell form 的路徑佔位符必須加雙引號（官方 hooks 文件），否則 repo 路徑含空白時 hook 無法啟動。
STAGE_CHECK_REL='.claude/hooks/wf-guard-stage-check.sh'
DELEGATE_CWD_REL='.claude/hooks/wf-guard-delegate-cwd.sh'
STAGE_CHECK='"$CLAUDE_PROJECT_DIR"/'"$STAGE_CHECK_REL"
DELEGATE_CWD='"$CLAUDE_PROJECT_DIR"/'"$DELEGATE_CWD_REL"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "=== Test 1 (AC-1): settings.json tracked, not ignored, valid JSON ==="
git -C "$REPO_ROOT" ls-files --error-unmatch -- "$SETTINGS" >/dev/null 2>&1 \
  || fail "$SETTINGS is not tracked by git"
# --no-index：已追蹤的檔案預設不受 ignore 規則檢查，不加此旗標斷言永遠成立。
# 不加 -v：verbose 連「!」否定規則的命中也會輸出，會讓合法的重新納入誤判為 FAIL。
# core.excludesFile=/dev/null：只看 repo 內規則，不讓個人全域 ignore 左右結果（S-3）。
IGNORED="$(git -C "$REPO_ROOT" -c core.excludesFile=/dev/null check-ignore --no-index -- "$SETTINGS" || true)"
[ -z "$IGNORED" ] || fail "$SETTINGS is matched by a repo ignore rule"
jq -e . "$REPO_ROOT/$SETTINGS" >/dev/null || fail "$SETTINGS is not valid JSON"
echo "PASS: $SETTINGS tracked, not ignored, valid JSON"

echo "=== Test 2 (AC-2): each guard registered exactly once ==="
check_guard() {
  local n
  n="$(jq --arg e "$1" --arg m "$2" --arg c "$3" \
    '[.hooks[$e][]? | select(.matcher == $m) | .hooks[]?
      | select(. == {"type": "command", "command": $c})] | length' \
    "$REPO_ROOT/$SETTINGS")"
  [ "$n" = "1" ] || fail "$1 / $2 / $3 registered $n times (expected 1)"
  echo "PASS: $1 / $2 / $3"
}
check_guard PreToolUse Agent "$STAGE_CHECK"
check_guard PreToolUse mcp__gemini-cli__ask-gemini "$DELEGATE_CWD pre"
check_guard PostToolUse mcp__gemini-cli__ask-gemini "$DELEGATE_CWD post"

echo "=== Test 3 (AC-3): guard scripts exist, executable, index mode 100755 ==="
for rel in "$STAGE_CHECK_REL" "$DELEGATE_CWD_REL"; do
  [ -f "$REPO_ROOT/$rel" ] || fail "$rel does not exist"
  [ -x "$REPO_ROOT/$rel" ] || fail "$rel is not executable"
  mode="$(git -C "$REPO_ROOT" ls-files -s -- "$rel" | cut -d' ' -f1)"
  [ "$mode" = "100755" ] || fail "$rel index mode is '${mode:-untracked}' (expected 100755)"
  echo "PASS: $rel exists, executable, index mode 100755"
done

echo "ALL TESTS PASSED!"
