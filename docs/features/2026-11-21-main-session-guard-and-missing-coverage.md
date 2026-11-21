# 功能規格：主對話護欄（Worktree 凍結 + 危險指令分級）與 MISSING COVERAGE 契約（G1 / G4）

> **建立日期**：2026-11-21
> **狀態**：草稿（STAGE 0a；§7 開放問題待 STAGE 0b 定案）
> **來源**：[`docs/brainstorm/2026-11-09-workflow-brainstorm.md`](../brainstorm/2026-11-09-workflow-brainstorm.md) 第十部分（garrytan/gstack）§3.1、§3.4、§5 G1（:3224）、G4（:3225）
> **前例**：[`2026-08-19-delegation-cwd-sensor.md`](2026-08-19-delegation-cwd-sensor.md)（同型問題的委派側解法）、[`2026-10-15-project-settings-hook-guards.md`](2026-10-15-project-settings-hook-guards.md)（掛載進版控 + 測試鎖定慣例）
> **基底**：自 `main`（`ce4693b`）開分支

---

## 1. 問題陳述

### 1.1 一句話

現有護欄只盯住 `ask-gemini` 委派子進程。**主對話自己的 `Edit`/`Write`/`Bash`**，以及**審查視角沒有回來**這兩種情況，出事時沒有任何攔截，也沒有任何標記。

### 1.2 現況（2026-11-21 實查）

| 項目 | 事實 | 證據 |
|:---|:---|:---|
| PreToolUse 掛載 | 只有 `Agent`（`wf-guard-stage-check.sh`）與 `mcp__gemini-cli__ask-gemini`（`wf-guard-delegate-cwd.sh pre`）兩個 matcher；`Edit`/`Write`/`Bash` 沒有任何 hook | `.claude/settings.json` |
| worktree 位置 | 所有 workflow worktree 都在**主 repo 根目錄內**的 `.claude/worktrees/<name>/`；目前並存 3 個工作樹（主 checkout + #255 + #257） | `git worktree list`、`.gitignore` 的 `.claude/worktrees/` |
| 規劃文件雙份 | STAGE 1 用 `cp`（不是 `mv`）把 spec/plan 帶進 worktree，主 repo 仍留著未 commit 的同名原檔。之後的修改很容易打到主 repo 那份 | `branch-worktree-rules.md:30-39` |
| state 檔不記 worktree 路徑 | state 檔存在 `<worktree>/.claude/workflow-state/<branch-slug>.json`，只記 `branch`。STAGE 0a/0b 只有主 repo 的 `.pending-<wf-id>.json`，這時還沒有綁定 worktree | `state-machine.md:45-102` |
| 既有 hook 錯誤語意 | 兩支既有 hook 都採 **fail-open**（hook 壞掉一律放行），本次凍結 hook 依決策改採 **fail-closed** | `wf-guard-delegate-cwd.sh` P-11（:381-387） |
| repo 內 symlink | 只有 `.agents/{hooks,rules,skills}`，皆為指向 `../.claude/*` 的相對連結 | `find . -maxdepth 3 -type l` |
| `MISSING COVERAGE` | 全 repo 0 處（brainstorm 除外） | `grep -rn "MISSING COVERAGE"` |
| verifier 對逾時的規範 | 只有 `verifier.md:37` 一句「若遇到執行逾時或環境故障，回報包含環境受阻說明的 finding，嚴禁吞沒異常」。前提是 verifier 自己還能回報，而且沒有接到 reviewer 報告與 PR 草稿 | `verifier.md:37` |
| 多 angle 聚合實作 | 範例腳本 `(await parallel([...])).filter(Boolean).flatMap(...)` 會**靜默丟棄**回傳 null 的 lens | `workflow-parallel.md:102` |
| ask-gemini timeout | 無法逐次帶 timeout，預設為數十分鐘等級 | `mcp-delegation-discipline.md:14` |

### 1.3 觸發場景

**(a) 主對話 `Edit` 打到主 repo（靜默）**

```
STAGE 1 cp spec/plan → 主 repo 與 worktree 各有一份 docs/plans/<x>.md
  → STAGE 2 主對話依 verifier 意見修計畫，Edit 帶的是 <repo>/docs/plans/<x>.md
  → 改到主 repo 那份（未追蹤、不在任何 branch 上）
  → worktree 裡的計畫沒變，implementer 照舊計畫做
  → wf-state.sh 與既有 hook 全數通過，無任何訊號
```

**(b) 不可逆 Bash 指令（任何時候）**：`rm -rf ~`（變數展開錯、路徑拼錯）、`git push --force origin main`、`git reset --hard` 洗掉未 commit 的工作。這些都無法事後補救，只能事前攔截。

**(c) 審查視角缺席被當成通過（靜默）**

```
STAGE 3 派發 correctness / security / 過度工程 三個 lens
  → security lens 逾時，回傳 null
  → workflow-parallel.md:102 的 .filter(Boolean) 把它濾掉
  → reviewer 收到的 findings 和「security 查無問題」完全無法區分
  → 報告寫通過 → STAGE 4 發布
```

`ask-gemini` 空回應或逾時同樣是這個結構。

### 1.4 為何不可接受

1. **(a)(c) 都是靜默失效**，與 delegation-cwd-sensor §1.2 同型：所有 guard 都通過，Guardrail 完全沒有反應。
2. **(b) 不可逆**：事後偵測沒有意義，只能在 PreToolUse 擋下。
3. **(c) 會把「沒看」偽裝成「看過沒問題」**。這比明確失敗更糟，因為使用者根本不知道還有東西要補看。

---

## 2. 使用者故事

- **US-1（擋越界寫入）**：身為開發者，worktree 啟用期間，主對話的 `Edit`/`Write` 一旦打到主 repo（或其他 worktree）的檔案，系統必須當場拒絕，並告訴我應該改寫哪個路徑。
- **US-2（不誤殺）**：身為開發者，寫 worktree 內的檔案、寫 repo 外的路徑（scratchpad、memory）、不在 workflow 中、或在主 repo 跑另一個 workflow 的 STAGE 0a/0b 時，護欄必須完全透明。
- **US-3（不可逆指令先擋或先問）**：身為開發者，不論有沒有在跑 workflow，`rm -rf ~` 與 force push main 一律擋下，`git reset --hard` 這類會丟掉工作的指令先問過我。
- **US-4（缺席看得見）**：身為使用者，任何審查視角或 `ask-gemini` 沒有回來時，我要在 reviewer 報告頂部與 PR 草稿裡看到「缺了哪個、為什麼」，而且必須在 STAGE 4 發布前看到。
- **US-5（失效不靜默）**：身為維護者，凍結 hook 自己壞掉時，結果要是拒絕而不是放行；掛載條目也要由測試鎖住，不能被悄悄移除。

---

## 3. 已確定決策（使用者已確認，STAGE 0b 不翻案）

### D-1 凍結範圍

- **只擋一種情況**：目標路徑在**主 repo 根目錄內**，但**不在 active worktree 內**。
- **只在 active wf-state 綁定 worktree 時生效**。其餘路徑一律放行，包括 scratchpad、`~/.claude` memory 等 repo 外位置。
- 路徑判定採**詞法 + realpath 雙解析**，兩者都必須通過才放行（防 `..` 與 symlink 逃逸）。
- **hook 出錯一律 deny（fail-closed）**。

### D-2 Bash 分級（常駐生效，不限 workflow 進行中）

| 分級 | 指令 |
|:---|:---|
| **deny** | `rm -rf` 目標為 `/`、`~`、`$HOME`；force push 到 `main` |
| **ask** | `git reset --hard`；`git checkout .` / `git restore .`；`git clean -f` |

### D-3 MISSING COVERAGE 語意

| 情境 | 判定 | 自動重試 | 計入通過 |
|:---|:---|:---:|:---:|
| lens 回傳合法 schema，`findings` 為空 | 合法結果（查無問題） | — | 是 |
| lens／`ask-gemini` **沒有可用回報**：逾時、空白、null、無法解析 | **`MISSING COVERAGE`** | **否** | **否** |
| verifier **有回報**，內容是環境受阻（既有） | `FAIL: INFRA` | 同 tier 1 次 | 否 |
| 某 lens 依特徵規則刻意未派發（既有） | Guard Clause Record（主審兜底） | — | 依兜底結果 |

- 界線在**誰回報**：`FAIL: INFRA` 是 verifier 自己說「環境擋住了」；`MISSING COVERAGE` 是該通道根本沒有交回可用結果。
- 呈現方式：缺席視角列在 reviewer 審查報告**頂部**，PR 草稿也要帶上，確保使用者在 STAGE 4 發布前看到（`balanced` 也會在這裡停）。
- 不自動重試，不自動退回 STAGE 2，由使用者在暫停點決定。

### D-4 基底與衝突

從 `main` 開分支。PR #256（stage3 rework verdict）、#258（subagent dev log）尚未合併，且與本次觸及的檔案重疊（見 §6 R-1）。衝突留待合併時 rebase 處理。

---

## 4. 驗收條件

> 情境中的 `<repo>` 指主 checkout 根目錄，`W` 指 active workflow 綁定的 worktree（位於 `<repo>/.claude/worktrees/` 下）。

### 4.1 G1-A：`Edit`/`Write` Worktree 凍結（`.claude/hooks/tests/` shell 測試）

| # | 條件 | 驗證 |
|:---:|:---|:---|
| AC-1 | **越界 deny**：active workflow 綁定 `W` 時，`Edit`/`Write` 目標為 `<repo>` 內、`W` 外的檔案（例：`<repo>/docs/plans/x.md`、`<repo>/lib/a.dart`）→ deny；訊息列出被擋路徑與 `W`，並提示改用 `W` 內的同相對路徑 | shell 測試 |
| AC-2 | **worktree 內放行**：同上情境，目標在 `W` 內 → 放行且無輸出。尚不存在的新檔（`Write` 建檔）也包含在內 | shell 測試 |
| AC-3 | **repo 外放行**：同上情境，目標在 `<repo>` 外（scratchpad、`~/.claude/projects/<proj>/memory/`、`/tmp`）→ 放行 | shell 測試 |
| AC-4 | **無 active workflow 放行**：沒有任何 state 檔 → 寫 `<repo>` 任意檔放行 | shell 測試 |
| AC-5 | **未綁 worktree 放行**：只有 STAGE 0a/0b 的 `.pending-*.json` → 寫 `<repo>/docs/features/`、`docs/plans/` 放行 | shell 測試 |
| AC-6 | **並行 workflow 不誤擋**：當前 session 不屬於任何 active workflow（位於 `<repo>`，當前 branch 沒有對應 state），但 `.claude/worktrees/` 下有其他 workflow 的 active worktree → 寫 `<repo>` 放行。這條保護 `SKILL.md` 宣告的多 workflow 並行，本規格就是在這種狀態下寫出的；判定機制見 Q-2 | shell 測試 |
| AC-7 | **跨 worktree deny**：目標為另一個 worktree `W2`（同樣在 `<repo>` 內）→ deny | shell 測試 |
| AC-8 | **詞法逃逸 deny**：路徑含 `..` 且正規化後落在 `W` 外、`<repo>` 內（例：`<W>/../../../lib/a.dart`）→ deny | shell 測試 |
| AC-9 | **symlink 逃逸 deny**：`W` 內有 symlink 指向 `<repo>` 中 `W` 外的目錄，經由該 symlink 的路徑 → deny | shell 測試 |
| AC-10 | **合法 symlink 不誤擋**：經由 `W` 內的相對 symlink（如 `.agents/skills` → `../.claude/skills`）解析後仍在 `W` 內，或指向 `<repo>` 外 → 放行 | shell 測試 |
| AC-11 | **fail-closed**：hook 執行中途發生未預期錯誤（以注入方式觸發，例如 payload 非 JSON、內部例外）→ deny，訊息標明是 hook 自身錯誤，可與越界 deny 區分 | shell 測試 |

### 4.2 G1-B：`Bash` 危險指令分級（shell 測試，每條正反例各至少一組）

| # | 條件 | 驗證 |
|:---:|:---|:---|
| AC-12 | **deny**：`rm -rf /`、`rm -rf ~`、`rm -rf $HOME` → deny。反例 `rm -rf ./build`、`rm -rf "$TMPDIR/wf-x"`、`rm -rf ~/scratch/x` → 放行 | shell 測試 |
| AC-13 | **deny**：`git push --force origin main`、`git push -f origin main` → deny。反例 `git push origin main`（非 force）、`git push --force origin feature/x` → 放行 | shell 測試 |
| AC-14 | **ask**：`git reset --hard`（含帶 ref）→ ask。反例 `git reset --soft HEAD~1` → 放行 | shell 測試 |
| AC-15 | **ask**：`git checkout .`、`git restore .` → ask。反例 `git checkout -b feat/x`、`git restore --staged lib/a.dart` → 放行 | shell 測試 |
| AC-16 | **ask**：`git clean -f`、`git clean -fd` → ask。反例 `git clean -n` → 放行 | shell 測試 |
| AC-17 | **常駐**：沒有任何 state 檔時，AC-12～16 正例的判定結果不變 | shell 測試 |
| AC-18 | deny/ask 輸出要說明命中哪條規則與原指令；一般指令（`git status`、`flutter test`）不產生輸出 | shell 測試 |

### 4.3 掛載與回歸

| # | 條件 | 驗證 |
|:---:|:---|:---|
| AC-19 | `.claude/settings.json` 新增 PreToolUse 條目，涵蓋 `Edit`、`Write`、`Bash`。擴充 `test_project_settings_hooks.sh`，鎖定新條目與新腳本（存在、可執行、index mode `100755`） | shell 測試 |
| AC-20 | 既有兩個 matcher（`Agent`、`mcp__gemini-cli__ask-gemini`）行為不變；`.claude/hooks/tests/` 既有 5 支測試全數通過 | shell 測試 |
| AC-21 | §5.3 已知盲區寫入 hook 腳本首部註解 | 審閱 |

### 4.4 G4：MISSING COVERAGE 契約（文件）

| # | 條件 | 驗證 |
|:---:|:---|:---|
| AC-22 | `verifier.md`、`reviewer.md`、`delegation-and-parallel.md`、`mcp-delegation-discipline.md` 四份文件各至少出現一次字面 `MISSING COVERAGE` | `grep -c` |
| AC-23 | 契約寫明 D-3 的四方界線：合法空 findings、`MISSING COVERAGE`、`FAIL: INFRA`、Guard Clause Record 各自的觸發條件、是否重試、是否計入通過。四份文件之間不互相矛盾 | 審閱 |
| AC-24 | `verifier.md`：STAGE 3 lens 模式下無法完成該視角時，必須以 `MISSING COVERAGE` 前綴明示原因，不得用空 findings 代替。`:37` 現行句改寫為此語意 | 審閱 |
| AC-25 | `reviewer.md`：審查報告**頂部**（結論之前）列出所有缺席視角（lens 名稱與原因）。有缺席時，結論不得寫成「全部視角通過」。缺席標記不因 reviewer 兜底而移除，並與 Guard Clause Record 分開列出 | 審閱 |
| AC-26 | `delegation-and-parallel.md`：結果聚合表新增 `MISSING COVERAGE` 列，規則為不計 PASS、不自動重試、不自動退回，交由使用者在暫停點決定，並明確和 `FAIL: INFRA` 的「同 tier 重試 1 次」區隔 | 審閱 |
| AC-27 | `mcp-delegation-discipline.md`：`ask-gemini` 逾時或空回應時不得視為完成或通過，必須標記 `MISSING COVERAGE` 並回報。此段與既有「已知限制：無逐次 timeout」段落相鄰 | 審閱 |
| AC-28 | 有 `MISSING COVERAGE` 時，PR 草稿要包含「缺席視角」段落，使用者在 STAGE 4 暫停點（`strict`/`balanced`）看得到。`autonomous` 下只保證寫進 PR 本文，不另加暫停（落點檔案見 Q-8） | 審閱 |

### 4.5 回寫

| # | 條件 | 驗證 |
|:---:|:---|:---|
| AC-29 | brainstorm `:3224` G1 與 `:3225` G4 的狀態欄，由 `⬜ 提案` 改為該表既有的已完成格式 `✅ 已完成（日期，Issue #N / PR #N）`，並註明本次未做的子項（G1：`$IFS`/base64 混淆偵測；G4：同家族隔離、雙層 timeout） | 審閱 |

---

## 5. 範圍邊界

### 5.1 做

- 新增 PreToolUse hook（`Edit`/`Write` 凍結、`Bash` 分級；拆一支還是兩支見 Q-3），並掛到 `.claude/settings.json`。
- `.claude/hooks/tests/` 新增對應 shell 測試，擴充 `test_project_settings_hooks.sh`。
- G4 契約寫入 `verifier.md`、`reviewer.md`、`delegation-and-parallel.md`、`mcp-delegation-discipline.md`（四份之外的必要落點見 Q-8）。
- 回寫 brainstorm G1/G4 狀態。
- 不觸及 `lib/`、`test/`，Flutter 測試與 analyze 基線不受影響。

### 5.2 不做

| 排除項 | 理由 |
|:---|:---|
| 攔截 Bash 寫檔（`sed -i`、`>`、`tee`、`cp`）繞過凍結 | 正常流程本身就靠 Bash 寫檔（STAGE 1 用 `cp` 搬規劃文件、環境防護用 `jq` 改 `settings.local.json`）；解析 shell 的寫入語意誤判率高。只列為已知盲區（§5.3） |
| `$IFS` / base64 混淆偵測 | 本專案要防的是手滑，不是對抗性模型 |
| G4 同家族隔離與雙層 timeout | MCP 呼叫無法逐次帶 timeout（`mcp-delegation-discipline.md:14`），雙層 timeout 在派發端無處施作 |
| `MISSING COVERAGE` 自動重試 | 使用者決策：缺席交由人判斷；重試會讓逾時成本翻倍 |
| 修改 `wf-state.sh` 強制暫停 | 既有 STAGE 4 暫停點（`strict`/`balanced`）已足夠；`autonomous` 是使用者明示放棄暫停 |
| 清單外的危險指令（`git branch -D`、`drop table`、`rm -rf` 其他路徑等） | 只做 D-2 列出的清單 |
| `NotebookEdit` matcher | repo 內沒有追蹤中的 notebook（`git ls-files '*.ipynb'` = 0） |
| Antigravity `.agents/hooks.json` 掛載 | 工具名不同；雙 harness 等價屬 G5 |
| 凍結事件的稽核 log | deny 是同步、當場可見的，不需要事後紀錄 |

### 5.3 已知盲區（需寫入 hook 首部註解）

- 凍結只攔 `Edit`/`Write` 的目標路徑。主對話用 Bash 寫檔（`sed -i`、`>`、`tee`、`cp`、`mv`）**完全不受凍結**。
- Bash 分級是**字串層比對**：經變數間接（例如 `$X` 在執行期展開成 `/`）、腳本檔內的指令、以及混淆寫法都偵測不到。
- cwd 漂回主 repo（`cd <R>`）時視為未綁定，此時寫主 repo 不受凍結。
- 目標屬於未綁定的 linked worktree（含 isolation subagent 的 worktree、沒有 state 檔的手動 worktree）時放行。
- macOS 檔案系統不分大小寫：以不同大小寫拼寫主 repo 路徑可繞過凍結判定。
- `onFailure: block` 下 python3／shebang／執行權限失效，會擋所有 session（含主 checkout）的 `Edit`/`Write`。
- Bash：heredoc 內文不比對；shlex 無法解析的尾段放行（已切出段照判）；`-o <值>` 這類帶值選項可能讓 refspec 判讀錯位；shlex 把詞中 `#` 當註解起點（`echo foo#bar; rm -rf ~`、URL 含 `#`），同一行其後內容不比對；偶數個反斜線結尾的行會被誤當行接續（`echo a\\⏎rm -rf ~`）。
- 以保留字或前綴開頭的段（`{ … }`、`then`、`do`、`!`、`time`、`env`、`command`、`xargs`、`sudo -u root`）、雙引號內的 `"$(…)"`、`git --git-dir <dir>`（空格分隔）、`git checkout ./`、子 shell 內 `cd` 延續到外層，皆可能漏判（fail-open）。
- hook `ask` 在 `bypassPermissions` 下不保證跳出確認，`dontAsk`／`-p` 下會變成拒絕；不可逆項目因此一律放在 deny 層。

> 本節及下列項目已依實作計畫 §6 於 STAGE 2 同步修訂（2026-11-21）：D-1／§4.1 收窄為「目標所屬 checkout 是主 checkout 或另一個已綁定 worktree」（使用者 0b 確認）；hook 檔名為 `.claude/hooks/wf-guard-worktree-freeze.py`、`.claude/hooks/guard-dangerous-bash.py`；AC-19 的 `Edit|Write` 條目 `onFailure: "block"`、`Bash` 條目 `onFailure: "continue"`；§5.1 落點補 `publisher.md`、`workflow-parallel.md`、`.agents/agents/publisher.yaml`（使用者 0b 確認）；AC-8／AC-12／AC-13 的補充例見計畫 §6；AC-29 PR 編號於 STAGE 6 補上。

---

## 6. 風險

| # | 風險 | 影響 | 緩解方向 |
|:---:|:---|:---|:---|
| R-1 | 與 PR #256、#258 衝突。重疊檔：`settings.json`、`test_project_settings_hooks.sh`、`verifier.md`（#258）、`reviewer.md`、`publisher.md`（#256）、`delegation-and-parallel.md`、`SKILL.md`（兩者皆有）、`workflow-parallel.md`（#258） | 中 | 合併時 rebase；`test_project_settings_hooks.sh` 的 `check_guard` 清單最容易在 rebase 時漏合 |
| R-2 | fail-closed 鎖死：凍結 hook 有 bug 時，所有 `Edit`/`Write` 都會被擋，包括修 hook 本身 | 高 | 見 Q-5 |
| R-3 | 誤擋並行 workflow：若 active 判定掃描所有 state 檔，另一個 workflow 的 STAGE 0a/0b 在主 repo 寫規格會被擋（AC-6）；`done` 後仍保留的 worktree 也可能讓主 repo 長期被凍結 | 高 | 見 Q-1、Q-2、Q-4 |
| R-4 | Bash 比對誤判：deny 誤擋合法指令會中斷流程（成本高）；ask 誤判只多一次確認（成本低） | 中 | deny 規則只收 D-2 的精確目標；變體涵蓋範圍見 Q-7 |
| R-5 | PreToolUse 也會在 subagent 的工具呼叫上觸發（待查證）。implementer Fallback、verifier 跑 Bash 都會經過護欄 | 低 | 規則本身與呼叫者無關，但 `ask` 在 subagent 情境的行為要查（Q-6） |
| R-6 | `.agents/agents/verifier.yaml` 鏡像有 8 處對應契約文字；只改 `.md` 會讓兩邊漂移 | 低 | 見 Q-8(c) |

---

## 7. 開放問題（留給 STAGE 0b）

### 7.1 使用者指定的三題

- **Q-1｜如何判定 active worktree**：做法一是讀 `.claude/workflow-state/*.json` 的 `branch`，再對 `git worktree list`；做法二是依 hook payload 的 `cwd` 往上找 state 目錄，再用當前 branch 對 slug（既有兩支 hook 的 P-3/P-4 範式）。已知事實：state 檔不記 worktree 路徑、存放位置在 worktree 內（§1.2）。做法二在主對話 cwd 漂回主 repo 時會漏擋場景 (a)；做法一要決定掃描範圍。
- **Q-2｜多 workflow 並行如何判定**：不論採哪個方案都必須滿足 AC-6。另需決定：session 綁定 `W1` 時寫 `W2` 一律 deny（AC-7 已定），但 session 不屬任何 workflow 時寫 `W2` 該怎麼處理。
- **Q-3｜Edit 凍結與 Bash 護欄拆兩支 hook 還是合一**：兩者的生效條件不同（workflow 範圍 vs 常駐），錯誤語意也可能不同（見 Q-5）。

### 7.2 本次實查衍生（設計層，需 0b 一併定案）

- **Q-4｜`stage: done` 的 state 算不算 active**：worktree 要到 STAGE 6 才清理，期間可能長期存在（目前就有兩個）。
- **Q-5｜fail-closed 的生效範圍與逃生口**：(i) Bash 護欄出錯時要 fail-closed 還是 fail-open？fail-closed 會連 Bash 自救路徑一起封死。(ii) 凍結 hook 出錯時，使用者在 session 內有沒有解除方式。
- **Q-6｜`ask` 的實際行為**：`permissionDecision` 的 `ask` 在 auto mode、`bypassPermissions`、subagent 情境下的實際效果，以及 deny 理由會不會回饋給模型。依 RULES「改設定前先查官方文件」，0b 必須先查 Claude Code hooks 官方文件。
- **Q-7｜Bash 比對精度**：AC-12～16 只規定最低限度。以下變體要不要納入需定案：flag 順序（`-fr`、`-r -f`、`-Rf`）、尾斜線（`~/`）、`${HOME}`、`/*`、`~/*`、串接指令（`&&`、`;`）、`sudo` 前綴、`--force-with-lease`、`+main` refspec、在 `main` 上省略 refspec 的 `git push -f`。
- **Q-8｜G4 必要落點超出四份文件（✅ 使用者已裁決 2026-11-21：三項全納入範圍）**：
  - (a) `workflow-parallel.md:102` 的 `.filter(Boolean)` 正是場景 (c) 的實作入口 → **納入**：null 結果改轉為 `MISSING COVERAGE` 標記，不得丟棄。
  - (b) PR 草稿由 `publisher.md`／`SKILL.md` STAGE 4 控制 → **納入 `publisher.md`**，作為 AC-28 落點。
  - (c) `.agents/agents/{verifier,reviewer}.yaml` 鏡像 → **同步**（沿用 #256/#258 慣例）。
- **Q-9｜STAGE 2 的 `MISSING COVERAGE` 路由**：implementer 的 `ask-gemini` 委派、或 STAGE 2 驗收 verifier 沒有回報時，標記之後要走 implementer Fallback 還是停下求助？與 `delegation-and-parallel.md` 既有「基礎設施錯誤（連線中斷等）同 tier 重派 1 次」的界線也要劃清。

---

## 8. 成功的定義

一句話：**主對話寫錯 worktree、敲下不可逆指令、審查視角沒回來，這三件事從「靜默發生」變成「當場被擋」或「發布前必定被看見」。**
