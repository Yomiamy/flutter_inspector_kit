# 主對話護欄（Worktree 凍結 + 危險指令分級）與 MISSING COVERAGE 契約 — 實作計畫

> **規格**：[`docs/features/2026-11-21-main-session-guard-and-missing-coverage.md`](../features/2026-11-21-main-session-guard-and-missing-coverage.md)（AC-1～AC-29；Q-8 已由使用者裁決）
> **日期**：2026-11-21 ｜ **模式**：Sequence ｜ **預估 Effort**：中（兩支 hook ≈ 95 + 150 行、兩支測試、settings 註冊；其餘為文件插入，文字已定稿）
> **不涉及 Dart 程式碼**：`lib/`、`test/` 零改動，不需跑 `flutter test` / `flutter analyze`；驗收以 `.claude/hooks/tests/` 為準。
> **官方文件依據**：<https://code.claude.com/docs/en/hooks>、<https://code.claude.com/docs/en/permission-modes>、<https://code.claude.com/docs/en/permissions>、<https://code.claude.com/docs/en/sub-agents>、<https://code.claude.com/docs/en/worktrees>（2026-11-21 以 curl 取 `.md` 版逐段查證，見 §4）。
> **修訂紀錄**：plan-verifier 初審 REVISE 第 1 次——B1（`rtk` 前綴繞過）、B2（isolation worktree 誤擋）與 N1～N9 已併入，程式碼重跑測試後重新貼入。
> **實測依據**：§8 的 hook 與測試已在 scratchpad 的本 repo clone（`ce4693b`）實跑：macOS、`/bin/bash` 3.2.57、Python 3.14.5、`jq-1.7.1-apple`、git 2.50.1、Claude Code 2.1.328。7 支 hook 測試全綠；另以兩輪 mutation（逐一拔掉 realpath、詞法判定、主 checkout 捷徑、未綁定 worktree 放行、heredoc 剝除、`rtk` 剝除、`cd`/`-C` 追蹤、`+refspec`、deny 優先序、shlex 例外保留已切出段等共 30 處）確認每條規則都有測試會失敗。

---

## 1. 核心判斷

【核心判斷】✅ 值得做：場景 (a) 主對話改到主 repo 那份規劃文件、(b) 不可逆指令、(c) 審查視角缺席被當成通過，目前三者都**零訊號**。前兩者靠兩支無狀態 PreToolUse hook 就能當場攔下；第三者是純契約問題，換掉 `workflow-parallel.md:102` 的 `.filter(Boolean)`、再加一張單一定義處的界線表即可。

【關鍵洞察】
- **資料結構**：凍結 hook 的唯一輸入是 payload 的 `cwd` 與 `tool_input.file_path`。「本 session 綁定哪個 worktree」**不需要掃描任何 state 檔**——cwd 往上第一個 `.git`：是目錄（主 checkout）就未綁定；是檔案（linked worktree）且該 worktree 內有 `<branch-slug>.json` 就是 W。主 repo 根 R 由 `git rev-parse --git-common-dir` 得出。**目標端用同一個判定**：目標所屬 checkout 是主 checkout 或另一個已綁定的 worktree 才擋；落在未綁定的 linked worktree（Claude Code `isolation: worktree` 的 subagent worktree）放行。沒有第二份狀態、沒有 session 對照表、沒有依 worktree 命名的特判。
- **可消滅的特殊情況**：Q-4（`done` 算不算 active）整題消失——綁定以 cwd 為準，一個 `done` 的 worktree 只影響 cwd 在它裡面的 session，不可能把主 repo 長期凍住，所以 stage 值根本不必讀。AC-6（並行 workflow）也不需要任何特判：cwd 在 R 就是未綁定。
- **最大破壞風險**：fail-closed 鎖死（R-2）。照實說：`onFailure: block` 下 **python3 缺失、shebang 失敗、執行權限遺失會擋住所有 session（含主 checkout）的 Edit/Write**；cwd 在已綁定 worktree 內時 git 失敗會連 scratchpad／memory 的寫入一起擋。收斂：(1) 執行權限由 settings 測試鎖 index mode `100755`；(2) cwd 在主 checkout 時腳本**完全不跑 git**，腳本內部錯誤的影響面只限 worktree 內的 session；(3) Bash 護欄刻意 fail-open，保住自救通道；(4) 官方 `disableAllHooks` 為最後逃生口。第二風險是 Bash deny 誤擋（R-4）：用 shlex 切詞（引號內字串不算指令）、剝除 heredoc 內文（commit message 提到 `rm -rf ~` 不會被擋）、追蹤 `cd <dir>` / `git -C <dir>`（在 feature worktree 裡 force push 不會因主 repo 在 main 而誤擋）。

---

## 2. 實作方向與 Trade-off

### 2.1 active worktree 判定（Q-1、Q-2、Q-4）

| 方向 | 作法 | 優點 | 缺點 | 結論 |
|:---|:---|:---|:---|:---|
| **A. cwd 定位**（採用） | payload `cwd` 往上找第一個 `.git`；`.git` 為檔案且 `<D>/.claude/workflow-state/<slug>.json` 存在 → W = D。目標端以同一判定找出所屬 checkout，只有主 checkout 或另一個已綁定 worktree 才擋 | 零掃描、零新狀態；AC-6 天然成立；`done` 問題消失；主 checkout 不跑 git；isolation subagent 不論 hook cwd 是 W 還是它自己的 worktree 都不誤擋 | cwd 漂回 R（`cd <R>`）時視為未綁定，此時寫 R 不擋 → 列入已知盲區 | ✅ |
| B. 掃描全部 state | `git worktree list` + 各 W 的 state 檔，任一 active 即凍結 R | cwd 漂移也擋得到 | 無法分辨「這個 session 屬於哪個 workflow」——state 不記 session。結果是任何 worktree active 時全 repo 凍結，直接違反 AC-6／US-2（本規格就是在 #255、#257 並存時於 R 寫成的） | ❌ |
| C. state 記 `session_id` | `wf-state.sh` 寫入綁定的 session，hook 比對 payload `session_id` | cwd 漂移也擋得到 | 要改 `wf-state.sh`（§5.2 排除）；state-machine 的設計是跨 session 續接，session_id 每次都變；subagent 的 session_id 行為未見文件 | ❌ |

`${CLAUDE_PROJECT_DIR}` 不能用：官方文件明載它停在 session 啟動處，進 worktree 後不變（§4 H3）。

**Q-2 定案**：綁定 W1 時寫**已綁定**的 W2 → deny（AC-7）；**未綁定的 session 寫任何 worktree → 放行**。D-1 規定只在綁定時生效，US-2 要求其餘透明；STAGE 6 於主 repo 收尾、手動到別的 worktree 修東西都屬此類。

**目標端判定（B2）**：綁定 W1 時，目標落在**未綁定的 linked worktree**（沒有對應 state 檔）→ 放行。官方文件：subagent「starts in the main conversation's current working directory」，`isolation: worktree` 的 subagent「runs its Bash … inside its worktree」，預設建在 `.claude/worktrees/` 下（§4 H11）——但它的 Edit/Write 觸發 hook 時 payload `cwd` 是 W1 還是它自己的 worktree，文件沒寫。若只看 cwd，前者會讓 `R/.claude/worktrees/agent-x/...` 被判「R 內、W1 外」而擋下，STAGE 2 的 `isolation: 'worktree'` 並行（`workflow-parallel.md` 適用點 2，含本計畫 §11 第 2 種執行方式）全滅。改為「目標所屬 checkout 是主 checkout 或另一個已綁定 worktree 才擋」：未綁定的 worktree 是另一份 checkout，寫進去改不到主 checkout 也改不到其他 workflow，與 D-1 要防的東西無關。判定不依賴 `agent-*` 命名（Claude Code 的命名不在我們控制內），只看 state 檔——`.worktreeinclude` 即使把 state 檔帶進 isolation worktree，branch 是 `worktree-<name>`，slug 也對不上。此項對 D-1 字面（「主 repo 根目錄內」）是收窄，列入 §6 待使用者確認。

**Q-4 定案**：stage 不參與判定。`done`、`5`、`6` 的 worktree 只要 state 檔還在，cwd 在其中的 session 就照樣凍結——STAGE 5 回覆 review 時寫錯主 repo 一樣是錯。STAGE 6 移除 worktree 後 state 檔隨之消失，綁定自然解除（cwd 不存在時往上走到 R 的 `.git` 目錄 → 未綁定）。

### 2.2 一支還是兩支 hook（Q-3）

| 方向 | 結論 |
|:---|:---|
| **A. 兩支**（採用）：`wf-guard-worktree-freeze.py`（`Edit\|Write`）、`guard-dangerous-bash.py`（`Bash`） | ✅ 生效條件（workflow 綁定 vs 常駐）、錯誤語意（fail-closed vs fail-open）、settings 的 `onFailure` 值三者都不同；一支 hook 只能有一個 `onFailure`，合併等於強迫其中一邊選錯 |
| B. 一支依 `tool_name` 分派 | ❌ 一處 bug 同時拖垮兩條防線；Bash 也會被 fail-closed 連坐 |

### 2.3 錯誤語意與逃生口（Q-5）——**本 repo 第一支 fail-closed 腳本**

既有兩支 guard 腳本對 payload／環境異常一律放行（`wf-guard-delegate-cwd.sh` P-11；`wf-guard-stage-check.sh` 只在 state 檔損毀時擋）；settings 的 `onFailure: block` 只補「腳本起不來／逾時」。本次凍結 hook **腳本內部也 fail-closed**，是新慣例，理由與邊界如下：

| | 凍結 hook | Bash 護欄 |
|:---|:---|:---|
| 腳本內部例外 | `exit 2` + `[WF-FREEZE ERROR]`（D-1）；cwd 在已綁定 worktree 內時，綁定判定先於讀 `file_path` 就要跑 git，git 失敗連 repo 外（scratchpad、memory）的寫入也擋 | `exit 0`、無輸出；shlex 解析失敗時保留已切出子指令的判定 |
| settings `onFailure` | `block`（起不來、逾時、exit 非 0/2 都擋）——**python3 缺失、shebang 失敗、執行權限遺失時，所有 session（含主 checkout）的 Edit/Write 都會被擋** | **`continue`**（官方列舉值 `"continue"` 或 `"block"`，見 §4 H4；明寫並由測試鎖住，防有人「統一」成 block） |
| 理由 | 越界寫入是靜默失效，hook 壞了放行等於回到無感現狀 | Bash 是凍結 hook 壞掉時的自救通道；護欄壞了只退回「沒有護欄」的現狀。`rm` 目標為 `/`、`~` 另有 Claude Code 內建的 critical-path 檢查兜底（§4 H9） |

**凍結 hook 的逃生口（不新增任何環境變數或開關，YAGNI）**：
1. **Bash 不受凍結**：可直接修或 revert hook 本身。
2. **`cd` 離開 W** 即解除綁定（主 checkout 路徑根本不跑 git，不會因 git 異常被鎖）。
3. 官方開關：使用者在 `.claude/settings.local.json` 設 `"disableAllHooks": true`，或以 `claude --settings '{"disableAllHooks": true}'` 啟動一次（官方文件：沒有逐支停用的方法；settings 內 hooks 的修改通常由 file watcher 自動套用）。

錯誤訊息只叫 model「停下回報使用者」，不教它自行關 hook。`.claude/` 屬 protected path（permission-modes「Protected paths」）：`default`／`acceptEdits` 下改 `settings.local.json` 會跳確認、`auto` 交 classifier 裁決、`bypassPermissions` 直接放行——本護欄防的是手滑，不是對抗。

### 2.4 Bash 比對精度（Q-7）

**採用 shlex 切詞 + 子指令逐段比對**，不用 raw regex：regex 會把 `echo "rm -rf ~"`、commit message 誤判成指令（deny 誤擋成本高，R-4）；`bashlex` 之類要新增相依，否決。

| 變體 | 納入 | 說明 |
|:---|:---:|:---|
| flag 順序／合併：`-rf` `-fr` `-Rf` `-r -f` `--recursive --force` | ✅ | 依短旗標字元集判定，順序無關 |
| 尾斜線 `~/`、`/*`、`~/*`、`$HOME/*`、`${HOME}`、`"$HOME"` | ✅ | 正規化後比對 `/ ~ $HOME ${HOME}` |
| 串接 `;` `&&` `\|\|` `\|` `&`、子 shell `( )`、`$( )`、換行 | ✅ | 切成子指令逐段判 |
| 前綴 `sudo`、`VAR=val`、**`rtk`／`rtk proxy`**；`/bin/rm` | ✅ | 剝除前綴；指令名取 basename。本機全域 `RTK.md` 規定 `git`／`ls` 等指令帶 `rtk`，不剝除就是 `rtk git push -f origin main` 直接繞過（B1） |
| `--force-with-lease`（任何 `--force*`）、`-fu` 這類合併短旗標、`+main` refspec | ✅ | 都會改寫 main 的歷史 |
| `HEAD:main`、`refs/heads/main`、`:main`（**與 force 合用時**） | ✅ | 取 refspec 目的端；單獨 `git push origin :main`（無 force）不擋，不在 D-2 清單 |
| **省略 refspec 或 `HEAD`** 且該處在 main | ✅ | 查該處當前 branch；追蹤 `cd <dir>` 與 `git -C <dir>`，避免 feature worktree 內的 force push 因 payload cwd 在 main 而誤擋 |
| heredoc 內文 | ✅（剝除） | 先移除內文再切詞：commit message 寫到 `git push -f origin main` 不會被擋，`'` 也不會讓 shlex 失敗 |
| 引號不平衡的尾段 | 部分 | shlex 拋 `ValueError` 前已切出的子指令照判（`rm -rf ~; echo 'x` 仍 deny），解析不了的尾段放行 |
| `bash -c "…"`、腳本檔、反引號、`$IFS`／base64、`rm -r`（無 `-f`）、`master`、`--mirror`、`git branch -D` | ❌ | §5.2 排除或不在 D-2 清單；列為已知盲區 |
| `git restore --staged .` | 會 ask | 不具破壞性，但多問一次成本低（R-4），不另開例外 |

### 2.5 腳本形式

| 方向 | 結論 |
|:---|:---|
| bash 包 `python3 -c '…'`（既有兩支 guard 的寫法） | ❌ python 段落內不能出現單引號（既有程式碼為此用 `chr(34)` 繞路），stdin 還要 here-string 轉手 |
| bash + jq（`wf-dev-log.sh` 的寫法） | ❌ macOS bash 3.2 沒有 `realpath -m`（不存在的新檔要能解析）；shell 切詞做不到 |
| **純 Python 檔 + shebang**（採用） | ✅ 無引號限制、可直接測；python3 啟動實測 ~30 ms（Bash 護欄每次呼叫約 30 ms，凍結 hook 在 worktree 內約 43 ms） |

副檔名 `.py` 偏離 `.claude/hooks/` 全為 `.sh` 的現況；settings 以 `command` 直接執行（mode `100755`），測試 Test 3 照樣鎖 mode，無其他相依於副檔名之處。

### 2.6 G4 契約的落點

| 方向 | 結論 |
|:---|:---|
| **A. 單一定義處 + 引用**（採用）：四方界線表只寫在 `delegation-and-parallel.md`「缺席視角契約」，其餘文件各一句話規範自己的行為並連回該節 | ✅ AC-23「四份文件不互相矛盾」最便宜的保證是只寫一份 |
| B. 四份文件各抄一份表 | ❌ 下一次改界線就會漂移（`.agents/agents/reviewer.yaml` 已經漏掉 Guard Clause Record 一條，就是前例） |

---

## 3. 資料結構與判定邏輯

### 3.1 凍結 hook（任一不成立即放行，零輸出）

```text
stdin → json.loads ──失敗──▶ exit 2 [WF-FREEZE ERROR]（AC-11）
  cwd = payload.cwd（缺席時用行程 cwd，兩者依文件同值）
  bound_repo(D)：D = 路徑往上第一個含 .git 的目錄（cwd 與目標共用此判定）
      找不到、或 D/.git 是目錄 ──▶ 未綁定（主 checkout；不跑 git）
      git -C D branch --show-current（失敗 ──▶ exit 2 [WF-FREEZE ERROR]）
      D/.claude/workflow-state/<branch 的 / 換 ->.json 不存在 ──▶ 未綁定（detached HEAD、沒有 state 的 worktree）
      否則 R = realpath(dirname(git rev-parse --path-format=absolute --git-common-dir))
  W = cwd 所屬的 D；bound_repo(W) 未綁定 ──▶ exit 0
  for p in (normpath(file_path), realpath(file_path)):
      p 不在 R 內，或 p 在 W 內 ──▶ 這一側通過
      owner = p 所屬的 D；owner 是 linked worktree 且未綁定 ──▶ 這一側通過（isolation subagent 的 worktree）
      否則 ──▶ exit 2 [WF-FREEZE BLOCK]：被擋路徑、W、W 內同相對路徑（relpath(p, owner)）、「另一個 workflow 請先 cd R」
  exit 0
```

「在 X 內」= `p == X or p.startswith(X + os.sep)`（以分隔符為界，`/repo-evil` 不會命中 `/repo`）。建議路徑取目標相對於**它所屬 checkout** 的路徑，主 checkout 與其他 worktree 一體適用，不依賴 `.claude/worktrees/` 命名慣例。branch 取法對齊既有兩支 guard（`git branch --show-current`，`wf-guard-stage-check.sh:87`、`wf-guard-delegate-cwd.sh:181`）。

### 3.2 Bash 護欄

```text
stdin → json.loads、tool_input.command ──任何例外──▶ exit 0（fail-open）
  剝除 heredoc 內文 → shlex（posix，punctuation_chars=";&|()<>\n"，空白不含換行）
  依「全由 ; & | ( ) 換行組成」的 token 切子指令
  每段：剝除前綴 sudo / rtk / rtk proxy / VAR=val；`cd <dir>` 更新目錄後跳過
  （shlex 中途拋 ValueError → 已切出的段照判，其餘放行）
     rm：同時有 r/R 與 f，且任一目標正規化後 ∈ {/, ~, $HOME, ${HOME}} → deny
     git（略過全域選項，追蹤 -C）：
        push：有 --force* / 合併短旗標含 f / +refspec，且目的端為 main、refs/heads/main，
              或為 HEAD／省略 refspec 而該目錄當前 branch 為 main → deny
        reset --hard → ask；checkout|restore 帶 "." → ask；clean 帶 -f/--force → ask
  有 deny → 輸出 deny；否則有 ask → 輸出 ask；都沒有 → 無輸出
```

輸出（exit 0）：

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
  "permissionDecisionReason": "[WF-BASH DENY] 命中規則：force push 到 main｜子指令：git push -f origin main"}}
```

### 3.3 MISSING COVERAGE 資料流（STAGE 3）

```text
parallel([correctness, ...special, 過度工程]) → results（逾時的 lens 為 null）
  lenses  = ['correctness', ...activeSpecialLenses, '過度工程']   ← 與陣列同序
  ok(r)   = Array.isArray(r?.findings)                          ← 合法空陣列算 ok
  missing = lenses 中 ok(results[i]) 為假者                       ← null／空白／無法解析
  findings = results.filter(ok).flatMap(r => r.findings)
reviewer：missing ∪ 自報 MISSING COVERAGE 的 finding → 報告頂部「缺席視角」→ publisher 帶進 PR 草稿 → STAGE 4 暫停點
```

---

## 4. 官方文件查證結果（Q-6）

| # | 查證項 | 結論與出處 | 計畫採用 |
|:-:|:---|:---|:---|
| H1 | payload 的 `cwd` | hooks「Common input fields」：`cwd`＝hook 觸發時的工作目錄。「Reference scripts by path」：進 worktree 後 `cwd` 為 worktree root，`cd` 後為新目錄；**`${CLAUDE_PROJECT_DIR}` 停在 session 啟動處** | §2.1 方向 A |
| H2 | `tool_input.file_path` | hooks「PreToolUse input」：Write/Edit/Read 的 `file_path` **一律為絕對路徑**，`~` 與相對路徑在 hook 執行前已展開 | 不另做 `~` 展開 |
| H3 | 決策輸出 | 「PreToolUse decision control」：`hookSpecificOutput.permissionDecision` = allow/deny/ask/defer；deny 的 reason **顯示給 Claude**，ask 的 reason 顯示在使用者的確認框；多個 hook 衝突時 `deny > defer > ask > allow`；exit 2 等同 deny、stderr 為理由 | 凍結用 exit 2 + stderr；Bash 用 JSON（ask 只能走 JSON） |
| H4 | 失敗語意 | 「Command hook fields」表：`onFailure`「`"continue"` or `"block"`」（官方列舉值）。「Block the action when a hook fails」：`"block"`（v2.1.295+）時起不來、exit 非 0/2、逾時、無效 JSON 都會擋；未設則為 non-blocking。「Timeouts」：PreToolUse 逾時預設不擋 | 凍結 `block`、Bash 明寫 `continue`（本機 2.1.328） |
| H5 | subagent 是否觸發 | 「Hook locations」：settings 的 hooks **也在 subagent 內執行**，PreToolUse/PostToolUse 觸發同一組，payload 帶 `agent_id`／`agent_type` | 規則與呼叫者無關（R-5） |
| H6 | `ask` 在 auto mode | 「PreToolUse `ask` decisions in auto mode」：hook 的 ask 一般送往使用者確認框，classifier 不代為裁決（protected path、沙箱外重試等例外由 classifier 先行拒絕） | ask 層在 auto mode 有效 |
| H7 | `ask` 在 bypassPermissions／dontAsk／`-p` | permission-modes「Actions no mode auto-approves」**未列** hook ask（只列 ask rule、critical-path rm 等）→ bypass 下**不保證**跳出確認；`dontAsk` 會把需要確認的呼叫自動拒絕；`-p` 無 permission prompt tool 時拒絕 | ask 層為 best-effort；不可逆項目一律放 deny 層（deny 先於權限規則生效：permissions「A blocking hook also takes precedence over allow rules」） |
| H8 | subagent 的 ask | sub-agents「Run subagents in foreground or background」：前景 subagent 的確認框直接轉給使用者；背景 subagent 的確認框浮到主對話並標出是哪個 subagent | 不需特別處理 |
| H9 | `Bash` matcher 範圍與內建防護 | hooks「Match Monitor commands」：`Bash` matcher 也會收到 Monitor 啟動的指令，deny/ask 有效。permission-modes「Critical paths」：`rm`／`rmdir` 目標為根目錄、家目錄、cwd 及其上層時，任何模式都會確認或拒絕，hook 的 allow 也放不行 | 本 hook 的 rm deny 是縱深防禦（把確認升級成硬擋） |
| H10 | 停用方法 | hooks「Disable or remove hooks」：`"disableAllHooks": true`（或 `--settings '{"disableAllHooks": true}'`）；**無法逐支停用**；settings 內 hooks 的直接修改通常由 file watcher 自動套用 | §2.3 逃生口 3 |
| H11 | subagent 的 cwd 與 isolation worktree | sub-agents：「A subagent starts in the main conversation's current working directory」，`cd` 不持久；`isolation: worktree` 的 subagent「runs its Bash and PowerShell commands inside its worktree」，且預設自 default branch 分出（非父 session 的 HEAD）。worktrees：預設建在 `.claude/worktrees/<name>/`。**isolation subagent 的 Edit/Write 觸發 hook 時 payload `cwd` 為何，文件未載明** | §2.1 目標端判定（兩種 cwd 都不誤擋）；§9 人工驗證 |

---

## 5. 開放問題裁決總表

| Q | 裁決 | 依據 |
|:-:|:---|:---|
| Q-1 | cwd 定位（§2.1 A）；目標端以同一判定排除未綁定的 linked worktree；cwd 漂回 R 的漏擋列入盲區 | 唯一不需新狀態又滿足 AC-6 的方案；目標端判定避免 isolation 並行被擋（B2） |
| Q-2 | 綁定時寫其他**已綁定** worktree deny、寫未綁定 worktree 放行；session 未綁定時一律放行 | D-1、US-2、§2.1 目標端判定 |
| Q-3 | 兩支 hook | §2.2 |
| Q-4 | stage 不參與判定，state 檔存在即綁定 | 綁定以 cwd 為準，`done` 不可能凍住主 repo |
| Q-5 | (i) Bash 護欄 fail-open（內部 + `onFailure: continue`）；(ii) 不新增開關，逃生口為 Bash／`cd`／`disableAllHooks`；python3／權限失效會擋所有 session 的 Edit/Write，照實列入 R-2 | §2.3 |
| Q-6 | 已查證 | §4 |
| Q-7 | §2.4 表內「✅」各項（含 `rtk`／`rtk proxy` 前綴） | 最小但涵蓋常見手滑；heredoc 剝除與 `cd`/`-C` 追蹤是為了**不誤擋** |
| Q-8 | (a)(b)(c) 依使用者裁決；另依同一鏡像慣例**加做 `.agents/agents/publisher.yaml`**（(b) 新增了 `publisher.md` 落點，不鏡像就是新漂移；初審同意保留）——仍請於 0b 暫停點確認 | 沿用 #256／#258 慣例 |
| Q-9 | STAGE 2 verifier 缺席 → 不計 `completed_tasks`、**立即停下求助**（不論 `pause_level`）；implementer 的 `ask-gemini` 缺席 → 標記後不重派，實查工作樹再走 Fallback；publisher 的 `ask-gemini` 缺席 → 退回 Fallback 自產草稿（四條路由全寫在契約節，AC-23）；派發**有明確錯誤碼**（400／429／5xx／連線中斷）才走既有「基礎設施錯誤同 tier 重派 1 次」，**沒錯誤也沒結果**（含逾時）一律 MISSING COVERAGE | verifier 是 STAGE 2 唯一閘門，缺席即無閘門；implementer 下游仍有 verifier，可降級。逾時本來就不在基礎設施錯誤清單內 |

---

## 6. 規格需同步修訂（請主對話於 0b 暫停點一併套用）

| 規格位置 | 修訂 |
|:---|:---|
| §5.3 已知盲區 | 補：(1) cwd 漂回主 repo（`cd <R>`）時視為未綁定；(2) 未綁定的 linked worktree（含 isolation subagent 的 worktree）的寫入不受凍結；(3) Bash：heredoc 內文不比對、shlex 無法解析的尾段放行、`-o <值>` 這類帶值選項可能讓 refspec 判讀錯位；(4) hook `ask` 在 `bypassPermissions` 不保證跳出確認，`dontAsk`／`-p` 下會變成拒絕（§4 H7）；(5) `onFailure: block` 下 python3／shebang／執行權限失效會擋所有 session 的 Edit/Write |
| D-1／§4.1（**需使用者確認**） | 「目標在主 repo 根目錄內」收窄為「目標所屬 checkout 是主 checkout 或另一個已綁定 worktree」：未綁定的 linked worktree（isolation subagent 的 worktree）放行，理由見 §2.1 目標端判定。AC-7 補反例：綁定 W 時寫未綁定 worktree 的檔案 → 放行 |
| §6 R-2 | 緩解方向改為「見計畫 §2.3」 |
| AC-8 | 補第二例：`<W>/inner/../../lib/a.dart`（`inner` 為指向 W 內更深處的 symlink）——詞法正規化落在 W 外而 realpath 在 W 內，依 D-1 仍 deny |
| AC-12／AC-13 | AC-12 正例補 `rtk proxy rm -rf ~`、`rm -rf ~; echo '…`（引號不平衡）；AC-13 反例補 `git push -f`（在非 main 上）、`git push origin :main`，正例補 `--force-with-lease`、`+main`、`HEAD:main`、在 main 上省略 refspec、`rtk git push -f origin main`、`rtk proxy git push --force origin main`（§2.4） |
| AC-19 | 註明 `Edit\|Write` 條目 `onFailure: "block"`、`Bash` 條目 `onFailure: "continue"`，兩者皆由 `check_guard` 鎖定 |
| AC-29 | PR 編號在 STAGE 2 尚未產生：本計畫 T5 先寫 `Issue #N`，PR 編號於 STAGE 6 `gen-sync-docs-by-branchs` 補上（先例：`3e91d41` 在 PR #203 建立後才寫入 `PR #203`） |
| §5.1 | 補列 `publisher.md` 與 `workflow-parallel.md`（Q-8 已裁決），以及 `.agents/agents/publisher.yaml`（待確認） |
| §4.1／§4.2 | hook 檔名定為 `.claude/hooks/wf-guard-worktree-freeze.py`、`.claude/hooks/guard-dangerous-bash.py`；測試檔 `test_worktree_freeze.sh`、`test_dangerous_bash.sh` |

---

## 7. 檔案異動清單

| # | 檔案 | 動作 | 任務 |
|:-:|:---|:---|:-:|
| 1 | `.claude/hooks/wf-guard-worktree-freeze.py` | 新增（mode `100755`） | T1 |
| 2 | `.claude/hooks/tests/test_worktree_freeze.sh` | 新增（mode `100755`），AC-1～AC-11 | T1 |
| 3 | `.claude/hooks/guard-dangerous-bash.py` | 新增（mode `100755`） | T2 |
| 4 | `.claude/hooks/tests/test_dangerous_bash.sh` | 新增（mode `100755`），AC-12～AC-18 | T2 |
| 5 | `.claude/hooks/tests/test_project_settings_hooks.sh` | 修改：`check_guard` 第 4 參數、兩個新條目、Test 3 清單（AC-19） | T3 |
| 6 | `.claude/settings.json` | 修改：`PreToolUse` 追加 `Edit\|Write`、`Bash` 兩個條目 | T3 |
| 7 | `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改：新增「缺席視角契約」節、聚合表一列、退回路徑一行（AC-23、AC-26） | T4 |
| 8 | `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` | 修改：`:102` 的 `.filter(Boolean)` 改為 `missing` 標記（Q-8a） | T4 |
| 9 | `.claude/skills/gen-dev-workflow/references/mcp-delegation-discipline.md` | 修改：緊接「無逐次 timeout」段新增一段（AC-27） | T4 |
| 10 | `.claude/agents/verifier.md` | 修改：`:37` 改寫（AC-24） | T4 |
| 11 | `.agents/agents/verifier.yaml` | 修改：鏡像 #10（`:36`） | T4 |
| 12 | `.claude/agents/reviewer.md` | 修改：工作原則插入一條（AC-25） | T4 |
| 13 | `.agents/agents/reviewer.yaml` | 修改：鏡像 #12 | T4 |
| 14 | `.claude/agents/publisher.md` | 修改：工作原則插入一條（AC-28） | T4 |
| 15 | `.agents/agents/publisher.yaml` | 修改：鏡像 #14（**待 0b 確認**） | T4 |
| 16 | `docs/brainstorm/2026-11-09-workflow-brainstorm.md` | 修改：`:3224`、`:3225` 狀態欄（AC-29） | T5 |

不需改：`SKILL.md`（R-1 重疊檔，AC-28 落點已由 `publisher.md` 承接）、`wf-state.sh`（§5.2）、`.agents/hooks.json`（§5.2）、既有兩支 guard 腳本、`.gitignore`。

**插入點刻意避開 #256／#258 的 hunk**（實查兩個 worktree 的 `git diff -U0 main...HEAD`）：`reviewer.md` 插在 `:29` 之後（#256 在 `:31` 後插入、改 `:37`，本計畫不碰 `:37`）；`publisher.md` 插在 `:42` 之後（#256 在 `:37` 後插入、改 `:50`）；`verifier.md` 只改 `:37`（#258 改 `:21` 後與 `:49-50`）；`delegation-and-parallel.md` 插在 `:73`、`:123`、`:134` 之後（#258 改 `:60`、`:70-71`，#256 改 `:157`）；`workflow-parallel.md` 改 `:89-104`（#258 在 `:46` 後插入）。`settings.json` 與 `test_project_settings_hooks.sh` 必然衝突（R-1）。

---

## 8. 任務拆分

| 順序 | 任務 | 寫入路徑 | 建議 model tier |
|:-:|:---|:---|:---|
| 1 | T1 凍結 hook + 測試（TDD） | #1、#2 | **整合（標準）**：路徑判定細節多，程式碼已定稿，不得「簡化」掉詞法判定或主 checkout 捷徑 |
| 2 | T2 Bash 護欄 + 測試（TDD） | #3、#4 | **整合（標準）**：同上，不得拿掉 heredoc 剝除與 `cd`/`-C` 追蹤 |
| 3 | T3 settings 註冊 + 鎖定測試 | #5、#6 | **機械性（快/便宜）** |
| 4 | T4 G4 契約文件 | #7～#15 | **機械性（快/便宜）**：文字已定稿，主要風險是 yaml 縮排 |
| 5 | T5 brainstorm 回寫 | #16 | **`[原地修改]`**（單檔、≤ 20 行、無公共 API） |

**預設序列 T1 → T2 → T3 → T4 → T5**，`total_tasks=5`。T3 依賴 T1、T2 已 commit（Test 3 讀 git index 的 mode）；T1、T2、T4 寫入路徑互不重疊，使用者 opt-in Workflow 時可同批並行（見 §11）。各任務 commit 走 `gen-commit`。

**範圍驗收規則**（implementer 先 commit 才交 verifier，不可用 `git status` 判定）：

```bash
BASE="$(git merge-base HEAD origin/main)"
# 本任務變更集 = 已 commit + 未 commit 的追蹤檔差異 ∪ 尚未 git add 的新檔
{ git diff --name-only "$BASE" -- <本任務路徑…>; git ls-files --others --exclude-standard -- <本任務路徑…>; } | sort -u
```

- **範圍檢查**：輸出恰好等於本任務檔案清單。
- **越界檢查**：拿掉路徑參數再跑一次，全量輸出不得出現 §7 清單（16 檔）與 STAGE 1 帶入的 spec／plan 以外的路徑。

> 本 feature 自己的 STAGE 2：session 從**主 checkout** 啟動（正常路徑）時，hook 與 settings 從主 checkout（`$CLAUDE_PROJECT_DIR`）載入，merge 前不生效。**例外**：若 session 是從 W 啟動，`$CLAUDE_PROJECT_DIR` 即 W，T3 commit 後 file watcher 會讓兩支 hook **立即對本 feature 其後的 T4、T5 生效**——兩者只寫 W 內檔案、不跑 D-2 指令，照常放行；若在此之後被擋，就是 hook 本身的 bug，先回報再修。

---

### Task 1：`wf-guard-worktree-freeze.py` + 測試（TDD）

**寫入**：`.claude/hooks/wf-guard-worktree-freeze.py`（新）、`.claude/hooks/tests/test_worktree_freeze.sh`（新）
**驗收**：AC-1～AC-11、AC-21（首部盲區註解）

#### 步驟 1.1（紅）：建立測試

建立 `.claude/hooks/tests/test_worktree_freeze.sh`，完整內容：

```bash
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
```

```bash
chmod +x .claude/hooks/tests/test_worktree_freeze.sh
bash .claude/hooks/tests/test_worktree_freeze.sh
```

**預期（紅）**：停在 AC-1，`FAIL: 預期 exit 2（…），實得 127`（hook 不存在）。

> fixture 的 repo 路徑刻意含空白（`re po`）：`rev-parse` 輸出若以 `split()` 切會在此炸成 `[WF-FREEZE ERROR]`，這是實測抓到的 bug，不得把路徑改回無空白。

#### 步驟 1.2（綠）：建立 hook

建立 `.claude/hooks/wf-guard-worktree-freeze.py`，完整內容（**不得**刪除詞法 `normpath` 判定、「主 checkout 不跑 git」那行、或「未綁定的 linked worktree」放行，三者各有測試鎖定，理由見 §2.1、§2.3、§3.1）：

```python
#!/usr/bin/env python3
# PreToolUse(Edit|Write) hook：主對話 worktree 凍結（G1-A）
# 規格：docs/features/2026-11-21-main-session-guard-and-missing-coverage.md §4.1
#
# 只擋一種情況：hook 輸入的 cwd 位於某個 workflow 綁定的 linked worktree W 內，
# 而 Edit/Write 的 file_path 落在主 repo R 內、W 外，且該檔所屬的 checkout 是
# 主 checkout 或另一個已綁定 workflow 的 worktree（主 repo 的規劃文件原檔、其他 workflow）。
#
# 「綁定」對 cwd 與目標用同一個判定：路徑往上第一個含 .git 的目錄 D ——
#   .git 是目錄（主 checkout）或找不到 → 未綁定（不跑 git）；
#   .git 是檔案（linked worktree）且 D/.claude/workflow-state/<branch-slug>.json 存在 → 已綁定。
# 不掃描其他 worktree 的 state 檔：並行 workflow、主 repo 的 STAGE 0a/0b 不受影響；
# stage 值不參與判定（done/5/6 一樣綁定）。目標落在「未綁定的 linked worktree」（例如
# Claude Code isolation: worktree 建立的 subagent worktree）放行——那是另一份 checkout，
# 寫進去不會改到主 checkout 或其他 workflow。
# 目標路徑以詞法（normpath）與 realpath 各判一次，兩者都通過才放行（防 .. 與 symlink 逃逸）。
#
# fail-closed：任何未預期錯誤 → exit 2，訊息前綴 [WF-FREEZE ERROR]（越界為 [WF-FREEZE BLOCK]）。
# settings 的 onFailure: block 另外涵蓋腳本起不來、逾時——因此 python3 缺失、shebang 失敗、
# 執行權限遺失時，所有 session（含主 checkout）的 Edit/Write 都會被擋（mode 由 settings 測試鎖定）。
# cwd 在已綁定 worktree 內時，判定綁定就要跑 git：git 失敗會連 repo 外的寫入（scratchpad、memory）一起擋。
# 解除：Bash 不受本 hook 影響（可直接修本檔）；cd 離開 W 即解除綁定；
# 或由使用者在 .claude/settings.local.json 設 "disableAllHooks": true（官方開關，會停用全部 hooks）。
#
# 已知盲區（規格 §5.3）：
# - 只攔 Edit/Write 的 tool_input.file_path。Bash 寫檔（sed -i、>、tee、cp、mv）完全不受凍結。
# - cwd 漂回主 repo（cd <R>）時視為未綁定，此時寫主 repo 不會被擋。
#
# 掛載於 .claude/settings.json（matcher: Edit|Write）；條目由 tests/test_project_settings_hooks.sh 鎖定。
import json
import os
import subprocess
import sys


def inside(p, root):
    return p == root or p.startswith(root + os.sep)


def checkout_of(path):
    """path 往上第一個含 .git 的目錄；找不到回傳 None。"""
    d = path
    while not os.path.lexists(os.path.join(d, ".git")):
        if d == os.path.dirname(d):
            return None
        d = os.path.dirname(d)
    return d


def bound_repo(d):
    """d 是已綁定 workflow 的 linked worktree → 回傳主 repo 根 R；否則 None。"""
    if d is None or os.path.isdir(os.path.join(d, ".git")):
        return None  # 主 checkout 不跑 git：fail-closed 的影響面只限 worktree 內的 session

    def git(*args):
        return subprocess.check_output(["git", "-C", d] + list(args),
                                       stderr=subprocess.DEVNULL, text=True).strip()

    branch = git("branch", "--show-current")
    state = os.path.join(d, ".claude", "workflow-state", branch.replace("/", "-") + ".json")
    if not os.path.isfile(state):
        return None
    return os.path.realpath(os.path.dirname(git("rev-parse", "--path-format=absolute", "--git-common-dir")))


def main():
    data = json.loads(sys.stdin.read())
    w = checkout_of(os.path.realpath(data.get("cwd") or os.getcwd()))
    r = bound_repo(w)
    if not r:
        sys.exit(0)
    fp = data["tool_input"]["file_path"]
    for p in (os.path.normpath(fp), os.path.realpath(fp)):
        if not inside(p, r) or inside(p, w):
            continue
        owner = checkout_of(p)
        if os.path.isfile(os.path.join(owner, ".git")) and not bound_repo(owner):
            continue  # 未綁定的 linked worktree（如 isolation subagent 的 worktree）
        rel = os.path.relpath(p, owner).split(os.sep)
        sys.stderr.write(
            "[WF-FREEZE BLOCK] 目標在主 repo 內、但不在本 session 綁定的 worktree 內。\n"
            "  被擋路徑：" + fp + "\n"
            "  綁定 worktree：" + w + "\n"
            "  請改寫：" + os.path.join(w, *rel) + "\n"
            "若這次寫入屬於主 repo 上另一個 workflow（STAGE 0a/0b），先 cd " + r + " 再寫。\n")
        sys.exit(2)
    sys.exit(0)


try:
    main()
except Exception as e:  # SystemExit 不是 Exception，正常 exit 不會落到這裡
    sys.stderr.write(
        "[WF-FREEZE ERROR] 凍結 hook 自身錯誤，依 fail-closed 拒絕本次寫入：" + repr(e) + "\n"
        "這不是越界判定。請停下回報使用者，由使用者決定處置"
        "（Bash 不受本 hook 影響；cd 離開 worktree 即解除綁定）。\n")
    sys.exit(2)
```

```bash
chmod +x .claude/hooks/wf-guard-worktree-freeze.py
bash .claude/hooks/tests/test_worktree_freeze.sh
```

**預期（綠）**：12 段 `PASS`（AC-1～AC-11 + AC-7 補充），最後一行 `ALL TESTS PASSED!`。

#### 步驟 1.3：mode 與 commit

```bash
git add .claude/hooks/wf-guard-worktree-freeze.py .claude/hooks/tests/test_worktree_freeze.sh
git ls-files -s .claude/hooks/wf-guard-worktree-freeze.py .claude/hooks/tests/test_worktree_freeze.sh | cut -d' ' -f1   # 兩行都必須是 100755
```

commit 走 `gen-commit`（建議：`feat(hooks): freeze main-session Edit/Write to the bound worktree (#<issue>)`）。

---

### Task 2：`guard-dangerous-bash.py` + 測試（TDD）

**寫入**：`.claude/hooks/guard-dangerous-bash.py`（新）、`.claude/hooks/tests/test_dangerous_bash.sh`（新）
**驗收**：AC-12～AC-18、AC-21

#### 步驟 2.1（紅）：建立測試

建立 `.claude/hooks/tests/test_dangerous_bash.sh`，完整內容：

```bash
#!/usr/bin/env bash
set -euo pipefail

# Bash 危險指令分級（guard-dangerous-bash.py）。
# 規格：docs/features/2026-11-21-main-session-guard-and-missing-coverage.md §4.2 AC-12～AC-18
# 輸出形狀依官方 hooks 文件：hookSpecificOutput.permissionDecision（deny / ask）+ permissionDecisionReason。

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/guard-dangerous-bash.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# fixture：一個在 main、一個在 feature branch 的 repo；PLAIN 沒有任何 state 檔，也不是 git repo（AC-17）
G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null)
ON_MAIN="$TMP/on-main"; ON_FEAT="$TMP/on-feat"; PLAIN="$TMP/plain"
"${G[@]}" init -q -b main "$ON_MAIN" && "${G[@]}" -C "$ON_MAIN" commit -q --allow-empty -m init
"${G[@]}" init -q -b feat/x "$ON_FEAT" && "${G[@]}" -C "$ON_FEAT" commit -q --allow-empty -m init
mkdir -p "$PLAIN" "$ON_FEAT/.claude/workflow-state"
echo '{"stage":"2"}' >"$ON_FEAT/.claude/workflow-state/feat-x.json"

run() {
  set +e
  OUT="$(jq -nc --arg c "$1" --arg cwd "$CWD" \
    '{hook_event_name: "PreToolUse", cwd: $cwd, tool_name: "Bash", tool_input: {command: $c}}' \
    | "$HOOK" 2>"$TMP/err")"
  CODE=$?
  set -e
  ERR="$(cat "$TMP/err")"
  [ "$CODE" -eq 0 ] && [ -z "$ERR" ] || fail "hook 必須 exit 0 且 stderr 為空（$1）：code=$CODE err='$ERR'"
}
decide() { # decide <deny|ask> <command>
  run "$2"
  jq -e --arg d "$1" --arg c "$2" '.hookSpecificOutput.hookEventName == "PreToolUse"
    and .hookSpecificOutput.permissionDecision == $d
    and (.hookSpecificOutput.permissionDecisionReason | contains("命中規則"))' <<<"$OUT" >/dev/null \
    || fail "預期 $1（$2），實得 '$OUT'"
}
pass() { run "$1"; [ -z "$OUT" ] || fail "預期放行且無輸出（$1），實得 '$OUT'"; }

check_all() {
  echo "=== AC-12: rm -rf 目標為 / ~ \$HOME → deny ==="
  for c in 'rm -rf /' 'rm -rf ~' 'rm -rf $HOME' 'rm -rf "$HOME"' 'rm -rf ${HOME}/' 'rm -fr ~/' \
           'rm -Rf /*' 'rm -r -f ~/*' 'sudo rm -rf /' '/bin/rm -rf --recursive -- ~' \
           'ls && rm -rf ~' 'cd /tmp; rm -rf $HOME' "$(printf 'cd /tmp\nrm -rf ~')" 'rtk proxy rm -rf ~' \
           "rm -rf ~; echo 'unbalanced"; do
    decide deny "$c"
  done
  for c in 'rm -rf ./build' 'rm -rf "$TMPDIR/wf-x"' 'rm -rf ~/scratch/x' 'rm -f ~' 'rm -r /' \
           'echo "rm -rf ~"' "$(printf 'git commit -F - <<EOF\nrm -rf ~ is denied\nEOF')"; do
    pass "$c"
  done
  echo "PASS"

  echo "=== AC-13: force push 到 main → deny ==="
  for c in 'git push --force origin main' 'git push -f origin main' 'git push origin main --force' \
           'git push --force-with-lease origin main' 'git push origin +main' 'git push -f origin HEAD:main' \
           'git push -fu origin refs/heads/main' "git -C $ON_MAIN push -f" "cd $ON_MAIN && git push --force origin HEAD" \
           'rtk git push -f origin main' 'rtk proxy git push --force origin main'; do
    decide deny "$c"
  done
  for c in 'git push origin main' 'git push --force origin feature/x' 'git push -u origin main' 'git push origin :main' \
           "git -C $ON_FEAT push -f" "cd $ON_FEAT && git push --force-with-lease" 'git push -f'; do
    pass "$c"
  done
  echo "PASS"

  echo "=== AC-14: git reset --hard → ask ==="
  decide ask 'git reset --hard'
  decide ask 'git reset --hard origin/main'
  decide ask 'rtk git reset --hard'
  pass 'git reset --soft HEAD~1'
  echo "PASS"

  echo "=== AC-15: git checkout . / git restore . → ask ==="
  decide ask 'git checkout .'
  decide ask 'git restore .'
  decide ask 'git checkout -- .'
  pass 'git checkout -b feat/x'
  pass 'git restore --staged lib/a.dart'
  echo "PASS"

  echo "=== AC-16: git clean -f → ask ==="
  decide ask 'git clean -f'
  decide ask 'git clean -fd'
  pass 'git clean -n'
  echo "PASS"

  echo "=== AC-18: deny 優先於 ask；理由含規則與子指令；一般指令無輸出 ==="
  decide deny 'git reset --hard && git push -f origin main'
  jq -e '.hookSpecificOutput.permissionDecisionReason | contains("force push 到 main") and contains("git push -f origin main")' \
    <<<"$OUT" >/dev/null || fail "理由缺規則或子指令：$OUT"
  for c in 'git status' 'flutter test' 'git log --oneline -5'; do pass "$c"; done
  echo "PASS"
}

echo "##### cwd 位於有 workflow state 的 repo #####"
CWD="$ON_FEAT"; check_all
echo "##### AC-17：cwd 無任何 state 檔（也不是 git repo），判定結果必須相同 #####"
CWD="$PLAIN"; check_all

echo "=== AC-13 補充：在 main 上省略 refspec 的 force push → deny ==="
CWD="$ON_MAIN"
decide deny 'git push -f'
decide deny 'git push --force origin'
pass 'git push'
echo "PASS"

echo "=== fail-open：壞 payload / 無法解析的指令放行且無輸出 ==="
for p in 'not json' '' '{"tool_input": "x"}'; do
  set +e; OUT="$(printf '%s' "$p" | "$HOOK" 2>&1)"; CODE=$?; set -e
  [ "$CODE" -eq 0 ] && [ -z "$OUT" ] || fail "壞 payload 應靜默放行：code=$CODE out='$OUT'"
done
pass "echo 'unbalanced"
echo "PASS"

echo "ALL TESTS PASSED!"
```

```bash
chmod +x .claude/hooks/tests/test_dangerous_bash.sh
bash .claude/hooks/tests/test_dangerous_bash.sh
```

**預期（紅）**：停在 AC-12，`FAIL: hook 必須 exit 0 且 stderr 為空（rm -rf /）：code=127 …`。

> 測試裡的危險指令全是 jq 組進 payload 的**字串**，只餵給 hook、從不執行。

#### 步驟 2.2（綠）：建立 hook

建立 `.claude/hooks/guard-dangerous-bash.py`，完整內容（**不得**拿掉 `HEREDOC_BODY` 剝除、`rtk` 前綴剝除與 `cd`/`-C` 目錄追蹤——第一項防 commit message 被誤擋，第二項防 `rtk git push -f` 繞過，第三項防 feature worktree 的 force push 被誤擋，各有測試鎖定）：

```python
#!/usr/bin/env python3
# PreToolUse(Bash) hook：危險指令分級（G1-B），常駐生效，與 workflow 狀態無關
# 規格：docs/features/2026-11-21-main-session-guard-and-missing-coverage.md §4.2
#
#   deny：rm 同時帶 -r/-R 與 -f，目標為 / ~ $HOME ${HOME}（含尾斜線與 /*）；force push 到 main
#         （-f / --force* / +refspec；省略 refspec 或 HEAD 時看該處當前 branch）
#   ask ：git reset --hard；git checkout . / git restore .；git clean 帶 -f
#
# 以 shlex 切詞，依 ; && || | & ( ) 換行切成子指令逐段比對；剝除前綴 sudo、rtk（含 rtk proxy）與 VAR=val；
# 子指令 `cd <dir>` 與 `git -C <dir>` 會更新判斷 branch 用的目錄。heredoc 內文先剝除，不當指令比對。
#
# fail-open：解析失敗或任何例外 → 放行（exit 0、無輸出），settings 亦設 onFailure: continue。
# Bash 是凍結 hook（fail-closed）壞掉時的自救通道；本護欄壞掉只退回「沒有護欄」的現狀。
#
# 已知盲區（規格 §5.3）：字串層比對。執行期變數展開（$X 展開成 /）、腳本檔與 bash -c 內的指令、
# 反引號、混淆寫法（$IFS、base64）都偵測不到；引號不平衡等 shlex 無法解析的部分放行（之前已切出的子指令照判）。
#
# 掛載於 .claude/settings.json（matcher: Bash）；條目由 tests/test_project_settings_hooks.sh 鎖定。
import json
import os
import re
import shlex
import subprocess
import sys

SEP_CHARS = set(";&|()\n")
HEREDOC_BODY = re.compile(r"(<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*)\n.*?\n[ \t]*\3[ \t]*(?=\n|$)", re.S)
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def segments(cmd):
    lx = shlex.shlex(HEREDOC_BODY.sub(r"\1", cmd), posix=True, punctuation_chars=";&|()<>\n")
    lx.whitespace = " \t\r"
    lx.whitespace_split = True
    seg = []
    for tok in lx:
        if set(tok) <= SEP_CHARS:
            yield seg
            seg = []
        else:
            seg.append(tok)
    yield seg


def short_has(arg, ch):
    return arg.startswith("-") and not arg.startswith("--") and ch in arg[1:]


def branch_of(d):
    try:
        return subprocess.check_output(
            ["git", "-C", d, "branch", "--show-current"],
            stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""


def rm_hit(args):
    flags, targets, opts_done = [], [], False
    for a in args:
        if not opts_done and a == "--":
            opts_done = True
        elif not opts_done and a.startswith("-"):
            flags.append(a)
        else:
            targets.append(a)
    recursive = any(short_has(f, "r") or short_has(f, "R") or f == "--recursive" for f in flags)
    force = any(short_has(f, "f") or f == "--force" for f in flags)

    def critical(t):
        t = t[:-2] if t.endswith("/*") else t
        return (t.rstrip("/") or "/") in ("/", "~", "$HOME", "${HOME}")

    return recursive and force and any(critical(t) for t in targets)


def push_main_hit(args, d):
    pos = [a for a in args if not a.startswith("-")]
    refspecs = pos[1:]
    force = any(a.startswith("--force") or short_has(a, "f") for a in args) \
        or any(r.startswith("+") for r in refspecs)
    if not force:
        return False
    dsts = [r.lstrip("+").split(":")[-1] for r in refspecs] or ["HEAD"]
    return any(x in ("main", "refs/heads/main") or (x == "HEAD" and branch_of(d) == "main")
               for x in dsts)


def classify(seg, d):
    """回傳 (level, 規則名) 或 None。"""
    if os.path.basename(seg[0]) == "rm":
        return ("deny", "rm -rf 目標為 / ~ $HOME") if rm_hit(seg[1:]) else None
    if os.path.basename(seg[0]) != "git":
        return None
    i = 1
    while i < len(seg) and seg[i].startswith("-"):
        if seg[i] == "-C" and i + 1 < len(seg):
            d = os.path.join(d, os.path.expanduser(seg[i + 1]))
        i += 2 if seg[i] in ("-C", "-c") else 1
    if i >= len(seg):
        return None
    sub, args = seg[i], seg[i + 1:]
    if sub == "push" and push_main_hit(args, d):
        return ("deny", "force push 到 main")
    if sub == "reset" and "--hard" in args:
        return ("ask", "git reset --hard")
    if sub in ("checkout", "restore") and "." in args:
        return ("ask", "git " + sub + " .")
    if sub == "clean" and any(short_has(a, "f") or a == "--force" for a in args):
        return ("ask", "git clean -f")
    return None


def main():
    data = json.loads(sys.stdin.read())
    cmd = data["tool_input"]["command"]
    d = data.get("cwd") or os.getcwd()
    hits = []
    try:
        for seg in segments(cmd):
            while seg and (seg[0] in ("sudo", "rtk") or ASSIGN.match(seg[0])):
                seg = seg[2:] if seg[:2] == ["rtk", "proxy"] else seg[1:]
            if not seg:
                continue
            if seg[0] == "cd" and len(seg) > 1:
                d = os.path.join(d, os.path.expanduser(seg[1]))
                continue
            hit = classify(seg, d)
            if hit:
                hits.append(hit + (" ".join(seg),))
    except ValueError:
        pass  # shlex 解析不了的尾段（引號不平衡）放行，已切出的子指令照判
    for level in ("deny", "ask"):
        found = [h for h in hits if h[0] == level]
        if found:
            reason = "[WF-BASH %s] 命中規則：%s｜子指令：%s" % (
                level.upper(), "；".join(h[1] for h in found), "；".join(h[2] for h in found))
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": level,
                "permissionDecisionReason": reason}}, ensure_ascii=False))
            return


try:
    main()
except Exception:
    sys.exit(0)  # fail-open（見檔首）
```

```bash
chmod +x .claude/hooks/guard-dangerous-bash.py
bash .claude/hooks/tests/test_dangerous_bash.sh
```

**預期（綠）**：兩輪 `check_all`（有 state／無 state）各 6 段 `PASS`，加上兩段補充，最後 `ALL TESTS PASSED!`。

#### 步驟 2.3：mode 與 commit

```bash
git add .claude/hooks/guard-dangerous-bash.py .claude/hooks/tests/test_dangerous_bash.sh
git ls-files -s .claude/hooks/guard-dangerous-bash.py .claude/hooks/tests/test_dangerous_bash.sh | cut -d' ' -f1   # 兩行 100755
```

commit：`feat(hooks): deny or ask before irreversible Bash commands (#<issue>)`。

---

### Task 3：settings 註冊 + 鎖定測試

**寫入**：`.claude/hooks/tests/test_project_settings_hooks.sh`、`.claude/settings.json`
**前置**：T1、T2 已 commit（Test 3 讀 index mode）
**驗收**：AC-19、AC-20

#### 步驟 3.1（紅）：`test_project_settings_hooks.sh`

四處 Edit：

1. `DELEGATE_CWD_REL=…` 那行之後插入：
   ```bash
   FREEZE_REL='.claude/hooks/wf-guard-worktree-freeze.py'
   BASH_GUARD_REL='.claude/hooks/guard-dangerous-bash.py'
   ```
   `DELEGATE_CWD='"$CLAUDE_PROJECT_DIR"/'"$DELEGATE_CWD_REL"` 那行之後插入：
   ```bash
   FREEZE='"$CLAUDE_PROJECT_DIR"/'"$FREEZE_REL"
   BASH_GUARD='"$CLAUDE_PROJECT_DIR"/'"$BASH_GUARD_REL"
   ```
2. `check_guard` 加第 4 參數（PreToolUse 預設仍為 `block`，既有三個呼叫不變）：
   ```bash
   # 第 4 參數：預期的 onFailure（PreToolUse 預設 block；PostToolUse 預設不帶）。
   check_guard() {
     local got want event="$1" matcher="$2" cmd="$3" on_failure="${4:-}"
     got="$(jq -cS --arg e "$event" --arg m "$matcher" --arg c "$cmd" \
       '[(.hooks[$e] | arrays)[] | select(.matcher == $m) | (.hooks | arrays)[]
         | select(.command == $c)]' "$REPO_ROOT/$SETTINGS")" \
       || fail "cannot query $event / $matcher in $SETTINGS"
     if [ "$event" = "PreToolUse" ] && [ -z "$on_failure" ]; then on_failure=block; fi
     want="$(jq -ncS --arg c "$cmd" --arg f "$on_failure" \
       '[{"type": "command", "command": $c} + (if $f == "" then {} else {"onFailure": $f} end)]')"
     [ "$got" = "$want" ] || fail "$event / $matcher / $cmd handlers: $got (expected exactly $want)"
     echo "PASS: $event / $matcher / $cmd"
   }
   ```
   （取代原本 `if [ "$event" = "PreToolUse" ]; then … else … fi` 的 `want` 兩分支。）
3. `check_guard PostToolUse mcp__gemini-cli__ask-gemini "$DELEGATE_CWD post"` 之後插入：
   ```bash
   # 凍結 fail-closed；Bash 護欄刻意 fail-open（它是凍結 hook 壞掉時的自救通道），onFailure 寫明 continue 並鎖住
   check_guard PreToolUse 'Edit|Write' "$FREEZE"
   check_guard PreToolUse Bash "$BASH_GUARD" continue
   ```
4. Test 3 的迴圈清單改為：
   ```bash
   for rel in "$STAGE_CHECK_REL" "$DELEGATE_CWD_REL" "$FREEZE_REL" "$BASH_GUARD_REL"; do
   ```

```bash
bash .claude/hooks/tests/test_project_settings_hooks.sh
```

**預期（紅）**：`FAIL: PreToolUse / Edit|Write / "$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-guard-worktree-freeze.py handlers: [] (expected exactly …)`。

#### 步驟 3.2（綠）：`settings.json`

在 `PreToolUse` 陣列中 `mcp__gemini-cli__ask-gemini` 條目之後追加兩個條目（其餘不動）：

```json
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-guard-worktree-freeze.py",
            "onFailure": "block"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard-dangerous-bash.py",
            "onFailure": "continue"
          }
        ]
      }
```

```bash
bash .claude/hooks/tests/test_project_settings_hooks.sh   # 預期：5 個 check_guard PASS、4 支腳本 100755、ALL TESTS PASSED!
```

#### 步驟 3.3：回歸（AC-20）

```bash
for t in .claude/hooks/tests/*.sh; do bash "$t" >/dev/null 2>&1 && echo "ok   $t" || echo "FAIL $t"; done
python3 .claude/hooks/tests/test_delegate_cwd_logic.py   # 預期 OK
```

**預期**：6 支 `.sh`（既有 4 支、含 settings 測試，加新 2 支）全 `ok`，python 測試印 `OK`——合計 7 支，即 AC-20 的既有 5 支 + 新 2 支。commit：`chore(hooks): mount worktree freeze and Bash guard in tracked settings (#<issue>)`。

---

### Task 4：G4 MISSING COVERAGE 契約文件

**寫入**：§7 #7～#15（9 檔）
**驗收**：AC-22～AC-28；Q-8(a)(b)(c)
**注意**：`.agents/agents/*.yaml` 的 `system_prompt: |` 區塊內每行前綴**兩個空白**，插入行照樣補兩格。

#### 步驟 4.1：`delegation-and-parallel.md`（3 處）

(a) 在「`FAIL: INFRA` 自動重試規範」那段（`:73`，結尾為「待人工介入排除後再行繼續。」）之後、`### STAGE 2 派發煞車` 之前插入（前後各留一個空行）：

```markdown
#### 缺席視角契約（MISSING COVERAGE）

界線在**誰回報**：`FAIL: INFRA` 是 verifier 自己交回報告、說「環境擋住了」；`MISSING COVERAGE` 是該通道**根本沒有交回可用結果**。下表為唯一定義處，`verifier.md`、`reviewer.md`、`publisher.md`、`mcp-delegation-discipline.md`、`workflow-parallel.md` 只引用、不重述：

| 情境 | 判定 | 自動重試 | 計入通過 |
|:---|:---|:---:|:---:|
| lens 回傳合法 schema，`findings` 為空 | 合法結果（查無問題） | — | 是 |
| lens／verifier／`ask-gemini` **沒有可用回報**：逾時、空白、null、無法解析（含 verifier 報告首行不是三種狀態前綴），或 lens 自報 `MISSING COVERAGE: <lens>: <原因>` | **`MISSING COVERAGE`** | **否** | **否** |
| verifier **有回報**，首行 `FAIL: INFRA`（環境受阻） | `FAIL: INFRA` | 同 tier 1 次 | 否 |
| 某 lens 依特徵規則刻意未派發 | Guard Clause Record（主審兜底） | — | 依兜底結果 |

路由（一律不自動重試、不自動退回 STAGE 2）：

- **STAGE 3 審查 lens 缺席**：reviewer 把缺席 lens 與原因列在審查報告**頂部**，與 Guard Clause Record 分開；結論不得寫成「全部視角通過」。publisher 把同一段帶進 PR 草稿，使用者在 STAGE 4 暫停點（`strict`／`balanced`）決定補審或接受；`autonomous` 只保證寫進 PR 本文。
- **STAGE 2 驗收 verifier 缺席**：該任務不得寫入 `completed_tasks`，立即停下向使用者回報，不論 `pause_level`（同重試耗盡時的「停止並回報」）——驗收是 STAGE 2 唯一的閘門，缺席等於沒有閘門。
- **STAGE 2 implementer 的 `ask-gemini` 委派缺席**：implementer 在回報中標記 `MISSING COVERAGE: ask-gemini: <原因>`，不重派 MCP；先以 `git status`／`git log` 實查工作樹，再走既有 Fallback 自行完成。下游仍有 verifier 驗收，所以這裡降級而不停下。
- **STAGE 4 publisher 的 `ask-gemini` 草稿委派缺席**：標記後不重派，退回既有 Fallback 以 `gen-pr` 自產草稿；草稿照常經 STAGE 4 暫停點給使用者確認。
- **與「基礎設施錯誤」的界線**：派發**回傳了明確錯誤**（`400` 參數／thinking 不支援、`429`、`5xx`、連線中斷）→ 走下方退回路徑的基礎設施錯誤分支；**沒有錯誤、也沒有可用結果** → `MISSING COVERAGE`。逾時不在基礎設施錯誤清單內。
```

(b) 結果聚合表中「部分回傳 `FAIL: CODE` 或 `FAIL: INFRA`」那一列（`:123`）之後插入一列：

```markdown
| 部分單元**沒有交回可用結果**（逾時、空白、null、無法解析） | 標記 `MISSING COVERAGE`：不計 `PASS`、不寫入 `completed_tasks`、**不自動重試、不自動退回**，交由使用者決定（路由見上方「缺席視角契約」）；與 `FAIL: INFRA` 的「同 tier 重試 1 次」不同 |
```

(c) 退回路徑樹中 `  ├─ 驗收環境異常 (FAIL: INFRA)  → 同 tier 自動重試 1 次；若仍未定則暫停向使用者求助`（`:134`）之後插入：

```text
  ├─ 沒有可用回報 (MISSING COVERAGE) → 不重試、不計失敗次數，依「缺席視角契約」路由
```

#### 步驟 4.2：`workflow-parallel.md`（`:89`、`:102-104`）

`const findings = (await parallel([` 改為 `const results = await parallel([`；陣列結尾與下方註解（原 `])).filter(Boolean).flatMap(r => r.findings)`、空行、`// 回到主對話：reviewer 親自收斂…`）整段改為：

```js
])
// null 不可濾掉：逾時/空白/null/無法解析的 lens 必須留下 MISSING COVERAGE 標記（契約見 delegation-and-parallel.md「缺席視角契約」）
const lenses = ['correctness', ...activeSpecialLenses, '過度工程'] // 與上方陣列順序一致
const ok = r => Array.isArray(r?.findings)
const missing = lenses.filter((_, i) => !ok(results[i]))
const findings = results.filter(ok).flatMap(r => r.findings)

// 回到主對話：reviewer 親自收斂 findings、去重、判定真偽；missing 非空 → 報告頂部列缺席視角 → 寫審查報告 → 暫停展示（不委派）
```

（已以 node 驗證：`[{findings:[…]}, null, {findings:[]}]` → `missing = ['security']`，合法空陣列不算缺席；`undefined`、`{findings:'oops'}`、`{}` 皆判缺席。）

#### 步驟 4.3：`mcp-delegation-discipline.md`（AC-27，緊接 `:14`）

在 `:14`（「已知限制：MCP 呼叫無法逐次帶 `--print-timeout`」那段，結尾為「不在派發端。」）之後追加：

```markdown
>
> ⚠️ **逾時或空回應不是完成：標記 `MISSING COVERAGE`。** `ask-gemini` 逾時、回應空白或無法辨識時，不得視為「已完成」或「已通過」：在回報中標記 `MISSING COVERAGE: ask-gemini: <原因>`，**不自動重派**（上一段的長 timeout 會讓成本翻倍）。後續路由（implementer、publisher 各自怎麼接手）見 [`delegation-and-parallel.md`](delegation-and-parallel.md)「缺席視角契約」。
```

#### 步驟 4.4：`verifier.md:37` 與 `verifier.yaml:36`（AC-24）

兩檔同一句子串替換（yaml 的縮排在子串之外，不受影響）。舊：

```text
依 schema 輸出結構化 `findings` 列表供主 Reviewer 綜整；若遇到執行逾時或環境故障，回報包含環境受阻說明的 finding，嚴禁吞沒異常或被誤判為零缺陷。
```

新：

```text
依 schema 輸出結構化 `findings` 列表供主 Reviewer 綜整。空 `findings` 只代表「本視角已完整審查且查無問題」；若因逾時、環境故障或其他原因**無法完成本視角**，不得以空 `findings` 代替，必須回報一筆以 `MISSING COVERAGE: <lens>: <原因>` 為前綴的 finding，嚴禁吞沒異常或被誤判為零缺陷（界線見 `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`「缺席視角契約」）。
```

#### 步驟 4.5：`reviewer.md`（`:29` 之後）與 `reviewer.yaml`（`:28` 之後）（AC-25）

在「**衝突裁決：**…a11y 一律不列為可簡化項。」那一條之後插入（yaml 前綴兩格；`reviewer.yaml` 原本就缺 Guard Clause Record 一條，屬既有漂移，本次不補）：

```markdown
- **缺席視角置頂（MISSING COVERAGE）：** 任一 lens 沒有交回可用結果（逾時、空白、null、無法解析，或自報 `MISSING COVERAGE: ...` 前綴的 finding）時，審查報告**頂部、結論之前**先列「缺席視角」段，逐項寫 lens 名稱與原因；有缺席時結論不得寫成「全部視角通過」。主審親自覆核不移除缺席標記（可另註覆核結果），且與 Guard Clause Record（刻意未派發）分開列；此段隨報告交給 publisher 帶進 PR 草稿。界線見 `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`「缺席視角契約」。
```

（不改 `完成條件` 那行：#256 也改它，留著只會多一個衝突。）

#### 步驟 4.6：`publisher.md`（`:42` 之後）與 `publisher.yaml`（`:41` 之後）（AC-28）

在「**草稿優先：** 必須先讓使用者確認描述內容。」之後插入（yaml 前綴兩格）：

```markdown
- **缺席視角入 PR：** reviewer 報告頂部有「缺席視角（MISSING COVERAGE）」段時，PR 草稿必須包含同名段落，逐項列出 lens 與原因，不得刪減或改寫成通過；STAGE 4 暫停點（`strict`／`balanced`）展示草稿時使用者即可看到，`autonomous` 下只保證寫進 PR 本文。
```

#### 步驟 4.7：驗收

```bash
D=.claude/skills/gen-dev-workflow/references
for f in .claude/agents/verifier.md .claude/agents/reviewer.md $D/delegation-and-parallel.md $D/mcp-delegation-discipline.md \
         .claude/agents/publisher.md $D/workflow-parallel.md .agents/agents/verifier.yaml .agents/agents/reviewer.yaml .agents/agents/publisher.yaml; do
  printf '%s %s\n' "$(grep -c 'MISSING COVERAGE' "$f")" "$f"   # 每行 ≥ 1（AC-22 的四份＋其餘落點）
done
grep -c 'filter(Boolean)' $D/workflow-parallel.md          # 預期 0（Q-8a）
for y in .agents/agents/{verifier,reviewer,publisher}.yaml; do
  ruby -ryaml -e 'd = YAML.load_file(ARGV[0]); abort "缺 MISSING COVERAGE：" + ARGV[0] unless d["system_prompt"].include?("MISSING COVERAGE"); puts "yaml ok " + ARGV[0]' "$y"
done
```

**預期**：9 行計數皆 ≥ 1（實測 delegation 為 7、其餘各 1）、`filter(Boolean)` 為 0、3 行 `yaml ok`。審閱 AC-23：其餘文件只出現「本角色怎麼做 + 連回契約」，四方界線表與四條路由（STAGE 3 lens、STAGE 2 verifier、implementer、publisher）只在 `delegation-and-parallel.md` 出現一次；`mcp-delegation-discipline.md` 不再列路由細節。commit：`docs(workflow): define MISSING COVERAGE contract for absent review lenses (#<issue>)`。

---

### Task 5：brainstorm 回寫（`[原地修改]`）

**寫入**：`docs/brainstorm/2026-11-09-workflow-brainstorm.md`
**驗收**：AC-29（PR 編號見 §6）

`:3224`（G1）最後一欄 `⬜ 提案` 改為：

```text
✅ 已完成（<實作日>，Issue #<issue>）；未做：`$IFS`／base64 混淆偵測（規格 §5.2 排除）
```

`:3225`（G4）最後一欄 `⬜ 提案` 改為：

```text
✅ 已完成（<實作日>，Issue #<issue>）；未做：同家族隔離、雙層 timeout（規格 §5.2 排除）
```

`<issue>` 取 state 檔的 `issue` 欄位；`<實作日>` 依 env 的 Today's date。PR 編號於 STAGE 6 `gen-sync-docs-by-branchs` 補成 `Issue #<issue> / PR #<pr>`。

```bash
sed -n '3224,3225p' docs/brainstorm/2026-11-09-workflow-brainstorm.md   # 兩列最後一欄皆為 ✅ 已完成（…）
```

commit：`docs(brainstorm): mark G1 and G4 as done (#<issue>)`。

---

## 9. 整體驗收（STAGE 2 收尾）

```bash
for t in .claude/hooks/tests/*.sh; do bash "$t" >/dev/null 2>&1 && echo "ok   $t" || echo "FAIL $t"; done
python3 .claude/hooks/tests/test_delegate_cwd_logic.py
```

全綠即滿足 AC-1～AC-20；AC-21～AC-29 為審閱項（§8 各任務已列檢查指令）。

**merge 後人工確認（一次性，結果記入 PR 描述或 STAGE 6 回報）**：新 session 從主 checkout 啟動、`cd` 進任一有 state 的 worktree 後，請 Claude 以 `Edit` 改主 repo 的 `docs/plans/` 任一檔 → 應看到 `[WF-FREEZE BLOCK]`；請 Claude 在 scratchpad 建一個空 git repo 並於其中執行 `git reset --hard` → 應跳出確認框並帶 `[WF-BASH ASK]` 理由。第三項：在上述 worktree 內請 Claude 派一個 `isolation: worktree` 的 subagent，讓它以 `Write` 在**它自己的** worktree 內建一個新檔 → 必須放行（無 `[WF-FREEZE …]`）；同時請它回報 `pwd`，記下 hook 實際看到的 cwd 是 W 還是它自己的 worktree（§4 H11 的未載明處）。這三項驗的是「Claude Code 真的把 payload 這樣送進來」，自動化測試只能偽造 payload。

---

## 10. 風險、已知限制與回退

| # | 風險 | 影響 | 緩解 |
|:-:|:---|:-:|:---|
| R-1 | 與 #256、#258 衝突 | 中 | 插入點已避開兩者的 hunk（§7 末段）；`settings.json`、`test_project_settings_hooks.sh` 必衝突——rebase 時**兩邊的 `check_guard` 呼叫與 Test 3 清單都要留**（#258 的 `DEV_LOG_REL` + 本次兩支），合併後跑 `test_project_settings_hooks.sh` 確認 |
| R-2 | 凍結 hook 鎖死 Edit/Write | 高→中 | 照實列出會擋**所有 session（含主 checkout）**的情況：python3 缺失、shebang 失敗、執行權限遺失（`onFailure: block` 生效）；只擋 worktree 內 session 的情況：腳本內部例外、git 失敗（連 scratchpad／memory 寫入一起擋，因綁定判定先於讀 `file_path`）。緩解：index mode 由 settings 測試鎖定、主 checkout 不跑 git（測試鎖定）、Bash fail-open、`cd` 離開、`disableAllHooks` |
| R-3 | 誤擋並行 workflow | 高→已消除 | cwd 定位，不掃描他人 state（AC-6 測試鎖定） |
| R-4 | Bash deny 誤擋 | 中 | 引號內字串、heredoc 內文不比對；`cd`/`-C` 追蹤；deny 只收 D-2 目標。誤擋時改寫指令（例如拆開 `cd` 或改 `-F <file>` 提交）即可繞過，不需關 hook |
| R-5 | ask 在 `bypassPermissions` 不保證跳出、`dontAsk`／`-p` 會變拒絕 | 低 | §4 H7；不可逆項目已放 deny 層 |
| R-6 | subagent 的 cwd | 低 | 文件載明一般 subagent 從主對話的 cwd 起步（§4 H11），三種情況：(1) 主對話在 W → subagent 照規則凍結；(2) 主對話在 R → 透明；(3) **`isolation: worktree` 的 subagent**：hook cwd 是 W 或它自己的 worktree 均未載明——寫它自己的 worktree 一律放行（目標端判定，AC-7 補充測試兩種 cwd 都鎖定），寫 R 時若 cwd 是 W 照擋、若是它自己的 worktree 則透明。失敗處置：§9 第三項人工驗證若被擋，視為 hook bug，先以 `disableAllHooks` 解除、回報並修 hook，不改用非 isolation 派發硬闖。另：同一 session 切換到另一個 workflow 時，主對話須先 `cd <R>` 再派 STAGE 0a/0b 的 subagent（subagent 的 `cd` 不持久，被擋後只能回報）。isolation worktree 預設自 default branch 分出而非 feature branch（§4 H11），屬 `workflow-parallel.md` 既有議題，不在本次範圍 |
| R-7 | 生效時機 | 低 | hook 與 settings 從 `$CLAUDE_PROJECT_DIR` 載入：從主 checkout 啟動的 session 在 merge 並更新主 checkout 後立即套用（file watcher，含 #255／#257 在 worktree 內的 session）；從 W 啟動的 session 在 T3 commit 後即套用（§8 開頭註記） |
| R-8 | 每次 Bash 多 ~30 ms、worktree 內每次 Edit/Write 多 ~43 ms | 低 | 實測值；與 Bash 工具本身的開銷相比可忽略 |

**回退**：單獨 revert T3 的 commit 即拆除兩個掛載點（腳本留著無害）；或使用者在 `.claude/settings.local.json` 設 `"disableAllHooks": true` 立即全停。

---

## 11. 執行方式

1. **Subagent-driven（預設，本 session）**：依 `gen-dev-workflow` STAGE 2 序列執行 T1 → T2 → T3 → T4，每個非微任務派 implementer、交 verifier 驗收；T5 主對話原地修改。`pause_level=balanced` 下任務間不停，STAGE 2 整體完成時停一次。
2. **Parallel session（使用者 opt-in Workflow 時）**：第一批 `pipeline([T1, T2, T4])`（寫入路徑互不重疊，各自 implementer → verifier），第二批 T3（依賴 T1、T2 的 index mode），最後 T5 原地修改。批與批之間的暫停由主指揮控制。
