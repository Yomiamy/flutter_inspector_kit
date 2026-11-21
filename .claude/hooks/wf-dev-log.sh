#!/bin/bash
# PostToolUse / PostToolUseFailure(Bash) hook：subagent Bash 側錄 dev log
# 規格：docs/features/2026-11-21-subagent-dev-log.md
#
# 只記「subagent（payload 帶 agent_id）且 cwd 位於 linked worktree」的 Bash，
# 一筆一列 JSONL 追加到 <worktree>/.claude/workflow-state/dev-log.jsonl，供 STAGE 2 verifier 對照。
#
# fail-open：解析失敗、非 subagent、非 linked worktree → 靜默 exit 0。
# 只有寫入失敗才 stderr 告警並 exit 1（non-blocking：使用者在 transcript 看得到 hook error，
# 被稽核的 subagent 看不到）。絕不 exit 2——PostToolUse 的 exit 2 會把 stderr 餵給 subagent。
#
# 掛載於 .claude/settings.json 的 PostToolUse 與 PostToolUseFailure（matcher: Bash）；
# 失敗的 Bash 只觸發 PostToolUseFailure，兩者缺一就漏記。條目由 tests/test_project_settings_hooks.sh 鎖定。

umask 077 # log 含指令與輸出尾段，與 state 檔同為 0600
input=$(cat) || exit 0

# 輸出 >30KB 時 tool_response.stdout 只留前段、全文落在 persistedOutputPath；尾段改從該檔取
persisted=$(jq -r '.tool_response.persistedOutputPath // empty | strings' <<<"$input" 2>/dev/null)
full=""
[ -n "$persisted" ] && [ -r "$persisted" ] && full=$(tail -c 8192 "$persisted" 2>/dev/null)

# 截斷以字元（codepoint）計，jq 字串切片保證不切斷多位元組字元。
# 失敗事件的 exit code 只信 error 首行 `Exit code N`；解析不到（或荒謬的 0）記 null，絕不記 0。
line=$(jq -c --arg full "$full" '
  select((.agent_id // "") != "" and (.cwd | type) == "string" and (.tool_input.command | type) == "string")
  | (.hook_event_name != "PostToolUse") as $failed
  | (if $failed then (.error // "" | tostring)
     elif $full != "" then $full
     else [.tool_response | objects | (.stdout, .stderr) | strings | select(. != "")] | join("\n")
     end) as $out
  | {ts: (now | todate),
     agent_type: (.agent_type // null),
     agent_id,
     cwd,
     command: .tool_input.command[:1000],
     exit_code: (if $failed
                 then (($out | split("\n")[0]) // "" | capture("^Exit code (?<n>[0-9]+)$").n | tonumber | select(. != 0)) // null
                 else 0 end),
     background: (.tool_input.run_in_background == true),
     output_tail: $out[-2000:]}
' <<<"$input" 2>/dev/null) || exit 0
[ -n "$line" ] || exit 0

cwd=$(jq -r '.cwd' <<<"$line") || exit 0
paths=$(git -C "$cwd" rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel 2>/dev/null) || exit 0
{ IFS= read -r git_dir; IFS= read -r common_dir; IFS= read -r top; } <<<"$paths"
[ "$git_dir" != "$common_dir" ] || exit 0 # 主 repo：沒有稽核落點

log="$top/.claude/workflow-state/dev-log.jsonl"
# 單次 write(2)：bash printf（>1KB）與 jq 直接 >>（>4KB）都會被 stdio 拆成多次 write，並行時列會交錯
mkdir -p "${log%/*}" 2>/dev/null &&
  perl -e 'my $s = "$ARGV[1]\n"; open(my $f, ">>", $ARGV[0]) or exit 1; (syswrite($f, $s) // -1) == length($s) or exit 1' \
    "$log" "$line" 2>/dev/null ||
  { echo "[WF-DEVLOG WARN] dev log 寫入失敗：$log" >&2; exit 1; }
exit 0
