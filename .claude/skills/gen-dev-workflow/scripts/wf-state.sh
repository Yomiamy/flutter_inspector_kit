#!/usr/bin/env bash
# wf-state.sh — gen-dev-workflow 的 state machine。
# 所有 workflow state 檔的讀寫都必須經過這支腳本；guard 在程式裡，不在文件裡：
#   1. schema 校驗 + 原子寫入（tmp + mv），手寫/半寫壞檔進不了磁碟
#   2. sequence 模式的 stage 轉移合法性檢查（非法跳段直接 exit 1）
#   3. 暫停點棘輪：stage-done / task-done 之後 awaiting_confirmation=true，
#      未帶 --confirmed 的 advance 一律拒絕——跳過暫停點需要「明示旗標」這個蓄意動作
set -euo pipefail

STATE_DIR="${WF_STATE_DIR:-.claude/workflow-state}"
SCHEMA_VERSION=1

die() { echo "wf-state: $*" >&2; exit 1; }
command -v jq >/dev/null || die "需要 jq"

usage() {
  cat <<'EOF'
用法：
  wf-state.sh init [--mode sequence|jump|quick] [--stage <S>] [--branch <branch>] [--set k=v ...]
      建新 state。無 --branch → .pending-<wf-id>.json；有 --branch → <branch-slug>.json
  wf-state.sh promote <pending-檔> --branch <branch> [--dest <state-dir>]
      pending → <branch-slug>.json（STAGE 1 建好 worktree 後，--dest 指向新 worktree 的 state dir）
  wf-state.sh get <檔>                    校驗後輸出 JSON
  wf-state.sh set <檔> k=v [k=v ...]      更新欄位（不可改 stage/awaiting_confirmation）
  wf-state.sh stage-done <檔> <stage>     標記 stage 完成，進入等待使用者確認
  wf-state.sh task-done <檔> <n>          STAGE 2 任務完成（記入 completed_tasks，進入等待確認）
  wf-state.sh confirm <檔>                使用者已確認（清除等待旗標，stage 不變）
  wf-state.sh advance <檔> <next> --confirmed
      推進 stage。等待確認中且未帶 --confirmed → 拒絕；sequence 模式非法轉移 → 拒絕
  wf-state.sh upgrade <檔>
      quick 升級為完整流程（mode→sequence、stage→2），單向：其他 mode 一律拒絕
<檔> 可為路徑，或相對 $STATE_DIR 的檔名。
EOF
  exit 1
}

resolve() { case "$1" in */*) echo "$1" ;; *) echo "$STATE_DIR/$1" ;; esac; }

validate() {
  jq -e '
    (.schema_version | type == "number") and
    (.workflow_id | type == "string") and
    (.stage | type == "string") and
    (.mode | IN("sequence", "jump", "quick")) and
    (.completed_tasks | type == "array") and
    (.awaiting_confirmation | type == "boolean")
  ' "$1" >/dev/null 2>&1 || die "state 檔校驗失敗：$1"
}

# atomic_write <目標檔>  （stdin 收 JSON）
atomic_write() {
  local f="$1" tmp
  mkdir -p "$(dirname "$f")"
  tmp="$(mktemp "$(dirname "$f")/.wf-tmp.XXXXXX")"
  jq . >"$tmp" || { rm -f "$tmp"; die "非法 JSON，寫入中止"; }
  ( validate "$tmp" ) || { rm -f "$tmp"; exit 1; }   # 子 shell 隔離 validate 的 die，確保 tmp 必被清掉
  mv "$tmp" "$f"
}

# jq 值解析：null / 數字 / 布林原樣，其餘當字串
jq_val() {
  case "$1" in
    null|true|false) echo "$1" ;;
    ''|*[!0-9]*) jq -n --arg v "$1" '$v' ;;
    *) echo "$1" ;;
  esac
}

slugify() { echo "${1//\//-}"; }

legal_transition() {
  case "$1->$2" in
    "0a->0b"|"0b->1"|"1->2"|"2->3"|"3->4"|"3->2"|"4->done") return 0 ;;
    *) return 1 ;;
  esac
}

apply_sets() { # $1=json, 之後 k=v...；回傳更新後 json
  local json="$1"; shift
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      spec|plan|branch|issue|pr|total_tasks|interrupted_by) ;;
      *) die "不可透過 set 修改欄位：${k}（stage 用 advance、確認用 confirm）" ;;
    esac
    json="$(echo "$json" | jq --arg k "$k" --argjson v "$(jq_val "$v")" '.[$k] = $v')"
  done
  echo "$json"
}

cmd="${1:-}"; shift || usage

case "$cmd" in
  init)
    mode="sequence"; stage="0a"; branch=""; sets=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --mode) mode="$2"; shift 2 ;;
        --stage) stage="$2"; shift 2 ;;
        --branch) branch="$2"; shift 2 ;;
        --set) sets+=("$2"); shift 2 ;;
        *) die "init：未知參數 $1" ;;
      esac
    done
    wf_id="wf-$(date +%s)-$(head -c2 /dev/urandom | xxd -p)"
    if [ -n "$branch" ]; then
      f="$STATE_DIR/$(slugify "$branch").json"
    else
      f="$STATE_DIR/.pending-$wf_id.json"
    fi
    [ -e "$f" ] && die "已存在：${f}（不覆蓋既有流程）"
    json="$(jq -n \
      --argjson sv "$SCHEMA_VERSION" --arg id "$wf_id" --arg st "$stage" --arg m "$mode" \
      --argjson br "$( [ -n "$branch" ] && jq -n --arg b "$branch" '$b' || echo null )" \
      '{schema_version:$sv, workflow_id:$id, stage:$st, mode:$m, spec:null, plan:null,
        branch:$br, issue:null, pr:null, completed_tasks:[], total_tasks:null,
        interrupted_by:null, awaiting_confirmation:false}')"
    [ ${#sets[@]} -gt 0 ] && json="$(apply_sets "$json" "${sets[@]}")"
    echo "$json" | atomic_write "$f"
    echo "$f"
    ;;

  promote)
    src="$(resolve "$1")"; shift
    branch=""; dest="$STATE_DIR"
    while [ $# -gt 0 ]; do
      case "$1" in
        --branch) branch="$2"; shift 2 ;;
        --dest) dest="$2"; shift 2 ;;
        *) die "promote：未知參數 $1" ;;
      esac
    done
    [ -n "$branch" ] || die "promote 需要 --branch"
    validate "$src"
    f="$dest/$(slugify "$branch").json"
    [ -e "$f" ] && die "已存在：$f"
    jq --arg b "$branch" '.branch = $b' "$src" | atomic_write "$f"
    rm "$src"
    echo "$f"
    ;;

  get)
    f="$(resolve "$1")"; validate "$f"; cat "$f"
    ;;

  set)
    f="$(resolve "$1")"; shift
    validate "$f"
    json="$(apply_sets "$(cat "$f")" "$@")"   # 先算後寫：apply_sets die 時整個中止，不會建 tmp
    echo "$json" | atomic_write "$f"
    ;;

  stage-done)
    f="$(resolve "$1")"; stage="$2"
    validate "$f"
    jq --arg s "$stage" '.stage = $s | .awaiting_confirmation = true' "$f" | atomic_write "$f"
    echo "stage $stage 完成 → 等待使用者確認（confirm 或 advance --confirmed 才能繼續）"
    ;;

  task-done)
    f="$(resolve "$1")"; n="$2"
    validate "$f"
    jq --argjson n "$n" \
      '.completed_tasks = ((.completed_tasks + [$n]) | unique) | .awaiting_confirmation = true' \
      "$f" | atomic_write "$f"
    echo "任務 $n 完成 → 等待使用者確認"
    ;;

  confirm)
    f="$(resolve "$1")"
    validate "$f"
    jq '.awaiting_confirmation = false' "$f" | atomic_write "$f"
    ;;

  upgrade)
    f="$(resolve "$1")"
    validate "$f"
    mode="$(jq -r '.mode' "$f")"
    [ "$mode" = "quick" ] || die "只允許 quick → sequence 升級（目前 mode：${mode}）"
    jq '.mode = "sequence" | .stage = "2" | .awaiting_confirmation = false' "$f" | atomic_write "$f"
    echo "quick → sequence，從 STAGE 2 接續"
    ;;

  advance)
    f="$(resolve "$1")"; next="$2"; shift 2
    confirmed=false
    [ "${1:-}" = "--confirmed" ] && confirmed=true
    validate "$f"
    cur="$(jq -r '.stage' "$f")"; mode="$(jq -r '.mode' "$f")"
    awaiting="$(jq -r '.awaiting_confirmation' "$f")"
    if [ "$awaiting" = "true" ] && [ "$confirmed" != "true" ]; then
      die "stage $cur 等待使用者確認中。先在對話中暫停詢問，獲確認後帶 --confirmed 重跑"
    fi
    if [ "$mode" = "sequence" ] && ! legal_transition "$cur" "$next"; then
      die "非法 stage 轉移：$cur -> ${next}（sequence 模式合法路徑：0a→0b→1→2→3→4、3→2、4→done）"
    fi
    jq --arg s "$next" '.stage = $s | .awaiting_confirmation = false | .interrupted_by = null' \
      "$f" | atomic_write "$f"
    echo "→ stage $next"
    ;;

  *) usage ;;
esac
