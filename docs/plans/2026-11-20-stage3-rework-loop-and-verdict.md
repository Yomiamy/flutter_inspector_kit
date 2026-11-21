# STAGE 3 退回迴圈上限與三值審查裁決 — 實作計畫

> **規格**：[`docs/features/2026-11-20-stage3-rework-loop-and-verdict.md`](../features/2026-11-20-stage3-rework-loop-and-verdict.md)
> **日期**：2026-11-20 ｜ **模式**：Sequence ｜ **預估 Effort**：中低（核心是一支 bash 腳本 ~60 行增量 + 一支新測試；其餘為文件同步）
> **不涉及 Dart 程式碼**：`lib/`、`test/` 零改動，不需跑 `flutter test` / `flutter analyze`。
> **修訂（0b 初審 REVISE）**：退回規則改為不分模式（§2.1）；publisher 只在建立新 PR 時（STAGE 4 或 quick 步驟④）讀裁決；quick 模式補裁決寫入；並行驗收改為對 `<base>` 比對本任務路徑、不受 commit 時機影響（§6）；jump 的退回上限明載為軟約束。規格 §3.3／§3.4／§3.6／D5／§5／§6／AC-12／§8 同步修訂。

---

## 1. 核心判斷

【核心判斷】✅ 值得做：`3→2→3` 目前在 `balanced`／`autonomous` 下完全沒有人類視線，且二值裁決逼出假 PASS。兩個缺陷都能用「state 多三個欄位 + `advance` 多兩道檢查」機械性解決，不需要任何推論。

【關鍵洞察】
- **資料結構**：三個頂層欄位（`review_verdict`、`review_concerns`、`rework_history`），各自只有一個寫入者。計數直接取 `rework_history | length`，沒有第二份計數器，所以不存在「計數與歷史不一致」這種特殊情況。
- **可消滅的複雜度**：3→4 閘門的六種組合收斂成一條不變式「放行 ⇔ `(verdict, concerns 非空)` ∈ `{(PASS,false), (CONCERNS,true)}`」，實作上是一個 `case "$v:$c"`，不寫巢狀 if。退回上限不新增覆寫旗標，直接沿用 `--confirmed`。
- **最大破壞風險**：`advance` 從「位置參數只認 `$3 == --confirmed`」改成旗標迴圈，未知參數改為 `die`。repo 內所有呼叫點已實查只帶 `--confirmed`（見 §8 R1），既有測試唯一受影響的是 `test_wf_state_done_reentry.sh` 的 3→4；行為面另有進行中的 jump state 在 stage 3 退回改為必須帶 `--reason`（§2.1）。

---

## 2. 實作方向與 Trade-off

| 方向 | 作法 | 優點 | 缺點 | 結論 |
|:---|:---|:---|:---|:---|
| **A. `advance` 內聯檢查 + 兩個短函式**（採用） | `advance` 解析 `--reason`；`check_rework` 管 3→2、`check_verdict` 管 3→4；寫入時以同一個 `jq` filter 清空裁決／追加歷史 | 所有 stage 轉移的守衛仍集中在 `advance` 一處；一次原子寫入；與既有 `total_tasks` 閘門同構 | `advance` 分支變長（但每個新判斷都抽成 ≤10 行函式） | ✅ |
| B. 新子指令 `rework <檔> --reason` / `verdict <檔> <V> [--concern]` | 退回與裁決各有專屬入口 | 參數語意更明確 | `advance <檔> 2` 本身仍必須擋（否則直接繞過），等於同一條規則寫兩處；規格 D4 已否決陣列化 concerns | ❌ |
| C. 上限做在 `should_pause` / `stage-done 3` | history ≥2 時讓 `stage-done 3` 強制 awaiting | 重用既有暫停機制 | 主對話略過 `stage-done` 直接 `advance` 即繞過；且會連 3→4 一起擋（規格 D2 已否決） | ❌ |

細節取捨：
- **`--reason` 存原文不 trim**：只在判空時去空白（`${2//[[:space:]]/}`），存入的字串保持原樣，少一次轉換。
- **呼叫 `check_rework` 用 `if … fi` 而非 `[ … ] && check_rework`**：bash 在 `&&` 串列中呼叫的函式內部會停用 `errexit`，用 `if` 本體呼叫才保持 `set -e` 語意。
- **時間戳**：`date -u +%Y-%m-%dT%H:%M:%SZ`，BSD / GNU `date` 皆支援，以 `--arg at` 傳進 `jq`。

### 2.1 規則的模式適用範圍（0b 初審裁決）

| 規則 | sequence | jump | quick | 理由 |
|:---|:-:|:-:|:-:|:---|
| 3→2 退回須 `--reason`、記入 `rework_history` | ✅ | ✅ | ✅（實務上不命中） | 退回邊在 jump 同樣存在、同樣會打轉；判定只看 `cur`/`next`，不依賴轉移表，套用不需任何模式特例。原案限 sequence，導致 jump 帶 `--reason` 被拒、cheatsheet 須寫模式註腳——那是補丁，刪掉 |
| 退回上限（history ≥ 2 須 `--confirmed`） | ✅ 完整強制 | ✅ 軟約束 | ✅ 軟約束 | 與理由同一條邊、同一份歷史；jump 記歷史卻不設上限，等於同一欄位兩種語意。舊 jump state 無歷史、從 0 起算，前兩次不受影響。**強制力只在 sequence 完整成立**：jump/quick 的 `stage-done` 可直接改 stage 標籤、且無轉移表可走 `3→4→2`，都繞得過 `3→2` 這條邊——jump 下的價值是理由留痕與正常路徑上的提醒，不是防繞過 |
| `--reason` 用於非退回轉移 → `die` | ✅ | ✅ | ✅ | 規則自然不分模式 |
| 進入 3 清空裁決 | ✅ | ✅ | ✅ | 規格 §3.5 原本就不分模式 |
| 3→4 裁決閘門 | ✅ | ❌ | ❌ | jump 可 `init --stage 4` 或從任意 stage 直接 `advance 4`，只擋 3→4 形同虛設；硬套會破壞「jump state 停在 3 直接 `advance 4`」的既有路徑（`/gen-dev-workflow code-review` 後接發布）。jump 仍照 SKILL.md 寫入裁決供 publisher 使用，只是不強制 |

quick 的 stage 是自由標籤（`init --mode quick` 預設 `0a`，之後以 `stage-done` 打標籤、不走 `advance` 迴圈），快掃不通過時由主對話修正後重掃，不經過 `3→2`。

---

## 3. 資料結構與資料流

### 3.1 欄位（schema_version 維持 1）

| 欄位 | 型別 | `init` 初值 | 寫入者 | 讀取者 |
|:---|:---|:---|:---|:---|
| `review_verdict` | `null` \| `"PASS"` \| `"CONCERNS"` \| `"FAIL"` | `null` | `set`（enum 校驗）；任何 `advance … 3` 清空 | `check_verdict`、publisher |
| `review_concerns` | `null` \| string | `null` | `set`；任何 `advance … 3` 清空 | `check_verdict`、publisher |
| `rework_history` | `[{reason: string, at: string}]` | `[]` | **僅** `advance` 的 `3→2` 追加（所有模式） | `check_rework`、續接 session、`/retro` |

舊檔缺席三欄：`validate` 以「`== null` 或型別正確」判定（jq 中缺席鍵即 `null`），與 `total_tasks` / `pause_level` 同構；`check_rework` 用 `.rework_history // []`、`check_verdict` 用 `.review_concerns // ""`。

### 3.2 `advance` 檢查順序（全部在寫入前，任一 `die` 即 state 不變）

```text
解析旗標（--confirmed / --reason <s> / 其他 → die）
  → validate
  → awaiting 棘輪（既有）
  → sequence 轉移合法性（既有）
  → rework = (cur==3 && next==2)                    ← 不分模式（§2.1）
  → --reason 但非 rework → die
  → rework → check_rework：理由空白 → die；history ≥ REWORK_CAP(2) 且無 --confirmed → die（列歷史）
  → sequence && cur==3 && next==4 → check_verdict  ← 僅 sequence（§2.1）
  → next==3 && sequence → total_tasks 閘門（既有）
  → 單次 jq 寫入：stage／awaiting／interrupted_by（既有）
                  + next==3 時清空 verdict/concerns（所有模式）
                  + rework 時追加 {reason, at}
```

### 3.3 主對話在 STAGE 3 的資料流

```text
reviewer 報告首行 REVIEW: <V>
  → set <檔> review_verdict=<V> [review_concerns="<未結案項>"]   （CONCERNS 同一次 set）
  → stage-done <檔> 3
  ├─ PASS / CONCERNS → advance <檔> 4                            （check_verdict 放行）
  └─ FAIL / 使用者要求修正 → advance <檔> 2 --reason "<摘要>"     （history < 2 自動）
       └─ history ≥ 2 → 腳本拒絕並列歷史 → ⏸ 使用者擇一：
            再修 → advance <檔> 2 --reason "<摘要>" --confirmed
            留案 → set review_verdict=CONCERNS review_concerns="…" → advance <檔> 4
            放棄 → state-machine.md 刪檔規則（批次則 batch-fail）
publisher（僅建立新 PR 時：STAGE 4 或 quick 步驟④）→ state 檔存在才 wf-state.sh get → CONCERNS 時 PR 描述附「未結案項」區段
  （無 state 檔 → 視為無裁決照常發布；校驗失敗 → 停下回報；STAGE 5 不依 state 增刪該區段）
```

---

## 4. 開放問題裁決（規格 §9）

| # | 問題 | 裁決 |
|:-:|:---|:---|
| 1 | 主對話把 `FAIL` 改判 `CONCERNS` 是否需額外確認 | **本次不做**。`set` 不加 `--confirmed`；覆寫一律以書面 `review_concerns` 留案並帶進 PR（信任模型同 `task-done` / `total_tasks`） |
| 2 | reviewer「建議精簡」是否自動構成 `CONCERNS` | **不自動**。由 reviewer 判斷是否值得進 PR 留案；寫進 `reviewer.md` / `reviewer.yaml` |
| 3 | reviewer 首行格式 | 定為 **`REVIEW: PASS` / `REVIEW: CONCERNS` / `REVIEW: FAIL`**，前綴與 verifier 的 `PASS` / `FAIL: CODE` / `FAIL: INFRA` 可區分 |
| 4 | `review_concerns` 為純數字時被校驗擋下 | **本次不處理，列為已知限制**（失敗而非靜默；寫進 `state-machine.md`） |

---

## 5. 檔案異動清單

| # | 檔案 | 動作 | 任務 |
|:-:|:---|:---|:-:|
| 1 | `.claude/skills/gen-dev-workflow/scripts/wf-state.sh` | 修改：常數、`usage()`、`validate`、`apply_sets`、兩個新函式、`init` 初值、`advance` | T1 |
| 2 | `.claude/hooks/tests/test_wf_state_rework_verdict.sh` | 新增（mode 100755），覆蓋 AC-1～AC-12 | T1 |
| 3 | `.claude/hooks/tests/test_wf_state_done_reentry.sh` | 修改：`new_done_state` 於 `advance 4` 前 `set review_verdict=PASS` | T1 |
| 4 | `.claude/agents/reviewer.md` | 修改：首行裁決格式、三值判定、未結案項區段、不寫 state、完成條件 | T2 |
| 5 | `.agents/agents/reviewer.yaml` | 修改：同步 #4 的新增段落與完成條件（鏡像定義，已實查存在） | T2 |
| 6 | `.claude/agents/publisher.md` | 修改：建立新 PR 時（STAGE 4 / quick ④）讀裁決（無 state 檔照常、校驗失敗才停）；`CONCERNS` 必附未結案項區段；STAGE 5 不依 state 增刪 | T2 |
| 7 | `.agents/agents/publisher.yaml` | 修改：同步 #6（鏡像定義，已實查存在） | T2 |
| 8 | `.claude/skills/gen-dev-workflow/SKILL.md` | 修改：STAGE 3 流程圖、暫停點表、不應暫停清單、暫停粒度例外 | T3 |
| 9 | `.claude/skills/gen-dev-workflow/references/state-machine.md` | 修改：guard 說明、指令表、JSON 範例與欄位說明、已知限制 | T3 |
| 10 | `.claude/skills/gen-dev-workflow/references/command-cheatsheet.md` | 修改：第 31、50 行退回指令 | T3 |
| 11 | `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改：第 157 行補上限規則 | T3 |
| 12 | `.claude/skills/gen-dev-workflow/references/execution-modes.md` | 修改：quick 步驟③（第 25–26 行）補 `CONCERNS` 裁決寫入；第 105 行批次失敗條件（原文「STAGE 3 審查連續退回 → `batch-fail`」與新行為「第 3 次退回停下問使用者」矛盾）。規格 §8 已同步補列 | T3 |

不需改：`.agents/skills` 為指向 `.claude/skills` 的 symlink，skill 文件無鏡像；`wf-guard-stage-check.sh` 只看 `stage`；`workflow-parallel.md:107`「退回 STAGE 2 的條件與層級不變」仍成立。

---

## 6. 任務拆分

| 任務 | 寫入路徑 | 建議 model tier | 可否並行 |
|:---|:---|:---|:---|
| T1 腳本 + 測試 | #1～#3 | 標準 | 🟢 與 T2、T3 寫入路徑不重疊 |
| T2 agent 定義 | #4～#7 | 快/便宜 | 🟢 |
| T3 workflow 文件 | #8～#12 | 標準（SKILL.md 流程圖需對齊框線） | 🟢 |

三個任務寫入路徑完全不重疊，文件內容已在本計畫定稿、不依賴 T1 的實作細節（文件不引用錯誤訊息原文），**可同批並行**。`total_tasks=3`。

**並行驗收規則**（三任務共用同一 worktree；implementer 依 `implementer.md` 先 commit 才交 verifier，故**不可用 `git status` 判定**——已 commit 的變更不會出現在 status）：

```bash
# <base> = worktree 建立時的 origin/main 分岔點；用 merge-base 取得，origin/main 之後前進也不影響
BASE="$(git merge-base HEAD origin/main)"
# 本任務變更集 = 已 commit + 未 commit 的追蹤檔差異 ∪ 尚未 git add 的新檔
{ git diff --name-only "$BASE" -- <本任務路徑…>; git ls-files --others --exclude-standard -- <本任務路徑…>; } | sort -u
```

- **範圍檢查**：上述輸出必須**恰好**等於本任務檔案清單（不多不少）。
- **越界檢查**：把路徑參數拿掉跑同一組指令（`git diff --name-only "$BASE"` 與 `git ls-files --others --exclude-standard`），全量輸出不得出現 §5 清單（12 檔）與 STAGE 1 帶入的 spec / plan 以外的路徑。其他任務的檔案出現在全量輸出屬正常，**不得**據此判定本任務越界。

---

### Task 1：`wf-state.sh` 三欄 schema、退回上限、裁決閘門（TDD）

**寫入**：`.claude/skills/gen-dev-workflow/scripts/wf-state.sh`、`.claude/hooks/tests/test_wf_state_rework_verdict.sh`（新）、`.claude/hooks/tests/test_wf_state_done_reentry.sh`

#### 步驟 1.1（紅）：建立新測試

建立 `.claude/hooks/tests/test_wf_state_rework_verdict.sh`，完整內容：

```bash
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

echo "ALL TESTS PASSED!"
```

```bash
chmod +x .claude/hooks/tests/test_wf_state_rework_verdict.sh
bash .claude/hooks/tests/test_wf_state_rework_verdict.sh
```

**預期**：exit 1，stderr `FAIL: init 未帶三欄初值`（planner 已在 scratchpad 對現行腳本實跑確認）。

#### 步驟 1.2：修改 `wf-state.sh`（7 處）

**(a) 檔頭 guard 清單**——在第 7 行（`#      未帶 --confirmed 的 advance 一律拒絕…`）之後加一行：

```bash
#   4. STAGE 3：3→2 退回（所有模式）須附理由、達上限須 --confirmed；sequence 3→4 須有合法審查裁決
```

**(b) 常數**——`SCHEMA_VERSION=1` 之後：

```bash
REWORK_CAP=2   # STAGE 3→2 自動退回上限；達上限後每次退回都須使用者確認（--confirmed）
```

**(c) `usage()`**——取代 `set` 與 `advance` 兩段：

```text
  wf-state.sh set <檔> k=v [k=v ...]      更新欄位（不可改 stage/awaiting_confirmation/rework_history）
      review_verdict=PASS|CONCERNS|FAIL；review_concerns=<未結案項 markdown>（CONCERNS 必填）
```

```text
  wf-state.sh advance <檔> <next> [--confirmed] [--reason <s>]
      推進 stage。等待確認中且未帶 --confirmed → 拒絕；sequence 模式非法轉移 → 拒絕
      3→2 退回（所有模式）：--reason 必填並記入 rework_history；已退回 ≥2 次須 --confirmed
      sequence 3→4：review_verdict 須為 PASS（無未結案項）或 CONCERNS（有未結案項）
      進入 stage 3 一律清空 review_verdict / review_concerns
```

**(d) `validate()`**——在 `pause_level` 那行之後、`awaiting_confirmation` 之前插入：

```jq
    (.review_verdict == null or .review_verdict == "PASS" or .review_verdict == "CONCERNS" or .review_verdict == "FAIL") and
    (.review_concerns == null or (.review_concerns | type == "string")) and
    (.rework_history == null or (.rework_history | type == "array" and all(type == "object" and (.reason | type == "string") and (.at | type == "string")))) and
```

**(e) `apply_sets()`**——取代 `spec|plan|branch|issue|pr|total_tasks|interrupted_by) ;;` 這一行：

```bash
      review_verdict)
        case "$v" in
          PASS|CONCERNS|FAIL) ;;
          *) die "不可設定無效的 review_verdict 值：'${v}'（允許值：PASS, CONCERNS, FAIL）" ;;
        esac
        ;;
      spec|plan|branch|issue|pr|total_tasks|interrupted_by|review_concerns) ;;
```

（`rework_history` 不加入，自然落到 `*) die`，滿足 AC-6。）

**(f) 新函式**——放在 `apply_sets()` 之後、`cmd="${1:-}"; shift || usage` 之前：

```bash
# check_rework <檔> <reason> <confirmed>  3→2 退回前置檢查（所有模式）：理由必填；達上限視同暫停點
check_rework() {
  [ -n "${2//[[:space:]]/}" ] || die "STAGE 3→2 退回須附理由：advance <檔> 2 --reason \"<摘要>\""
  local n
  n="$(jq '.rework_history // [] | length' "$1")"
  if [ "$n" -ge "$REWORK_CAP" ] && [ "$3" != "true" ]; then
    die "已退回 ${n} 次（上限 ${REWORK_CAP}），本次退回視同暫停點。先向使用者展示以下歷史並取得決定：再修 → 帶 --confirmed 重跑；留案發布 → set review_verdict=CONCERNS review_concerns=\"<項目>\" 後 advance 4；放棄 → 依刪檔規則"$'\n'"$(jq -r '.rework_history[] | "  - \(.at)  \(.reason)"' "$1")"
  fi
}

# check_verdict <檔>  sequence 3→4 裁決閘門：放行 ⇔ verdict ∈ {PASS, CONCERNS} 且 (verdict == CONCERNS) == (concerns 非空)
check_verdict() {
  local v c
  v="$(jq -r '.review_verdict' "$1")"
  c="$(jq -r '(.review_concerns // "") | test("\\S")' "$1")"
  case "$v:$c" in
    PASS:false|CONCERNS:true) ;;
    FAIL:*) die "審查裁決為 FAIL，不可推進至 STAGE 4（--confirmed 不可覆寫）。修正請走 advance <檔> 2 --reason \"<摘要>\"；決定帶問題發布則改判 CONCERNS 並寫入 review_concerns" ;;
    PASS:true) die "裁決 PASS 卻有未結案項，兩者矛盾：改判 CONCERNS，或 set <檔> review_concerns=null" ;;
    CONCERNS:false) die "裁決 CONCERNS 須附未結案項：set <檔> review_concerns=\"<項目>\"" ;;
    *) die "STAGE 3 尚未記錄審查裁決：先執行 set <檔> review_verdict=PASS|CONCERNS|FAIL" ;;
  esac
}
```

（`validate` 已保證 `v ∈ {null, PASS, CONCERNS, FAIL}`，`*)` 只會接到 `null:*`。）

**(g) `init` 初值**——JSON 模板最後一行改為：

```bash
        pause_level:$pl, interrupted_by:null, review_verdict:null, review_concerns:null,
        rework_history:[], awaiting_confirmation:false}')"
```

**(h) `advance`**——三處：

1. 用法訊息改為 `…用法：wf-state.sh advance <檔> <next> [--confirmed] [--reason <s>]`。
2. 取代原本兩行 `confirmed=false` / `[ "${1:-}" = "--confirmed" ] && confirmed=true`：

```bash
    confirmed=false; reason=""; has_reason=false
    while [ $# -gt 0 ]; do
      case "$1" in
        --confirmed) confirmed=true; shift ;;
        --reason) [ $# -ge 2 ] || die "--reason 需要值"; reason="$2"; has_reason=true; shift 2 ;;
        *) die "advance：未知參數 $1" ;;
      esac
    done
```

3. 在 sequence 轉移合法性檢查（`legal_transition` 那個 `if`）之後、`total_tasks` 閘門之前插入：

```bash
    rework=false
    [ "$cur" = "3" ] && [ "$next" = "2" ] && rework=true   # 退回不分模式；3→4 閘門才限 sequence
    if [ "$has_reason" = "true" ] && [ "$rework" != "true" ]; then
      die "--reason 僅用於 STAGE 3→2 退回（本次：${cur} -> ${next}），理由不會被記錄"
    fi
    if [ "$rework" = "true" ]; then
      check_rework "$f" "$reason" "$confirmed"
    fi
    if [ "$mode" = "sequence" ] && [ "$cur" = "3" ] && [ "$next" = "4" ]; then
      check_verdict "$f"
    fi
```

4. 取代結尾的寫入（原 `jq --arg s "$next" '.stage = $s | …' "$f" | atomic_write "$f"`）：

```bash
    jq --arg s "$next" --arg r "$reason" --argjson rw "$rework" \
       --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .stage = $s | .awaiting_confirmation = false | .interrupted_by = null
      | if $s == "3" then .review_verdict = null | .review_concerns = null else . end
      | if $rw then .rework_history = ((.rework_history // []) + [{reason: $r, at: $at}]) else . end
    ' "$f" | atomic_write "$f"
```

#### 步驟 1.3（綠）：新測試轉綠

```bash
bash -n .claude/skills/gen-dev-workflow/scripts/wf-state.sh
bash .claude/hooks/tests/test_wf_state_rework_verdict.sh
```

**預期**：兩者 exit 0，最後一行 `ALL TESTS PASSED!`。

#### 步驟 1.4（紅）：確認既有測試被新閘門擋下

```bash
bash .claude/hooks/tests/test_wf_state_done_reentry.sh
```

**預期**：exit 1。注意錯誤訊息會是 `非法 stage 轉移：3 -> 5`，**不是**裁決閘門的訊息——`new_done_state` 在 `$(...)` 內執行，bash 3.2 的命令替換不繼承 `errexit`，`advance 4` 失敗後迴圈繼續，直到 Test 1 的 `advance 5` 才在外層炸掉。這是預期現象，不是新 bug。

#### 步驟 1.5（綠）：修補 `new_done_state`

`test_wf_state_done_reentry.sh` 的迴圈改為：

```bash
  for s in 2 3 4 done; do
    if [ "$s" = "4" ]; then "$WF_STATE" set "$state" review_verdict=PASS; fi   # 3→4 裁決閘門
    "$WF_STATE" advance "$state" "$s" --confirmed >/dev/null
  done
```

這是規格 §5 第 3 點允許的唯一既有測試改動。

#### 步驟 1.6：回歸

```bash
bash .claude/hooks/tests/test_wf_state_rework_verdict.sh
bash .claude/hooks/tests/test_wf_state_done_reentry.sh
bash .claude/hooks/tests/test_wf_state_total_tasks.sh
bash .claude/hooks/tests/test_project_settings_hooks.sh
bash .claude/hooks/tests/test_retro_skill.sh
python3 .claude/hooks/tests/test_delegate_cwd_logic.py
git ls-files -s .claude/hooks/tests/test_wf_state_rework_verdict.sh   # git add 後確認 100755
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- .claude/skills/gen-dev-workflow/scripts/wf-state.sh .claude/hooks/tests/; git ls-files --others --exclude-standard -- .claude/skills/gen-dev-workflow/scripts/wf-state.sh .claude/hooks/tests/; } | sort -u
```

**T1 驗收**：上述 6 支測試全部 exit 0（基準：2026-11-20 在 main 上實跑，既有 5 支全綠）；`bash -n` 通過；新增函式皆 ≤ 3 層縮排；`<base>` 比對輸出恰為本任務 3 檔（`wf-state.sh`、`test_wf_state_rework_verdict.sh`、`test_wf_state_done_reentry.sh`），越界檢查依 §6「並行驗收規則」。

---

### Task 2：reviewer / publisher agent 定義（含 `.agents/` 鏡像）

**寫入**：`.claude/agents/reviewer.md`、`.agents/agents/reviewer.yaml`、`.claude/agents/publisher.md`、`.agents/agents/publisher.yaml`

**步驟 2.1：`reviewer.md`**——在「## 工作原則」與「## 使用的 Skills」之間新增：

```markdown
## 裁決輸出（報告首行固定格式）

報告**第一行**頂格輸出以下三者之一（前綴 `REVIEW:` 刻意與 verifier 的 `PASS` / `FAIL: CODE` / `FAIL: INFRA` 區分）：

| 首行 | 判定依據 |
|:---|:---|
| `REVIEW: PASS` | 無 Critical / Important，且無須留案的事項 |
| `REVIEW: CONCERNS` | 無 Critical / Important（不阻擋發布），但有須在 PR 揭露、留待後續處理的未結案項 |
| `REVIEW: FAIL` | 有任何 Critical / Important（含上述兩種阻擋型 simplification） |

- `CONCERNS` 時報告必須有「## 未結案項」區段，一行一項 markdown 清單——主對話會原樣寫入 state，publisher 會原樣貼進 PR 描述。
- 「建議精簡」（非阻擋 simplification）**不自動構成 `CONCERNS`**；只有你判斷值得進 PR 留案時才列入未結案項。
- **不寫 state**：不執行 `wf-state.sh`。裁決由主對話依首行寫入（`set review_verdict=…`）。
```

「## 完成條件」整段改為：

```markdown
報告首行為 `REVIEW: PASS` / `REVIEW: CONCERNS` / `REVIEW: FAIL`（`CONCERNS` 附「未結案項」區段），無 Critical/Important 問題時才可為 `PASS` 或 `CONCERNS`；未派發 Lens 之維度均已覆核並完成免除記錄，測試全部通過，回報給主對話（`PASS` / `CONCERNS` 交 publisher subagent 發布，`FAIL` 由主對話退回 STAGE 2）。非阻擋的 simplification「建議精簡」項不擋發布，僅列於報告尾段供使用者決定。
```

**步驟 2.2：`reviewer.yaml`**——在 `system_prompt` 的「## 工作原則」與「## 使用的 Skills」之間插入與 2.1 相同的「## 裁決輸出」段落（每行前綴 2 空白縮排，與既有 block scalar 對齊）；「## 完成條件」改為 2.1 的文字但**去掉**「未派發 Lens 之維度…免除記錄」子句（yaml 本來就沒有該機制；既有 md/yaml 漂移不在本次範圍）。

**步驟 2.3：`publisher.md`**——在「## 職責」的「**發布：**」項目之前新增：

````markdown
- **審查留案（僅在建立新 PR 時：STAGE 4，或 quick 模式步驟④）：** 產草稿前自行讀 state，不依賴派發 prompt 轉述：
  ```bash
  f=".claude/workflow-state/$(git branch --show-current | tr '/' '-').json"
  if [ -f "$f" ]; then
    .claude/skills/gen-dev-workflow/scripts/wf-state.sh get "$f" | jq -r '.review_verdict, .review_concerns'
  else
    echo "no-state"
  fi
  ```
  - `review_verdict == CONCERNS` → PR 描述必須含「## 未結案項（Review CONCERNS）」區段，原樣列出 `review_concerns`（不改寫、不刪減）；其他裁決不加此區段。
  - 輸出 `no-state`（無 state 檔）→ 視為無裁決，照常發布。
  - state 檔存在但 `get` 失敗（stderr 出現 `state 檔校驗失敗`）→ 停下回報主對話，不猜。
  - **STAGE 5 更新 PR 描述時不讀裁決、不依 state 增刪未結案區段**：STAGE 5 不寫裁決，state 中的值停在 STAGE 3，已非最新。
````

「## 完成條件」改為：`PR 已建立並獲得 URL；建立新 PR 時若 review_verdict 為 CONCERNS，PR 描述含未結案項區段。本地 branch 保留不刪除。`

**步驟 2.4：`publisher.yaml`**——同 2.3：在 `system_prompt` 的「## 職責」中「**發布：**」之前插入相同項目（2 空白縮排），完成條件同步修改。

**步驟 2.5：驗收**

```bash
grep -c "REVIEW: CONCERNS" .claude/agents/reviewer.md .agents/agents/reviewer.yaml
grep -c "review_concerns" .claude/agents/publisher.md .agents/agents/publisher.yaml
grep -c "no-state" .claude/agents/publisher.md .agents/agents/publisher.yaml
ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }; puts "yaml ok"' .agents/agents/reviewer.yaml .agents/agents/publisher.yaml
head -7 .claude/agents/reviewer.md .claude/agents/publisher.md   # frontmatter 未被動到
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- .claude/agents/ .agents/agents/; git ls-files --others --exclude-standard -- .claude/agents/ .agents/agents/; } | sort -u
```

**T2 驗收**：各 `grep -c` 皆 ≥ 1；`yaml ok`（本機無 PyYAML，改用 ruby）；frontmatter 不變；`<base>` 比對輸出恰為本任務 4 檔（`.claude/agents/`、`.agents/agents/` 下其餘檔不得出現）；越界檢查依 §6「並行驗收規則」。

---

### Task 3：workflow 文件同步

**寫入**：`SKILL.md`、`references/state-machine.md`、`references/command-cheatsheet.md`、`references/delegation-and-parallel.md`、`references/execution-modes.md`（皆位於 `.claude/skills/gen-dev-workflow/`）

**步驟 3.1：`SKILL.md`（4 處）**

1. **編排流程圖 STAGE 3 區塊**（現第 126–138 行）：保留 reviewer / opt-in / Ponytail 三段，把「⏸ 暫停…」到區塊結尾、以及下方箭頭標籤換成（框線寬度依現有區塊對齊）：

```text
    │  → 依報告首行 REVIEW: PASS|CONCERNS|FAIL 寫入   │
    │    wf-state.sh set <檔> review_verdict=<V>      │
    │    （CONCERNS 同一次 set 帶 review_concerns）    │
    │    → stage-done 3                               │
    │  ⏸ 暫停：展示審查報告＋歷次退回理由，問「確認繼續嗎？」│
    │  ┌─ PASS / CONCERNS → advance 4             ─┐   │
    │  └─ FAIL / 使用者要求修正                     │   │
    │       → advance 2 --reason "<摘要>" 退回修正  │   │
    │       → 再回 STAGE 3（進 3 自動清空裁決）─────┘   │
    │  ⏸ 第 3 次起退回被腳本拒絕（任何 pause_level）： │
    │     展示歷次退回理由，使用者擇一：再修（帶     │
    │     --confirmed）／改判 CONCERNS 留案發布／放棄 │
    └──────────────────────┬──────────────────────────┘
                           │ 裁決 PASS／CONCERNS（且使用者確認）
```

2. **暫停點規則表**「審查報告完成後」列改為：

```markdown
| 審查報告完成後 | 展示完整審查報告（含首行裁決；`rework_history` 非空時一併列出歷次退回的 `at` + `reason`），問「確認繼續發布嗎？或需要修正？」 | `PASS`／`CONCERNS` 且使用者確認 → STAGE 4；`FAIL` 或要求修正 → `advance 2 --reason` 退回 STAGE 2 |
```

3. **「不應該暫停的情況」**：把「STAGE 3 審查失敗退回 STAGE 2」改為「STAGE 3 審查失敗退回 STAGE 2（**僅前 2 次**；第 3 次起任何 `pause_level` 都停，見下方暫停粒度）」。

4. **暫停粒度**：level 表 `autonomous` 列的「全不停」改為「全不停（例外見下）」，並在表格正下方加：

```markdown
> **唯一跨 level 的例外：STAGE 3 第 3 次起的退回。** `rework_history` 已有 2 筆時，`advance <檔> 2` 未帶 `--confirmed` 會被腳本拒絕——不看 `pause_level`，`balanced`／`autonomous` 也停。此上限在 sequence 由腳本完整強制；jump 下是軟約束（可被繞過，見 state-machine.md），主對話仍須照此停下。拒絕訊息列出歷次 `at` + `reason`，原樣展示給使用者，由使用者決定：再修（確認後帶 `--confirmed` 重跑）、改判 `CONCERNS` 並寫入 `review_concerns` 後推進 STAGE 4，或放棄。沒有其他覆寫旗標；`FAIL` 不能靠 `--confirmed` 推進 STAGE 4。
```

**步驟 3.2：`state-machine.md`（4 處）**

1. guard 清單「暫停點棘輪」bullet 之後新增：

```markdown
- **STAGE 3 退回與裁決閘門**（退回規則不分模式；3→4 閘門僅 sequence）：
  - `3→2` 退回（任何模式）須帶 `--reason "<摘要>"`（空白視同未帶），腳本把 `{reason, at}`（`at` 為 UTC ISO 8601）追加到 `rework_history`；`--reason` 用在其他轉移一律拒絕，避免誤以為理由已被記錄。
  - `rework_history` 已有 2 筆時，再退回視同暫停點：未帶 `--confirmed` 即拒絕，**不看 `pause_level`**，拒絕訊息列出歷次理由。`rework_history` 不可 `set`、永不重置。
  - **強制力範圍**：上限只在 sequence 由腳本完整強制。jump 下是**軟約束**——jump 的 `stage-done` 可直接改 stage 標籤、且無轉移表可走 `3→4→2`，都繞得過 `3→2` 這條邊；jump 的價值是理由留痕與正常路徑上的提醒，不是防繞過。
  - sequence 的 `3→4` 須先 `set review_verdict`：放行 ⇔ `PASS` 且 `review_concerns` 為空，或 `CONCERNS` 且 `review_concerns` 非空；`null`、`FAIL`、矛盾組合一律拒絕，`--confirmed` 不可覆寫。jump 不強制（可 `init --stage 4` 直接進 4，閘門形同虛設），但主對話照常寫入裁決供 publisher 使用。
  - 任何模式 `advance <檔> 3` 都清空 `review_verdict`／`review_concerns`（裁決只屬於本輪審查），`rework_history` 不動。
```

2. 指令表在「使用者確認並推進 stage」列之後新增兩列：

```markdown
| STAGE 3 記錄審查裁決 | `wf-state.sh set <檔> review_verdict=PASS\|CONCERNS\|FAIL`；`CONCERNS` 同一次 `set` 帶 `review_concerns="<未結案項>"` |
| STAGE 3 退回 STAGE 2 | `wf-state.sh advance <檔> 2 --reason "<摘要>"`（已退回 2 次後須使用者確認並加 `--confirmed`） |
```

3. sequence 模式 JSON 範例在 `"interrupted_by"` 之後加三欄：

```json
  "review_verdict": null,
  "review_concerns": null,
  "rework_history": [],
```

4. `interrupted_by` 說明段之後新增：

```markdown
`review_verdict` / `review_concerns` / `rework_history`（STAGE 3 專用；舊檔缺席等同 `null` / `null` / `[]`）：
- `review_verdict`：本輪審查裁決 `PASS` / `CONCERNS` / `FAIL`，主對話依 reviewer 報告首行 `REVIEW: <V>` 寫入。退回期間（stage 2）保留可見，重新 `advance 3` 才清空。
- `review_concerns`：未結案項 markdown（一行一項）。`CONCERNS` 必填、`PASS` 必空；保留至 STAGE 4 供 publisher 寫進 PR 描述。
- `rework_history`：`[{reason, at}]`，僅 `advance <檔> 2 --reason` 追加。續接 session 與 `/retro` 由此追溯退回次數與理由。
- 已知限制：`review_concerns` 若為純數字（如 `42`），`set` 會把它解析成 number 而校驗失敗（失敗而非靜默），未結案項請寫成文字。
```

**步驟 3.3：`command-cheatsheet.md`**——第 31 行與第 50 行（兩處相同的「[若不通過] 退回 STAGE 2…」）各改為兩行：

```text
    → 依報告首行裁決：wf-state.sh set <檔> review_verdict=PASS|CONCERNS|FAIL（CONCERNS 同次帶 review_concerns="…"）
    → [若 FAIL] wf-state.sh advance <檔> 2 --reason "<摘要>" 退回 STAGE 2；微任務由主進程原地修改並跑測試，其餘任務才派發 Task("implementer", "修正以下問題：<reviewer 回報>")；第 3 次起退回須使用者確認（見 SKILL.md 暫停粒度）
```

兩處文字完全相同，不分 sequence / jump（退回規則不分模式，見 §2.1），不加任何模式註腳。

**步驟 3.4：`delegation-and-parallel.md`**——第 157 行句末追加：

```markdown
STAGE 3 退回有次數上限：前 2 次自動，第 3 次起任何 `pause_level` 都停下由使用者決定（sequence 由腳本強制、jump 為軟約束，見 [`../SKILL.md`](../SKILL.md)「暫停粒度」）。
```

**步驟 3.5：`execution-modes.md`（2 處）**

1. quick 步驟③（第 25–26 行）「發現問題 → 主對話修正後重掃」那一行之後新增：

   ```text
      - reviewer 首行 `REVIEW: CONCERNS` → `wf-state.sh set <檔> review_verdict=CONCERNS review_concerns="<未結案項>"`（publisher 會帶進 PR）；之後重掃結論改變時以同法覆寫（`PASS` 時同次帶 `review_concerns=null`），避免舊未結案項殘留——quick 不經 `advance 3`，裁決不會自動清空
   ```

2. 第 105 行「某項失敗（STAGE 3 審查連續退回、tier 升級後仍失敗）」改為「某項失敗（STAGE 3 退回達上限後使用者選擇放棄、tier 升級後仍失敗）」。

**步驟 3.6：驗收**

```bash
grep -c -- "--reason" .claude/skills/gen-dev-workflow/SKILL.md .claude/skills/gen-dev-workflow/references/state-machine.md .claude/skills/gen-dev-workflow/references/command-cheatsheet.md
grep -c "review_verdict" .claude/skills/gen-dev-workflow/SKILL.md .claude/skills/gen-dev-workflow/references/state-machine.md
grep -c "上限" .claude/skills/gen-dev-workflow/references/delegation-and-parallel.md .claude/skills/gen-dev-workflow/references/execution-modes.md
grep -c "REVIEW: CONCERNS" .claude/skills/gen-dev-workflow/references/execution-modes.md
bash .claude/hooks/tests/test_retro_skill.sh    # 會 grep SKILL.md 的 /retro，確認沒被誤刪
grep -c "軟約束" .claude/skills/gen-dev-workflow/references/state-machine.md .claude/skills/gen-dev-workflow/SKILL.md
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- .claude/skills/gen-dev-workflow/SKILL.md .claude/skills/gen-dev-workflow/references/; git ls-files --others --exclude-standard -- .claude/skills/gen-dev-workflow/SKILL.md .claude/skills/gen-dev-workflow/references/; } | sort -u
```

**T3 驗收**：各 `grep -c` ≥ 1；`test_retro_skill.sh` exit 0；`<base>` 比對輸出恰為本任務 5 檔（`references/` 下其餘檔不得出現）；越界檢查依 §6「並行驗收規則」；人工目視 SKILL.md 流程圖框線未錯位。

---

## 7. 整體驗收（STAGE 2 收尾，非獨立任務）

| AC | 覆蓋 |
|:---|:---|
| AC-1～AC-12 | `test_wf_state_rework_verdict.sh` 各 `===` 區段（標題即 AC 編號；AC-5 區段另含規格 §3.2 未知參數） |
| AC-13 | 下方 6 支回歸指令全 exit 0 |
| AC-14 | T2、T3 的 `git diff` 人工檢視 |

回歸基準（`.claude/hooks/tests/` 下全部 `*.sh` / `*.py`）：

```bash
bash .claude/hooks/tests/test_wf_state_rework_verdict.sh
bash .claude/hooks/tests/test_wf_state_done_reentry.sh
bash .claude/hooks/tests/test_wf_state_total_tasks.sh
bash .claude/hooks/tests/test_project_settings_hooks.sh
bash .claude/hooks/tests/test_retro_skill.sh
python3 .claude/hooks/tests/test_delegate_cwd_logic.py
```

> 本計畫的 T1 程式碼與測試（含 0b 修訂後版本）已在 scratchpad 複本上實跑：新測試對現行腳本為紅（AC-9 即失敗）、對修改後腳本為綠；修改後腳本 + 修補後 `done_reentry` + `total_tasks` 皆綠；拿掉 `check_verdict` 呼叫的突變版本會被 AC-7 抓到。

---

## 8. 風險與已知限制

| # | 風險 | 處置 |
|:-:|:---|:---|
| R1 | `advance` 未知參數改為 `die` | 已實查：`.claude/`、`.agents/agents/` 內所有 `advance` 呼叫只帶 `--confirmed`（含 `wf-guard-stage-check.sh:124` 的提示字串） |
| R2 | **本流程自身吃到新規則**：主對話在 worktree 內用的是 worktree 版 `wf-state.sh`，T1 落地後，本 feature 自己的 STAGE 3 就必須 `set review_verdict` 才能 `advance 4`、退回必須帶 `--reason` | 主對話 STAGE 3 依新流程操作；本流程的 state 檔由舊腳本建立（缺三欄），由 AC-10 的舊檔相容保證可續用 |
| R3 | 進行中、停在 stage 3 的其他 sequence state，`advance 4` 會被拒 | 規格 §6 已接受；拒絕訊息直接給出 `set` 指令 |
| R4 | 進行中的 jump state 停在 stage 3 時，`advance 2` 改為必須帶 `--reason`，且計入上限 | §2.1 裁決本意；錯誤訊息直接給出用法。issue-id 路徑的 state 模式文件未明定，但退回規則已不分模式，不再受此歧義影響。jump 的上限為軟約束（§2.1），已在 state-machine.md / SKILL.md 明載，不誇大為腳本強制 |
| R5 | `reviewer.yaml` / `publisher.yaml` 與 md 版本早已漂移（yaml 缺 Lens 兜底、publisher 發布步驟簡化） | 本次只同步新增段落，不修既有漂移 |
| R6 | 主對話可把 `FAIL` 直接改判 `CONCERNS` 繞過（開放問題 1） | 本次不擋；改判必留書面 `review_concerns` 並進 PR |
| R7 | `review_concerns` 純數字被校驗擋下（開放問題 4） | 已知限制，寫進 state-machine.md |
| R8 | `execution-modes.md` 原為規格 §8 外補列 | 0b 初審後已納入規格 §8（quick 裁決寫入 + 批次失敗措辭） |
| R9 | 測試 helper 在 `$(...)` 內執行，bash 3.2 不繼承 `errexit` | `new_stage3` 結尾以 `expect … .stage 3` 顯式擋下 |
| R10 | quick 不經 `advance 3`，裁決不會自動清空 | execution-modes.md 要求重掃結論改變時覆寫 `review_verdict` / `review_concerns` |

未處理（YAGNI）：SKILL.md frontmatter `description` 的「autonomous 全不停」字樣不改（屬觸發描述，例外寫在暫停粒度章節）；`at` 不做格式校驗（只校驗型別，由腳本自己產生）。

---

## 9. 執行方式

1. **Subagent-driven（建議）**：同一 session 依 SKILL.md STAGE 2 派發。T1、T2、T3 寫入路徑不重疊，同批並行派發 3 個 implementer，各自由 verifier 依該任務「驗收」段落（含 §6 並行驗收規則）做兩階段驗收；全部完成後主對話跑 §7 回歸。
2. **Parallel session**：開 3 個 session 各領一個任務，在同一 worktree 內各改各的檔案（無共享檔），最後由任一 session 跑 §7 回歸。協調成本較高，僅在想人工盯每個任務時採用。
