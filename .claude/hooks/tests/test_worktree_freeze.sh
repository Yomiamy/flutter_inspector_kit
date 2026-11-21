#!/usr/bin/env bash
set -euo pipefail

# 主對話 worktree 凍結（wf-guard-worktree-freeze.py）。
# 規格：docs/features/2026-11-21-main-session-guard-and-missing-coverage.md §4.1 AC-1～AC-11
# payload 形狀依官方 hooks 文件：common input 的 cwd、Edit/Write 的 tool_input.file_path（一律絕對路徑）。

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/wf-guard-worktree-freeze.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)" # macOS：/var → /private/var，讓斷言與 hook 的 realpath 同形

fail() { echo "FAIL: $*" >&2; exit 1; }

# fixture：主 repo R（main）+ 兩個 workflow worktree（W1、W2 各有 state 檔）+ 一個沒有 state 的 worktree（WX）
# + 一個仿 isolation: worktree 的 subagent worktree（AG，branch worktree-agent-a1，沒有 state 檔）
R="$TMP/re po"; W1="$R/.claude/worktrees/w1"; W2="$R/.claude/worktrees/w2"; WX="$R/.claude/worktrees/wx"
AG="$R/.claude/worktrees/agent-a1"
OUT_DIR="$TMP/outside"
G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null)
"${G[@]}" init -q -b main "$R"
"${G[@]}" -C "$R" commit -q --allow-empty -m init
"${G[@]}" -C "$R" worktree add -q -b feat/202611/1-w1 "$W1"
"${G[@]}" -C "$R" worktree add -q -b feat/202611/2-w2 "$W2"
"${G[@]}" -C "$R" worktree add -q -b feat/202611/3-wx "$WX"
"${G[@]}" -C "$R" worktree add -q -b worktree-agent-a1 "$AG"
mkdir -p "$W1/.claude/workflow-state" "$W2/.claude/workflow-state" "$R/.claude/workflow-state" \
  "$W1/lib" "$W1/.claude/skills" "$W1/.agents" "$R/lib" "$OUT_DIR"
echo '{"stage":"2"}' >"$W1/.claude/workflow-state/feat-202611-1-w1.json"
echo '{"stage":"done"}' >"$W2/.claude/workflow-state/feat-202611-2-w2.json"
echo '{"stage":"0b"}' >"$R/.claude/workflow-state/.pending-wf-1-abcd.json"
ln -s ../.claude/skills "$W1/.agents/skills" # 合法相對 symlink（同 repo 的 .agents/skills）
ln -s ../../../lib "$W1/escape"               # 指向 R/lib 的逃逸 symlink
ln -s "$OUT_DIR" "$W1/ext"                     # 指向 repo 外
mkdir -p "$W1/deep/sub" && ln -s deep/sub "$W1/inner" # 指向 W 內更深處：詞法與 realpath 對 .. 的解讀不同

# payload <cwd> <file_path> [tool]
payload() {
  jq -nc --arg cwd "$1" --arg fp "$2" --arg t "${3:-Edit}" '{
    session_id: "s", hook_event_name: "PreToolUse", cwd: $cwd, permission_mode: "default",
    tool_name: $t, tool_input: {file_path: $fp, old_string: "a", new_string: "b"}, tool_use_id: "toolu_1"}'
}
run() {
  set +e
  OUT="$(printf '%s' "$1" | "$HOOK" 2>"$TMP/err")"
  CODE=$?
  set -e
  ERR="$(cat "$TMP/err")"
}
allowed() {
  run "$(payload "$@")"
  [ "$CODE" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] \
    || fail "預期放行（$*），實得 code=$CODE out='$OUT' err='$ERR'"
}
blocked() {
  run "$(payload "$@")"
  [ "$CODE" -eq 2 ] || fail "預期 exit 2（$*），實得 $CODE err='$ERR'"
  [[ "$ERR" == *"[WF-FREEZE BLOCK]"* ]] || fail "缺 [WF-FREEZE BLOCK]：$ERR"
  [[ "$ERR" == *"$2"* ]] || fail "訊息缺被擋路徑 $2：$ERR"
}

echo "=== AC-1: 越界 deny，訊息含被擋路徑、W 與 W 內同相對路徑 ==="
blocked "$W1" "$R/docs/plans/x.md"
[[ "$ERR" == *"綁定 worktree：$W1"* ]] || fail "訊息缺 W：$ERR"
[[ "$ERR" == *"請改寫：$W1/docs/plans/x.md"* ]] || fail "訊息缺建議路徑：$ERR"
blocked "$W1/lib" "$R/lib/a.dart" Write # cwd 在 W 的子目錄也算綁定
echo "PASS"

echo "=== AC-2: W 內放行（含尚不存在的新檔）==="
allowed "$W1" "$W1/lib/a.dart"
allowed "$W1" "$W1/lib/new/deep/file.dart" Write
echo "PASS"

echo "=== AC-3: repo 外放行 ==="
allowed "$W1" "$OUT_DIR/scratch.md" Write
allowed "$W1" "$HOME/.claude/projects/p/memory/m.md" Write
allowed "$W1" "/tmp/x.md" Write
echo "PASS"

echo "=== AC-4: 無 state 檔放行（主 repo、沒有 state 的 worktree、非 git 目錄）==="
allowed "$WX" "$R/lib/a.dart"
allowed "$OUT_DIR" "$R/lib/a.dart"
echo "PASS"

echo "=== AC-5: 只有 .pending-*.json（STAGE 0a/0b）放行 ==="
allowed "$R" "$R/docs/features/x.md" Write
allowed "$R" "$R/docs/plans/x.md" Write
echo "PASS"

echo "=== AC-6: 當前 session 不屬任何 workflow，但其他 worktree 有 active workflow → 放行 ==="
allowed "$R" "$R/lib/a.dart"
allowed "$R/lib" "$W2/lib/a.dart" # 未綁定時寫其他 worktree 也放行（Q-2）
echo "PASS"

echo "=== AC-7: 跨 worktree deny（建議路徑取目標 worktree 內的相對路徑）==="
blocked "$W1" "$W2/lib/a.dart"
[[ "$ERR" == *"請改寫：$W1/lib/a.dart"* ]] || fail "跨 worktree 建議路徑錯誤：$ERR"
blocked "$W2" "$W1/lib/a.dart" # stage=done 仍綁定（Q-4）
echo "PASS"

echo "=== AC-7 補充：目標在未綁定的 linked worktree（isolation subagent 的 worktree）→ 放行 ==="
# subagent 的 hook cwd 可能仍是主對話的 W1，也可能是它自己的 worktree：兩種都不得誤擋
allowed "$W1" "$AG/lib/new.dart" Write
allowed "$AG" "$AG/lib/new.dart" Write
allowed "$W1" "$WX/lib/a.dart"
echo "PASS"

echo "=== AC-8: 詞法 .. 逃逸 deny ==="
blocked "$W1" "$W1/../../../lib/a.dart"
# 詞法正規化落在 W 外（realpath 雖回到 W 內）→ 依 D-1「兩者都通過才放行」仍 deny
blocked "$W1" "$W1/inner/../../lib/a.dart"
echo "PASS"

echo "=== AC-9: symlink 逃逸 deny ==="
blocked "$W1" "$W1/escape/a.dart"
echo "PASS"

echo "=== AC-10: 合法 symlink 放行（解析後仍在 W 內、或指向 repo 外）==="
allowed "$W1" "$W1/.agents/skills/x/SKILL.md"
allowed "$W1" "$W1/ext/x.md" Write
echo "PASS"

echo "=== AC-11: fail-closed（hook 自身錯誤 deny，且與越界訊息可區分）==="
errored() {
  [ "$CODE" -eq 2 ] || fail "hook 錯誤應 exit 2，實得 $CODE"
  [[ "$ERR" == *"[WF-FREEZE ERROR]"* ]] || fail "缺 [WF-FREEZE ERROR]：$ERR"
  [[ "$ERR" != *"[WF-FREEZE BLOCK]"* ]] || fail "錯誤訊息不得與越界混用：$ERR"
}
run "not json"; errored
run ""; errored
run "$(payload "$W1" "$R/x" | jq -c '.tool_input = "broken"')"; errored
run "$(payload "$W1" "$R/x" | jq -c 'del(.tool_input.file_path)')"; errored
# git 執行失敗：W 內 fail-closed；主 checkout 不跑 git，照常放行（fail-closed 影響面只限 worktree 內的 session）
mkdir "$TMP/badgit" && printf '#!/bin/sh\nexit 1\n' >"$TMP/badgit/git" && chmod +x "$TMP/badgit/git"
badgit() { run "$(payload "$@")"; } # run 之前先把壞 git 放到 PATH 最前面
PATH="$TMP/badgit:$PATH" badgit "$W1" "$W1/lib/a.dart"; errored
PATH="$TMP/badgit:$PATH" badgit "$R" "$R/lib/a.dart"
[ "$CODE" -eq 0 ] && [ -z "$ERR" ] || fail "主 checkout 不應依賴 git：code=$CODE err='$ERR'"
echo "PASS"

echo "ALL TESTS PASSED!"
