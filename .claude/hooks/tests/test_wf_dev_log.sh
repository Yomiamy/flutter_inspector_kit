#!/usr/bin/env bash
set -euo pipefail

# subagent Bash 側錄 dev log（wf-dev-log.sh）。
# 規格：docs/features/2026-11-21-subagent-dev-log.md §7 AC-1～AC-10
# payload 形狀依官方 hooks 文件（PostToolUse 的 Bash tool_response、PostToolUseFailure 的 error 首行 `Exit code N`）。

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/wf-dev-log.sh"

TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# fixture：主 repo + linked worktree + 非 git 目錄。-c 隔離個人 git 設定（簽章、全域 hooks）
MAIN="$TMP/main"; WT="$TMP/wt"; WT2="$TMP/wt2"; PLAIN="$TMP/plain"
G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null)
"${G[@]}" init -q "$MAIN"
"${G[@]}" -C "$MAIN" commit -q --allow-empty -m init
"${G[@]}" -C "$MAIN" worktree add -q -b wt "$WT"
"${G[@]}" -C "$MAIN" worktree add -q -b wt2 "$WT2"
mkdir "$PLAIN"
DIR="$WT/.claude/workflow-state"
LOG="$DIR/dev-log.jsonl"

# payload <event> <cwd>：subagent 的基準 payload；變體由呼叫端再接 `| jq -c '<改寫>'`
payload() {
  jq -nc --arg e "$1" --arg cwd "$2" '{
      session_id: "s", hook_event_name: $e, cwd: $cwd,
      agent_id: "agent-abc", agent_type: "implementer",
      tool_name: "Bash", tool_input: {command: "flutter test", run_in_background: false},
      tool_use_id: "toolu_1"}
    | if $e == "PostToolUse"
      then .tool_response = {stdout: "All tests passed!", stderr: "", interrupted: false, isImage: false}
      else .error = "Exit code 3\nSome tests failed." end'
}

# run <stdin>：執行 hook，結果存入 OUT / ERR / CODE
run() {
  set +e
  OUT="$(printf '%s' "$1" | "$HOOK" 2>"$TMP/err")"
  CODE=$?
  set -e
  ERR="$(cat "$TMP/err")"
}
quiet() {
  [ "$CODE" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] \
    || fail "預期 exit 0 且無輸出，實得 code=$CODE out='$OUT' err='$ERR'"
}
lines() { if [ -f "$LOG" ]; then wc -l <"$LOG" | tr -d ' '; else echo 0; fi; }
expect_lines() { [ "$(lines)" = "$1" ] || fail "預期 $1 列，實得 $(lines)"; }
last_is() { tail -n 1 "$LOG" | jq -e "$@" >/dev/null || fail "最後一列不符 $*：$(tail -n 1 "$LOG")"; }

echo "=== AC-3: 主對話（無 agent_id）不記，含 --agent session（只有 agent_type）==="
run "$(payload PostToolUse "$WT" | jq -c 'del(.agent_id, .agent_type)')"; quiet
run "$(payload PostToolUse "$WT" | jq -c 'del(.agent_id)')"; quiet
[ ! -e "$DIR" ] || fail "主對話不應建立 $DIR"
echo "PASS"

echo "=== AC-4: 主 repo、非 git 目錄、不存在的 cwd 不記 ==="
run "$(payload PostToolUse "$MAIN")"; quiet
[ ! -e "$MAIN/.claude" ] || fail "主 repo 不應建立 .claude/"
run "$(payload PostToolUse "$PLAIN")"; quiet
[ -z "$(ls -A "$PLAIN")" ] || fail "非 git 目錄不應被寫入"
run "$(payload PostToolUse "$TMP/nope")"; quiet
echo "PASS"

echo "=== AC-1: 成功指令記錄（目錄不存在時由 hook 建立）==="
run "$(payload PostToolUse "$WT")"; quiet
expect_lines 1
last_is --arg cwd "$WT" '(keys == ["agent_id","agent_type","background","command","cwd","exit_code","output_tail","ts"])
  and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  and .agent_type == "implementer" and .agent_id == "agent-abc" and .cwd == $cwd
  and .command == "flutter test" and .exit_code == 0 and .background == false
  and .output_tail == "All tests passed!"'
touch "$DIR/fixture.json" # AC-10 用：state 檔 glob 基準
echo "PASS"

echo "=== AC-2: 失敗指令記錄（PostToolUseFailure），exit code 取不到時為 null 而非 0 ==="
run "$(payload PostToolUseFailure "$WT")"; quiet
expect_lines 2
last_is '.exit_code == 3 and (.output_tail | endswith("Some tests failed."))'
run "$(payload PostToolUseFailure "$WT" | jq -c '.error = "spawn failed"')"; quiet
expect_lines 3
last_is '.exit_code == null and .output_tail == "spawn failed"'
run "$(payload PostToolUseFailure "$WT" | jq -c '.error = "Exit code 0"')"; quiet
expect_lines 4
last_is '.exit_code == null'
run "$(payload PostToolUseFailure "$WT" | jq -c 'del(.error)')"; quiet
expect_lines 5
last_is '.exit_code == null'
run "$(payload PostToolUse "$WT" | jq -c 'del(.hook_event_name)')"; quiet
expect_lines 6
last_is '.exit_code == null'
echo "PASS"

echo "=== AC-5: 背景執行標記 ==="
run "$(payload PostToolUse "$WT" | jq -c '.tool_input.run_in_background = true')"; quiet
last_is '.background == true'
echo "PASS"

echo "=== AC-6: 以字元截斷（output_tail 取尾 2000、command 取頭 1000），結果為合法 UTF-8 ==="
BIG="$(printf '中😀%.0s' $(seq 1 1500))" # 3000 字元，多位元組
CMD="$(printf 'x%.0s' $(seq 1 1500))"
run "$(payload PostToolUse "$WT" | jq -c --arg b "$BIG" --arg c "$CMD" '.tool_response.stdout = $b | .tool_input.command = $c')"; quiet
last_is --arg b "$BIG" --arg c "$CMD" '.output_tail == $b[-2000:] and (.output_tail | length) == 2000
  and .command == $c[:1000] and (.command | length) == 1000'
run "$(payload PostToolUse "$WT" | jq -c --arg b "$BIG" '.tool_response.stdout = $b | .tool_response.stderr = "尾巴"')"; quiet
last_is '(.output_tail | length) == 2000 and (.output_tail | endswith("\n尾巴"))'
printf '%s\n' "$BIG" "00:19 +1005: All tests passed!" >"$TMP/persisted.txt"
run "$(payload PostToolUse "$WT" | jq -c --arg p "$TMP/persisted.txt" '.tool_response.stdout = "00:05 +134: head only" | .tool_response.persistedOutputPath = $p')"; quiet
last_is '.output_tail | endswith("All tests passed!") and (contains("head only") | not)'
iconv -f UTF-8 -t UTF-8 "$LOG" >/dev/null || fail "log 不是合法 UTF-8"
echo "PASS"

echo "=== AC-7: append-only（既有位元組不變）==="
cp "$LOG" "$TMP/before"
before_lines="$(lines)"
run "$(payload PostToolUse "$WT")"; quiet
expect_lines $((before_lines + 1))
head -c "$(wc -c <"$TMP/before")" "$LOG" | cmp -s - "$TMP/before" || fail "既有內容被改寫"
echo "PASS"

echo "=== AC-8: 並行寫入不交錯（單筆 > 4KB，可抓出 stdio 分段寫入）==="
before_lines="$(lines)"
EMOJI="$(printf '😀%.0s' $(seq 1 2000))" # 截斷後仍約 8KB，逼出 stdio 的多次 write
P8="$(payload PostToolUse "$WT" | jq -c --arg b "$EMOJI" '.tool_response.stdout = $b')"
N=50; ROUNDS=4 # 交錯屬機率事件，多輪提高檢出率
for _ in $(seq 1 "$ROUNDS"); do
  for _ in $(seq 1 "$N"); do printf '%s' "$P8" | "$HOOK" & done
  wait
done
expect_lines $((before_lines + N * ROUNDS))
jq -Rn '[inputs | fromjson] | length' "$LOG" >/dev/null || fail "有列不是合法 JSON（並行交錯）"
echo "PASS"

echo "=== AC-9: fail-open ==="
run ""; quiet
run "not json"; quiet
# warned：寫入失敗須 exit 1（non-blocking，絕不 2）、stderr 告警、stdout 乾淨
warned() {
  [ "$CODE" -eq 1 ] || fail "寫入失敗應 exit 1，實得 $CODE"
  [[ "$ERR" == *"[WF-DEVLOG WARN]"* ]] || fail "stderr 缺告警：$ERR"
  [ -z "$OUT" ] || fail "stdout 應為空：$OUT"
}
before_lines="$(lines)"
chmod 444 "$LOG" # 既有 log 不可追加（對目錄 chmod 555 擋不住追加既有檔）
run "$(payload PostToolUse "$WT")"
chmod 644 "$LOG"
warned
expect_lines "$before_lines"
mkdir "$WT2/.claude" && chmod 555 "$WT2/.claude" # workflow-state/ 建不出來
run "$(payload PostToolUse "$WT2")"
warned
echo "PASS"

echo "=== AC-10: 位置、ignore 規則、*.json glob 不受影響 ==="
[[ "$LOG" != *.json ]] || fail "log 檔名不得以 .json 結尾"
git -C "$REPO_ROOT" -c core.excludesFile=/dev/null check-ignore -q --no-index -- .claude/workflow-state/dev-log.jsonl \
  || fail ".claude/workflow-state/dev-log.jsonl 未被 repo 規則忽略"
[ "$(cd "$DIR" && echo *.json)" = "fixture.json" ] || fail "*.json glob 結果改變：$(cd "$DIR" && echo *.json)"
echo "PASS"

echo "ALL TESTS PASSED!"
