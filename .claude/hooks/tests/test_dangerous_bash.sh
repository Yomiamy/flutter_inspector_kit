#!/usr/bin/env bash
set -euo pipefail

# Bash 危險指令分級（guard-dangerous-bash.py）。
# 規格：docs/features/2026-11-21-main-session-guard-and-missing-coverage.md §4.2 AC-12～AC-18
# 輸出形狀依官方 hooks 文件：hookSpecificOutput.permissionDecision（deny / ask）+ permissionDecisionReason。

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/guard-dangerous-bash.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# fixture：一個在 main、一個在 feature branch 的 repo；PLAIN 沒有任何 state 檔，也不是 git repo（AC-17）
G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null)
ON_MAIN="$TMP/on-main"; ON_FEAT="$TMP/on-feat"; PLAIN="$TMP/plain"
"${G[@]}" init -q -b main "$ON_MAIN" && "${G[@]}" -C "$ON_MAIN" commit -q --allow-empty -m init
"${G[@]}" init -q -b feat/x "$ON_FEAT" && "${G[@]}" -C "$ON_FEAT" commit -q --allow-empty -m init
mkdir -p "$PLAIN" "$ON_FEAT/.claude/workflow-state"
echo '{"stage":"2"}' >"$ON_FEAT/.claude/workflow-state/feat-x.json"

run() {
  set +e
  OUT="$(jq -nc --arg c "$1" --arg cwd "$CWD" \
    '{hook_event_name: "PreToolUse", cwd: $cwd, tool_name: "Bash", tool_input: {command: $c}}' \
    | "$HOOK" 2>"$TMP/err")"
  CODE=$?
  set -e
  ERR="$(cat "$TMP/err")"
  [ "$CODE" -eq 0 ] && [ -z "$ERR" ] || fail "hook 必須 exit 0 且 stderr 為空（$1）：code=$CODE err='$ERR'"
}
decide() { # decide <deny|ask> <command>
  run "$2"
  jq -e --arg d "$1" --arg c "$2" '.hookSpecificOutput.hookEventName == "PreToolUse"
    and .hookSpecificOutput.permissionDecision == $d
    and (.hookSpecificOutput.permissionDecisionReason | contains("命中規則"))' <<<"$OUT" >/dev/null \
    || fail "預期 $1（$2），實得 '$OUT'"
}
pass() { run "$1"; [ -z "$OUT" ] || fail "預期放行且無輸出（$1），實得 '$OUT'"; }

check_all() {
  echo "=== AC-12: rm -rf 目標為 / ~ \$HOME → deny ==="
  for c in 'rm -rf /' 'rm -rf ~' 'rm -rf $HOME' 'rm -rf "$HOME"' 'rm -rf ${HOME}/' 'rm -fr ~/' \
           'rm -Rf /*' 'rm -r -f ~/*' 'sudo rm -rf /' '/bin/rm -rf --recursive -- ~' \
           'ls && rm -rf ~' 'cd /tmp; rm -rf $HOME' "$(printf 'cd /tmp\nrm -rf ~')" 'rtk proxy rm -rf ~' \
           "rm -rf ~; echo 'unbalanced" "$(printf 'rm -rf \\\n  ~')"; do
    decide deny "$c"
  done
  for c in 'rm -rf ./build' 'rm -rf "$TMPDIR/wf-x"' 'rm -rf ~/scratch/x' 'rm -f ~' 'rm -r /' \
           'echo "rm -rf ~"' "$(printf 'git commit -F - <<EOF\nrm -rf ~ is denied\nEOF')"; do
    pass "$c"
  done
  echo "PASS"

  echo "=== AC-13: force push 到 main → deny ==="
  for c in 'git push --force origin main' 'git push -f origin main' 'git push origin main --force' \
           'git push --force-with-lease origin main' 'git push origin +main' 'git push -f origin HEAD:main' \
           'git push -fu origin refs/heads/main' "git -C $ON_MAIN push -f" "cd $ON_MAIN && git push --force origin HEAD" \
           'rtk git push -f origin main' 'rtk proxy git push --force origin main' \
           "$(printf 'git fetch origin  # update\ngit push --force origin main')" \
           "$(printf 'git push --force \\\n  origin main')"; do
    decide deny "$c"
  done
  for c in 'git push origin main' 'git push --force origin feature/x' 'git push -u origin main' 'git push origin :main' \
           "git -C $ON_FEAT push -f" "cd $ON_FEAT && git push --force-with-lease" 'git push -f'; do
    pass "$c"
  done
  echo "PASS"

  echo "=== AC-14: git reset --hard → ask ==="
  decide ask 'git reset --hard'
  decide ask 'git reset --hard origin/main'
  decide ask 'rtk git reset --hard'
  decide ask "$(printf 'git stash  # save\ngit reset --hard origin/main')"
  pass 'git reset --soft HEAD~1'
  echo "PASS"

  echo "=== AC-15: git checkout . / git restore . → ask ==="
  decide ask 'git checkout .'
  decide ask 'git restore .'
  decide ask 'git checkout -- .'
  pass 'git checkout -b feat/x'
  pass 'git restore --staged lib/a.dart'
  echo "PASS"

  echo "=== AC-16: git clean -f → ask ==="
  decide ask 'git clean -f'
  decide ask 'git clean -fd'
  pass 'git clean -n'
  echo "PASS"

  echo "=== AC-18: deny 優先於 ask；理由含規則與子指令；一般指令無輸出 ==="
  decide deny 'git reset --hard && git push -f origin main'
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("force push 到 main") and contains("git push -f origin main")' \
    <<<"$OUT" >/dev/null || fail "理由缺規則或子指令：$OUT"
  for c in 'git status' 'flutter test' 'git log --oneline -5'; do pass "$c"; done
  echo "PASS"
}

echo "##### cwd 位於有 workflow state 的 repo #####"
CWD="$ON_FEAT"; check_all
echo "##### AC-17：cwd 無任何 state 檔（也不是 git repo），判定結果必須相同 #####"
CWD="$PLAIN"; check_all

echo "=== AC-13 補充：在 main 上省略 refspec 的 force push → deny ==="
CWD="$ON_MAIN"
decide deny 'git push -f'
decide deny 'git push --force origin'
decide deny 'git push -f 2>&1'
decide deny 'git push -f >/dev/null 2>&1'
decide deny 'git push --force origin 2>&1 | tail -3'
pass 'git push'
pass 'git push -f origin feat/x 2>&1'
echo "PASS"

echo "=== 引號內的 > 不吞後面的分隔符；失敗的 cd 不改判斷目錄；--all 視同含 main ==="
CWD="$ON_MAIN"
decide deny "echo '>'; git push -f origin main"
decide deny "echo '>' && git push -f origin main"
decide deny 'cd /definitely-missing; git push -f origin'
CWD="$ON_FEAT"
decide deny 'git push --force --all origin'
decide deny 'git push --all -f origin'
decide deny 'git push --branches -f origin'
decide deny 'git push --branches -f -o ci.skip origin'  # -o 的值不是 refspec
decide deny 'git push --all --push-option ci.skip -f origin'
decide deny 'git push --repo origin --all -f'
pass 'git push --all origin'
pass 'git push -o ci.skip origin feat/x'
pass 'git push -f -o ci.skip origin feat/x'
CWD="$TMP"; decide deny 'cd on-main && git push -f origin'  # 相對路徑 cd
CWD="$ON_FEAT"
pass "echo '>'; git push -f origin feat/x"
pass "cd $ON_MAIN && git push -f origin feat/x"
echo "PASS"

echo "=== fail-open：壞 payload / 無法解析的指令放行且無輸出 ==="
for p in 'not json' '' '{"tool_input": "x"}'; do
  set +e; OUT="$(printf '%s' "$p" | "$HOOK" 2>&1)"; CODE=$?; set -e
  [ "$CODE" -eq 0 ] && [ -z "$OUT" ] || fail "壞 payload 應靜默放行：code=$CODE out='$OUT'"
done
pass "echo 'unbalanced"
echo "PASS"

echo "ALL TESTS PASSED!"
