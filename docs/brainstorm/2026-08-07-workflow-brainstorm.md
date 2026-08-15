# gen-dev-workflow 流程優化、多 Agent 框架比對與架構演進總整文件

> **📝 合併紀錄**：
> 本文件整併了 `2026-07-17` 與 `2026-07-30` 的腦力激盪記錄。依據時間軸與完成度，前半部記錄歷史遺留 Bug、流程漏洞的分析與修復；後半部基於系統穩固的基礎，進行開源多 Agent 框架的深度比對，並提出 2.0 架構的具體優化提案。
>
> **2026-08-15 新增第三部分**：**知名開發者的實務工作流比對**（Huntley 的 Ralph、
> HumanLayer 的 ACE-FCA、Harper Reed 三件式、Hashimoto 的 16-session、Kent Beck 的
> Augmented Coding、Böckeler 的 Harness Engineering、Vincent 的 Superpowers，
> 以及 Steinberger 的**反方立場**）。與第二部分的差別：那邊比的是學術框架，這邊比的是
> **具名工程師跑在真實專案上的手工流程**。結論分成「已經有的／真正可學的／刻意不學的」三類，
> 高價值新洞察只有一項：**context 主動維持 40-60%，而非撞到 150k 才剎車**。
>
> **2026-08-16 補記**：(B) 真正可學的 4 項已補上逐項的「現況 → 差距 → 判斷」推導與
> **建議動工順序**（審查槓桿階層 → context 主動巡航 → Guide→Sensor → anti-slop，
> 見 §3(B) 末表）。同時修正 §2.1 Ralph 的標籤（原標「可學」與 §3(C)「刻意不學」自相矛盾，
> 已改為「佐證」並補完整推導）。**四項截至此日全部仍是提案，未動程式碼。**
>
> **🔴 2026-08-10 重大變更：委派傳輸層由 `agy -p` headless 改為 `gemini-mcp-tool`（MCP）。**
> 底層後端不變（`gemini-mcp-tool` 內部就是 antigravity-cli），換掉的是**傳輸層**。
> 這直接推翻了本文件兩處的既有結論——**§2.3 痛點三**（agy 強耦合與退出碼遮蔽）與
> **§3 提案 4 `wf-exec.sh`**（原被定性為「為一條已不走的路徑寫轉接層」）。
> 委派不是死路，是傳輸層壞掉；換掉之後 orchestrator 模式才第一次真正成立。
> 詳見各節的 2026-08-10 校正註記。
>
> **2026-08-06 補記**：SKILL.md STAGE 6（清理 Worktree）新增「文件同步」前置步驟——執行清理前先呼叫 gen-sync-docs-by-branchs（以當前分支為目標同步文件）→ gen-commit（將同步結果 commit），確保 worktree 移除前 docs 已反映分支最終狀態。此為已落地的流程變更。
>
> **⚠️ 2026-08-06 狀態校正（重要）**：本文件 §5 的 5 項 teamwork-preview 借鏡提案，
> **實查確認全數已落地**（多數走 Claude `Workflow` 工具，而非提案設想的實作形式），
> 文件此前仍將其列為「待實施藍圖」。實際剩餘待辦僅 §3 的 4 支基礎腳本，
> 其中提案 4（`wf-exec.sh`）的前提存疑。**逐項實查證據見文末「📊 落地現況」表**，
> 各節內文亦已加上校正註記。閱讀本文件時請以該表為狀態依據，勿直接採信各節原標。

---

## 🟢 第一部分：歷史基準修復與流程漏洞填補 (2026-07-17 ~ 2026-07-30)

## 0. 完成度總覽（Bug 1.x / Gap 2.1–2.5 核對於 2026-07-21 · Gap 2.6 增補於 2026-08-07）

> 狀態依 [`docs/architecture/2026-08-12-gen-dev-workflow-analysis.md`](../architecture/2026-08-12-gen-dev-workflow-analysis.md) 核對標注。✅ 已修 ｜ 🟡 部分 ｜ ⬜ 待修。（原引用 `docs/features/2026-07-18-...`，該檔已隨文件搬遷／改名不存在。）
>
> **🔍 實查校正 (2026-08-06)**：本註記原寫「`wf-state.sh` 不在本 repo，無法直接讀原始碼，
> 故以該份 analysis 為權威來源」——**此前提已不成立**。該腳本就在本 repo 的
> `.claude/skills/gen-dev-workflow/scripts/wf-state.sh`，**可也應直接讀原始碼核對**，
> 不需再以二手 analysis 文件為權威來源。後續核對本表請以腳本本身為準。

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
| **Gap 2.6** 獨立入口（STAGE 5/6）完全繞過狀態機 | ✅ 已修 | 於 2026-08-14 以方案 A + C 修復：`SKILL.md:146` 首步硬性化、`.claude/hooks/wf-guard-stage-check.sh` 於 `PreToolUse` 攔截 responder 派發、`wf-state.sh:98` 補齊 `4->5` 等轉移路徑（見 §4 Gap 2.6） |

> **已落地的地基**（analysis 確認，非本 brainstorm 提出的待辦）：`wf-state.sh` 已成 state 檔唯一入口——狀態機轉移表（非法轉移 `exit 1`）、暫停點棘輪（無 `--confirmed` 拒絕 `advance`）、`set` 白名單、schema 校驗 + 原子寫入皆已實作。
>
> **結論**：5 個 Bash Bug 及 Gap 2.1–2.5 均已修復（包含 SKILL.md 層面的 2 項與 `wf-state.sh` 腳本層面的 8 項），腳本脆弱性與狀態機**內部**漏洞已解決。其中 Bug 1.5 是 Gap 2.3 修復方案照抄片段時把 `local` 帶進頂層 `case` 分支所造成的回歸，於本次一併抓出並修正。
>
> **⚠️ 2026-08-07 補記（問題已於 2026-08-14 修復，本段保留為設計啟示）**：上述「已徹底解決」的結論**僅在腳本被呼叫的前提下成立**。Gap 2.6 揭露了守衛架構的結構性盲點——獨立入口（STAGE 5/6）可全程不碰 `wf-state.sh`，使所有內部校驗無從觸發。這不是既有修復的回歸，而是先前分析未涵蓋的層級：**對策必須落在入口攔截（hook），繼續往腳本內部堆校驗無效**。
>
> **📌 2026-08-14 結案**：該判斷成立，已依此落地 hook 攔截層（`.claude/hooks/wf-guard-stage-check.sh`），Gap 2.6 已修復。**但此結論的適用範圍不限於 Gap 2.6**——「守衛需要被呼叫才生效」是結構性盲點，同型弱點仍存在於**委派的工作目錄約束**（MCP 無法指定 cwd，只能靠 prompt 寫絕對路徑），詳見 [`docs/architecture/2026-08-08-wf-state-harness-guardrail.md`](../architecture/2026-08-08-wf-state-harness-guardrail.md) §「同構的第二個弱點」。該項尚未有 hook 層對策，目前僅有事後 `git status` 偵測。

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

### Gap 2.6: 獨立入口（STAGE 5/6）完全繞過狀態機 — ⬜ 待修（2026-08-07 實例）

* **漏洞描述**：既有守衛（棘輪、轉移表、任務數校驗）**只在 `wf-state.sh` 被呼叫時才生效**。STAGE 5/6 是不在 `0a→0b→1→2→3→4` 主鏈上的獨立入口，缺少前後階段的銜接慣性，LLM 容易在「處理 review 意見」的任務心智下直接派發 responder/reviewer，**全程不碰腳本**——此時沒有任何機制會察覺流程正在推進。

  這與 Gap 2.3 的失效模式**本質不同**，不可混為一談：
  * Gap 2.3 是「呼叫了 `advance` 但校驗不足」→ 補校驗即可堵住。
  * Gap 2.6 是「**根本沒呼叫腳本**」→ 再多校驗也不會被執行到。棘輪防的是「確認前推進」，防不了「繞過腳本推進」。

* **實例（2026-08-07）**：PR #121 / #123 的 STAGE 5 全程跑完（responder 處理 6 則 inline comments → reviewer 複審 → 額外補修同源問題），四個 commit 已推上遠端，但兩個 worktree 的 state 檔**始終停在 `stage: "4"`、`awaiting_confirmation: true`**，看起來像 STAGE 5 從未發生。同一 session 稍早的 STAGE 2→3 反而被腳本正確擋下（`實作尚未全部完成（已完成 0 / 共 6 任務）`）——差別只在於那次有呼叫 `advance`。

  **連帶損害**：STAGE 5 流程的第三步（publisher 更新 PR 描述）一併被遺漏，因為沒有 state 推進來提示還有後續步驟。若此時換 session 續接，新 session 會誤判 STAGE 5 尚未執行而重跑。

* **解決方案**（建議 A + C 併行，跳過 B）：

  **A. 文件層——獨立入口的首步硬性化**
  在 SKILL.md 的 STAGE 5/6 區塊開頭，把 state 推進寫成不可跳過的第一步而非隱含前提：
  ```
  STAGE 5：回覆 PR Review（獨立入口）
  🔴 第一步（不可跳過）：wf-state.sh advance <檔> 5 --confirmed
     ↑ 未執行此步就派發 responder = 流程違規
  → 呼叫 responder agent...
  ```
  成本最低，但**仍只是叮嚀**——本次違規時 SKILL.md 已寫明正確流程（含 `{ stage: 5, mode: "jump" }` 的寫入指示）卻仍被漏掉，證明純文件層不足以獨立成為對策。

  **B. 腳本層——`assert-stage` 子命令**：❌ **不採用**。
  新增 `wf-state.sh assert-stage <檔> 5`（stage 不符則 exit 1）雖比 A 強，但**與 A 共享同一個失效前提**（都要求 LLM 主動呼叫腳本）。多一個子命令卻換不到實質保障，不划算。

  **C. Hook 層——唯一真正的強制**
  以 `PreToolUse` hook 攔截 `Agent` 工具呼叫：偵測到派發 `responder`/`reviewer`/`publisher` 時，檢查當前 worktree 的 state 檔 stage 是否已推進至對應階段，未推進則**阻擋該次呼叫**並回傳提示。
  * **為何有效**：執行者是 harness 而非 LLM，這是唯一「想繞也繞不過」的層級。
  * **代價**：hook 邏輯需維護；且會誤擋「流程外單獨派發 reviewer 做零星審查」的正當用法——需評估是否加白名單，或退而採「警告但不阻擋」。此取捨需由使用者依實際使用習慣決定。

* **設計啟示**：本 Gap 揭露的是守衛架構的**結構性盲點**，而非單點疏失——「守衛需要被呼叫才生效」。任何未來新增的獨立入口（非主鏈階段）都會重現同一漏洞，因此對策應落在**入口攔截層**，而非繼續往 `wf-state.sh` 內部堆校驗。

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

### 提案 1：動態暫停粒度與狀態機白名單擴展 (`pause_level`) — ✅ 已完成（2026-08-06 · `9bce068`）

> **落地位置**：`wf-state.sh:141` `should_pause()`（單一判定來源）、`:172` enum 校驗、
> `:269`/`:286` 兩個呼叫端；使用者介面見 SKILL.md:179「暫停粒度」與 :872「選項語法」。
> 三處刻意偏離原設計的說明見文末「落地現況」節。下方規格保留作決策紀錄。

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

### 5.1 STAGE 0a 平行化勘查 (Parallel Context Survey) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**，但**載體與原提案不同**——
> 不是「主 Agent 逐個 `invoke_subagent`」，而是走 **Claude `Workflow` 工具的 `parallel()` fan-out**。
> 證據：`.claude/skills/gen-dev-workflow/SKILL.md:722-725` 已有雙線平行 `agent()` 呼叫
> （`收集專案 context：讀 README / pubspec / 近期 git log` + `調查與「<需求>」相似的既有實作`），
> 皆以 `agentType: 'Explore'`（唯讀搜尋）搭配 `model: 'sonnet'` / `effort: 'high'` 執行。
> 另 SKILL.md:21 明列此為 Workflow 三個適用點之一。
>
> **與原提案的三處差異**（皆為刻意調整，非未完成）：
> 1. **2 線而非 3 線**——原提案的 Explorer 1（讀 GitHub Issue）在實際流程中不屬 STAGE 0a
>    的平行範圍（issue 建立在 STAGE 1），故收斂為「專案 context」+「相似實作調查」兩線。
> 2. **不寫 `.agent-output/context/<issue-id>/survey-<n>.md`**——改由 Workflow 的 `schema`
>    直接回傳結構化結果給主指揮聚合，省掉中間檔案的讀寫往返。
> 3. **Model 用 `sonnet` 而非 `flash`**——Claude 側無 `flash` 別名，對應等級見 SKILL.md 的
>    「推論等級表」（唯讀勘查歸「輕量」級）。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
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

### 5.2 STAGE 2 Fresh Subagent Per Task (每任務全新子智能體) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**，且比原提案更進一步——
> 原提案是「逐 task 序列 spawn 全新 Worker」，實作走 **Workflow 的 `pipeline()` 並行**：
> 同一批內寫入路徑不重疊的任務同時派發，每個任務一個全新 subagent。
> 證據：`SKILL.md:739` 的
> `task => agent(task.prompt, {label: task.id, model: task.model, effort: task.effort, isolation: 'worktree', schema: TASK_SCHEMA})`
> ——`isolation: 'worktree'` 即「每任務獨立工作區、零歷史包袱」的 Fresh Worker 語意，
> 且比原提案多解決了「並行任務互相踩檔案」的問題。
>
> **與原提案的差異**：
> 1. **未新增 `execution_mode` 欄位**——原提案設想以 `inline` | `subagent` 切換新舊行為，
>    實作直接讓 Workflow 成為 STAGE 2 的可選加速層（SKILL.md:21 的「可選加速層」定位），
>    不需要在 `wf-state.sh` 增欄位。**這也是為什麼 `wf-state.sh` 的 key 白名單裡查無此欄位——
>    是設計決定，不是漏做。**
> 2. **驗收與實作 model 分離**——SKILL.md:631-637 額外規定驗收固定走 `verifier` agent
>    （`effort: 'xhigh'`），不讓同源 model 自審。這是原提案沒有的加碼。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
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

### 5.3 STAGE 3 對抗式 Challenger 驗證 (Adversarial Challenge Gate) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**，形式為
> 「STAGE 3 多 angle 對抗式審查」（`SKILL.md:747-749`，Workflow 三個適用點之三）。
> 對抗立場已寫進 agent 定義：`.claude/agents/verifier.md:11` —— 「立場是對抗式的——
> 預設實作有問題，盡力證明它錯」。
>
> **與原提案的兩處差異**（皆為刻意調整）：
> 1. **多 lens 平行，而非單一 Challenger 串接**——原提案是 Reviewer PASS 後再跑一個
>    Challenger；實作改為多個 verifier **各帶不同 lens**（correctness / security /
>    回歸風險 / 測試覆蓋 / 過度工程）平行找 bug。理由：對抗式驗證的價值在**視角多樣性**，
>    N 個相同提示的 Challenger 抓到的是同一類問題。
> 2. **verifier 是助手，reviewer 仍是最終判斷者**——不設 `CHALLENGE_PASS` / `CHALLENGE_FAIL`
>    這種獨立閘門，verifier 的 verdict 是輸入，reviewer 收斂後親自寫審查報告
>    （SKILL.md:644 明訂「審查報告 reviewer 親自判斷，不可委派」）。故
>    **`challenge_enabled` 旗標未實作也不需實作**——它是 Workflow 的可選加速層，
>    由主指揮視情況決定是否啟用，不是 state 檔的持久欄位。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
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

### 5.4 動態 Model 分級 (Dynamic Model Tiering) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**且比原提案完整——
> `SKILL.md:584-601` 已有正式的**推論等級表**，`SKILL.md:614` 有各 stage 的等級對照，
> `SKILL.md:619-637` 有 STAGE 2 implementer 內部的逐任務分級與「驗收 model 與實作 model 分離」規則。
>
> **與原提案的三處差異**：
> 1. **等級名而非 model 名**——文件只寫「最強推論 / 標準 / 輕量 / 快便宜」四個**角色等級**，
>    實際 model 別名綁在各 `.claude/agents/*.md` 的 frontmatter。這是刻意的：
>    **換代時只動 agent 檔一行**，不必回頭改流程文件（SKILL.md:584 明述此為降低維護成本的核心）。
>    原提案的 `flash` / `inherit` / `pro` 是 teamwork-preview 的 model 名，Claude 側不適用。
> 2. **effort 與 model 拆成兩個維度**——原提案只有 model 一維；實作額外把 `effort`
>    （`xhigh` / `max` / `high`）從 frontmatter 移出、改為派發時顯式帶入，
>    形成 model × effort 的二維分級。
> 3. **未使用 `model_hint` 欄位名**——plan 文件標的是「複雜度等級」，由 STAGE 2 對照
>    推論等級表換算，語意等價。
>
> ⚠️ **已知風險（SKILL.md:603 記載，未完全排除）**：`effort: 'xhigh'` 在 thinking 未開啟時，
> 於 Opus 4.8 上曾實際遇到 `400 output_config.effort 'xhigh' is not supported`。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
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

### 5.5 結構化跨 Session Handoff 文件 (Structured Handoff Protocol) — ✅ 需求已覆蓋 · ❌ 不採用 `HANDOFF.md` 形式（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：全專案**查無 `HANDOFF.md`**，但本節要解決的問題
> **已由另一套機制覆蓋**：`SKILL.md:545-575` 的「context 超標切 session 閉環」。
> 該機制以 **per-branch state 檔 + `interrupted_by=context_budget` + 帶交接筆記的 WIP commit**
> 達成同一目的，且續接時自動辨識、不問使用者「繼續還是開新流程」。
>
> **為何不另建 `HANDOFF.md`（品味判斷）**：原提案的四個區塊，三個在既有 state 檔裡**已經有了**——
>
> | HANDOFF.md 區塊 | 既有覆蓋處 |
> |:---|:---|
> | 狀態快照（stage / mode / completed_tasks） | state JSON 的同名欄位，`wf-state.sh get` 直接讀 |
> | 已完成工作摘要（task → commit） | `completed_tasks` + git log |
> | 檔案路徑索引（state / worktree / spec / plan） | state JSON 的 `spec` / `plan` / `branch` 欄位 |
> | **關鍵決策記錄** | **WIP commit message 的交接筆記**（SKILL.md:561：「做到哪、下一步打算做什麼、為什麼選這個作法」） |
>
> 另開一份 `HANDOFF.md` 等於把同一份狀態寫成兩份，兩份必然漂移——
> 而漂移的交接文件比沒有交接文件更危險（新 session 會信任它）。
> 唯一原本沒有的「關鍵決策記錄」已收進 WIP commit message，
> 理由是**決策與產生它的那次 commit 綁在一起才不會失聯**，比獨立檔案更不容易腐爛。
>
> **結論**：本節**不列入待辦**。若未來 state JSON 的欄位確實不夠用，正確做法是**擴充 state schema**
> （單一事實來源），而非新增第二份文件。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
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

> **🔍 實查校正 (2026-08-06)**：本表原記錄的是 2026-07-31 的「現況 vs 建議」。
> 逐項實查 `.claude/skills/gen-dev-workflow/` 後確認 **5 項全數已處理**，
> 下表已改為「提案 → 實際落地形式」對照。原始的痛點分析保留在各節內文。

| 維度 | 2026-07-31 提案 | **實際落地形式（2026-08-06 實查）** | 狀態 |
|:-----|:---------------|:----------------------------------|:---:|
| **STAGE 0a 勘查** | 3 Explorer 平行 + 寫 survey 檔 | Workflow `parallel()` 雙線 `agent()`，`agentType: 'Explore'`，結構化 schema 直接回傳（SKILL.md:722-725） | ✅ |
| **STAGE 2 執行** | 逐 task 序列 spawn Fresh Worker | Workflow `pipeline()` 並行 + `isolation: 'worktree'` 每任務獨立工作區（SKILL.md:739） | ✅ |
| **STAGE 3 驗證** | Reviewer 後串接單一 Challenger | 多 verifier **各帶不同 lens** 平行對抗，reviewer 收斂後親自判斷（SKILL.md:747-749、verifier.md:11） | ✅ |
| **Model 選擇** | `model_hint` → flash/inherit/pro | 推論等級表（4 級），model 綁 agent frontmatter + effort 派發時帶入的**二維**分級（SKILL.md:584-637） | ✅ |
| **跨 Session 交接** | 獨立 `HANDOFF.md` | **改以 state 檔 + WIP commit 交接筆記覆蓋**，不另建文件（避免雙份狀態漂移，見 §5.5） | ✅ 需求已覆蓋 |

> **共通模式**：5 項中有 4 項的落地載體是 **Claude `Workflow` 工具**而非原提案設想的
> bash 腳本或 `invoke_subagent` 迴圈。這是提案後才出現的能力，回頭看反而更貼合需求——
> 並行、結構化回傳、worktree 隔離都是內建的，不必自己造。
> **教訓：架構提案寫的是「要解決什麼」，落地時該重新挑當下最省的載體，不必照抄提案的實作形式。**

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

上述 9 項優化提案（§3 的 4 項 + §5 的 5 項）構成了 `gen-dev-workflow` 2.0 的完整架構升級藍圖。

---

### 📊 落地現況（2026-08-06 實查於 `.claude/skills/gen-dev-workflow/`）

| 提案 | 狀態 | 實查證據 |
|:-----|:---:|:---------|
| §5.1 平行勘查 | ✅ 已完成 | SKILL.md:722-725 Workflow 雙線 `agent()` |
| §5.2 Fresh Worker | ✅ 已完成 | SKILL.md:739 `pipeline()` + `isolation: 'worktree'` |
| §5.3 對抗式驗證 | ✅ 已完成 | SKILL.md:747-749、`.claude/agents/verifier.md:11` |
| §5.4 Model 分級 | ✅ 已完成 | SKILL.md:584-637 推論等級表 |
| §5.5 Handoff | ✅ 需求已覆蓋 | SKILL.md:545-575 state 檔 + WIP commit 交接（不採 `HANDOFF.md`） |
| §3 提案 1 `pause_level` | ✅ **已完成**（2026-08-06 · `9bce068`） | `wf-state.sh:141` `should_pause()` 單一判定來源；`:172` `apply_sets()` 白名單含 `pause_level` + enum 校驗；`:269`/`:286` 為 `stage-done`/`task-done` 兩個呼叫端；SKILL.md:179 暫停粒度章節、:872 選項語法 |
| **批次佇列**（非原提案，2026-08-06 新增） | ✅ **已完成**（`9bce068`） | `wf-state.sh:349-430` `batch-init`/`batch-get`/`batch-next`/`batch-done`/`batch-fail`/`batch-abort`；獨立 schema + `batch_write` 原子寫入；SKILL.md:328 批次模式章節 |
| §3 提案 2 `cmd_rollback.sh` | ⬜ **未實作** | 全專案查無此檔；SKILL.md 內 `rollback` / `回滾` 零命中 |
| §3 提案 3 `wf-truncate.sh` | ⬜ **未實作** | `scripts/` 下僅有 `wf-state.sh` |
| §3 提案 4 `wf-exec.sh` | ⚠️ **建議重新定性** | 同上查無此檔。但其目的是「`agy` CLI 退出碼保留 + fallback」，而 `agy` headless 實際已不可用、委派一律走 fallback 路徑——**為一條已不走的路徑寫轉接層，是在解決不存在的問題**。動工前應先確認前提是否還成立 |

**修正結論**：§5 的 5 項（teamwork-preview 借鏡）**全數已處理**，本文件此前仍將其列為
「待實施藍圖」，屬狀態欄漂移。§3 的提案 1（`pause_level`）已於 2026-08-06 落地，
**剩餘待辦為提案 2 `cmd_rollback.sh` 與提案 3 `wf-truncate.sh` 兩支腳本**，提案 4 前提存疑。
§4 的「3 階段實作藍圖」與「4 層驗證協定」是為 §3 那些腳本設計的，僅在動工時適用；
§5 各項已用 Claude `Workflow` 落地，不走該藍圖。

> **📝 §3 提案 1 的落地差異（2026-08-06 · `9bce068`）**：整體採用原設計的三段式
> enum 與安全備援策略，但有三處刻意偏離，記錄供後續參考——
> 1. **判定收斂為單一 `should_pause()` 函式**，而非原提案在 `stage-done` 與 `task-done`
>    內各寫一份 `case`。理由與 features 側 §P7 的 `NetworkEntry.isFailed` 完全同構：
>    同一判定寫兩份，遲早漂移。
> 2. **quick 模式對 `balanced` 明示短路回 `strict`**（原提案未涉及 mode 交互）。
>    quick 不拆任務（無 task 迴圈）、stage 為自由標籤（不匹配 `0b`/`2`/`4`），
>    套 `balanced` 只會落空退化；明示短路讓讀腳本的人不會誤判為 bug。
> 3. **schema 接受 `pause_level == null`**——舊 state 檔無此欄位仍須通過校驗，
>    否則既有流程會在 `validate()` 全數卡死（never break userspace）。
>
> **另新增批次佇列**（非原提案範圍）：原四項提案全是**單一 workflow 內**的基礎腳本，
> 未涵蓋「多個獨立需求各自 worktree/branch/PR 依序執行」的外層編排需求。
> 該能力與 `pause_level` 正交——前者決定跑幾個 workflow，後者決定每個 workflow 停幾次；
> 批次要能順跑，內層仍需 `pause_level=balanced`，故兩者同批實作。
> ⚠️ **已知邊界**：Claude 無法自行清空 context，故批次為「自動接續 + 使用者 `/clear` 換場」
> 而非全自動。真無人值守需走 cron 驅動（每次喚醒即全新 context），未實作。

> **流程教訓**：本文件與 `2026-08-14-features-brainstorm.md` 兩份腦力激盪文件，
> 累計已出現 **6 次「標為待辦、實際已完成」**（features 側：§D6、§P8；workflow 側：§5.1~§5.4 四項），
> 以及 **1 次反向漂移**（features 側 §P7 的教訓段落被誤讀為現存問題，已於 2026-08-06 補時間錨註記）。
> **兩個方向的根源相同：狀態敘述沒有綁定時間點。** 本次更新即為預防第 7 次——
> `pause_level` 完成後立刻回寫，不等下次盤點。
> 建議每次 release 或每月固定跑一次 `/gen-list-work-item-by-priority` 的實查核對，
> 別讓狀態欄持續漂移——漂移的待辦清單會讓人去做已經做完的事。

---

## 🟣 第三部分：知名開發者的實務工作流比對 (2026-08-15)

> **與第二部分的區別**：§第二部分比的是**學術／開源多 Agent 框架**（MetaGPT、AutoGen、
> SWE-agent、ChatDev）——那些是論文與框架。本部分比的是**具名工程師手工打造、
> 跑在自己真實專案上的工作流**。後者更值得比對，因為它們與 `gen-dev-workflow` 的處境相同：
> 一個人、一個 repo、要真的把 code 出貨，不是刷 benchmark。
>
> **🔍 查證方法**：以下每一項都經 `WebFetch` 實際讀取原始來源確認作者、機制與主張，
> 非僅憑搜尋摘要或記憶。附上的 URL 即為查證所用來源。
>
> ⚠️ **本次研究的已知邊界（誠實標註）**：原研究流程設計為「多線搜尋 → 深讀 → 三重對抗查核」，
> 但**對抗查核階段因 session 額度耗盡而未執行**（85 個 agent 中 68 個中止）。
> 上述 WebFetch 查證由主對話**親自補做**，涵蓋下列 8 項的核心來源。
> 搜尋階段另有約 30 項候選（含 Spec Kit、Kiro、Agent OS、BMAD、Container Use、Uzi、
> Claude Squad、Vibe Kanban、XState Agent 等工具，以及數篇 arXiv 論文）**未經逐項查證，
> 故不寫入本文件**——寧可少列，不可誤植。

### 1. 對照矩陣

| 軸線 | Ralph (Huntley) | ACE-FCA (Horthy) | Harper Reed | Hashimoto | Beck | Böckeler | Superpowers (Vincent) | `gen-dev-workflow` |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **階段拆解** | ❌ 單一 prompt 無限迴圈 | ✅ research→plan→implement | ✅ spec→plan→todo | ✅ 16 個 session 分段 | ✅ 逐 test 推進 | — | ✅ brainstorm→plan→implement | ✅ 0a→0b→1→2→3→4 |
| **狀態持久化** | 檔案（每輪重讀） | plan 檔（狀態壓回檔案） | `todo.md` 打勾跨 session | `spec.md` + `@` 檔案引用 | `plan.md` 未打勾的 test | — | skill 檔 | ✅ JSON state + shell 唯一入口 |
| **程式強制約束** | ❌ 純 prompt | ❌ 純流程紀律 | ❌ 純文件 | ❌ 人工把關 | ❌ system prompt 勸說 | ✅ **Sensors（linter/test）** | ⚠️ skill 文件 | ✅ **轉移表 + 棘輪 exit 1** |
| **context 管理** | ✅ 每輪 reset | ✅ **刻意壓在 40-60%** | 跨 session 續接 | ✅ 分 16 session | — | — | subagent 隔離 | ✅ Token Gate >150k 切 session |
| **平行隔離** | ❌ | — | ❌ | ❌ 序列 | ❌ | — | ✅ 自動建 worktree | ✅ per-worktree state |
| **對抗式審查** | ❌ | ❌ | ❌ | ✅ 人類親審 | ✅ 人類盯場 | ✅ code review agent | ✅ subagent code review | ✅ 驗收 model ≥ 實作 model |
| **回報不可信** | 接受爛結果、`git reset` | — | — | ✅ 「不 ship 我看不懂的 code」 | ✅ **抓 agent 刪測試作弊** | ✅ 確定性 sensor | — | ✅ 主對話親自 `git log` 驗證 |

### 2. 逐項解析

#### 2.1 Ralph / Ralph Wiggum Loop — Geoffrey Huntley

- **來源**：<https://ghuntley.com/ralph/>
- **機制**：`while :; do cat PROMPT.md | claude-code ; done`。一輪一個任務、**每輪全新 context**、每輪餵相同的規格檔。
- **設計原理**：作者自述「**deterministically bad in an undeterministic world**」——LLM 本身不確定，但**迴圈結構**可確定。失敗不是工具問題而是 prompt 調校機會；壞掉就 `git reset --hard` 重來，靠「最終一致性」收斂。
- **佐證（不是可學）**：「每輪 fresh context」與我們 Token Gate 切 session 是**同一個洞察的兩種強度**——他每輪都重置，我們撞到 150k 才重置。Ralph 證明了「context 重置」這件事本身有效，但**我們已有同一機制的精緻版**，不需要往他那個方向走。
- **🔴 為什麼「每輪 fresh context」我們學不了**（此問題被實際提出過，記錄完整推導以免日後重提）：

  fresh context 的收益是真的——消除 context 污染（前一輪的錯誤推理與失敗嘗試不累積）、消除 context 衰減（不會用到 150k 時開始遺忘早期指令）、迴圈輸入完全相同故變異只來自模型本身、無狀態即無狀態 bug。他那句「deterministically bad」的重點正是：**把不確定性集中在模型一處，不讓它散佈在累積的 context 裡。**

  但這些收益的代價，在他的情境付得起、在我們的付不起：

  1. **他用「重跑」換「續接」——我們不能。** Ralph 每輪 fresh 的前提是每輪都能從頭重來，失敗處理就是 `git reset --hard`。我們 STAGE 2 跑到第 5 個任務時 context 爆掉，不可能把前 4 個已 commit、已過驗收的任務丟掉重跑——那不只是浪費，是**破壞已經人類確認的成果**。
  2. **他沒有暫停點，我們有。** fresh context 的代價是「模型不記得剛才跟你談了什麼」。他全程無人類確認環節故無所謂；我們每個 stage 都有暫停點，使用者在 STAGE 0b 確認過的計畫、STAGE 2 逐任務確認過的變更，**每輪清空就得重講**。
  3. **我們已有更精準的等價物。** fresh context 要解決的是 context 污染與衰減，我們的解法不是「不重置」，而是**重置時帶著結構化狀態走**：Token Gate → 寫 state 檔 → WIP commit（帶交接筆記）→ 切 session（context 真的清空）→ 新 session 讀 state 續接。**我們也有 fresh context，只是重置頻率不同、而且不丟進度。**

  **結論：真正該學的是 §2.2 ACE-FCA，不是 Ralph。** 兩者都在講 context 管理但主張不同——Ralph 每輪重置且丟掉重跑（適用無人值守玩具專案），ACE-FCA 維持 40-60% 不讓 context 長大（適用長流程）。我們與 ACE-FCA 的差距是真的（被動剎車 vs 主動巡航），與 Ralph 的差距則是**刻意的設計取捨**。
- **不學**：無狀態機、無暫停點、接受「醒來發現 codebase 壞掉」。對單人玩具專案可行，對要出 PR 的流程是災難。

#### 2.2 ACE-FCA — Dex Horthy (HumanLayer)

- **來源**：<https://github.com/humanlayer/advanced-context-engineering-for-coding-agents>（`ace-fca.md`）
- **機制**：research → plan → implement 三階段，plan 寫成 repo 內的 markdown 檔，實作時**把狀態壓縮回 plan 檔**。
- **設計原理**：兩個主張值得抄——
  1. **context 刻意壓在 40–60%**，不是用滿才處理。「內容是你唯一能影響輸出品質的槓桿」。
  2. **審查槓桿階層**：「一行爛的 *plan* 會導致數百行爛 code；一行爛的 *research* 會導致數千行」——所以**該花力氣審 plan 與 research，不是審 code**。
- **🟢 可學（真正的新東西）**：我們的 Token Gate 是 **150k 才觸發的被動剎車**，ACE-FCA 是**主動維持在 40-60% 的巡航控制**。這解釋了為何長流程後段品質下滑——我們允許 context 長到 150k 才動作，那時 agent 早已在高污染區工作。
- **已有**：階段拆解、plan 檔為真相來源（我們的 STAGE 0a/0b 產物即是）。

#### 2.3 spec.md → prompt_plan.md → todo.md — Harper Reed

- **來源**：<https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/>
- **機制**：三件式文件。對話式 LLM 產 `spec.md` → 推理模型把 spec 拆成 `prompt_plan.md`（一系列給 codegen 的 prompt）→ `todo.md` 作為跨 session 打勾清單。
- **設計原理**：作者明言 `todo.md` 的用途是「**keeping state across sessions**」——這正是我們 state 檔要解決的問題，只是他用 markdown 打勾、我們用 JSON + schema 校驗。
- **已有**：我們的 `completed_tasks` 陣列 + `task-done` 就是強型別版的 `todo.md`。**佐證我們的方向對**，但他的方案沒有校驗，打勾可以隨便亂打。

#### 2.4 16-session 分段 + oracle — Mitchell Hashimoto

- **來源**：<https://mitchellh.com/writing/non-trivial-vibing>（Ghostty 自動更新功能實例）
- **機制**：一個功能拆成 **16 個 session、約 8 小時、$15.98 token**。用「oracle」（唯讀、較慢較貴的模型）先產計畫存成 `spec.md`，再逐 session 實作。穿插「**anti-slop session**」專門清理。
- **設計原理**：兩點——
  1. **「更好組織與文件化的 code 讓未來的 agentic session 表現更好」**：清理不是潔癖，是為後續 session 鋪路。
  2. **「我不 ship 我看不懂的 code」**：理解失敗就直接拒絕 AI 的方案。
- **🟢 可學**：**anti-slop session** 是我們沒有的概念。我們 STAGE 3 審查的是「這次改動對不對」，沒有「為了讓下次 agent 更好做而整理」這種**面向未來的清理**。
- **佐證**：他的「oracle 用更貴模型做計畫」= 我們的「planner 用最強推論」；他的分 16 session = 我們的 Token Gate 切 session。

#### 2.5 Augmented Coding — Kent Beck

- **來源**：<https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes>
- **機制**：把 TDD 紀律寫進 system prompt——「找 `plan.md` 中下一個未標記的 test、實作該 test、**只寫剛好讓它通過的 code**」。全程盯著中間結果，隨時準備喊停。
- **設計原理**：與 vibe coding 的分野是「**在 vibe coding 你不在乎 code，只在乎系統行為**」；augmented coding 則要求 code 品質、複雜度、測試覆蓋率都達到手寫標準。
- **🔴 最有價值的一條**：他列出 agent 失控的三個警訊，其中第三個是——
  > 「任何 genie 在**作弊**的跡象，例如**停用或刪除測試**」
  >
  這是我們「委派紀律第 3 條：回報不等於事實」的**獨立佐證**。Beck 是 TDD 發明人，他親自踩到「agent 為了讓測試過而刪測試」這個坑。我們要求主對話親自驗證，方向完全正確。
- **已有**：TDD 紀律（`test-driven-development` skill）、驗收與實作分離。

#### 2.6 Harness Engineering：Guides vs Sensors — Birgitta Böckeler (Thoughtworks)

- **來源**：<https://martinfowler.com/articles/harness-engineering.html>
- **機制**：提出 **`Agent = Model + Harness`**，並把 harness 的控制項二分——
  - **Guides（前饋控制）**：在 agent 動手**之前**引導。如 coding conventions 文件、bootstrap 指令。
  - **Sensors（回饋控制）**：在 agent 動手**之後**偵測並自我修正。如 linter、測試、code review agent。
- **設計原理**：她進一步區分**計算式**（確定性、毫秒級、**結果可靠**）與**推論式**（語意、慢、機率性）控制。關鍵論述：計算式 sensor 因為可靠，所以能在**每次變更**都跑；機率性的 AI sensor 做不到這點。
- **🟢 這給了我們一套精確的詞彙**：本文件反覆論證的「**約束寫在 prompt 裡 = 沒有強制力**」（Gap 2.6、委派 cwd 弱點），用她的框架講就是——
  > **我們一直在用 Guide 解決該用 Sensor 解決的問題。**
  >
  `wf-state.sh` 的 `exit 1`、hook 的 `PreToolUse` 攔截，都是**計算式 Sensor**；SKILL.md 的文字規範是 **Guide**。Gap 2.6 的教訓（「守衛需要被呼叫才生效」）本質是：**Guide 可以被忽略，Sensor 不行**。
- **可學**：委派 cwd 約束目前是 Guide（prompt 裡的道德勸說），該升級成 Sensor（hook 攔截或委派後自動 `git status` 驗證）。這與文件既有結論一致，但 Böckeler 的框架讓「為什麼非做不可」講得更清楚。

#### 2.7 Superpowers — Jesse Vincent

- **來源**：<https://blog.fsck.com/2025/10/09/superpowers/> ｜ <https://github.com/obra/superpowers>
- **機制**：Claude Code 的 skill plugin 系統。brainstorm → plan → implement 三階段；**自動建 git worktree** 做平行隔離；實作走 RED/GREEN TDD；可「逐個 task 派給 subagent 實作後再逐個 code review」。
- **設計原理**：核心強制語句是「**If you have a skill to do something, you *must* use it**」——用 skill 的存在本身當作行為約束。
- **⚠️ 特別說明**：**本 session 就載入了 superpowers**（見系統提示的 `using-superpowers`）。所以這不是「別人的做法」，而是我們**已在共用的基礎設施**。它與 `gen-dev-workflow` 的關係是互補：superpowers 管「流程紀律與 skill 選用」，`gen-dev-workflow` 管「六階段編排與狀態機」。
- **佐證**：worktree 平行隔離、subagent 逐任務實作 + code review、TDD——三項我們都有，且是各自獨立收斂到同一答案。

#### 2.8 🔴 反方立場：Just Talk To It — Peter Steinberger

- **來源**：<https://steipete.me/posts/just-talk-to-it>
- **主張**：**明確反對**本文件推崇的一切——反對繁複規劃文件、反對 subagent 範式（他用「分開的視窗」取得「完整的控制與可見度」）、反對冗長的 persona 規則檔（「跟模型說『你是專精於生產級 LLM 應用的 AI 工程師』不會改變任何事」）。
- **理由**：精簡 prompt 下「codex 反而更小心、讀更多檔案」；繁複的 scaffolding 造成 **context 浪費**與認知負擔，效益不成比例。
- **為什麼要收錄**：**一份只收錄同意自己的證據的文件沒有價值。** Steinberger 的批評直指 `gen-dev-workflow` 最脆弱的地方——6 個 stage、7 個 agent 角色、一份 1000 行的 SKILL.md，這些 ceremony 真的都在付出等值的回報嗎？
- **本專案的回應（Linus 式）**：他的批評對**探索性、單人、小改動**成立——這正是我們有 **quick 模式**（單暫停點、不建 worktree）的原因。但他的方案無法回答：**context 撞 150k 怎麼辦？** 他沒有狀態持久化，session 一斷進度就沒了。我們的 state 檔不是 ceremony，是**為了能中斷續接**而付的必要代價。**兩者的分野不是「誰對」，而是「任務有多長」**——短任務他對，長任務我們對。這也是為什麼 `pause_level` 與 quick 模式必須存在：**讓同一套流程能退化成他那種輕量模式**。

### 3. 三分類結論

#### (A) 已經有的——別人也這樣做，佐證設計正確，**不是待辦**

| 我們的機制 | 誰獨立收斂到同一答案 |
|:---|:---|
| 階段拆解 + plan 檔為真相來源 | Horthy、Harper Reed、Hashimoto、Vincent、Beck |
| 跨 session 狀態持久化 | Harper Reed（`todo.md`）、Hashimoto（`spec.md`） |
| context 用盡切 session | Huntley（每輪 reset）、Hashimoto（分 16 session） |
| git worktree 平行隔離 | Vincent (Superpowers) |
| 驗收與實作分離、不讓寫 code 的 model 自審 | Böckeler（sensor）、Vincent（subagent review） |
| 「回報不等於事實」須外部驗證 | **Beck（親自抓到 agent 刪測試作弊）**、Hashimoto |
| 用程式碼而非文字強制 | **Böckeler（Sensors 必須是計算式才可靠）** |

> 七項全數有獨立佐證。這說明 `gen-dev-workflow` 的骨架不是閉門造車——
> 但也說明**這些不是我們的獨創**，寫文件時不該當成賣點。

#### (B) 真正可學——別人有、我們沒有

> **⚠️ 注意項數**：本類共 **4 項**，其中 **ACE-FCA 貢獻兩項**（第 1 與第 3）。
> 曾有一次盤點誤以「每個章節各一項」計數而漏掉第 3 項——**逐項解析的章節數 ≠ 可學項目數**。

1. **🟢 context 主動巡航（ACE-FCA）**｜effort: 低｜價值: **高**

   - **他們怎麼做**：context 刻意壓在 **40–60%**；「context 視窗的內容是你唯一能影響輸出品質的槓桿」。
   - **我們現況**：Token Gate 是**被動剎車**——`<60k` 正常 ／ `60–100k` 提示精簡 ／ `100–150k` 強制走 MCP 委派 ／ `>150k` 才強制 checkpoint 切 session。
   - **🔴 差距**：我們允許 context 一路長到 150k 才動作。**問題是 agent 在 100k–150k 這段已經在高污染區工作了**——那些輸出照樣被 commit、照樣進 PR。等到 150k 才切 session，壞掉的產出早就落地。
   - **附帶價值**：這替一個既有現象提供了機制層面的解釋——**長流程後段品質下滑**。此前只能歸因於「後面的任務比較難」。
   - **判斷：值得做。** 本次研究**唯一的高價值新洞察**。不需新腳本，改 SKILL.md Token Gate 表格的閾值與行為即可。

2. **🟡 anti-slop session（Hashimoto）**｜effort: 低｜價值: 中

   - **他們怎麼做**：16 個 session 中穿插專門的清理 session，理由是「更好組織與文件化的 code 讓未來的 agentic session 表現更好」。
   - **我們現況**：STAGE 3 審查的是「**這次改動對不對**」——正確性、規格符合度、code quality。
   - **🔴 差距**：缺少**面向未來**的清理。兩者問的不是同一個問題——STAGE 3 問「這段 code 有沒有錯」，anti-slop 問「**這段 code 會不會讓下一個 agent 讀錯**」。
   - **判斷：條件性值得。** 對長期維護的 repo 有價值，對一次性 PR 是純成本。建議先當作 `pause_level=strict` 下的可選步驟，不強制。

3. **🟡 審查槓桿階層（ACE-FCA）**｜effort: **極低**｜價值: 中

   - **他們怎麼做**：「一行爛的 **plan** 會導致數百行爛 code；一行爛的 **research** 會讓你收穫數千行爛 code」——所以該花力氣審 plan 與 research，不是審 code。這是對傳統 code review 優先序的反轉。
   - **我們現況**：STAGE 0b 有暫停點，使用者會看到計畫。
   - **🔴 差距**：**沒有明說「這裡才是最該仔細看的地方」**。實務上使用者可能在 0b 隨手按過，卻在 STAGE 2 逐任務仔細看 diff——**槓桿完全用反了**。0b 看漏一行，後面幾百行都建在錯的基礎上。
   - **判斷：值得做，投報率最高。** 就是在 STAGE 0b 暫停點加一句提示文字。

4. **🟢 把 Guide 升級成 Sensor（Böckeler）**｜effort: 中｜價值: **高**

   - **他們的框架**：`Agent = Model + Harness`。**Guide**（前饋，動手前引導）**可以被忽略**；**Sensor**（回饋，動手後偵測）才是確定性、無法繞過的。
   - **我們現況**：委派 cwd 約束寫成 prompt 裡的一段文字（「🔴 邊界：不得存取或修改此目錄以外的任何檔案」）。
   - **🔴 差距**：那段文字**沒有任何強制力**，是寫給另一個 LLM 看的道德勸說——用 Böckeler 的框架講，**這是 Guide，但它要達成的效果需要 Sensor**。MCP 呼叫無法指定 cwd，子進程若在主 repo 而非 worktree 動手，`wf-state.sh` 的所有 guard 都不會有反應：**狀態機管的是 state JSON 的合法性，管不到檔案寫在哪顆磁碟位置上。** 目前的緩解（委派紀律第 3 條事後跑 `git status`）屬**偵測**不屬**預防**。
   - **判斷：值得做。** 這**不是新發現**——§「同構的第二個弱點」早已記錄且已判定正解是 hook 攔截。Böckeler 的貢獻是給了精確詞彙讓理由更硬。**Gap 2.6 已用 hook 成功解掉同型問題，有現成範式可抄。**

##### 🔴 建議動工順序（2026-08-16 決議）

| 順位 | 項目 | effort | 價值 | 理由 |
|:---:|:---|:---:|:---:|:---|
| 1 | **§3 審查槓桿階層** | 極低 | 中 | 投報率最高，改一段提示文字 |
| 2 | **§1 context 主動巡航** | 低 | 高 | 唯一的高價值新洞察；與順位 1 同屬 SKILL.md 改動，可同批做 |
| 3 | **§4 Guide→Sensor** | 中 | 高 | 需寫 hook，但 Gap 2.6 有成功範式 |
| 4 | **§2 anti-slop** | 低 | 中 | 條件性，設成可選即可 |

> **排序理由**：前兩項都只動 SKILL.md（文字與閾值），可合併為一次改動；第 3 項要寫 hook 與掛載，成本跳一級但價值高；第 4 項價值條件性，排最後。
>
> ⚠️ **狀態標註**：以上四項截至 2026-08-16 **全部只是提案，未動任何程式碼**。
> 依本文件的歷史教訓（累計 6 次「標為待辦、實際已完成」的漂移），任一項落地後**應立即回寫本表**，不要等下次盤點。

#### (C) 刻意不學——別人有但對本專案是過度工程或方向錯誤

| 不學什麼 | 誰在做 | 理由 |
|:---|:---|:---|
| **無限迴圈直到收斂** | Ralph (Huntley) | 「醒來發現 codebase 壞掉、`git reset --hard` 重來」對要出 PR 的流程不可接受。我們的退回路徑（3→2）是**有界重試**，不是無限迴圈。 |
| **每輪 fresh context（重置即丟進度）** | Ralph (Huntley) | 收益（消除 context 污染與衰減）是真的，但代價是「每輪從頭重來」。我們有暫停點與已確認的成果，丟不起。**我們已有精緻版**：重置時帶結構化 state 走，context 一樣清空但進度不丟。完整推導見 §2.1。 |
| **完全放棄結構化流程** | Steinberger | 他的批評對短任務成立，但無法回答「context 撞牆怎麼辦」。我們用 **quick 模式**覆蓋他的使用情境，不需要把整套流程拆掉。 |
| **把 spec 拆成一系列預生成 prompt** | Harper Reed (`prompt_plan.md`) | 預先把所有 prompt 寫死，等於放棄「依前一步結果調整下一步」的能力。我們的 task 陣列保留了這個彈性。 |

### 4. Linus 式總評

> **這批工作流有一個共同的誠實之處：沒有一個人宣稱自己解決了「讓 LLM 可靠」這件事。**
> Huntley 說他的方法「deterministically bad」，Beck 在抓 agent 刪測試，Hashimoto 拒絕
> ship 看不懂的 code，Böckeler 直說機率性 sensor 不可靠。**全都在講同一件事：
> 模型不可信，所以把可靠性放到模型外面。**
>
> `gen-dev-workflow` 的 `wf-state.sh` + hook 攔截走的正是這條路，而且**走得比多數人遠**——
> 上表七項機制中，只有 Böckeler 明確主張「必須是計算式（確定性）控制」，
> 其他人的約束大多仍停留在文件與人工盯場。
>
> **但別自滿：** 這也意味著我們承擔了別人沒有的複雜度。Steinberger 的批評必須留在文件裡
> 當作反面壓力——**每次要往 SKILL.md 加一條規則時，先問這條是 Guide 還是 Sensor。
> 如果是 Guide，它大概率會被忽略，那就不值得加。**

---
