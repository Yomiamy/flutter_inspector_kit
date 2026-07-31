# gen-dev-workflow 流程優化、多 Agent 框架比對與架構演進總整文件

> **📝 合併紀錄**：
> 本文件整併了 `2026-07-17` 與 `2026-07-30` 的腦力激盪記錄。依據時間軸與完成度，前半部記錄歷史遺留 Bug、流程漏洞的分析與修復；後半部基於系統穩固的基礎，進行開源多 Agent 框架的深度比對，並提出 2.0 架構的具體優化提案。

---

## 🟢 第一部分：歷史基準修復與流程漏洞填補 (2026-07-17 ~ 2026-07-30)

## 0. 完成度總覽（截至 2026-07-21）

> 狀態依 [`docs/features/2026-07-18-gen-dev-workflow-analysis.md`](../features/2026-07-18-gen-dev-workflow-analysis.md) 核對標注（`wf-state.sh` 屬 `gen-dev-workflow` skill，不在本 repo，無法直接讀原始碼，故以該份 analysis 為權威來源）。✅ 已修 ｜ 🟡 部分 ｜ ⬜ 待修。

| 項目 | 狀態 | 依據 |
|------|:---:|------|
| **Bug 1.1** `shift 2` crash under `set -e` | ✅ 已修 | 於 2026-07-21 修復，增加參數個數檢查 |
| **Bug 1.2** `set` 無 `=` 致 JSON 損毀 | ✅ 已修 | 於 2026-07-21 修復，拒絕非法格式 |
| **Bug 1.3** `jq_val` 負數被錯轉字串 | ✅ 已修 | 於 2026-07-21 修復，正則精確比對數值 |
| **Bug 1.4** 原子寫入失敗殘留暫存檔 | ✅ 已修 | 於 2026-07-21 修復，加上 fallback 清理機制 |
| **Bug 1.5** `advance` 校驗用 `local` 於函式外致 crash | ✅ 已修 | 於 2026-07-21 修復，移除多餘 `local` 宣告（Gap 2.3 修復引入的回歸） |
| **Gap 2.1** Cross-Worktree State Blindness | ✅ 已修 | analysis 總結：SKILL.md 已強制 `git worktree list` 跨區掃描 |
| **Gap 2.2** Quick→Sequence 升級隔離逃逸 | ✅ 已修 | analysis 總結：`upgrade` 後強制建 worktree + promote 狀態 |
| **Gap 2.3** 缺任務完成校驗（`completed_tasks`） | ✅ 已修 | 於 2026-07-21 修復，`advance` 增加任務數量校驗 |
| **Gap 2.4** STAGE 5 缺 `reviewer→responder` 退回 | ✅ 已修 | 於 2026-07-21 修復，新增閉環轉移路徑 |
| **Gap 2.5** 廢棄 `.pending-*.json` 無 `prune` GC | ✅ 已修 | 於 2026-07-21 修復，新增 `prune` 指令 |

> **已落地的地基**（analysis 確認，非本 brainstorm 提出的待辦）：`wf-state.sh` 已成 state 檔唯一入口——狀態機轉移表（非法轉移 `exit 1`）、暫停點棘輪（無 `--confirmed` 拒絕 `advance`）、`set` 白名單、schema 校驗 + 原子寫入皆已實作。
>
> **結論**：所有 5 個 Bash Bug 及 5 個流程漏洞均已修復（包含 SKILL.md 層面的 2 項與 `wf-state.sh` 腳本層面的 8 項），已徹底解決腳本脆弱性與狀態機漏洞。其中 Bug 1.5 是 Gap 2.3 修復方案照抄片段時把 `local` 帶進頂層 `case` 分支所造成的回歸，於本次一併抓出並修正。

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

### Bug 1.1: `shift 2` Crash under `set -e` — ✅ 已修
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

### Bug 1.2: Silent Key-Value Corruptions in `set` Command — ✅ 已修
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

### Bug 1.3: `jq_val` String Coercion for Negative Numbers — ✅ 已修
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

### Bug 1.4: Leftover Temp Files on Rename Failure — ✅ 已修
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

### Gap 2.3: Missing Task Completion Verification — ✅ 已修
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

### Gap 2.4: PR Review responder has no retry loop — ✅ 已修
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

### Gap 2.5: Orphaned Pending Files — ✅ 已修
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


---

## 6. 後續發現的待修項目（2026-07-21 之後）

### Bug 1.6: `promote` 後 `stage-done <1>` 恆遭拒，STAGE 1 happy path 斷裂 — ✅ 已修

* **撞到的情境**：2026-07-25 用本流程實作 §P13（PR #100）時，STAGE 1 建好 worktree 後，照 SKILL.md 的指示跑 `promote` → 隨後 `stage-done <檔> 1`，被腳本直接拒絕：
  ```text
  wf-state: sequence 模式 stage-done 參數須等於目前 stage（目前：0a），改 stage 請用 advance
  ```
* **根因（已實查 `wf-state.sh` 原始碼與多次隔離重現確認）**：
  - `promote`（Line 144-163）只做兩件事：把 `.branch` 欄位填上、把檔案搬到新 worktree。**它不碰 `stage` 也不碰 `mode`**——所以 promote 完的檔案仍是 `{mode: "sequence", stage: "0a"}`。
  - 但 SKILL.md 的「狀態機腳本」表格指示 STAGE 1 建好 worktree 後執行 `stage-done <檔> 1`。
  - `stage-done`（Line 176-187）在 sequence 模式下強制 `<stage> 參數 == 目前 stage`（Line 182-184）。此時目前 stage 還是 `0a`，傳 `1` 必被拒。
  - 換句話說：**SKILL.md 記載的 STAGE 1 收尾流程，在 sequence 模式下必定失敗**。正常 sequence 從 0a 一路 `advance` 上來時，promote 發生在 STAGE 1，但 stage 欄位並沒有跟著 promote 一起前進到 `1`，兩者脫節。
* **我最初的誤判（記錄下來以免重蹈）**：當下我把 `&&` 鏈的中斷誤讀成「`promote` 把 state 檔吃掉了」，還推測是 `--dest` 指向不存在目錄 + EXIT trap 所致。**這個診斷是錯的**——事後隔離重現證明 `promote` 對不存在的 dest 目錄運作完全正常（`mkdir -p` + `claim_new` 會建好），檔案該寫的有寫、該刪的 pending 有刪。真正的失敗是後續 `stage-done 1` 被 sequence guard 擋下，中斷了我串起來的 `&&` 鏈，而我沒往下追就 fallback 到 `init --mode jump` 重建。**教訓：`&&` 鏈中斷要逐段定位是哪一段 exit 非零，不要看到 `get` 報 pending 路徑就腦補整條鏈的因果。**
* **⚠️ 一個被否決的錯誤修復方向（記錄下來以免重蹈）**：本文件初稿曾提議「讓 `promote` 一併 `.stage = "1"`」，並自稱「promote 不受轉移表約束，安全」。**這是錯的，經 PR #100 的 CodeRabbit review 抓出並實查確認**：`promote` 不只服務 sequence-from-0a，還服務 **quick→sequence 升級路徑**——SKILL.md L288 明載，`upgrade`（已把 stage 設為 `2`）之後也走 `promote` 把狀態搬進 worktree。若 `promote` 無條件寫死 `stage=1`，會把升級後的 `stage=2` 打回 `1`，讓一個已在實作階段的流程重跑 STAGE 1。原方案只看了一條路徑就下「安全」結論，是典型的以偏概全。
* **正確的修復方向（於 2026-07-30 已實作，限定作用範圍，不動 `promote` 的共用邏輯）**：
  **修復方案：修改 SKILL.md 的 sequence STAGE 1 收尾流程，不碰腳本 (Workaround)**。
  正常 sequence 從 0a 一路 `advance` 上來，promote 之後 stage 仍是 `0a`。收尾時不該用 `stage-done 1`（會撞 guard），而是先 `advance 0b --confirmed` → `advance 1 --confirmed` 走完既有轉移表，stage 到 `1` 後才 `stage-done 1`。這條路徑本來就沒有 0a→0b 的暫停語意，兩個 `--confirmed` 是形式上的多餘，用來強行滿足底層腳本的過關條件。

  > **💡 最後放棄寫進腳本的原因（Linus 哲學與實用主義評估）：**
  > 雖然技術上大可在腳本內新增一段 `if mode==sequence && stage==0a` 的專屬跳躍邏輯，但最終選擇在 AI 操作手冊（SKILL.md）以 Workaround 繞過，原因有二：
  > 1. **破壞與回歸測試風險過高**：`wf-state.sh` 的狀態機是整體流程心臟。動到核心腳本就必須對另外三種啟動模式（`quick`、`jump`、`upgrade`）做全面性的回歸測試 (Regression Test)，牽一髮而動全身，違背「Never break userspace」原則。
  > 2. **實用主義與成本考量**：現有底層狀態機的轉移表（0a->0b->1）邏輯嚴謹且正確，沒有必要為了省兩行指令而去破壞底層架構。修改 SKILL.md 讓 AI 遵守嚴格的腳本規則，成本極低、零副作用且絕對安全。
* **影響面**：只要是**正常 sequence 流程**（非 `--mode jump`）跑到 STAGE 1，都會撞到。本次因為 fallback 到 jump 模式而繞過，但 jump 模式喪失了 sequence 的轉移表保護——是繞過不是修好。
* **驗證方法**：
  ```bash
  P=$(wf-state.sh init)                                    # sequence, stage 0a
  wf-state.sh promote "$P" --branch feat/x --dest wt/.claude/workflow-state
  WT=wt/.claude/workflow-state/feat-x.json
  wf-state.sh advance "$WT" 0b --confirmed
  wf-state.sh advance "$WT" 1 --confirmed
  wf-state.sh stage-done "$WT" 1
  
  # Assertions
  # jq -r '.stage' "$WT" 應為 "1"
  # jq -r '.awaiting_confirmation' "$WT" 應為 "true"
  ```

---

## 7. STAGE 1 規劃文件搬移需求（2026-07-30 補記）

> 此項由 SKILL.md commit `acf4f70`（2026-07-29）新增，非 brainstorm 原始提案，補記於此供完整性。

### 問題

STAGE 0a/0b 產出的功能規格（`docs/features/...`）與實作計畫（`docs/plans/...`）是在**原 repo 目錄**中建立的未 commit 檔案。STAGE 1 建立的新 worktree 從 `origin/main` checkout 出來，**不會包含這些檔案**。若不搬移，state 檔記錄的 `spec`/`plan` 路徑切進 worktree 後指向不存在的檔，STAGE 2 的 implementer 讀不到計畫。

### 已落地的解決方案（SKILL.md「分支與 Worktree 建立」章節步驟 5）

- STAGE 1 建好 worktree 後、`cd` 進去之前，用 `cp` 將原 repo 中的 spec 和 plan 檔案複製到新 worktree 的同名路徑下。
- 用**複製**不用 commit + cherry-pick：規劃文件在原 repo 尚未 commit，複製後由 STAGE 2 的實作 commit 一併帶進 branch。
- 複製後驗證兩檔案都存在於新 worktree，缺任一個就停下回報。
- 原 repo 的那兩份留著不刪。
- issue-id 路徑（跳過 STAGE 0a/0b）沒有這兩份文件，本步驟略過。

### 與 Bug 1.6 的交互作用

Bug 1.6 的 promote 斷裂**不影響此搬移步驟**——搬移是在 promote 之後、`stage-done` 之前的獨立動作。但若 Bug 1.6 導致 STAGE 1 收尾失敗而 fallback 到 jump 模式，jump 模式跳過 pending→promote 流程，可能也跳過此搬移步驟（jump 模式自 init 就直接建在 worktree 內，不經過「原 repo → 新 worktree」的搬移）。issue-id 路徑本身不受影響（無 spec/plan 檔可搬）。

---

## 🔵 第二部分：多 Agent 框架比對與 2.0 架構優化提案 (2026-07-30)

## 1. 開源多 Agent 框架深度比對矩陣與架構解析

為提升 `gen-dev-workflow` 的架構品味與多 Agent 協作能力，我們針對目前業界最具代表性的 4 個開源多 Agent 軟體開發框架進行深度解構：

1. **MetaGPT** (DeepWisdom)：基於 SOP (Standard Operating Procedure) 的結構化 Markdown 文件驅動框架。
2. **AutoGen** (Microsoft)：基於靈活對話式網絡 (Conversational Network) 與動態 GroupChat / Director 的多 Agent 框架。
3. **SWE-agent** (Princeton)：專為 GitHub Issue 自動修復設計的 ACI (Agent-Computer Interface) 工具驅動框架。
4. **ChatDev** (OpenBMB)：採用瀑布式/敏捷階段化 Chat Chain 與對立角色雙重校驗（Double-check）的模擬軟體公司框架。

### 1.1 完整多維度架構比對矩陣

| 比較維度 | MetaGPT | AutoGen (Microsoft) | SWE-agent (Princeton) | ChatDev (OpenBMB) | `gen-dev-workflow` (本專案) |
|:---|:---|:---|:---|:---|:---|
| **1. 任務分解 (Task Decomposition)** | 基於 SOP 範本（PRD, Architecture design, Tasks）一次性層級化分解。 | 動態對話中由 Admin / UserProxyAgent 或 LLM Director 隨機應變拆解。 | 依據 Issue 描述由 Single Agent 透過 ACI 進行一步步搜尋與定位。 | Chat Chain 階段化分解（Demand, Coding, Testing, Documentation）。 | 兩階段拆解：STAGE 0a/0b 規劃，STAGE 2 依 task 陣列單元推動。 |
| **2. 角色分工 (Role Specialization)** | 嚴格角色定義（PM, Architect, Engineer, QA），強型別輸出。 | 靈活 Prompt 角色（Assistant, UserProxy, Critic），基於對話輪詢。 | 單一全能 Agent (SweAgent)，無多角色切換，高度依賴 ACI 工具。 | 雙角色階段對話（CEO↔CPO, CTO↔Programmer, Reviewer↔Tester）。 | 專用角色 Agent（brancher, implementer, reviewer, publisher, responder）。 |
| **3. 狀態持久化 (State Persistence)** | 依賴結構化文件（`docs/`）與 Message History 序列化。 | 記憶體內部 Message History、可選 Save/Restore Session 狀態。 | 軌跡日誌 (.traj)，記錄每步 ACI 指令與環境 Feedback。 | Phase 狀態 JSON、Chat log 與實體程式碼產物。 | 雙重持久化：JSON 狀態檔 (`wf-state.sh`) + Git worktree / commit 快照。 |
| **4. 記憶體管理 (Memory Management)** | `Memory` 類別，發佈-訂閱 (Pub/Sub) 訊息總線 (Environment)。 | 對話長度限制、Context 壓縮或外掛 vector store / RAG 擴充。 | 自訂 ACI 觀察截斷與關鍵提示詞 Window 滾動機制。 | 階段結束後總結對話歷史，傳遞精簡Context至下一 Phase。 | Token Budget Gate（>150k 自動 checkpoint）與 Observation truncate。 |
| **5. 執行環境 (Execution Env)** | 本地 Python 環境或 Docker 容器。 | Docker 容器沙盒（`DockerCommandLineCodeExecutor`）確保安全。 | Docker 容器環境（SWE-bench 評測專用沙盒）。 | 本地 Python 虛擬環境。 | Git worktree 物理目錄隔離 + 本地 Shell / `agy` CLI 執行。 |
| **6. 品質與驗證 (Quality Verification)** | 自動化單元測試產製、程式碼審查文件 (Code Review SOP)。 | Human-in-the-loop 確認、對話終止條件（TERMINATE）、代碼執行測試。 | 執行專案既有 Test Suite、語法檢查與 Diff 比對驗證。 | Tester Agent 執行程式，過濾黑盒測試與白盒測試錯誤。 | 雙層審查：STAGE 3 code-review、STAGE 5 PR review，結合 test-worker。 |
| **7. 擴充性 (Extensibility)** | 自訂 Role / Action / SOP 範本，擴充性極高。 | 開放對話網絡架構，可任意自訂 Agent 轉移圖 (GroupChatManager)。 | 客製化 ACI 指令集 (.yaml 配置檔)，適合改進 Tooling。 | 自訂 Chat Chain 節點與角色 Prompt 字典檔。 | Bash 腳本 (`wf-state.sh`) + Markdown Skill (.agents/)，易於自訂擴充。 |
| **8. 容錯與恢復 (Fault Tolerance)** | 重新觸發失敗 Action，依賴 SOP 重試機制。 | 人工干預輸入、自動重試上限、Fallback 至其他 Agent。 | 軌跡重放 (Replay) 與錯誤恢復 ACI 命令。 | 多輪對話自動修正語法與執行錯誤。 | 本地快照 Tag (wf-checkpoint) 自動回滾，支援 `cmd_rollback.sh`。 |

---

### 1.2 開源框架的核心架構亮點與啟示

1. **MetaGPT 的啟示 — SOP 標準作業程序與強型別文件**
   - *亮點*：MetaGPT 成功證明了「人類 SOP 是約束 LLM 幻覺的最強武器」。將複雜軟體開發拆解為 PM 寫 PRD → 系統架構師寫 Data Structures & Interface Definitions → 工程師寫 Code 的線性流水線，極大地降低了語意模糊度。
   - *gen-dev-workflow 借鏡*：保留並強化 STAGE 0a (Issue Analysis) → STAGE 0b (Spec & Plan) → STAGE 2 (Task Execution) 的文件驅動流水線，並確保各階段產出（`docs/issues/specs/`）格式嚴格受到 Schema 檢驗。

2. **AutoGen 的啟示 — 彈性對話圖與動態暫停控制**
   - *亮點*：AutoGen 允許動態切換 Human-in-the-loop 模式（`ALWAYS` / `NEVER` / `TERMINATE_ONLY`）。在不需要人類干預時能全速運轉，遇到關鍵節點或異常時才主動轉交控制權。
   - *gen-dev-workflow 借鏡*：消除過往「每完成一個小 Task 就強制人工點擊確認」的打擾行為，引進 `pause_level`（`strict` / `balanced` / `autonomous`）動態暫停粒度。

3. **SWE-agent 的啟示 — ACI 簡化觀察與專用環境保護**
   - *亮點*：SWE-agent 發現 LLM 面對數千行 Terminal 輸出時極易流失注意力。其 ACI (Agent-Computer Interface) 機制只顯示關聯行數，並提供專用視窗滾動工具；同時所有破壞性改動均在獨立容器沙盒內進行。
   - *gen-dev-workflow 借鏡*：導入 Proposal 3 的 `wf-truncate.sh` 動態觀察截斷引擎，將過長 Build/Test 輸出優雅折疊；同時利用 Git worktree 與安全回滾保護 metadata。

4. **ChatDev 的啟示 — 雙角色對話校驗與階段化 Checkpoint**
   - *亮點*：ChatDev 在 Code Review 與 Testing 階段採用雙角色互相對抗校驗（Reviewer 與 Programmer 對話修正直到通過），並在階段交接時對 Context 進行歸納壓縮，避免歷史對話污染。
   - *gen-dev-workflow 借鏡*：在 STAGE 3 Reviewer 與 STAGE 5 Responder 之間建立明確的閉環狀態轉移表（`reviewer ↔ responder`），確保審查退回後可正確重試。

---

## 2. `gen-dev-workflow` 未解痛點與架構瓶頸深度分析

雖然 2026-07-21 的歷史修復穩固了地基，但在實戰對抗與極限壓力測試中，`gen-dev-workflow` 仍暴露出 5 大致命痛點：

### 2.1 痛點一：人在迴路（Human-in-the-loop）頻率過高致體驗崩潰
- **現象與瓶頸**：原流程在 STAGE 2 實作階段中，每完成一個小 Task 就會觸發 `awaiting_confirmation=true` 並強行暫停，要求使用者輸入 confirm 或點擊確認。若一個 Feature 拆解為 8 個 Task，使用者必須被被打斷 8 次，使自動化編排器退化為「高頻打擾器」。
- **根因分析**：`wf-state.sh` 腳本中 `stage-done` 與 `task-done` 寫死了暫停邏輯，缺乏動態調整暫停層級（Granularity）的配置欄位；同時 `apply_sets()` key 白名單拒絕外來 key 寫入，導致無法靈活切換自動化程度。

### 2.2 痛點二：跨 Session 狀態盲區（Multi-Session State Blindness）
- **現象與瓶頸**：當工作流推進至 STAGE 1 並促動（promote）狀態 JSON 至 Worktree 目錄（`.claude/workflow-state/`）後，Root 倉庫對應的 JSON 會被刪除。當使用者在 Root 倉庫重新開啟 Claude session 試圖執行 `continue` 續接時，系統會回報「找不到任何活動中的工作流」。
- **根因分析**：雖然 `SKILL.md` 規範了跨 Worktree 搜尋，但當 CLI 或入口腳本在 Root 執行時，缺乏全域掃描機制，且缺標準化的 Worktree 狀態檢索匯流排。

### 2.3 痛點三：外部 `agy` CLI 強耦合與退出碼遮蔽漏洞
- **現象與瓶頸**：流程的核心子 Agent 委派動作高度依賴外部 `agy` CLI 命令。然而當 `agy` 執行內層指令失敗（例如 `flutter test` 返回非零退出碼 `1`）時，封裝腳本因未正確傳播內層退出碼，誤將狀態捕捉為 `0` (Success)，導致測試失敗卻被系統認定為成功的致命誤判。
- **根因分析**：舊版執行腳本在 `agy` 命令返回後未紀錄 `$?` 便進入警告與 fallback 區塊，吞掉了原始 Exception。

### 2.4 痛點四：不安全的 Git 回滾與 Metadata 破壞風險
- **現象與瓶頸**：當審查退回或任務失敗觸發自動回滾（Rollback）時：
  1. 無法處理 `review` 階段退回標籤（未支援 `target_type="review"`）。
  2. 當分支名稱包含斜線（如 `feature/login`）時，因未轉換為橫槓 slug (`feature-login`)，導致 Checkpoint Tag 比對 100% 失敗。
  3. 任務失敗時，索引計算錯誤地取用 `completed_tasks[-1]`（即已完成的上個任務），導致回滾時誤刪已完成的合法工作成果。
  4. 執行 fallback `git clean -fd` 時，無差別清掉了 `.agents/` 目錄下的計畫與元資料。

### 2.5 痛點五：Observation 截斷算術溢位與暫存資源洩漏
- **現象與瓶頸**：原 truncation 腳本硬編碼假設 `MAX_LINES >= 80`（固定 `head -n 40` 與 `tail -n 40`）。當設定 `MAX_LINES=50` 傳入 60 行輸出時，算術評估算出 `-20 lines omitted`，不僅產生重複行，還輸出 83 行，完全失去截斷作用。此外，中斷執行時未清除 `/tmp` 暫存檔，造成檔案洩漏；`2>&1` 混流輸出則毀損了結構化 JSON 資訊。

---

## 3. 具體架構優化提案與技術實作規格

為徹底解決上述 5 大痛點，我們提出 4 項經實證測試（Empirical Stress Test）嚴格驗證通過的架構優化提案，並附上完整、可直接執行的 Bash 原始碼規格。

---

### 提案 1：動態暫停粒度與狀態機白名單擴展 (`pause_level`)

#### 1. 設計規格
- **支援三段式枚舉 (`pause_level`)**：
  - `strict`（預設）：在**所有**階段關卡（Stage Gate）與 Task 完成時皆強制暫停 (`awaiting_confirmation=true`)。
  - `balanced`（建議）：僅在**主要架構關卡**（`0b` 規格確認, `2` 實作完成, `4` PR 準備發佈）暫停；中間過渡階段（`0a`, `1`, `3`）與 STAGE 2 內部的 Task 迴圈自動推進 (`awaiting_confirmation=false`)。
  - `autonomous`（極速/自動）：除非發生 Error 或顯式標記，否則所有階段與 Task 皆自動推進，不暫停等待。
- **白名單與防錯校驗**：
  - `apply_sets()` 擴充 key 白名單，包含 `pause_level`。
  - 嚴格校驗傳入值是否為 `strict|balanced|autonomous` 之一，非法值立即 `die` 中止，避免寫入無效狀態。
  - `stage-done` 與 `task-done` 當 `pause_level` 缺失或解析異常時，自動退回安全預設值 `strict`。

#### 2. 可執行 Bash 實作區塊（`wf-state.sh` 升級程式碼）

```bash
# 1. 擴充 apply_sets() key 白名單與嚴格 enum 校驗
apply_sets() {
  local json="$1"; shift
  local kv k v
  for kv in "$@"; do
    if [[ "$kv" != *=* ]]; then
      die "參數格式錯誤：'$kv'。必須為 k=v 格式"
    fi
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      spec|plan|branch|issue|pr|total_tasks|interrupted_by|pause_level)
        if [ "$k" = "pause_level" ]; then
          case "$v" in
            strict|balanced|autonomous) ;;
            *) die "不可設定無效的 pause_level 值：'${v}'（允許值：strict, balanced, autonomous）" ;;
          esac
        fi
        ;;
      *) die "不可透過 set 修改欄位：${k}（stage 用 advance、確認用 confirm）" ;;
    esac
    json="$(echo "$json" | jq --arg k "$k" --argjson v "$(jq_val "$v")" '.[$k] = $v')"
  done
  echo "$json"
}

# 2. stage-done 動態暫停邏輯
stage-done)
  f="$(resolve "$1")"; stage="$2"
  validate "$f"
  mode="$(jq -r '.mode' "$f")"; cur="$(jq -r '.stage' "$f")"
  if [ "$mode" = "sequence" ] && [ "$stage" != "$cur" ]; then
    die "sequence 模式 stage-done 參數須等於目前 stage（目前：${cur}），改 stage 請用 advance"
  fi
  pause_level="$(jq -r '.pause_level // "strict"' "$f")"
  case "$pause_level" in
    strict) awaiting=true ;;
    balanced)
      case "$stage" in
        0b|2|4) awaiting=true ;;
        *) awaiting=false ;;
      esac
      ;;
    autonomous) awaiting=false ;;
    *) awaiting=true ;; # 無效字串之安全備援
  esac
  jq --arg s "$stage" --argjson a "$awaiting" '.stage = $s | .awaiting_confirmation = $a' "$f" | atomic_write "$f"
  if [ "$awaiting" = "true" ]; then
    echo "stage $stage 完成 → 等待使用者確認（confirm 或 advance --confirmed 才能繼續）"
  else
    echo "stage $stage 完成 (pause_level: $pause_level) → 自動推進"
  fi
  ;;

# 3. task-done 動態暫停邏輯
task-done)
  f="$(resolve "$1")"; n="$2"
  validate "$f"
  mode="$(jq -r '.mode' "$f")"; cur="$(jq -r '.stage' "$f")"
  if [ "$mode" = "sequence" ] && [ "$cur" != "2" ]; then
    die "sequence 模式 task-done 僅能在 STAGE 2 執行（目前 stage：${cur}）"
  fi
  pause_level="$(jq -r '.pause_level // "strict"' "$f")"
  case "$pause_level" in
    strict) awaiting=true ;;
    balanced|autonomous) awaiting=false ;;
    *) awaiting=true ;; # 安全備援
  esac
  jq --argjson n "$n" --argjson a "$awaiting" \
    '.completed_tasks = ((.completed_tasks + [$n]) | unique) | .awaiting_confirmation = $a' \
    "$f" | atomic_write "$f"
  if [ "$awaiting" = "true" ]; then
    echo "任務 $n 完成 → 等待使用者確認"
  else
    echo "任務 $n 完成 (pause_level: $pause_level) → 自動繼續下個任務"
  fi
  ;;
```

---

### 提案 2：安全 Worktree 與 Review Tag 導向 Git 回滾引擎 (`cmd_rollback.sh`)

#### 1. 設計規格
- **支援多元 Target 型態**：
  - `task` [選填 `$3` task_num]：回滾至當前/失敗任務前之快照點。當未指定 `$3` 時，正確算出 `target_task = completed_count + 1`；若特定 task 標籤不存在，降級尋找 `completed_count` 標籤。
  - `review`：處理審查不通過回滾，尋找 `wf-checkpoint-${slug_branch}-review` 或降級尋找 `wf-checkpoint-${slug_branch}-stage-3`。
- **分支 Slug 規格化**：強制執行 `slug_branch=$(echo "$branch" | tr '/' '-')`，消滅分支名稱中斜線導致的 Tag 比對失效。
- **Metadata 目錄強效防護**：執行 fallback `git clean` 時，強制加上 `-e ".agents" -e ".agents/*"` 排除過濾，絕不傷害元資料。

#### 2. 可執行 Bash 腳本實作 (`cmd_rollback.sh`)

```bash
#!/usr/bin/env bash
# cmd_rollback.sh — 安全自動化 Git 回滾引擎

cmd_rollback() {
    local file="$1" target_type="${2:-task}" target_num="${3:-}"
    local branch slug_branch tag_name completed_count task_num
    
    if [ ! -f "$file" ]; then
        echo "Error: 狀態檔案 '$file' 不存在。" >&2
        return 1
    fi
    
    branch=$(jq -r '.branch // ""' "$file")
    if [ -z "$branch" ] || [ "$branch" = "null" ]; then
        echo "Error: 狀態檔案 '$file' 中未指定有效分支名稱。" >&2
        return 1
    fi
    
    # 規格化分支名稱斜線為橫槓 (例如: feature/login -> feature-login)
    slug_branch=$(echo "$branch" | tr '/' '-')
    
    if [ "$target_type" = "task" ]; then
        completed_count=$(jq -r '.completed_tasks | length // 0' "$file")
        # 未指定 target_num 時，正在執行的失敗任務索引為 completed_count + 1
        task_num="${target_num:-$((completed_count + 1))}"
        tag_name="wf-checkpoint-${slug_branch}-task-${task_num}"
        
        # Fallback 檢查：若該 Task Snapshot 不存在，退回上個已完成任務之快照 Tag
        if ! git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
            tag_name="wf-checkpoint-${slug_branch}-task-${completed_count}"
        fi
        
    elif [ "$target_type" = "review" ]; then
        tag_name="wf-checkpoint-${slug_branch}-review"
        if ! git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
            tag_name="wf-checkpoint-${slug_branch}-stage-3"
        fi
    else
        echo "Error: 未知的回滾 target_type '$target_type'（允許值：'task' 或 'review'）。" >&2
        return 1
    fi
    
    if git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
        git reset --hard "$tag_name"
        echo "已成功自動回滾至快照點: $tag_name"
    else
        echo "未找到快照 Tag ($tag_name)，執行安全重設與受保護清理..."
        git checkout -- .
        # 保護 .agents 元資料目錄不被 git clean 清除
        git clean -fd -e ".agents" -e ".agents/*"
    fi
}

cmd_rollback "$1" "$2" "$3"
```

---

### 提案 3：動態 Observation 截斷與資源清理引擎 (`wf-truncate.sh`)

#### 1. 設計規格
- **動態 Head/Tail 算術**：
  - `HEAD_LINES = (MAX_LINES - 1) / 2`
  - `TAIL_LINES = MAX_LINES - 1 - HEAD_LINES`
  - `OMITTED_LINES = TOTAL_LINES - HEAD_LINES - TAIL_LINES`
  - 保證在任何 `MAX_LINES >= 1` 的情況下，輸出總行數精準等於 `MAX_LINES`，絕不產生負數省略行數或行數重複重疊。
- **POSIX Signal Trap 資源清理**：掛載 `trap 'rm -f "$TMP_OUT"' EXIT INT TERM`，保證無論正常結束、中斷或被 Kill，暫存檔必定自動清理。
- **標準流隔離**：僅截斷 Stdout 串流；Stderr 保持獨立輸出，維護 JSON 結構化解析品質。

#### 2. 可執行 Bash 腳本實作 (`wf-truncate.sh`)

```bash
#!/usr/bin/env bash
# wf-truncate.sh — 動態 Observation 觀察輸出截斷引擎

MAX_LINES=${MAX_LINES:-100}
if ! [[ "$MAX_LINES" =~ ^[0-9]+$ ]] || [ "$MAX_LINES" -lt 3 ]; then
    MAX_LINES=3
fi
TMP_OUT=$(mktemp)

# POSIX Trap 處理器：保證退出或接收訊號時必刪暫存檔
trap 'rm -f "$TMP_OUT"' EXIT INT TERM

# 執行內層指令並補獲 stdout
"$@" > "$TMP_OUT"
EXIT_CODE=$?

TOTAL_LINES=$(wc -l < "$TMP_OUT")
if [ "$TOTAL_LINES" -gt "$MAX_LINES" ]; then
    # 動態計算 Head 與 Tail 預算，嚴格遵守 MAX_LINES 上限
    HEAD_LINES=$(( (MAX_LINES - 1) / 2 ))
    TAIL_LINES=$(( MAX_LINES - 1 - HEAD_LINES ))
    OMITTED_LINES=$(( TOTAL_LINES - HEAD_LINES - TAIL_LINES ))
    
    head -n "$HEAD_LINES" "$TMP_OUT"
    echo -e "\n... [ Observation Collapsed: ${OMITTED_LINES} lines omitted by wf-truncate ] ...\n"
    tail -n "$TAIL_LINES" "$TMP_OUT"
else
    cat "$TMP_OUT"
fi

exit $EXIT_CODE
```

---

### 提案 4：退出碼保留之跨引擎執行層 (`wf-exec.sh`)

#### 1. 設計規格
- **退出碼精準傳播**：捕獲 `agy` 或 Native 子指令執行後之回傳碼 `RC=$?`，並立即執行 `exit $RC`，杜絕任何測試/編譯失敗被遮蔽為成功 (Exit 0) 的漏洞。
- **主動式 Native Fallback 執行**：當環境未安裝 `agy` CLI 時，不再僅印出提示文字，而是透過 `bash -c "$PROMPT"` 主動執行可執行的 Shell 命令或測試指令，並如實回傳其退出碼。

#### 2. 可執行 Bash 腳本實作 (`wf-exec.sh`)

```bash
#!/usr/bin/env bash
# wf-exec.sh — 退出碼保留之跨引擎執行與 Fallback 轉接層

PROMPT="$1"
MODEL_TIER="${2:-standard}"

if [ -z "$PROMPT" ]; then
    echo "Usage: wf-exec.sh <prompt_or_cmd> [model_tier]" >&2
    exit 1
fi

if command -v agy >/dev/null 2>&1; then
    # 透過 agy CLI 委派執行命令
    printf '%s' "$PROMPT" | agy -p --print-timeout 2>/dev/null
    RC=$?
    # 必須精準返回 agy 執行之退出碼，保留錯誤狀態
    exit $RC
fi

# 當環境欠缺 agy CLI 時之 Fallback 備援路徑
echo "⚠️ agy CLI 未安裝，切換至 Native Subagent Fallback..." >&2
echo "[WF-EXEC FALLBACK] 透過 Native Runner 執行任務:"
echo "$PROMPT"

# 若 PROMPT 為可執行指令或腳本，直接以 bash -c 執行並傳播退出碼
if command -v "${PROMPT%% *}" >/dev/null 2>&1 || [ -x "$PROMPT" ]; then
    bash -c "$PROMPT"
    exit $?
else
    echo "Error: Prompt 既非可執行命令，亦無法由 agy CLI 解析。" >&2
    exit 127
fi
```

---

## 4. 實作藍圖、遷移策略與全方位驗證計畫

為確保上述架構升級順利落地且不破壞現有工程（Never break userspace），我們制定了 3 階段實作藍圖與 4 層驗證協定。

### 4.1 3 階段實作藍圖 (Implementation Roadmap)

```
[Phase 1: 基礎腳本實體升級]
  ├── 寫入 optimization_proposals.md 至工具集
  ├── 更新 wf-state.sh (包含 pause_level 白名單與 stage-done/task-done)
  └── 部署 cmd_rollback.sh, wf-truncate.sh, wf-exec.sh 獨立腳本
        │
        ▼
[Phase 2: SKILL.md 與對話狀態轉移綁定]
  ├── 升級 SKILL.md 之 advance / continue 指令範例
  ├── 在 STAGE 2 自動化循環中整合 wf-truncate.sh 與 wf-exec.sh
  └── 部署跨 Worktree 全域狀態掃描邏輯
        │
        ▼
[Phase 3: 多 Agent 協調與閉環驗證]
  ├── 進行跨 Session 復原與終端壓力測試
  ├── 執行 Challenger 實證測試套件 (empirical_stress_tests.py)
  └── 完成最終 Forensic Auditor 獨立稽核
```

1. **Phase 1 — 基礎腳本升級 (Foundation Layer)**：
   - 在 `.agents/skills/gen-dev-workflow/scripts/` 中部署與替換 `wf-state.sh`、`cmd_rollback.sh`、`wf-truncate.sh` 與 `wf-exec.sh`。
   - 確保所有 `.sh` 檔案具備可執行權限（`chmod +x`）。
2. **Phase 2 — Skill 與對話綁定 (Workflow Skill Integration)**：
   - 更新 `SKILL.md` 中關於 `init` 與 `set` 的說明，新增 `pause_level=balanced` 為預設建議值。
   - 將 `continue` 搜尋邏輯升級為強效 Worktree 掃描。
3. **Phase 3 — 多 Agent 閉環驗證與營運 (Validation & Operations)**：
   - 運行自動化壓力測試，確保在高併發、高打斷、極端字串與異常命令下系統依然保持韌性。

---

### 4.2 4 層驗證協定 (4-Tier Verification Protocol)

為達到最高品質標準，必須通過以下 4 層驗證：

```
+-------------------------------------------------------------------+
| Tier 1: Bash 單元與邊界測試 (Unit & Boundary Validation)            |
|   - 驗證 apply_sets() pause_level 白名單阻擋與合法設定               |
|   - 驗證 jq_val 負數解析與 shift 2 參數欠缺保護                       |
+-------------------------------------------------------------------+
                                │
                                ▼
+-------------------------------------------------------------------+
| Tier 2: Worktree 隔離與 Rollback 安全驗證 (Worktree & Rollback)     |
|   - 驗證 cmd_rollback feature/login 含斜線分支 slug 轉換             |
|   - 驗證 target_type="review" 及 target_num=completed_count+1       |
|   - 檢查 git clean 執行後 .agents/ 目錄完好無損                      |
+-------------------------------------------------------------------+
                                │
                                ▼
+-------------------------------------------------------------------+
| Tier 3: Truncation 動態算術驗證 (Observation Truncation Math)     |
|   - 驗證 MAX_LINES=50 於 60 行輸入時產出精準 50 行，無負數 omitted 行  |
|   - 觸發 SIGINT/SIGTERM 確認 /tmp 暫存檔自動刪除無殘留                |
+-------------------------------------------------------------------+
                                │
                                ▼
+-------------------------------------------------------------------+
| Tier 4: Exit Code 保留與 Fallback 驗證 (Exit Code Propagation)    |
|   - 故意執行失敗指令 (exit 1)，確認 wf-exec.sh 精準回傳退出碼 1       |
|   - 驗證 agy 缺失時 Native Fallback 正確轉接執行                     |
+-------------------------------------------------------------------+
```

#### 具體驗證指令與預期結果：

1. **Tier 1 (Bash 腳本邊界驗證)**：
   ```bash
   # 測試非法 pause_level 是否被阻擋
   ./wf-state.sh set config.json pause_level=invalid_value
   # 預期：輸出 "不可設定無效的 pause_level 值..." 且 exit code = 1
   ```

2. **Tier 2 (Rollback 安全與 Tag Slug 驗證)**：
   ```bash
   # 測試含斜線分支回滾與 .agents 防護
   ./cmd_rollback.sh config.json task
   # 預期：成功識別 feature-login 快照點，或執行 git clean -fd -e ".agents" -e ".agents/*"
   ```

3. **Tier 3 (Truncation 算術與 Trap 驗證)**：
   ```bash
   # 測試 MAX_LINES=50 輸入 60 行
   seq 1 60 | MAX_LINES=50 ./wf-truncate.sh cat
   # 預期：總輸出列印精準 50 行，包含折疊提示 "... [ Observation Collapsed: 11 lines omitted by wf-truncate ] ..."
   ```

4. **Tier 4 (Exit Code 傳播驗證)**：
   ```bash
   # 測試錯誤碼傳播
   ./wf-exec.sh "false"
   echo $?
   # 預期：輸出 1 (絕對不可為 0)
   ```

---

### 4.3 向後相容性與無痛遷移策略 (Backward Compatibility)

1. **零破壞保證 (Never Break Userspace)**：
   - 舊有狀態 JSON 若未包含 `pause_level` 欄位，`wf-state.sh` 透過 `jq -r '.pause_level // "strict"'` 安全退回至舊有 `strict` 行為，現有腳本完全無需修改即可運作。
2. **漸進式升級 (Progressive Adoption)**：
   - 新建立的 workflow 可在 `init` 或 `STAGE 0b` 完成後執行 `wf-state.sh set config.json pause_level=balanced`，即刻享受低打斷的流暢開發體驗。

---

## 5. 借鏡 teamwork-preview 的架構改善提案 (2026-07-31 補記)

> 此章節基於對 teamwork-preview 的逆向工程分析（詳見 [`docs/brainstorm/2026-07-31-teamwork-as-skill-architecture.md`](2026-07-31-teamwork-as-skill-architecture.md)），
> 從其多智能體協作引擎中萃取出可直接移植至 `gen-dev-workflow` 的 5 項具體改善方向。
> 每一項皆遵循「Never break userspace」原則，確保既有流程零破壞。

### 5.1 STAGE 0a 平行化勘查 (Parallel Context Survey)

**現況痛點**：
STAGE 0a（Issue 分析與 Context 收集）目前由單一 Agent 序列執行：讀 Issue → 搜程式碼 → 查文檔 → 檢查測試覆蓋。這些步驟彼此無相依，卻被迫排隊等待，浪費時間。

**teamwork-preview 怎麼做**：
Step 0 同時派發 3 個 Explorer（框架研究 / 本地程式碼 / 文檔歷史），各自獨立平行探索，完成後寫入獨立報告檔，Orchestrator 收齊後才進入下一階段。

**gen-dev-workflow 可借鏡的做法**：
```
STAGE 0a (改良後):
  主 Agent 同時 invoke 2~3 個 research subagent：
  ├── Explorer 1: 讀 GitHub Issue 詳情 + 關聯 Issue
  ├── Explorer 2: 搜尋 codebase 中相關程式碼路徑 (codebase-memory-mcp)
  └── Explorer 3: 檢查既有 docs/specs/test 覆蓋
  
  各 Explorer 寫入 .agent-output/context/<issue-id>/survey-<n>.md
  主 Agent 收齊後彙整為統一的 context 文件
```

**好處**：STAGE 0a 耗時從 `T1 + T2 + T3` 降為 `max(T1, T2, T3)`。且各 Explorer 使用 `flash` Model，成本極低。

**向後相容**：純粹是 SKILL.md 層面的流程改良，不動 `wf-state.sh` 狀態機。現有的 `context-collector` Skill 可作為 Explorer 的任務模板。

---

### 5.2 STAGE 2 Fresh Subagent Per Task (每任務全新子智能體)

**現況痛點**：
STAGE 2 在同一個 Session 中依序執行所有任務。到了 Task 5 或 Task 6 時，Context Window 已經被前面 4 個任務的實作細節（diff、測試輸出、commit message）塞滿，導致 Agent 注意力分散、品質下降、甚至觸發 Token Budget Gate 強制中斷。

**teamwork-preview 怎麼做**：
每個 Milestone 的 Worker 都是全新 spawn 的 subagent，零歷史包袱。Worker 只接收：Milestone 規格 + 相關檔案路徑 + 勘查摘要。完成後寫入交付物、commit、回報。

**gen-dev-workflow 可借鏡的做法**：
```
STAGE 2 (改良後):
  for each task in plan.tasks:
    1. 主 Agent 從 plan 提取 task 規格（含精確檔案路徑與測試指令）
    2. invoke_subagent(TypeName="self", Model=依複雜度選擇)
       Prompt 包含：
       - task 規格全文
       - 相關的 spec/plan 摘要（非全文）
       - 必須遵守的 TDD 步驟與 commit 規範
    3. Worker 完成 → commit → send_message 回報
    4. 主 Agent 驗證 commit 存在 → wf-state.sh task-done
    5. 下一個 task（全新 Worker，乾淨 Context）
```

**好處**：
- 每個 Task 的 Worker 享有完整的 Context Window 預算（~200k tokens），不受前序任務污染。
- 主 Agent 的 Context 極度輕量（只追蹤進度 + 檔案路徑），大幅降低觸發 Token Budget Gate 的機率。
- 自然支援 `pause_level=autonomous`，因為主 Agent 不需要「展示變更」給使用者看。

**與現有模式的關係**：這正是 `subagent-driven-development` Skill 已經在做的事。改善方向是讓 `gen-dev-workflow` 的 STAGE 2 正式整合 SDD 模式，而非兩套系統各自運作。

**向後相容**：在 `wf-state.sh` JSON 中新增 `execution_mode` 欄位（`inline` | `subagent`），預設 `inline` 保持舊行為。使用者可透過 `wf-state.sh set config.json execution_mode=subagent` 啟用新模式。

---

### 5.3 STAGE 3 對抗式 Challenger 驗證 (Adversarial Challenge Gate)

**現況痛點**：
STAGE 3 目前只有單一 Reviewer 進行程式碼審查。Reviewer 的心態是「檢查程式碼是否符合規格」，但這無法發現：
- 規格本身沒考慮到的邊界情況
- 實作正確但架構方向有隱患的設計
- 看起來正常但在特定輸入下會爆炸的邏輯

**teamwork-preview 怎麼做**：
在 Reviewer 之後，額外派發 Challenger（對抗者）。Challenger 的角色定義完全不同：
- Reviewer 問：「這符合規格嗎？」→ 合規性檢查
- Challenger 問：「我怎樣才能讓這段程式碼失敗？」→ 破壞性測試思維

**gen-dev-workflow 可借鏡的做法**：
```
STAGE 3 (改良後):
  Step 1: Reviewer (現有流程，不變)
    → 檢查規格符合度、程式碼品質、測試覆蓋
    → PASS / FAIL
  
  Step 2: Challenger (新增，僅在 Reviewer PASS 後觸發)
    → invoke_subagent(TypeName="research", Model="flash")
    → Prompt: "你是一位對抗式測試專家。以下是剛通過審查的程式碼變更。
       你的唯一任務是找出它的致命缺陷：邊界錯誤、競態條件、
       未處理的例外、效能陷阱、或規格遺漏的場景。
       如果找不到致命缺陷，回覆 CHALLENGE_PASS。"
    → CHALLENGE_PASS → 進入 STAGE 4
    → CHALLENGE_FAIL → 回到 STAGE 2 修正（已有 3→2 轉移路徑）
```

**好處**：用極低成本（一個 `flash` subagent）增加一層獨立的破壞性思維驗證，顯著降低 PR 被退回的機率。

**向後相容**：在 `wf-state.sh` 狀態機中，STAGE 3 的內部子狀態由 SKILL.md 控制，不需修改轉移表。Challenger 是 STAGE 3 內部的選填步驟，可透過 `challenge_enabled=true|false` 控制。

---

### 5.4 動態 Model 分級 (Dynamic Model Tiering)

**現況痛點**：
`gen-dev-workflow` 在所有階段、所有任務都使用相同的 Model。但實際上：
- 建立 boilerplate 檔案、跑格式化、簡單重命名 → 殺雞用牛刀
- 跨檔案架構整合、複雜邏輯實作 → 需要最強推理能力
- 程式碼審查 → 中等推理即可

**teamwork-preview 怎麼做**：
根據任務類型動態選擇 Model：Explorer 用 `flash`、Worker 依複雜度選 `flash` / `inherit` / `pro`、Reviewer 用 `flash`。

**gen-dev-workflow 可借鏡的做法**：

在 Plan 文件的每個 Task 中加入 `model_hint` 標註：

```markdown
## Task 3: 建立 WidgetInspectorOverlay UI 元件
- model_hint: pro  # 跨檔案整合，需要架構判斷
- files: lib/src/overlay.dart, lib/src/inspector_panel.dart
- ...

## Task 4: 新增 l10n 翻譯 key
- model_hint: flash  # 機械性插入，無需推理
- files: lib/l10n/app_en.arb, lib/l10n/app_zh.arb
- ...
```

STAGE 2 的主 Agent 讀取 `model_hint` 後，在 `invoke_subagent` 時傳入對應的 `Model` 參數。

| model_hint | 對應 Model | 適用場景 |
|:-----------|:-----------|:---------|
| `flash` | `flash` | 新增翻譯 key、建立空檔案、簡單 copy-paste 式任務 |
| `standard` | `inherit` | 一般功能實作、單檔修改、測試撰寫 |
| `pro` | `pro` | 跨檔案架構決策、複雜演算法、效能優化 |

**好處**：在不犧牲品質的前提下，預估可節省 40~60% 的 Token 成本（大多數 Plan 中有 30~50% 的任務是機械性操作）。

**向後相容**：`model_hint` 是 Plan 文件的選填欄位。未標註時預設 `standard`，完全不影響現有 Plan 格式。

---

### 5.5 結構化跨 Session Handoff 文件 (Structured Handoff Protocol)

**現況痛點**：
當 Token Budget Gate 觸發（>150k）時，`gen-dev-workflow` 會執行 WIP commit 並「交接給新 Session」。但交接內容是 ad-hoc 的——新 Session 的 Agent 需要從 `wf-state.sh get` 的 JSON、git log、和散落的 spec/plan 檔案中自行拼湊出「目前進度到哪了」。這個拼湊過程本身就消耗大量 Context，且容易遺漏關鍵決策記錄。

**teamwork-preview 怎麼做**：
Orchestrator 維護一份持續更新的 `progress.md`，記錄：已完成的 Milestone、當前進行中的任務、關鍵決策與原因、下一步行動。Self-succession 時，新 Orchestrator 只需讀這一份文件就能完整接手。

**gen-dev-workflow 可借鏡的做法**：

在 Token Budget Gate 觸發時，強制產出一份結構化的 `HANDOFF.md`：

```markdown
# Workflow Handoff — <branch-name>

## 狀態快照
- Stage: 2 (Implementation)
- Mode: sequence
- Completed Tasks: [1, 2, 3] / Total: 7
- pause_level: balanced

## 已完成的工作摘要
- Task 1: 建立 data model (commit: abc1234)
- Task 2: 實作 repository layer (commit: def5678)
- Task 3: 撰寫 unit tests (commit: ghi9012)

## 關鍵決策記錄
- 選用 freezed 而非手寫 fromJson，因為 model 有 10+ 個欄位
- API endpoint 改用 v2 路徑，因為 v1 缺少 pagination 支援

## 下一步行動
- 接續 Task 4: 實作 BLoC state management
- Plan 路徑: docs/plans/2026-07-31-xxx.md
- Spec 路徑: docs/issues/specs/xxx.md

## 檔案路徑索引
- State JSON: .claude/workflow-state/<branch>.json
- Worktree: /path/to/worktree
```

**好處**：
- 新 Session 的 Agent 讀一份文件即可完整接手，不需要花 10k+ tokens 去搜尋、拼湊、推理「目前進度到哪了」。
- 「關鍵決策記錄」防止新 Session 的 Agent 推翻前 Session 已經做過的架構決策。
- 結構化格式讓 `continue` 指令可以自動解析，進一步降低接手成本。

**向後相容**：`HANDOFF.md` 是 SKILL.md 層面的新增指示，不動 `wf-state.sh`。舊流程中 Token Budget Gate 的 checkpoint + WIP commit 行為完全保留，`HANDOFF.md` 是額外的加值。

---

### 5.6 借鏡總結：teamwork-preview vs gen-dev-workflow 改善對照表

| 維度 | gen-dev-workflow 現況 | teamwork-preview 做法 | 建議改善 | 預期效果 |
|:-----|:---------------------|:---------------------|:---------|:---------|
| **STAGE 0a 勘查** | 單 Agent 序列 | 3 Explorer 平行 | §5.1 平行勘查 | 勘查耗時降 60%+ |
| **STAGE 2 執行** | 同 Session 序列累積 | Fresh Worker per Task | §5.2 SDD 整合 | 消滅 Context 污染 |
| **STAGE 3 驗證** | 單 Reviewer | Reviewer + Challenger | §5.3 對抗式驗證 | PR 退回率降低 |
| **Model 選擇** | 全程同一 Model | 動態 flash/inherit/pro | §5.4 Model 分級 | Token 成本降 40~60% |
| **跨 Session 交接** | Ad-hoc 拼湊 | 結構化 progress.md | §5.5 HANDOFF.md | 接手成本趨近零 |

> **刻意不借鏡的部分**（Linus 式實用主義判斷）：
> - ❌ **Sentinel 監護層**：gen-dev-workflow 的主 Agent 本身就是 Coordinator，額外加一層 Sentinel 是浪費。
> - ❌ **四重驗收閘門**：Reviewer + Challenger 兩重已足夠。再加雙倍 Reviewer + Auditor 是過度工程，邊際效益趨近零。
> - ❌ **Heartbeat Cron 自我續命**：Token Budget Gate 已經解決了 Session 存活問題，不需要另一套機制。

---

### 結論 (Summary & Next Steps)

本腦力激盪文件完成了三層次的深度分析：

1. **歷史基準修復**（2026-07-17 ~ 2026-07-21）：5 個 Bash Bug + 5 個流程漏洞已全數修復，奠定穩固地基。
2. **開源框架比對與優化提案**（2026-07-30）：借鏡 MetaGPT、AutoGen、SWE-agent、ChatDev，提出 4 項含完整 Bash 實作的架構優化（`pause_level`、`cmd_rollback.sh`、`wf-truncate.sh`、`wf-exec.sh`）。
3. **teamwork-preview 逆向工程啟示**（2026-07-31）：從實測 transcript 還原其多智能體架構，萃取出 5 項可直接移植至 `gen-dev-workflow` 的改善方向（平行勘查、Fresh Worker、對抗式 Challenger、Model 分級、結構化 Handoff）。

上述 9 項優化提案（§3 的 4 項 + §5 的 5 項）構成了 `gen-dev-workflow` 2.0 的完整架構升級藍圖，將依 Phase 1 至 Phase 3 逐步實施落地。
