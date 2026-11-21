# 功能規格：Subagent Bash 側錄 dev log 與 Verifier 對照驗收（Subagent Dev Log）

> **建立日期**：2026-11-21
> **關聯提案**：[`docs/brainstorm/2026-11-09-workflow-brainstorm.md`](../brainstorm/2026-11-09-workflow-brainstorm.md) §3.6 R9（稽核對象該是系統側錄的軌跡，不是 agent 自述）、§3.6 借鏡表「委派 dev log（append-only）」
> **狀態**：草案（What & Why，待 STAGE 0a 確認）
> **模式**：Sequence
> **需求來源**：gen-grill brief（Q1–Q5 已與使用者確認）

---

## 1. 背景與痛點（Why）

### 1.1 現況實查（以程式碼為準）

| 位置 | 現況 |
|:---|:---|
| [`.claude/settings.json`](../../.claude/settings.json) | `PreToolUse`：`Agent` → `wf-guard-stage-check.sh`、`mcp__gemini-cli__ask-gemini` → `wf-guard-delegate-cwd.sh pre`（兩者 `onFailure: block`）；`PostToolUse`：只有 `mcp__gemini-cli__ask-gemini` → `wf-guard-delegate-cwd.sh post`。**沒有任何 `Bash` matcher** |
| `.claude/settings.local.json` | `PostToolUse` `Bash` → `cbm-reindex-on-pr.sh`（只在 `gh pr create` / `git push` / `git pull` 時背景 reindex，不記錄任何東西）。此檔被個人全域 gitignore 排除，**clone 環境不存在** |
| [`wf-guard-delegate-cwd.sh`](../../.claude/hooks/wf-guard-delegate-cwd.sh) | 只檢查 gemini 委派 prompt 的 cwd 與越界寫入；越界時寫 `.claude/workflow-state/cwd-violations.log`（JSONL，寫入失敗吞掉）。不記錄指令 |
| [`.claude/agents/verifier.md`](../../.claude/agents/verifier.md) | 兩階段驗收 + `PASS` / `FAIL: CODE` / `FAIL: INFRA` 契約；證據來源是 verifier **自己**跑的 `flutter test` / `flutter analyze`，對實作方「宣稱跑過什麼」只能讀回報文字 |
| [`.claude/agents/implementer.md`](../../.claude/agents/implementer.md) | MCP 可用時為「工頭」：實作與測試委派 `gemini-mcp-tool`，自身不親跑繁瑣測試；MCP 不可用時 Fallback 自行用 Bash 實作與測試 |
| `<worktree>/.claude/workflow-state/` | gitignored（`.gitignore` 第 5 行）；每個 worktree 各有一份，內含 `<branch-slug>.json` state 檔，隨 worktree 刪除 |
| `wf-state.sh` / `wf-guard-*.sh` | 以 `*.json`、`.batch-*.json`、`.pending-*.json` glob 掃描 `workflow-state/` 找 state 檔 |

### 1.2 缺陷

1. **驗收的過程證據只有自述**：verifier 能自己重跑測試確認「現在綠不綠」，但實作方回報中「我跑過 X、通過 Y」這類**過程宣稱**無從對照。宣稱跑過但沒跑、跑失敗卻報成功、只引述最後一次而隱去中途失敗——現行機制全部看不出來。
2. **是紀律不是基礎設施**：gdw 的「回報不等於事實」靠 skill 文字要求驗收方親自檢查；R9 指出的差別是「應該遵守」對上「想不記錄也做不到」。

### 1.3 借鏡什麼、不借鏡什麼

- **借 R9 的核心**：由 runtime 在邊界自動側錄「實際執行了什麼」，驗收讀側錄而非讀自述。
- **不借 Container Use 的容器隔離**：對單人 Flutter package 是過度工程。現成的 worktree 就是掛載點，`PostToolUse(Bash)` hook 就是側錄器。

---

## 2. 使用者故事

- **身為 verifier（STAGE 2）**：驗收時我讀該 worktree 的 dev log，逐條核對實作方宣稱的測試／分析指令是否真的跑過、最後一次是否成功；對不上就判 `FAIL: CODE`，不必再相信回報文字。
- **身為使用者**：我不必信任 subagent 的「全綠」；側錄壞掉時流程會明確停在 `FAIL: INFRA` 告訴我，而不是默默放行或冤枉實作端。
- **身為實作端 subagent（implementer / test-worker / feature-worker）**：側錄是透明的——不改變我的 Bash 結果、不阻斷、不往我的 context 塞訊息；hook 自身壞掉也不影響我工作。
- **身為主對話（稽核方）**：我自己的 Bash 不被側錄，dev log 只裝被稽核者的軌跡。

---

## 3. 行為規格（What）

### 3.1 側錄範圍

| 呼叫來源 | 是否記錄 | 說明 |
|:---|:---|:---|
| Claude subagent 的 `Bash`，cwd 位於 linked worktree 內 | **記錄** | 含 implementer、test-worker、feature-worker、Workflow fan-out 的 agent，以及 verifier 自己（verifier 的紀錄作為 §3.5 的 canary，比對時排除） |
| 主對話的 `Bash` | 不記錄 | 主對話是稽核方（hook input 無 `agent_id`） |
| `mcp__gemini-cli__ask-gemini` 委派端內部執行的 shell | 不記錄 | 不經 Claude `Bash` 工具，hook 看不到；屬範圍外 |
| Claude subagent 的 `Bash`，cwd 不在 linked worktree（主 repo、非 git 目錄） | 不記錄，靜默放行 | 沒有稽核落點；判定方式同 `wf-guard-delegate-cwd.sh` P-6：`--git-dir != --git-common-dir` |
| 非 `Bash` 工具（`Read` / `Write` / `Edit` 等） | 不記錄 | 範圍外（見 §5） |

- **subagent 判準**：hook input 帶 `agent_id`（非空）即 subagent，缺席即主對話。`agent_type` 不可當判準——以 `--agent` 啟動的主對話也帶 `agent_type`（官方 hooks 文件 common input fields）。
- 不依 workflow stage 過濾：STAGE 2 是主要消費者，但其他 stage 的 subagent Bash 一併記錄無害，且省掉一次 state 檔解析。
- **成功與失敗的 Bash 都必須記錄**。失敗的嘗試正是本功能要揭露的東西；若 runtime 對失敗指令改走其他 hook 事件（見 H2），同一支腳本須一併掛上。

### 3.2 記錄格式（建議 JSONL，一列一筆）

| 欄位 | 型別 | 說明 |
|:---|:---|:---|
| `ts` | string | UTC ISO 8601，`YYYY-MM-DDTHH:MM:SSZ`（與 `rework_history[].at` 同格式） |
| `agent_type` | string | subagent 類型（如 `implementer`、`verifier`） |
| `agent_id` | string | subagent 實例識別；同時是判準欄位，缺席即不記錄 |
| `cwd` | string | hook input 的工作目錄 |
| `command` | string | 實際執行的指令（`tool_input.command`）；取**頭** 1000 字元 |
| `exit_code` | int \| null | 成功為 `0`（`PostToolUse` 只在工具成功時觸發）；失敗（`PostToolUseFailure`）為 `error` 首行 `Exit code N` 的 N；取不到精確值時為 `null`（「不知道」不是數字，不用哨兵值）。**失敗絕不記成 `0`** |
| `background` | bool | 是否為 `run_in_background` 啟動。背景啟動當下尚無結果，該筆不得作為通過證據 |
| `output_tail` | string | stdout + stderr 的**尾段**，以字元（非位元組）截斷，保證輸出為合法 UTF-8；取**尾** 2000 字元（0b 定案：涵蓋 `flutter test` 結尾的 `All tests passed!` / `Some tests failed.` 與 `flutter analyze` 的 `N issues found`；成功事件為 `stdout`、`stderr` 非空者以換行串接，失敗事件為 `error` 全文） |

- **append-only**：只追加，不改寫、不刪除既有列。每筆記錄以單次 `O_APPEND` 寫入完成，STAGE 2 同 worktree 並行的多個 subagent 同時寫入時，列與列不得交錯。實作以 `perl syswrite` 單次 `write(2)` 達成——bash `printf >>`（> 約 1 KB）與 `jq >>`（> 4 KB）會被 stdio 拆成多次 write，並行時列會交錯（0b 實測）。整筆長度因截斷而有上界，但原子性靠單次 write，不靠上界。
- hook 成功路徑**不輸出任何 stdout / stderr**，不污染 subagent context。

### 3.3 位置與生命週期

- 路徑：`<worktree 根>/.claude/workflow-state/<log 檔名>`，建議 `dev-log.jsonl`。
- **檔名不得以 `.json` 結尾**：`wf-state.sh`、`wf-guard-stage-check.sh`、`wf-guard-delegate-cwd.sh` 以 `*.json` 掃描 state 檔，`.json` 結尾會被誤判為 state 檔。
- 目錄已 gitignored，log 不會進版控；隨 worktree 刪除（與既有 state 檔同一生命週期，不另做輪替或清理）。
- 目錄不存在時由 hook 建立（worktree 內的 `workflow-state/` 由 wf-state 建立，但 hook 不應假設先後順序）。

### 3.4 失敗語意（fail-open，只告警）

1. hook **絕不 `exit 2`**：`PostToolUse` 的 exit 2 會把 stderr 回饋給 subagent 模型，等同干擾被稽核者。
2. settings 條目**不設 `onFailure: block`**（與既有 `PostToolUse` 條目同形）。
3. payload 解析失敗、欄位缺失、cwd 解析失敗 → 靜默放行。
4. 寫入失敗（權限、磁碟、路徑異常）→ stderr 輸出一行 `[WF-DEVLOG WARN] …` 告警，以 exit `1` 結束（官方文件：非 0/2 為 non-blocking error，transcript 顯示 `<hook name> hook error` 與 stderr 首行，Claude 看不到；exit 0 的 stderr 只進 debug log）。
5. 不讀網路、不跑 `git status` 或任何檔案系統遍歷；每次只做 git 路徑解析與一次 append——它掛在每一次 subagent Bash 之後，延遲必須可忽略。
6. 不修改、不取代既有 hooks：`cbm-reindex-on-pr.sh` 與其 `settings.local.json` 條目原樣保留，兩個 `PostToolUse(Bash)` hook 各自獨立執行。

### 3.5 Verifier 對照規則（僅 STAGE 2 任務驗收模式）

前置：主對話派發 verifier 時，prompt 須附上 **implementer 的完整回報**、`DEV_LOG`（dev log 絕對路徑）與 `SINCE`（主對話每次派發 implementer 前記下的 UTC 時間 `YYYY-MM-DDTHH:MM:SSZ`，見 H5）。**未附 `DEV_LOG` → 本節不適用**，verifier 報告註明「dev log 對照：未啟用（派發未附 DEV_LOG）」後照常執行既有兩階段驗收（如非 Claude Code runtime）；附了而 canary 查無 → `FAIL: INFRA`。

步驟：

1. **Canary**：verifier 自訂本次驗收唯一的字串，在 `DEV_LOG` 所屬 worktree 執行 `cd <worktree> && echo devlog-canary-<唯一字串>`，再讀 dev log 查回該筆。執行約束（缺一即可能誤判）：
   - **echo 與查詢必須是兩次獨立的 Bash 呼叫**：hook 在一次 Bash 呼叫結束後才寫入，同一次呼叫內查不到。
   - `DEV_LOG` 路徑、`SINCE`、`ME`（步驟 3）一律以派發 prompt 附的**字面值**代入：每次 Bash 都是新 shell，變數不存在。
   - canary 必須是**字面字串、每次驗收自訂**：不可用 `$RANDOM`、`$(date)` 等展開式（log 記的是未展開的指令原文，查不回來），也不可照抄範例值（舊驗收的同名紀錄會讓壞掉的側錄看似正常）。
   - 查詢以 `first(...)` / `limit(1; ...)` 只取最早一筆：查詢指令自身也含 canary 字串，重查時會多命中。
2. 若 log 不存在、無法解析、或查無該筆 canary 紀錄 → **`FAIL: INFRA: dev log 側錄失效`**（側錄基礎設施沒在運作，不是代碼問題，走既有重試 1 次 → 暫停求助）。
3. 比對時排除與 canary 紀錄同 `agent_type`（記為 `ME`）的紀錄（不寫死 `verifier` 字串；同批其他 verifier 一併排除），只看 `ts >= SINCE` 的被稽核者紀錄。
4. 逐條判定實作方「宣稱由自己執行」的測試／分析指令：

下列「對應紀錄／最後一筆」皆先剔除 `background == true` 的啟動列（尚無結果，不是證據；前台失敗後的背景重試不得蓋掉那筆失敗）。

| 情境 | 判定 |
|:---|:---|
| log 中有對應指令，且最後一筆對應紀錄的實際結果與宣稱一致（測試類 `exit_code == 0` 且 `output_tail` 一致；分析類見下） | 宣稱成立，繼續既有兩階段驗收 |
| log 中**無對應指令** | `FAIL: CODE: 宣稱的 <指令> 無側錄紀錄` |
| 測試類指令最後一筆對應紀錄 `exit_code != 0`（含 `null`） | `FAIL: CODE: 宣稱通過的 <指令> 最後一次執行失敗` |
| `exit_code == 0` 但 `output_tail` 顯示失敗或數字對不上（如管線 `\| tail` 遮蔽 exit code、宣稱 981 passed 但尾段為 `+975 -6`） | `FAIL: CODE`，以 `output_tail` 為準 |
| 分析類指令（`flutter analyze` 有任何 issue，含既有 7 info，即 exit 1——0b 實測） | 不看 exit code，以 `output_tail` 的 `N issues found` 核對宣稱；不符即 `FAIL: CODE` |
| 中途失敗、最後一筆成功（TDD red → green） | **不是** FAIL；屬正常過程，可在報告中引述 |
| 回報中標示為「委派端（gemini）回報」的宣稱 | 不以 log 判定（範圍外），報告註明「未側錄、不採信」；通過與否仍以 verifier 自己的執行結果為準 |

5. 「對應指令」為語意比對：忽略 `cd <path> &&` 前綴、`rtk` 前綴、環境變數賦值、輸出重導，比對工具與目標範圍（如 `flutter test test/ui/console_tab_test.dart`）。**位置限定**：紀錄的 `cwd` 須位於本 worktree 內，指令中 `cd` 的目標（若有）也須位於本 worktree 內；`cd` 到主 repo、其他 worktree 或任何 worktree 外路徑的紀錄不採計（視同無對應紀錄）。
6. 報告的實證引述段落須列出所比對的 log 紀錄（`ts` + `command` + `exit_code`）。
7. 既有規則不變：verifier 仍須親自跑 `flutter test` / `flutter analyze` 並引述；dev log 對照是**額外**一道關卡，不取代自身執行。

### 3.6 實作端回報的歸屬標示

implementer 走 MCP 主路徑時，測試多由 gemini 委派端執行，不會出現在 dev log。為了不讓 §3.5 在主路徑上**全面誤判 `FAIL: CODE`**，implementer 回報中每一項測試／分析宣稱須標示來源：

- 自行執行（Claude subagent Bash）→ 受 §3.5 對照；
- 委派端回報 → 標示「委派端回報」，verifier 不以 log 判定。

未標示來源的宣稱一律視為「自行執行」。

### 3.7 典型流程（STAGE 2，單一任務）

```text
主對話 ──記 SINCE──Task(implementer)──▶ implementer
   implementer Bash: flutter test test/x_test.dart   → exit 1  ─┐
   implementer Bash: flutter test test/x_test.dart   → exit 0  ─┼─ PostToolUse / PostToolUseFailure hook 各追加一列
   implementer Bash: flutter analyze lib/ test/      → exit 1  ─┘  <worktree>/.claude/workflow-state/dev-log.jsonl
                                                      （7 info 基線即 exit 1）
   回報：「（自行執行）x_test 通過；analyze 7 info」
主對話 ──Task(verifier, 附回報 + DEV_LOG + SINCE)──▶ verifier
   verifier Bash: cd <worktree> && echo devlog-canary-… → canary 列出現 ✓
   讀 log：x_test 最後一筆 exit 0 ✓（中途 exit 1 屬 red 階段，不判 FAIL）、analyze 尾段 7 issues found ✓（exit 1 為基線，不構成不符）
   verifier 自跑 flutter test / analyze → 首行 PASS
```

---

## 4. 設計判斷與 Trade-off

| # | 決策 | 建議 | 捨棄方案與理由 |
|:---|:---|:---|:---|
| D1 | 分辨 subagent 與主對話 | (A) 讀 hook input 的 `agent_id`：存在即 subagent，缺席即主對話（H1 已於 0b 以官方文件驗證；`agent_type` 在 `--agent` 主對話也會出現，不可當判準） | (B) `SubagentStart` / `SubagentStop` 維護 marker 檔：多兩個掛載點與狀態檔，並行 subagent 下 marker 歸屬難判；(C) 由 `transcript_path` 的路徑型態推斷：依賴未文件化的檔案佈局。A 是零狀態方案，B/C 只在 H1 被證偽時才考慮 |
| D2 | 記錄格式 | JSONL | TSV：指令與輸出本身含 tab / 換行，需要自訂跳脫規則（多一個特殊情況）；JSONL 由 `json.dumps` 天然處理，`jq` 可直接查，且與 `cwd-violations.log` 先例一致 |
| D3 | log 位置 | `<worktree>/.claude/workflow-state/`，非 `.json` 副檔名 | 主 repo 集中一份：多 workflow 並行時混在一起，且不會隨 worktree 刪除；放 worktree 根目錄：未被 gitignore，會被誤 commit |
| D4 | hook 註冊位置 | `.claude/settings.json`（進版控），並由 `test_project_settings_hooks.sh` 鎖定 | `settings.local.json`：被全域 gitignore 排除，clone 環境沒有 hook → 每次驗收 canary 失敗、永遠 `FAIL: INFRA`。verifier 契約依賴的基礎設施必須跟著 repo 走 |
| D5 | 側錄失效的判定 | verifier 以自身 Bash 紀錄作 canary，失效判 `FAIL: INFRA` | (a) log 不存在就跳過對照：hook 壞掉時默默退化成現狀，且「實作方根本沒跑 Bash」與「hook 沒裝」無法區分；(b) log 不存在判 `FAIL: CODE`：hook 沒裝時冤枉實作端，正是 D3 契約要消滅的情況。canary 讓兩種情況可區分，且讓 H1/H3 這類設定錯誤在第一次驗收就大聲失敗 |
| D6 | gemini 主路徑的相容 | 回報標示宣稱來源（§3.6） | 要求 implementer 一律自己重跑測試：違反 implementer 的 context 壓縮原則，且屬 brief 外的流程變更；不處理：主路徑每次驗收都會被判 `FAIL: CODE`，等於把 STAGE 2 打壞 |
| D7 | 中途失敗是否判 FAIL | 只看「最後一筆對應紀錄」 | 任何失敗都判 FAIL：TDD 的 red 階段本來就要失敗，會讓正常流程全數不通過 |
| D8 | 輸出保留量 | 尾段截斷 | 全量：單次 `flutter test` 輸出可達數千行，log 膨脹且單筆無法原子追加；只留 exit code：管線遮蔽 exit code 時失去唯一的反證 |

---

## 5. 範圍邊界

### 包含（In Scope）

1. 新 hook 腳本（建議 `.claude/hooks/wf-dev-log.sh`，mode `100755`），行為依 §3.1–3.4。
2. `.claude/settings.json` 新增 `PostToolUse` 與 `PostToolUseFailure` 的 `Bash` 條目（H2 成立：失敗的 Bash 只觸發後者）。
3. 新 shell 測試 `.claude/hooks/tests/test_wf_dev_log.sh`（以 fixture payload 經 stdin 驅動、`mktemp` + `git worktree add` 建立 linked worktree fixture）。
4. `test_project_settings_hooks.sh` 鎖定新條目與腳本 mode。
5. verifier 對照規則（§3.5）、implementer 歸屬標示（§3.6）、派發 prompt 附件（§3.5 前置）的文件同步（§8）。

### 不包含（Out of Scope）

- E3 `decisions.tsv` 決策軌跡。
- session `.jsonl` transcript 對照稽核。
- 容器隔離（Container Use / Dagger）。
- STAGE 3 reviewer 或 STAGE 3 多 angle verifier lens 讀 dev log。
- log 輪替、大小上限、清理（隨 worktree 刪除）。
- 主對話 Bash、gemini 委派端內部 shell 的側錄。
- 非 Bash 工具（`Write` / `Edit`）的側錄。
- 防竄改：subagent 擁有 `Bash` / `Write` 權限，理論上可改寫或刪除 log（以 Bash 刪除時，刪除指令本身會被寫進新 log；以 `Write` / `Edit` 改寫則無痕）。本案處理的是「誤報 / 隱瞞」，不是對抗性竄改；後者需要權限隔離，另案。
- brainstorm / architecture 文件的狀態回寫（交 STAGE 6 `gen-sync-docs-by-branchs`）。

---

## 6. 破壞性分析

| 受影響對象 | 影響 | 處置 |
|:---|:---|:---|
| 所有 subagent 的 Bash | 每次多一個 hook 程序 | §3.4 第 5 點限制工作量；成功路徑零輸出 |
| `cbm-reindex-on-pr.sh`（`settings.local.json`） | 同為 `PostToolUse(Bash)` | 不修改其檔案與條目；兩者並存（H4 驗證多來源 hooks 合併執行） |
| `wf-state.sh` / `wf-guard-*.sh` 的 `*.json` 掃描 | log 若為 `.json` 會被當成 state 檔 | §3.3 禁用 `.json` 副檔名，AC-10 鎖定 |
| implementer MCP 主路徑 | 若無 §3.6，verifier 會對所有委派端宣稱判 `FAIL: CODE` | §3.6 歸屬標示 + implementer.md 同步 |
| verifier 既有流程 | 多一道對照與 canary；新增 `FAIL: INFRA` 觸發條件 | 契約三態不變，僅擴充判定準則 |
| 進行中的 STAGE 2 workflow（舊 worktree 無 log） | 升級後第一次驗收：canary 會讓 log 自動生成，但先前任務沒有紀錄 | 比對範圍僅限本次驗收任務（H5），舊任務不回溯 |
| `test_project_settings_hooks.sh` Test 2 / Test 3 | 新條目未鎖定即可能被誤刪 | 補 `check_guard PostToolUse Bash …` 與 mode 檢查 |
| `lib/`、`test/`（Dart） | 不觸及 | flutter test / analyze 基線不受影響 |

---

## 7. 驗收條件（Acceptance Criteria）

AC-1 – AC-9 由 `test_wf_dev_log.sh` 以 bash 斷言覆蓋（payload 為 fixture JSON，欄位形狀依 0b 驗證後的官方 schema；cwd 指向測試建立的 linked worktree，另以 `WF_*` 環境變數或等效方式隔離真實 repo）。

1. **AC-1 成功指令記錄**：subagent payload（帶 `agent_type`）+ exit 0 → log 恰新增 1 列；該列為合法 JSON，`ts` 符合 `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`，`agent_type`、`agent_id`、`cwd`、`command` 等於 payload 值，`exit_code == 0`；hook 的 stdout、stderr 皆為空，exit 0。
2. **AC-2 失敗指令記錄**：`PostToolUseFailure` payload（`error` 首行 `Exit code 3`）→ 新增 1 列且 `exit_code == 3`；`error` 無 `Exit code` 首行 → `exit_code == null`（不得為 `0`）。
3. **AC-3 主對話不記**：不帶 subagent 欄位的 payload → log 檔不存在或列數不變，exit 0。
4. **AC-4 非 linked worktree 不記**：cwd 為主 repo 或非 git 目錄 → 列數不變，exit 0，無輸出。
5. **AC-5 背景執行標記**：`tool_input.run_in_background == true` 的 payload → 該列 `background == true`；一般 payload 為 `false`。
6. **AC-6 截斷**：輸出長度超過上限 → `output_tail` 長度等於上限且等於原輸出的結尾；含中文多位元組字元的輸出截斷後仍為合法 UTF-8 / JSON；過長 `command` 同樣受上限約束。
7. **AC-7 append-only**：連續兩次呼叫 → 共 2 列，第 1 列位元組內容與第一次呼叫後完全相同。
8. **AC-8 並行寫入**：同時背景啟動 N（≥ 10）次 hook → 恰 N 列，每列皆為合法 JSON。
9. **AC-9 fail-open**：空 stdin、非 JSON stdin → exit 0、無輸出；寫入失敗兩情境——既有 log `chmod 444`（無法追加）、`.claude/` `chmod 555`（`workflow-state/` 建不出來）；對目錄 `chmod` 擋不住追加既有檔（0b 實測）——→ exit code 為 `1`、stderr 含 `[WF-DEVLOG WARN]`、stdout 為空、列數不變；所有情況 exit code 皆不為 2。
10. **AC-10 位置與 ignore**：log 位於 `<worktree>/.claude/workflow-state/`，檔名不以 `.json` 結尾；`git check-ignore` 確認其被 repo 規則忽略；fixture state 目錄寫入 log 後，`*.json` glob 的結果不變。
11. **AC-11 settings 鎖定**：`test_project_settings_hooks.sh` 新增斷言——`.claude/settings.json` 的 `PostToolUse` `Bash` matcher 下，本 hook 恰註冊一次、形狀為 `{"type":"command","command":…}`（無 `onFailure`）；`PostToolUseFailure` 的 `Bash` 條目同樣鎖定；腳本存在、可執行、index mode `100755`。
12. **AC-12 不破壞既有 hooks**：`cbm-reindex-on-pr.sh`、`cbm-reindex-on-sync.sh`、`settings.local.json` 無改動；`test_project_settings_hooks.sh`、`test_delegate_cwd_logic.py`、`test_wf_state_total_tasks.sh`、`test_wf_state_done_reentry.sh`、`test_wf_state_rework_verdict.sh`（若存在：#255 merge 後才有）、`test_retro_skill.sh` 全數 exit 0。
13. **AC-13 Verifier 契約文件**：`verifier.md` 與 `.agents/agents/verifier.yaml` 載明 §3.5 全部規則（canary → `FAIL: INFRA`、無對應紀錄 / 最後一筆非 0 / 尾段不符 → `FAIL: CODE`、red→green 不判 FAIL、委派端宣稱不以 log 判定、背景列不作證據、排除 verifier 自身紀錄、僅適用 STAGE 2 任務驗收模式）。人工檢視。
14. **AC-14 Verifier 情境實測（人工、一次性）**：於從 worktree 根目錄啟動的新 session 執行（hook 與 agent 定義從 session 啟動處載入）。以**真實 `DEV_LOG` + 假回報**（宣稱跑過一個 log 中不存在的指令）派發 verifier，首行為 `FAIL: CODE: …`；`DEV_LOG` 給「存在的非 git 目錄 + 固定後綴」的缺失路徑（如 `/tmp/.claude/workflow-state/dev-log.jsonl`，`WORKTREE` = `/tmp`：canary 的 `cd` 成功、echo 照常執行，但 `/tmp` 非 linked worktree、hook 不寫入，canary 必然找不到；不存在的目錄會讓 `cd` 先失敗，探針沒跑到 echo，證明不了任何事；**不可**用 worktree 內尚未建立的標準路徑——canary 的 echo 會觸發 hook 先建出該檔，canary 查得到而不會 `FAIL: INFRA`），首行為 `FAIL: INFRA: …`。同時觀察 subagent `Bash` 的 `cwd` 語意：subagent 的 Bash 未寫入 worktree log、或紀錄的 `cwd` 不在 worktree 內 → **不 merge，退回 0b** 改走 H3 備案。註：此 session 的 `$CLAUDE_PROJECT_DIR` 與 subagent 起始 cwd 都是 worktree，與正式佈局（session 從主 checkout 啟動、主對話再 `cd` 進 worktree）不同；正式佈局下 canary 自帶 `cd`、驗不到 subagent 起始 cwd（merge 前主 checkout 尚無此 hook，也無從預先驗證）；起始 cwd 不在 worktree 時症狀為不帶 `cd` 的指令無紀錄（或被位置限定剔除）→ `FAIL: CODE: 無側錄紀錄`，首次正式使用若出現此 FAIL 先人工確認 subagent 起始 cwd。另跑一個輸出 >30KB 的探針（如 `seq 1 10000`），確認 payload 帶 `tool_response.persistedOutputPath` 且 `output_tail` 為輸出結尾；若無此欄位，`output_tail` 缺結尾摘要行時應視為截斷而非「數字對不上」，退回 0b 修 verifier 規則。結果記入 PR 描述。
15. **AC-15 派發與回報文件閉環**：§8 所列其餘文件已更新，人工檢視。
16. **AC-16 Dart 零觸及**：`git diff --name-only main...HEAD` 不含 `lib/`、`test/` 路徑。

---

## 8. 需同步的文件

| 檔案 | 改動 |
|:---|:---|
| `.claude/agents/verifier.md`、`.agents/agents/verifier.yaml` | 兩階段驗收前加入 dev log 對照步驟（§3.5）；`FAIL: CODE` / `FAIL: INFRA` 判定準則表補對應條件 |
| `.claude/agents/implementer.md`、`.agents/agents/implementer.yaml` | 回報中每項測試／分析宣稱標示「自行執行 / 委派端回報」（§3.6） |
| `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 「STAGE 2 驗收的 model」段補：派發 verifier 時附 implementer 完整回報、dev log 路徑與比對範圍錨點；階層式契約表的 `FAIL: INFRA` 觸發補「dev log 側錄失效」 |
| `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` | 適用點 2 註記：Workflow 的 verify 步驟不附 `DEV_LOG`，dev log 對照未接線（`isolation: 'worktree'` 下側錄位置未實測），verifier 報告註明未啟用；需要對照時走 `Task(...)` 路徑 |
| `.claude/skills/gen-dev-workflow/SKILL.md` | STAGE 2 流程圖「委派實作任務，verifier 兩階段階層式驗收」處註記 dev log 對照（一行，指向 references） |
| `.claude/hooks/tests/test_project_settings_hooks.sh` | 見 AC-11 |

---

## 9. 開放問題（需於 0b 以官方文件驗證的假設）

0b 須先以 Context7 / 官方 hooks 文件逐一驗證下列假設，並以實測 payload 佐證；**H1 或 H3 被證偽且無 D1 備案可行時，停止並回報使用者**，不得以猜測的 payload 形狀寫測試。

1. **H1：subagent 識別欄位**。假設 subagent 內觸發的 hook input 帶 `agent_id` / `agent_type`，主對話則缺席。需確認：欄位名稱、是否 `PostToolUse` 也帶、Workflow fan-out agent 是否同樣帶。證偽則改走 D1 的 (B) 或 (C)。
   - **0b 結論：✅ 成立。** 判準為 `agent_id` 非空；`agent_type` 在 `--agent` 主對話也會出現，不可當判準。D1 (B)/(C) 不需要。
2. **H2：失敗指令的事件與 exit code 來源**。需確認：exit code ≠ 0 的 Bash 觸發 `PostToolUse` 還是 `PostToolUseFailure`（或兩者皆否）；exit code 位於 `tool_response` 的哪個欄位，或只能從錯誤文字解析；被中斷 / 逾時時的形狀。若失敗只走 `PostToolUseFailure`，同一腳本須一併掛上——這是為滿足 §3.1「失敗必記」，屬 brief「PostToolUse(Bash)」的必要延伸。
   - **0b 結論：✅ 失敗只觸發 `PostToolUseFailure`。** 其 `error` 首行為 `Exit code N`，其餘為顯示文字（可能中段截斷、插入逾時訊息）；`PostToolUse` 的 Bash `tool_response` 無 exit code 欄位，成功事件記 `0`。同一腳本掛兩事件。
3. **H3：hook input `cwd` 是否反映 subagent 實際所在 worktree**。主對話於 STAGE 1 後 `cd` 進 worktree；需確認 subagent 的 Bash 與 hook input `cwd` 是 worktree 還是原始啟動目錄。若是後者，備案為解析指令開頭的 `cd <絕對路徑> &&`，或由 workflow state 反推目標 worktree（同 `wf-guard-delegate-cwd.sh` P-6）。D5 的 canary 保證此假設錯誤時會以 `FAIL: INFRA` 大聲失敗，不會默默放行。
   - **0b 結論：✅ 成立。** `cwd` 為 Claude 進入的 worktree root、`cd` 後為新目錄；`$CLAUDE_PROJECT_DIR` 停在 session 啟動處，不可用。hook 以 `git -C "$cwd" rev-parse` 定位 worktree。連帶：hook 腳本與 settings、agent 定義都從主 checkout 載入，merge 並更新主 checkout 前不生效。subagent Bash cwd 每次呼叫後重設的語意未見文件 → AC-14 觀察；若 hook 看到的 cwd 不在 worktree 內，canary 查無 → `FAIL: INFRA`（大聲失敗，不會默默放行）。
4. **H4：多來源 hooks 合併**。確認 `settings.json` 與 `settings.local.json` 的同事件 `Bash` matcher 會合併並各自執行，`cbm-reindex-on-pr.sh` 不被覆蓋；並確認 `PostToolUse` 非 0/2 exit code 的 stderr 對使用者的可見度，據以選定 §3.4 第 4 點的告警 exit code。
   - **0b 結論：✅ 合併執行**，同一 handler 定義在多檔只跑一次；告警 exit code 定為 `1`（§3.4 第 4 點）。
5. **H5：比對範圍錨點**。同一 worktree 跨任務、跨 FAIL 重派、甚至並行任務共用一份 log，需界定「本次驗收」的範圍。候選：(a) 主對話派發 implementer 前記下 UTC 時間 `since`，verifier 只看之後的紀錄；(b) 若 `Task` 結果可取得 subagent 的 `agent_id`，以 `agent_id` 精確過濾（可排除並行任務互相背書）。建議 (a) 為基線，(b) 在 H1 驗證 `agent_id` 可得時升級。
   - **0b 結論：採 (a) `SINCE`**，每次派發 implementer（含 FAIL 重派）前重記。(b) 不做：`Task` 結果是否帶 `agent_id` 未見文件，且同一 worktree 內他任務跑過的相同指令測的是同一棵樹，「互相背書」屬實。`agent_id` 仍寫入 log 供人工追查。
6. **H6：`command` 欄位是否為 rtk 改寫後的指令**。PreToolUse 的 rtk hook 會改寫指令；確認 `PostToolUse` 看到的是改寫前或改寫後，§3.5 第 5 點的語意比對兩者皆須容忍。
   - **0b 結論：⚠️ 推論為改寫後**（文件：`tool_input` 為「the arguments sent to the tool」；0b 期間實際觀察到 PreToolUse 把 `cat` 改寫為 `rtk read`）。比對忽略 `rtk` 前綴；AC-14 實測確認。
7. **截斷上限數值**：`output_tail` 與 `command` 的上限、整筆長度上限，由 0b 依 `flutter test` / `flutter analyze` 實際輸出結尾長度定案。
   - **0b 結論：** `output_tail` 尾 2000 字元、`command` 頭 1000 字元。實測 `flutter analyze lib/ test/` 46 行、3861 bytes、**exit 1**、最後一行 `7 issues found.`；`flutter test` 的判定資訊在最後一行。
