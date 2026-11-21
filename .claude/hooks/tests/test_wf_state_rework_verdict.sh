#!/usr/bin/env bash
set -euo pipefail

# STAGE 3 退回上限（rework_history）與三值審查裁決閘門（review_verdict）。
# 規格：docs/features/2026-11-20-stage3-rework-loop-and-verdict.md §7 AC-1～AC-12

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WF_STATE="$REPO_ROOT/.claude/skills/gen-dev-workflow/scripts/wf-state.sh"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
export WF_STATE_DIR="$TEMP_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }

# 經 init → 0b → 1 → promote → 2 → 3 建立停在 STAGE 3 的 sequence state
new_stage3() {
  local branch="$1" level="${2:-strict}" pending state
  pending="$("$WF_STATE" init --pause-level "$level")"
  "$WF_STATE" advance "$pending" 0b --confirmed >/dev/null
  "$WF_STATE" advance "$pending" 1 --confirmed >/dev/null
  state="$("$WF_STATE" promote "$pending" --branch "$branch" --dest "$TEMP_DIR")"
  "$WF_STATE" advance "$state" 2 --confirmed >/dev/null
  "$WF_STATE" advance "$state" 3 --confirmed >/dev/null
  expect "$state" '.stage' 3   # $(...) 不繼承 errexit，前置步驟失敗要在這裡顯式擋下
  echo "$state"
}

q() { "$WF_STATE" get "$1" | jq -r "$2"; }
expect() { [ "$(q "$1" "$2")" = "$3" ] || fail "$2 預期 '$3'，實得 '$(q "$1" "$2")'"; }

# must_fail <指令...>：斷言 exit≠0；輸出存入 $ERR 供 has 比對
must_fail() {
  set +e
  ERR="$("$@" 2>&1)"
  local code=$?
  set -e
  [ "$code" -ne 0 ] || fail "應失敗卻成功：$*"
}
has() { [[ "$ERR" == *"$1"* ]] || fail "輸出缺少 '$1'：$ERR"; }

# 直接改寫 state 檔（模擬舊檔／壞檔），刻意繞過 wf-state.sh
rewrite() { jq "$2" "$1" >"$1.tmp" && mv "$1.tmp" "$1"; }

echo "=== AC-9: init 初值 ==="
P="$("$WF_STATE" init)"
"$WF_STATE" get "$P" | jq -e 'has("review_verdict") and has("review_concerns")
  and .review_verdict == null and .review_concerns == null and .rework_history == []' >/dev/null \
  || fail "init 未帶三欄初值"
echo "PASS"

echo "=== AC-1/AC-2: 退回理由必填、空白理由拒絕 ==="
F="$(new_stage3 t/reason)"
for r in "" "   "; do
  must_fail "$WF_STATE" advance "$F" 2 --reason "$r"; has "--reason"
done
must_fail "$WF_STATE" advance "$F" 2; has "--reason"
expect "$F" '.stage' 3
expect "$F" '.rework_history | length' 0
echo "PASS"

echo "=== AC-3: 退回記錄理由與 UTC 時間 ==="
"$WF_STATE" advance "$F" 2 --reason "R1" >/dev/null
expect "$F" '.stage' 2
expect "$F" '.rework_history | length' 1
expect "$F" '.rework_history[0].reason' R1
"$WF_STATE" get "$F" | jq -e '.rework_history[0].at
  | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' >/dev/null \
  || fail "at 格式錯誤：$(q "$F" '.rework_history[0].at')"
echo "PASS"

echo "=== AC-5: --reason 用於退回以外的轉移；§3.2 未知參數 ==="
must_fail "$WF_STATE" advance "$F" 3 --reason x
must_fail "$WF_STATE" advance "$F" 3 --bogus
expect "$F" '.stage' 2
echo "PASS"

echo "=== AC-4: 第 3 次退回須 --confirmed（autonomous 亦然）==="
F4="$(new_stage3 t/cap autonomous)"
for r in R1 R2; do
  "$WF_STATE" advance "$F4" 2 --reason "$r" >/dev/null
  "$WF_STATE" advance "$F4" 3 >/dev/null
done
must_fail "$WF_STATE" advance "$F4" 2 --reason R3
has R1; has R2; has "--confirmed"
expect "$F4" '.rework_history | length' 2
"$WF_STATE" advance "$F4" 2 --confirmed --reason R3 >/dev/null
expect "$F4" '.rework_history | length' 3
"$WF_STATE" advance "$F4" 3 >/dev/null
must_fail "$WF_STATE" advance "$F4" 2 --reason R4
expect "$F4" '.rework_history | length' 3
echo "PASS"

echo "=== AC-6: set 白名單與 enum ==="
F6="$(new_stage3 t/set)"
for v in PASS CONCERNS FAIL; do
  "$WF_STATE" set "$F6" review_verdict="$v"
  expect "$F6" '.review_verdict' "$v"
done
must_fail "$WF_STATE" set "$F6" review_verdict=pass
must_fail "$WF_STATE" set "$F6" review_verdict=OK
must_fail "$WF_STATE" set "$F6" rework_history=x
echo "PASS"

echo "=== AC-7: 3→4 裁決閘門 ==="
F7="$(new_stage3 t/gate)"
must_fail "$WF_STATE" advance "$F7" 4 --confirmed; has "review_verdict="
"$WF_STATE" set "$F7" review_verdict=FAIL
must_fail "$WF_STATE" advance "$F7" 4 --confirmed
"$WF_STATE" set "$F7" review_verdict=PASS review_concerns=X
must_fail "$WF_STATE" advance "$F7" 4 --confirmed
"$WF_STATE" set "$F7" review_verdict=CONCERNS review_concerns=null
must_fail "$WF_STATE" advance "$F7" 4 --confirmed
"$WF_STATE" set "$F7" review_concerns="   "
must_fail "$WF_STATE" advance "$F7" 4 --confirmed
expect "$F7" '.stage' 3
"$WF_STATE" set "$F7" review_verdict=PASS review_concerns=null
"$WF_STATE" advance "$F7" 4 --confirmed >/dev/null
expect "$F7" '.stage' 4
F7c="$(new_stage3 t/gate-concerns)"
"$WF_STATE" set "$F7c" review_verdict=CONCERNS review_concerns=X
"$WF_STATE" advance "$F7c" 4 --confirmed >/dev/null
expect "$F7c" '.stage' 4
expect "$F7c" '.review_concerns' X
echo "PASS"

echo "=== AC-8: 進 3 清空裁決，歷史保留 ==="
F8="$(new_stage3 t/clear)"
"$WF_STATE" set "$F8" review_verdict=FAIL review_concerns=old
"$WF_STATE" advance "$F8" 2 --reason R1 >/dev/null
expect "$F8" '.review_verdict' FAIL
"$WF_STATE" advance "$F8" 3 >/dev/null
expect "$F8" '.review_verdict' null
expect "$F8" '.review_concerns' null
expect "$F8" '.rework_history | length' 1
echo "PASS"

echo "=== AC-10: 缺三欄的舊檔相容 ==="
OLD='del(.review_verdict, .review_concerns, .rework_history)'
F10="$(new_stage3 t/old-rework)"; rewrite "$F10" "$OLD"
"$WF_STATE" get "$F10" >/dev/null
"$WF_STATE" advance "$F10" 2 --reason R1 >/dev/null
expect "$F10" '.rework_history | length' 1
F10b="$(new_stage3 t/old-gate)"; rewrite "$F10b" "$OLD"
"$WF_STATE" set "$F10b" review_verdict=PASS
"$WF_STATE" advance "$F10b" 4 --confirmed >/dev/null
expect "$F10b" '.stage' 4
echo "PASS"

echo "=== AC-11: 壞值校驗擋下 ==="
F11="$(new_stage3 t/bad-verdict)"; rewrite "$F11" '.review_verdict = "MAYBE"'
must_fail "$WF_STATE" get "$F11"
F11b="$(new_stage3 t/bad-history)"; rewrite "$F11b" '.rework_history = [{"at": "2026-11-20T00:00:00Z"}]'
must_fail "$WF_STATE" get "$F11b"
echo "PASS"

echo "=== AC-12: jump——退回規則適用、3→4 閘門不適用 ==="
J="$("$WF_STATE" init --mode jump --stage 3 --branch t/jump-publish)"
"$WF_STATE" advance "$J" 4 >/dev/null
expect "$J" '.stage' 4
J4="$("$WF_STATE" init --mode jump --stage 4 --branch t/jump-direct)"
expect "$J4" '.stage' 4
J2="$("$WF_STATE" init --mode jump --stage 3 --branch t/jump-rework)"
must_fail "$WF_STATE" advance "$J2" 2; has "--reason"
"$WF_STATE" set "$J2" review_verdict=FAIL
"$WF_STATE" advance "$J2" 2 --reason R1 >/dev/null
expect "$J2" '.rework_history | length' 1
"$WF_STATE" advance "$J2" 3 >/dev/null
expect "$J2" '.review_verdict' null
"$WF_STATE" advance "$J2" 2 --reason R2 >/dev/null
"$WF_STATE" advance "$J2" 3 >/dev/null
must_fail "$WF_STATE" advance "$J2" 2 --reason R3; has "--confirmed"
expect "$J2" '.rework_history | length' 2
echo "PASS"

echo "=== strict：stage-done 3 後 advance 須 --confirmed ==="
S="$(new_stage3 t/strict-confirm)"
"$WF_STATE" set "$S" review_verdict=PASS
"$WF_STATE" stage-done "$S" 3 >/dev/null
must_fail "$WF_STATE" advance "$S" 4; has "--confirmed"
"$WF_STATE" advance "$S" 4 --confirmed >/dev/null
expect "$S" '.stage' 4
echo "PASS"

echo "ALL TESTS PASSED!"
