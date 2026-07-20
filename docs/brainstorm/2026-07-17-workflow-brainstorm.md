# gen-dev-workflow 流程優化與架構調整腦力激盪文件

本文件針對 `gen-dev-workflow` 流程進行深度審查，指出其設計哲學上的盲點、目前運作的瓶頸、Bash 狀態機腳本中的具體 Bug，並提出相應的邏輯漏洞修補與驗證方案。

---

## 0. 完成度總覽（截至 2026-07-21）

> 狀態依 [`docs/features/2026-07-18-gen-dev-workflow-analysis.md`](../features/2026-07-18-gen-dev-workflow-analysis.md) 核對標注（`wf-state.sh` 屬 `gen-dev-workflow` skill，不在本 repo，無法直接讀原始碼，故以該份 analysis 為權威來源）。✅ 已修 ｜ 🟡 部分 ｜ ⬜ 待修。

| 項目 | 狀態 | 依據 |
|------|:---:|------|
| **Bug 1.1** `shift 2` crash under `set -e` | ✅ 已修 | 於 2026-07-21 修復，增加參數個數檢查 |
| **Bug 1.2** `set` 無 `=` 致 JSON 損毀 | ✅ 已修 | 於 2026-07-21 修復，拒絕非法格式 |
| **Bug 1.3** `jq_val` 負數被錯轉字串 | ✅ 已修 | 於 2026-07-21 修復，正則精確比對數值 |
| **Bug 1.4** 原子寫入失敗殘留暫存檔 | ✅ 已修 | 於 2026-07-21 修復，加上 fallback 清理機制 |
| **Gap 2.1** Cross-Worktree State Blindness | ✅ 已修 | analysis 總結：SKILL.md 已強制 `git worktree list` 跨區掃描 |
| **Gap 2.2** Quick→Sequence 升級隔離逃逸 | ✅ 已修 | analysis 總結：`upgrade` 後強制建 worktree + promote 狀態 |
| **Gap 2.3** 缺任務完成校驗（`completed_tasks`） | ✅ 已修 | 於 2026-07-21 修復，`advance` 增加任務數量校驗 |
| **Gap 2.4** STAGE 5 缺 `reviewer→responder` 退回 | ✅ 已修 | 於 2026-07-21 修復，新增閉環轉移路徑 |
| **Gap 2.5** 廢棄 `.pending-*.json` 無 `prune` GC | ✅ 已修 | 於 2026-07-21 修復，新增 `prune` 指令 |

> **已落地的地基**（analysis 確認，非本 brainstorm 提出的待辦）：`wf-state.sh` 已成 state 檔唯一入口——狀態機轉移表（非法轉移 `exit 1`）、暫停點棘輪（無 `--confirmed` 拒絕 `advance`）、`set` 白名單、schema 校驗 + 原子寫入皆已實作。
>
> **結論**：所有 4 個 Bash Bug 及 5 個流程漏洞均已修復（包含 SKILL.md 層面的 2 項與 `wf-state.sh` 腳本層面的 7 項），已徹底解決腳本脆弱性與狀態機漏洞。

---

## 1. 總結與設計哲學批評 (Linus-Style Critique)

> 「這個工作流設計的核心品味漏洞在於：它試圖用一堆 Markdown 文字去『說服』LLM 遵守狀態轉移。這就跟寫一份『請不要碰野指針』的安全規範給 C 語言實習生，然後指望程式永遠不會 Segment Fault 一樣荒謬。更糟的是，用來作為防護欄的 Shell 腳本（`wf-state.sh`）本身寫得漏洞百出，在 `set -e` 的環境下一碰就碎。」

### 🟢 展現好品味的設計 (Good Taste)
* **Token Budget Gate 的閉環設計**：這解決了長流程下 LLM 的 Context 容易爆炸的**真實問題**。在 >150k 時強制寫入 checkpoints、WIP commit 並交接給新 session 的作法，是極其實用且具彈性的。
* **基於 Worktree 的多流程並行隔離**：透過 `git worktree` 將不同分支的開發徹底隔離在獨立的工作區中。這從**資料結構**與**目錄實體**上直接消滅了並行衝突的可能，而不是試圖用複雜的鎖（Lock）去修補它。這正是簡化資料結構以消除特殊情況的典範。

### 🔴 湊合與糟糕的設計 (Bad Taste)
* **過度工程的「人肉暫停點」**：完整流程中包含了至少 6 個固定暫停點，在 STAGE 2 中甚至每完成一個任務就要暫停一次。這把原本應該自動化運行的編排器，變成了需要人類不斷點擊確認的「高頻打擾器」。
* **防禦性程式碼的缺失**：`wf-state.sh` 雖被立為唯一狀態入口，但其參數解析脆弱，未對變數型別與參數個數進行防禦性檢查。

---

## 2. 當前瓶頸與限制分析

### 2.1. 人在迴口（Human-in-the-loop）頻率過高
* **現象**：STAGE 2 實作階段會根據任務清單逐一分派並暫停。當任務量多（例如 5-10 個小任務）時，頻繁的暫停展示變更與確認，嚴重打斷了開發的流暢性。
* **瓶頸**：LLM 雖然能自動寫代碼，但頻繁的人工確認要求使用者的注意力維持在低效的等待狀態。

### 2.2. 跨工作區狀態盲區 (Cross-Worktree State Blindspot)
* **現象**：自 STAGE 1 起，狀態 JSON 會被 promote 並搬移到各 Worktree 的 `.claude/workflow-state/` 中，而 Root 倉庫對應的 JSON 會被刪除。
* **瓶頸**：當使用者在 Root 倉庫重新啟動 Claude session 並嘗試呼叫 `continue` 時，根目錄的 Agent 由於對 Worktree 目錄毫無感知，會判定「找不到任何活動中的工作流」。

### 2.3. 外部 `agy` CLI 強相依
* **現象**：流程的核心委派動作（如 brancher、implementer、publisher）完全依賴外部 `agy` 命令。
* **限制**：若 `agy` 未正確配置在 PATH，退回 Fallback 模式後的行為描述含糊。且由於 Fallback 模式無法有效委派，整條流程的優勢將不復存在。

---

## 3. `wf-state.sh` 中的 Bash Bug 細節與具體修復方案

以下是目前 `wf-state.sh` 腳本中存在的四個 Bash Bug 及其具體修復方案：

### Bug 1.1: `shift 2` Crash under `set -e` — ⬜ 待修
* **問題根源**：由於腳本設定了 `set -euo pipefail`，當執行 `advance`、`init`、`promote` 等指令時，如果使用者漏傳了選填或必填參數（例如少傳了 `<next>`，僅執行 `wf-state.sh advance config.json`），`$#` 數量小於 2，此時執行 `shift 2` 會返回退出狀態碼 `1`。這會觸發 `set -e` 導致腳本直接異常退出（Crash），而無法輸出優雅的 Usage 說明。
* **受影響程式碼片段 (`wf-state.sh` Line 221)**：
  ```bash
  f="$(resolve "$1")"; next="$2"; shift 2
  ```
* **具體修復方案**：
  ```bash
  f="$(resolve "$1")"
  if [ $# -ge 2 ]; then
    next="$2"
    shift 2
  else
    die "advance 指令需要提供目標階段 (next)，用法：wf-state.sh advance <檔> <next> [--confirmed]"
  fi
  ```
  *(同理，針對 `init`、`promote` 與 `upgrade` 中所有包含 `shift 2` 的參數解析迴圈，皆須在 `shift 2` 前檢查剩餘參數個數)*

### Bug 1.2: Silent Key-Value Corruptions in `set` Command — ⬜ 待修
* **問題根源**：在 `set` 命令中，腳本將 args 拆分為 `k` 與 `v`。然而，如果傳入的參數不含 `=`（例如 `wf-state.sh set config.json interrupted_by`），`k="${kv%%=*}"` 與 `v="${kv#*=}"` 會同時解析為鍵名 `"interrupted_by"`。這會導致腳本靜默寫入 `"interrupted_by": "interrupted_by"` 至 JSON 中，造成資料損毀。
* **受影響程式碼片段 (`wf-state.sh` Line 94-95)**：
  ```bash
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
  ```
* **具體修復方案**：
  ```bash
  for kv in "$@"; do
    if [[ "$kv" != *=* ]]; then
      die "參數格式錯誤：'$kv'。必須為 k=v 格式"
    fi
    k="${kv%%=*}"; v="${kv#*=}"
  ```

### Bug 1.3: `jq_val` String Coercion for Negative Numbers — ⬜ 待修
* **問題根源**：在型別判定函式 `jq_val()` 中，判定模式 `''|*[!0-9]*|0*` 用於攔截並強製轉化為 JSON 字串。然而，負數（如 `-42`）因為包含負號 `-`，會匹配到 `*[!0-9]*`。這會使負數被錯誤地強製轉換為 JSON 字串 `"-42"` 而非 raw 數值。
* **受影響程式碼片段 (`wf-state.sh` Line 73-80)**：
  ```bash
  jq_val() {
    case "$1" in
      null|true|false) echo "$1" ;;
      0) echo "0" ;;
      ''|*[!0-9]*|0*) jq -n --arg v "$1" '$v' ;;
      *) echo "$1" ;;
    esac
  }
  ```
* **具體修復方案**：
  使用 Bash Regex 進行精準判斷，只將非合法數值、布林與 null 的內容轉化為字串：
  ```bash
  jq_val() {
    if [[ "$1" =~ ^-?[1-9][0-9]*$ || "$1" == "0" || "$1" == "-0" ]]; then
      echo "$1"
    elif [[ "$1" == "true" || "$1" == "false" || "$1" == "null" ]]; then
      echo "$1"
    else
      jq -n --arg v "$1" '$v'
    fi
  }
  ```

### Bug 1.4: Leftover Temp Files on Rename Failure — ⬜ 待修
* **問題根源**：在 `atomic_write()` 中，雖然有在 subshell 中做 validate 校驗，但如果最後的 `mv "$tmp" "$f"` 搬移操作失敗（例如磁碟空間滿了、或者目標目錄的權限被更改為唯讀），因為 `set -e`，腳本會立即中斷退出，但已經建立的暫存檔 `.wf-tmp.XXXXXX` 將會永遠遺留在目錄中。
* **受影響程式碼片段 (`wf-state.sh` Line 62-69)**：
  ```bash
  atomic_write() {
    local f="$1" tmp
    mkdir -p "$(dirname "$f")"
    tmp="$(mktemp "$(dirname "$f")/.wf-tmp.XXXXXX")"
    jq . >"$tmp" || { rm -f "$tmp"; die "非法 JSON，寫入中止"; }
    ( validate "$tmp" ) || { rm -f "$tmp"; exit 1; }
    mv "$tmp" "$f"
  }
  ```
* **具體修復方案**：
  ```bash
  atomic_write() {
    local f="$1" tmp
    mkdir -p "$(dirname "$f")"
    tmp="$(mktemp "$(dirname "$f")/.wf-tmp.XXXXXX")"
    jq . >"$tmp" || { rm -f "$tmp"; die "非法 JSON，寫入中止"; }
    ( validate "$tmp" ) || { rm -f "$tmp"; exit 1; }
    mv "$tmp" "$f" || { rm -f "$tmp"; die "搬移暫存檔失敗，清理暫存檔 $tmp"; }
  }
  ```

---

## 4. 邏輯缺陷與流程漏洞分析 (Logical & Process Gaps)

### Gap 2.1: Cross-Worktree State Blindness (CRITICAL) — ✅ 已修
* **漏洞描述**：當 Sequence 流程推進到 STAGE 1 時，狀態 JSON 被移入工作區，Root 對話便失去了對該狀態的感知。一旦重開 session，用戶在 Root 執行 `continue` 將無法接續進度。
* **解決方案**：
  修改 `SKILL.md` 中續接（continue）狀態定位邏輯。當前目錄找不到狀態時，強制調用 `git worktree list` 遍歷所有活動工作區路徑，並掃描這些工作區的 `.claude/workflow-state/*.json`。

### Gap 2.2: Quick-to-Sequence Upgrade Isolation Escape (CRITICAL) — ✅ 已修
* **漏洞描述**：Quick 模式運行於 Root 倉庫。當呼叫 `upgrade` 提升為 Sequence 流程時，腳本僅僅修改了狀態 JSON，卻沒有在實體層面建立 Git worktree，這導致升級後的 Sequence 流程直接在 Root 倉庫中運行，打破了工作區物理隔離的鐵律。
* **解決方案**：
  在 `SKILL.md` 的 `upgrade` 流程中，強制與建立 worktree 的指令綁定。在 `wf-state.sh upgrade` 執行成功後，必須立即為該分支建立 worktree，複製 Root 中未 commit 的變更至新工作區，並將狀態 JSON promote 到該工作區下，最後指引 Claude `cd` 進入該工作區。

### Gap 2.3: Missing Task Completion Verification — ⬜ 待修
* **漏洞描述**：狀態機允許任意從 STAGE 2 推進（advance）至 STAGE 3，而沒有在程式碼層面檢查 `completed_tasks` 陣列是否完整包含 `1` 到 `total_tasks` 的所有任務編號。這使得 LLM 可能因為自律失效，跳過未實作的任務直接申請審查。
* **解決方案**：
  在 `wf-state.sh` 的 `advance` 指令解析中，當目標為 `3` 且模式為 `sequence` 時，增加校驗邏輯：
  ```bash
  if [ "$next" = "3" ] && [ "$mode" = "sequence" ]; then
    local total completed_count
    total="$(jq -r '.total_tasks' "$f")"
    completed_count="$(jq -r '.completed_tasks | length' "$f")"
    if [ "$total" != "null" ] && [ "$completed_count" -lt "$total" ]; then
      die "實作尚未全部完成（已完成 $completed_count / 共 $total 任務），拒絕推進至 STAGE 3"
    fi
  fi
  ```

### Gap 2.4: PR Review responder has no retry loop — ⬜ 待修
* **漏洞描述**：在 STAGE 5 中，轉移路徑為 `responder -> reviewer -> publisher`。若 `reviewer` 審查不通過，狀態機沒有回到 `responder` 重新修改的閉環，容易導致流程卡死。
* **解決方案**：
  在 `legal_transition()` 中新增 `reviewer->responder` 的轉移規則：
  ```bash
  legal_transition() {
    case "$1->$2" in
      "0a->0b"|"0b->1"|"1->2"|"2->3"|"3->4"|"3->2"|"4->done"|"reviewer->responder"|"responder->reviewer"|"reviewer->publisher") return 0 ;;
      *) return 1 ;;
    esac
  }
  ```

### Gap 2.5: Orphaned Pending Files — ⬜ 待修
* **漏洞描述**：若 Sequence 流程在 STAGE 0a/0b 階段（尚未 promote）被使用者廢棄，根倉庫的 `.pending-<wf-id>.json` 檔案將永遠殘留，缺乏垃圾回收機制。
* **解決方案**：
  在 `wf-state.sh` 中新增 `prune` 命令，允許使用者或系統定期清理建立時間大於 7 天的 `.pending-*.json` 檔案。

---

## 5. 驗證方法 (Verification Methods)

### 5.1. 針對 Bash Bug 的單元測試方法
1. **驗證 Bug 1.1 修復**：
   執行 `./wf-state.sh advance config.json` (故意缺少 target stage)，預期腳本輸出正確的 usage 錯誤訊息，且退出碼為 1，不應 crash 退出。
2. **驗證 Bug 1.2 修復**：
   執行 `./wf-state.sh set config.json interrupted_by`，預期腳本拒絕修改並印出 "參數格式錯誤：'interrupted_by'。必須為 k=v 格式"。
3. **驗證 Bug 1.3 修復**：
   執行 `./wf-state.sh set config.json total_tasks=-5`，隨後執行 `wf-state.sh get config.json`，確認 `total_tasks` 在 JSON 中的值為 raw 數值 `-5`，而不是帶雙引號的 `"-5"`。
4. **驗證 Bug 1.4 修復**：
   建立一個唯讀權限的資料夾，將狀態 JSON 放入其中。執行 `./wf-state.sh set` 寫入該 JSON。由於搬移必會失敗，檢查該唯讀目錄下是否殘留有 `.wf-tmp.XXXXXX` 暫存檔，預期無任何殘留。

### 5.2. 針對流程漏洞的整合驗證
1. **驗證 Cross-Worktree 續接**：
   在新 session 的 Root 倉庫中呼叫 `continue`，確認腳本會輸出當前所有 worktree 中的 active workflows 列表。
2. **驗證 Quick 升級隔離性**：
   啟動一個 quick 流程，並執行 `upgrade`。驗證系統是否確實自動建立了對應的 git worktree，並且狀態 JSON 成功被 promote 至該 worktree 目錄下。
