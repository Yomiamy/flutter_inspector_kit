# Subagent Bash 側錄 dev log 與 Verifier 對照驗收 — 實作計畫

> **規格**：[`docs/features/2026-11-21-subagent-dev-log.md`](../features/2026-11-21-subagent-dev-log.md)
> **日期**：2026-11-21 ｜ **模式**：Sequence ｜ **預估 Effort**：中（核心是一支 ~50 行 hook + 一支新測試；其餘為 settings 註冊與文件同步）
> **不涉及 Dart 程式碼**：`lib/`、`test/` 零改動，不需跑 `flutter test` / `flutter analyze`。
> **官方文件依據**：<https://code.claude.com/docs/en/hooks>（主對話已以 WebFetch 驗證 H1–H6；planner 另以 curl 取 `hooks.md` 補查 exit code 可見度與 `PostToolUseFailure` 細節，見 §4）。
> **實測依據**：本計畫 T1 的 hook 與測試已在 scratchpad 複本實跑（macOS、`/bin/bash` 3.2.57、`jq-1.7.1-apple`、git 2.50.1、Claude Code 2.1.328），結果見 §2.1、§8。

---

## 1. 核心判斷

【核心判斷】✅ 值得做：verifier 現在只能讀實作方的自述，「宣稱跑過但沒跑、跑失敗卻報成功」完全看不出來。官方文件確認 subagent 的 hook input 帶 `agent_id`、失敗的 Bash 走 `PostToolUseFailure` 且 `error` 首行固定為 `Exit code N`、`cwd` 跟著 Claude 走——一支零狀態的 hook 就能在邊界側錄，不需要任何 marker 檔或 transcript 解析。

【關鍵洞察】
- **資料結構**：一列 JSONL = 一次 subagent `Bash`（8 個欄位，見 §3.1）。**唯一寫入者**是 hook、只追加；讀取者是 verifier（`jq`）與人。沒有第二份狀態、沒有計數器、沒有索引。
- **可消滅的複雜度**：「主對話 vs subagent」不需要 `SubagentStart/Stop` marker——`agent_id` 存在與否就是答案（D1-A，H1 成立）。「排除 verifier 自己」不需要寫死 `agent_type` 字串——直接取 canary 那筆的 `agent_type` 當排除值。「派發方忘了附路徑 vs 側錄壞掉」用「是否附 `DEV_LOG`」一個開關分開：沒附 → 不適用（報告註明）；附了但 canary 查無 → `FAIL: INFRA`。
- **最大破壞風險**：(1) `flutter analyze` 在既有 7 info 基線下**一律 exit 1**（實測，見 §2.5）——規格 §3.5 原表「最後一筆 `exit_code != 0` → FAIL」照抄會讓每次 analyze 宣稱都被判 `FAIL: CODE`；本計畫改為分析類以尾段核對。(2) hook 與 settings 都從 `$CLAUDE_PROJECT_DIR`（session 啟動處的主 checkout）載入，**merge 進主 checkout 之前完全不生效**——本 feature 自己的 STAGE 2 用的是舊 verifier、不受新規則影響（無自舉死結），但 AC-14 必須在「從 worktree 啟動的新 session」裡做（§8.2）。

---

## 2. 實作方向與 Trade-off

### 2.1 單筆追加的原子性（`>>` / flock / 單次 write）

規格 §3.2 要求並行寫入時列與列不交錯。POSIX 對 `O_APPEND` 的保證是「定位到檔尾與寫入之間不會插入其他修改」——**前提是整筆記錄由一次 `write(2)` 寫出**。問題在於 shell 工具多半透過 stdio，長字串會被拆成多次 `write(2)`。實測（20 個 writer × 20 列並行，計交錯的列數）：

| 方向 | 作法 | 實測 | 結論 |
|:---|:---|:---|:---|
| A. `printf '%s\n' "$line" >> log` | bash 3.2 builtin 走 stdio，緩衝 1 KB | 1000 字元 0/400；**1500 字元 35/400 交錯** | ❌ 單筆上限 2000 字元（中文 6 KB）遠超 1 KB |
| B. `jq -c … >> log` | jq 的 stdout 緩衝為 `st_blksize`（APFS 4096） | 4000 字元 0/400；**5000 字元 48/400 交錯** | ❌ 同上；要守 4 KB 就得以位元組截斷，與「以字元截斷」衝突 |
| C. `flock(1)` 或 `mkdir` 鎖 | 序列化寫入 | macOS 預設無 `flock`；`mkdir` 鎖在 hook 被殺時留下殘鎖，需要過期判斷 | ❌ 多一個會壞的狀態 |
| **D. `perl` `syswrite`**（採用） | `open(">>")` + 一次 `syswrite`，並比對寫出長度 | **30000 字元 0/400** | ✅ 一次 syscall；perl 為 macOS / Linux 內建 |
| E. `python3` `os.write` | 同 D | 9000 字元 0/400 | ❌ 保證同 D，但啟動 20 ms vs perl 3.5 ms（每次 subagent Bash 都要付） |

**結論**：`jq` 負責解析與組裝（主對話要求、且與測試端同一套切片語意），**最後一步交給 `perl syswrite` 寫出**。hook 內以一行註解說明為何不用 `>>`，避免後人「簡化」回 A/B。AC-8 以 4 輪 × 50 並行、單筆約 8 KB 的記錄驗證，突變成 A 時 3/3 抓到、突變成 B 時 6/6 抓到（§8.1）。

### 2.2 hook 整體形狀

| 方向 | 作法 | 優點 | 缺點 | 結論 |
|:---|:---|:---|:---|:---|
| **A. bash + jq + git + perl**（採用） | 一次 `jq` 組裝記錄（非 subagent 在此 `select` 掉）→ `git rev-parse` 判 linked worktree → `perl` 單次寫入 | 主對話路徑只付 bash + 1 次 jq（實測 **9 ms/次**）；subagent 路徑 **30 ms/次** | 依賴 jq、perl、git ≥ 2.31（`--path-format`） | ✅ |
| B. 全 python3（同 `wf-guard-delegate-cwd.sh`） | 單一 python 程序做完 | 單程序、與既有 hook 同構 | 主對話每次 Bash 也要付 python 啟動（~20 ms），而主對話的 Bash 數量遠多於 subagent | ❌ |
| C. D1-B `SubagentStart`/`SubagentStop` marker | 起訖寫 marker 判斷是否在 subagent 內 | — | H1 已成立，marker 完全多餘；並行 subagent 下歸屬難判 | ❌ |

依賴缺失時的行為：缺 `jq` → 記錄組不出來、靜默 exit 0；缺 `perl` → 寫入失敗、`[WF-DEVLOG WARN]` + exit 1。兩者都會讓 verifier 的 canary 查無紀錄 → `FAIL: INFRA`，不會默默放行。

### 2.3 exit code 的來源（H2）

- `PostToolUse` 只在工具**成功**時觸發 → 記 `0`。文件列出的 Bash `tool_response` 只有 `stdout`、`stderr`、`interrupted`、`isImage`，沒有 exit code 欄位，也不需要。
- `PostToolUseFailure` → 從 `error` **首行**解析 `^Exit code (\d+)$`。文件明言其餘內容是顯示文字、會被中段截斷、可能插入 `Command timed out after …`，所以只看首行。
- 解析不到（shell 起不來、中斷、格式改變）→ `null`。解析出 `0`（失敗事件卻寫 0，不合理）→ 也記 `null`。**失敗事件絕不記 `0`**，以 jq 的 `select(. != 0) // null` 一個運算式守住。
- 選 `null` 而非 `-1` 之類的哨兵值：「不知道」不是數字。對照規則一律寫 `exit_code != 0`，`null` 天然落在「失敗」那一側（jq 中 `null != 0` 為真），不需要第二條規則。

### 2.4 寫入失敗的告警 exit code（H4 後半）

官方文件：exit 0 時「Claude never sees stderr」，只進 debug log；非 0/2 為 non-blocking error，transcript 顯示 `<hook name> hook error` 與 stderr 首行（`Failed with non-blocking status code: …`）；exit 2 在 `PostToolUse` / `PostToolUseFailure` 會把 stderr 交給 Claude。→ **寫入失敗用 exit 1**：使用者看得到、被稽核的 subagent 看不到、不阻斷。exit 0 等於吞掉告警，exit 2 等於干擾被稽核者，都不行。其餘所有異常（解析失敗、非 subagent、非 linked worktree）一律靜默 exit 0。

### 2.5 截斷上限（規格 §9.7）

實測本 repo `flutter analyze lib/ test/`：46 行、3861 bytes，**exit code 1**，最後一行 `7 issues found. (ran in 5.6s)`。`flutter test` 的判定資訊在最後一行（`All tests passed!` / `+975 -6: Some tests failed.`）。

| 欄位 | 上限 | 方向 | 理由 |
|:---|:---|:---|:---|
| `output_tail` | 2000 字元 | 取**尾** | 涵蓋 analyze 的 `N issues found` 與 test 的最終統計行；判定只需要結尾 |
| `command` | 1000 字元 | 取**頭** | 比對看的是工具與目標（開頭）；heredoc 寫檔之類的長指令不需要全文 |

以 jq 字串切片截斷（以 codepoint 計，不會切斷多位元組字元，AC-6 以中文 + emoji 驗證）。單筆位元組數因此有上界（最壞約 20 KB），但**原子性不靠上界**——靠 §2.1 的單次 `write(2)`，上界只是控制 log 膨脹。

### 2.6 比對範圍錨點（H5）

| 方向 | 結論 |
|:---|:---|
| **(a) `SINCE`**：主對話**每次**派發 implementer 前記下 UTC 時間（`FAIL: CODE` 重派時重記），verifier 只看 `ts >= SINCE` | ✅ 採用 |
| (b) 另以 implementer 的 `agent_id` 精確過濾 | ❌ 不做。`Task` 結果是否帶 `agent_id` 未見於 hooks 文件；且它要防的「並行任務互相背書」在同一 worktree 下其實是**真話**——他任務跑過的 `flutter test` 測的是同一棵樹。`agent_id` 仍寫進 log，供人工追查 |

排除驗收方紀錄：verifier 以 canary 那筆的 `agent_type` 為排除值（`agent_type != $ME`），不寫死 `"verifier"` 字串——custom / plugin subagent 的 `agent_type` 命名格式不必猜。同批並行的其他 verifier 同類型，一併排除。

---

## 3. 資料結構與資料流

### 3.1 dev log 記錄（`<worktree>/.claude/workflow-state/dev-log.jsonl`，一列一筆）

| 欄位 | 型別 | 來源 | 說明 |
|:---|:---|:---|:---|
| `ts` | string | jq `now \| todate` | UTC `YYYY-MM-DDTHH:MM:SSZ`，與 `SINCE` 同格式，可直接字串比較 |
| `agent_type` | string \| null | payload | subagent 類型 |
| `agent_id` | string | payload | **存在即 subagent**（判準）；缺席即主對話 → 不記 |
| `cwd` | string | payload | hook input 的工作目錄 |
| `command` | string | `tool_input.command` | 取頭 1000 字元 |
| `exit_code` | int \| null | §2.3 | 成功 `0`；失敗為首行解析值；取不到 `null`；失敗絕不為 `0` |
| `background` | bool | `tool_input.run_in_background == true` | 背景啟動列不得作為通過證據 |
| `output_tail` | string | 成功：`stdout`、`stderr` 非空者以 `\n` 串接；失敗：`error` 全文 | 取尾 2000 字元 |

不記：`session_id`、`tool_use_id`、`duration_ms`、`is_interrupt`（對照規則用不到；YAGNI）。

### 3.2 hook 判斷順序（任一不成立即 exit 0，零輸出）

```text
stdin → jq：agent_id 非空 ∧ cwd 為字串 ∧ tool_input.command 為字串？ ──否──▶ exit 0（主對話／壞 payload）
      → 組裝記錄（ts、exit_code、background、截斷）
      → git -C "$cwd" rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel
           失敗 ──▶ exit 0（非 git、cwd 不存在）
           git-dir == git-common-dir ──▶ exit 0（主 repo，沒有稽核落點）
      → mkdir -p <top>/.claude/workflow-state && perl 單次 syswrite
           失敗 ──▶ stderr [WF-DEVLOG WARN] + exit 1
      → exit 0
```

`--path-format=absolute` 讓兩個 git dir 都是絕對路徑、可直接字串比較（同一次 `rev-parse` 產出，不需 realpath）。不讀網路、不跑 `git status`、不遍歷檔案系統（規格 §3.4 第 5 點）。

### 3.3 STAGE 2 單一任務的資料流

```text
主對話：SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ) → Task(implementer)
   implementer Bash: flutter test test/x_test.dart → exit 1  ─┐ PostToolUseFailure ─┐
   implementer Bash: flutter test test/x_test.dart → exit 0  ─┤ PostToolUse ────────┼─▶ wf-dev-log.sh 各追加一列
   implementer Bash: flutter analyze lib/ test/    → exit 1  ─┘ PostToolUseFailure ─┘   （7 info 基線即 exit 1）
   回報：「（自行執行）x_test 通過；analyze 7 issues（基線）」
主對話：Task(verifier, 附 implementer 完整回報 + DEV_LOG + SINCE)
   verifier Bash①: cd '<worktree>' && echo devlog-canary-<自訂字面值>  → 呼叫結束後 hook 寫入 canary 列
   verifier Bash②: jq first(command 含 canary) → agent_type ✓（記為 ME，下一步以字面值代入）
   verifier Bash③: jq：ts >= SINCE ∧ agent_type != ME（cwd／cd 目標須在本 worktree 內才採計）
      x_test 最後一筆 exit 0 ✓（中途 exit 1 屬 red，不判 FAIL）
      analyze 尾段 "7 issues found" 與宣稱一致 ✓（exit 1 不構成不符）
   verifier 自跑 flutter test / analyze → 首行 PASS
```

### 3.4 生效範圍與時機（由 H3 文件內容導出）

- `$CLAUDE_PROJECT_DIR` 停在 session 啟動處，hook 腳本與 `.claude/settings.json`、`.claude/agents/*.md` 都從**主 checkout** 載入；`cwd` 才跟著 Claude 進 worktree。hook 用 `cwd` 定位 log，不用 `$CLAUDE_PROJECT_DIR`。
- 因此新 hook 與新 verifier 規則**同時**在「feature merge 且主 checkout 更新後、新啟動的 session」生效；新啟動的 session 不會出現「verifier 要求 canary、hook 卻沒裝」的錯配；例外是在 STAGE 2 任務進行中途更新主 checkout（見 §9 R4）。
- `.agents/`（Antigravity runtime）不鏡像 hook（payload 無 `agent_id`；先例：`wf-guard-delegate-cwd.sh` 也未鏡像進 `.agents/hooks.json`）。該 runtime 下派發不附 `DEV_LOG` → verifier 報告「未啟用」，行為等同現狀。

---

## 4. 規格 §9 假設的驗證結果

| # | 結論 | 依據 | 計畫採用 |
|:-:|:---|:---|:---|
| H1 | ✅ 成立 | common input fields：`agent_id`「Unique identifier for the subagent or in-process teammate」；文件明言 subagent 呼叫工具時 PreToolUse / PostToolUse 觸發同一組 hooks 並帶 `agent_id` / `agent_type` | 判準為 **`agent_id` 非空**。`agent_type` 不可當判準：`--agent` 啟動的主對話也帶 `agent_type`（AC-3 第二個 payload 鎖定） |
| H2 | ✅ 失敗走 `PostToolUseFailure` | `PostToolUse`「Runs immediately after a tool completes successfully」；`PostToolUseFailure` 的 `error` 首行 `Exit code N`，其餘為顯示文字、會中段截斷 | 雙事件掛同一腳本；§2.3 |
| H3 | ✅ 成立 | `cwd`「is the worktree root after Claude enters a worktree, and the new directory after Claude runs `cd`」；`${CLAUDE_PROJECT_DIR}` stays put | `git -C "$cwd" rev-parse` 找 worktree root；導出 §3.4 生效時機。subagent 的 Bash cwd 每次呼叫後重設，hook 看到的是重設前或後未見文件說明 → AC-14 觀察；若 hook 看到的 cwd 不在 worktree 內，canary 查無 → `FAIL: INFRA`（大聲失敗） |
| H4 | ✅ 合併執行 | 各層 settings 的 hooks 合併、同 handler 只跑一次；非 0/2 exit 為 non-blocking、transcript 可見 | `cbm-reindex-on-pr.sh`（`settings.local.json`）原樣並存；告警用 exit 1（§2.4） |
| H5 | 設計決策 | — | `SINCE`（§2.6） |
| H6 | ⚠️ 推論為改寫後 | `PostToolUse` 的 `tool_input` 是「the arguments sent to the tool」；本 session 實際觀察到 PreToolUse hook 把 `cat` 改寫成 `rtk read` | verifier 比對忽略 `rtk` 前綴；AC-14 實測確認 |
| H7 | 定案 | 實測（§2.5） | `output_tail` 尾 2000、`command` 頭 1000 字元 |

另有三項**實測新發現**，直接影響規格：

- **F1**：`flutter analyze lib/ test/` 在 7 info 基線下 exit 1 → 規格 §3.5 對照表與 §3.7 範例需修（§5）。
- **F2**：bash `printf >>` 與 `jq >>` 的長字串會被 stdio 拆寫（§2.1）→ 規格 §3.2「單次 `O_APPEND` 寫入」改由 `perl syswrite` 實現。
- **F3**：對目錄 `chmod 555` 擋不住對**既有檔案**的追加 → AC-9 的「目錄不可寫」fixture 改為兩個情境：既有 log `chmod 444`（追加失敗）、`.claude/` `chmod 555`（`workflow-state/` 建不出來）。

---

## 5. 規格需同步修訂（已於 0b 套用，含初審 REVISE 第 1 次）

| 規格位置 | 修訂 |
|:---|:---|
| §3.1 表格、D1 | 判準改為「`agent_id` 存在即 subagent」；註明 `agent_type` 在 `--agent` 主對話也會出現，不可當判準 |
| §3.2 `exit_code` | 型別 `int` → `int \| null`；「文件化的非零哨兵值」改為 `null`（失敗但取不到精確值）；註明成功事件記 `0` 的依據（`PostToolUse` 只在成功時觸發） |
| §3.2 append-only | 「單次 `O_APPEND` 寫入」補：由 `perl syswrite` 實現；bash `printf` / `jq` 重導向會被 stdio 拆寫（F2） |
| §3.4 第 4 點 | 告警 exit code 定為 `1`（§2.4 依據） |
| §3.5 前置 | 派發附件命名為 `DEV_LOG` / `SINCE`；**未附 `DEV_LOG` → 本節不適用，報告註明「未啟用」**；附了而 canary 查無 → `FAIL: INFRA` |
| §3.5 步驟 1、3 | canary 改為帶唯一字串的 `cd <worktree> && echo devlog-canary-…`；明載 echo 與查詢為兩次獨立 Bash、`DEV_LOG`／`SINCE`／`ME` 以字面值代入、canary 為每次自訂的字面字串（禁 `$RANDOM`／`$(date)`／照抄範例）、查詢以 `first`／`limit(1; …)` 取一筆；排除對象改為「與 canary 同 `agent_type` 的紀錄」 |
| §3.5 第 5 點 | 補**位置限定**：`cwd` 與 `cd` 目標須在本 worktree 內，否則不採計 |
| §9 H3 結論 | 「canary 自帶 `cd`，不受影響」改為「cwd 不在 worktree 內則 canary 查無 → `FAIL: INFRA`」 |
| AC-12 | `test_wf_state_rework_verdict.sh` 補「若存在」 |
| AC-14 | 改為「真實 `DEV_LOG` + 假回報」；補失敗處置（cwd 行為不符 → 不 merge、退回 0b）與 worktree 啟動 session 對正式佈局的差異 |
| §3.5 對照表 | 「最後一筆 `exit_code != 0`」限測試類；新增一列：分析類（`flutter analyze` 有任何 issue 即 exit 1）以 `output_tail` 的 issue 統計核對，exit 1 本身不構成不符（F1） |
| §3.7 範例 | `flutter analyze … → exit 0` 改為 `→ exit 1（7 info 基線）`；verifier 段改為「尾段 7 issues found ✓」 |
| §8 | 補列 `.claude/skills/gen-dev-workflow/references/workflow-parallel.md`（Workflow 路徑未接線的註記，§9 R7） |
| §9 | H1–H7 標註本計畫 §4 的結論 |
| AC-9 | 「log 目錄不可寫（`chmod`）」改為 F3 的兩個情境，且寫入失敗 exit code 斷言為 `1` |

---

## 6. 檔案異動清單

| # | 檔案 | 動作 | 任務 |
|:-:|:---|:---|:-:|
| 1 | `.claude/hooks/wf-dev-log.sh` | 新增（mode `100755`） | T1 |
| 2 | `.claude/hooks/tests/test_wf_dev_log.sh` | 新增（mode `100755`），覆蓋 AC-1～AC-10 | T1 |
| 3 | `.claude/hooks/tests/test_project_settings_hooks.sh` | 修改：鎖定兩個新條目與腳本 mode（AC-11） | T1 |
| 4 | `.claude/settings.json` | 修改：`PostToolUse` 追加 `Bash` 條目；新增 `PostToolUseFailure` 鍵 | T1 |
| 5 | `.claude/agents/verifier.md` | 修改：新增「Dev log 對照」節；判定標準表 `FAIL: CODE` / `FAIL: INFRA` 各補一條 | T2 |
| 6 | `.agents/agents/verifier.yaml` | 修改：鏡像 #5 | T2 |
| 7 | `.claude/agents/implementer.md` | 修改：工作原則補「宣稱標示來源」 | T2 |
| 8 | `.agents/agents/implementer.yaml` | 修改：鏡像 #7 | T2 |
| 9 | `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改：派發 verifier 附件；契約表兩列補條件 | T3 |
| 10 | `.claude/skills/gen-dev-workflow/SKILL.md` | 修改：STAGE 2 流程圖一行 | T3 |
| 11 | `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` | 修改：適用點 2 註記 dev log 對照未接線（規格 §8 外補列） | T3 |

不需改：`cbm-reindex-on-pr.sh`、`cbm-reindex-on-sync.sh`、`settings.local.json`（AC-12）；`.agents/hooks.json`（§3.4）；`wf-state.sh` 與 `wf-guard-*.sh`（log 檔名不以 `.json` 結尾，glob 不受影響，AC-10 鎖定）；`.gitignore`（`.claude/workflow-state/` 已在第 5 行）。

---

## 7. 任務拆分

| 順序 | 任務 | 寫入路徑 | 建議 model tier |
|:-:|:---|:---|:---|
| 1 | T1 hook + 測試 + settings 註冊 | #1～#4 | **整合（標準）**：shell 細節多（單次 write、bash 3.2、jq 切片），程式碼已定稿但不得「簡化」 |
| 2 | T2 agent 定義 | #5～#8 | **機械性（快/便宜）**：文字已定稿，主要風險是 yaml 縮排 |
| 3 | T3 workflow 文件 | #9～#11 | **機械性（快/便宜）**：文字已定稿，SKILL.md 只插一行 |

**一律序列：T1 → T2 → T3**（0b 初審裁決，不並行派發）。前一任務經 verifier `PASS` 並完成 commit 後才派發下一任務；各任務的 commit 仍走 `gen-commit`。`total_tasks=3`。

settings 註冊併入 T1 而非獨立任務：`test_project_settings_hooks.sh` 的 Test 3 讀 git index 的 mode，必須在 hook 腳本 `git add` 之後才綠，拆開就變成跨任務依賴。

**範圍驗收規則**（implementer 先 commit 才交 verifier，**不可用 `git status` 判定**——已 commit 的變更不會出現在 status）：

```bash
# <base> = worktree 自 origin/main 的分岔點；origin/main 之後前進也不影響
BASE="$(git merge-base HEAD origin/main)"
# 本任務變更集 = 已 commit + 未 commit 的追蹤檔差異 ∪ 尚未 git add 的新檔
{ git diff --name-only "$BASE" -- <本任務路徑…>; git ls-files --others --exclude-standard -- <本任務路徑…>; } | sort -u
```

- **範圍檢查**：輸出必須**恰好**等於本任務檔案清單（不多不少）。
- **越界檢查**：拿掉路徑參數跑同一組指令，全量輸出不得出現 §6 清單（11 檔）與 STAGE 1 帶入的 spec / plan 以外的路徑。先前任務已 commit 的檔案出現在全量輸出屬正常，**不得**據此判定本任務越界。

> 本 feature 自己的 STAGE 2 **不受新規則約束**：hook 與 verifier 定義都從主 checkout 載入（§3.4），merge 前派發的仍是舊 verifier，派發時**不附** `DEV_LOG`。

---

### Task 1：`wf-dev-log.sh` + 測試 + settings 註冊（TDD）

**寫入**：`.claude/hooks/wf-dev-log.sh`（新）、`.claude/hooks/tests/test_wf_dev_log.sh`（新）、`.claude/hooks/tests/test_project_settings_hooks.sh`、`.claude/settings.json`

#### 步驟 1.1（紅）：建立 hook 測試

建立 `.claude/hooks/tests/test_wf_dev_log.sh`，完整內容：

```bash
#!/usr/bin/env bash
set -euo pipefail

# subagent Bash 側錄 dev log（wf-dev-log.sh）。
# 規格：docs/features/2026-11-21-subagent-dev-log.md §7 AC-1～AC-10
# payload 形狀依官方 hooks 文件（PostToolUse 的 Bash tool_response、PostToolUseFailure 的 error 首行 `Exit code N`）。

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/wf-dev-log.sh"

TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# fixture：主 repo + linked worktree + 非 git 目錄。-c 隔離個人 git 設定（簽章、全域 hooks）
MAIN="$TMP/main"; WT="$TMP/wt"; WT2="$TMP/wt2"; PLAIN="$TMP/plain"
G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null)
"${G[@]}" init -q "$MAIN"
"${G[@]}" -C "$MAIN" commit -q --allow-empty -m init
"${G[@]}" -C "$MAIN" worktree add -q -b wt "$WT"
"${G[@]}" -C "$MAIN" worktree add -q -b wt2 "$WT2"
mkdir "$PLAIN"
DIR="$WT/.claude/workflow-state"
LOG="$DIR/dev-log.jsonl"

# payload <event> <cwd>：subagent 的基準 payload；變體由呼叫端再接 `| jq -c '<改寫>'`
payload() {
  jq -nc --arg e "$1" --arg cwd "$2" '{
      session_id: "s", hook_event_name: $e, cwd: $cwd,
      agent_id: "agent-abc", agent_type: "implementer",
      tool_name: "Bash", tool_input: {command: "flutter test", run_in_background: false},
      tool_use_id: "toolu_1"}
    | if $e == "PostToolUse"
      then .tool_response = {stdout: "All tests passed!", stderr: "", interrupted: false, isImage: false}
      else .error = "Exit code 3\nSome tests failed." end'
}

# run <stdin>：執行 hook，結果存入 OUT / ERR / CODE
run() {
  set +e
  OUT="$(printf '%s' "$1" | "$HOOK" 2>"$TMP/err")"
  CODE=$?
  set -e
  ERR="$(cat "$TMP/err")"
}
quiet() {
  [ "$CODE" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ] \
    || fail "預期 exit 0 且無輸出，實得 code=$CODE out='$OUT' err='$ERR'"
}
lines() { if [ -f "$LOG" ]; then wc -l <"$LOG" | tr -d ' '; else echo 0; fi; }
expect_lines() { [ "$(lines)" = "$1" ] || fail "預期 $1 列，實得 $(lines)"; }
last_is() { tail -n 1 "$LOG" | jq -e "$@" >/dev/null || fail "最後一列不符 $*：$(tail -n 1 "$LOG")"; }

echo "=== AC-3: 主對話（無 agent_id）不記，含 --agent session（只有 agent_type）==="
run "$(payload PostToolUse "$WT" | jq -c 'del(.agent_id, .agent_type)')"; quiet
run "$(payload PostToolUse "$WT" | jq -c 'del(.agent_id)')"; quiet
[ ! -e "$DIR" ] || fail "主對話不應建立 $DIR"
echo "PASS"

echo "=== AC-4: 主 repo、非 git 目錄、不存在的 cwd 不記 ==="
run "$(payload PostToolUse "$MAIN")"; quiet
[ ! -e "$MAIN/.claude" ] || fail "主 repo 不應建立 .claude/"
run "$(payload PostToolUse "$PLAIN")"; quiet
[ -z "$(ls -A "$PLAIN")" ] || fail "非 git 目錄不應被寫入"
run "$(payload PostToolUse "$TMP/nope")"; quiet
echo "PASS"

echo "=== AC-1: 成功指令記錄（目錄不存在時由 hook 建立）==="
run "$(payload PostToolUse "$WT")"; quiet
expect_lines 1
last_is --arg cwd "$WT" '(keys == ["agent_id","agent_type","background","command","cwd","exit_code","output_tail","ts"])
  and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  and .agent_type == "implementer" and .agent_id == "agent-abc" and .cwd == $cwd
  and .command == "flutter test" and .exit_code == 0 and .background == false
  and .output_tail == "All tests passed!"'
touch "$DIR/fixture.json" # AC-10 用：state 檔 glob 基準
echo "PASS"

echo "=== AC-2: 失敗指令記錄（PostToolUseFailure），exit code 取不到時為 null 而非 0 ==="
run "$(payload PostToolUseFailure "$WT")"; quiet
expect_lines 2
last_is '.exit_code == 3 and (.output_tail | endswith("Some tests failed."))'
run "$(payload PostToolUseFailure "$WT" | jq -c '.error = "spawn failed"')"; quiet
expect_lines 3
last_is '.exit_code == null and .output_tail == "spawn failed"'
run "$(payload PostToolUseFailure "$WT" | jq -c '.error = "Exit code 0"')"; quiet
expect_lines 4
last_is '.exit_code == null'
run "$(payload PostToolUseFailure "$WT" | jq -c 'del(.error)')"; quiet
expect_lines 5
last_is '.exit_code == null'
run "$(payload PostToolUse "$WT" | jq -c 'del(.hook_event_name)')"; quiet
expect_lines 6
last_is '.exit_code == null'
echo "PASS"

echo "=== AC-5: 背景執行標記 ==="
run "$(payload PostToolUse "$WT" | jq -c '.tool_input.run_in_background = true')"; quiet
last_is '.background == true'
echo "PASS"

echo "=== AC-6: 以字元截斷（output_tail 取尾 2000、command 取頭 1000），結果為合法 UTF-8 ==="
BIG="$(printf '中😀%.0s' $(seq 1 1500))" # 3000 字元，多位元組
CMD="$(printf 'x%.0s' $(seq 1 1500))"
run "$(payload PostToolUse "$WT" | jq -c --arg b "$BIG" --arg c "$CMD" '.tool_response.stdout = $b | .tool_input.command = $c')"; quiet
last_is --arg b "$BIG" --arg c "$CMD" '.output_tail == $b[-2000:] and (.output_tail | length) == 2000
  and .command == $c[:1000] and (.command | length) == 1000'
run "$(payload PostToolUse "$WT" | jq -c --arg b "$BIG" '.tool_response.stdout = $b | .tool_response.stderr = "尾巴"')"; quiet
last_is '(.output_tail | length) == 2000 and (.output_tail | endswith("\n尾巴"))'
iconv -f UTF-8 -t UTF-8 "$LOG" >/dev/null || fail "log 不是合法 UTF-8"
echo "PASS"

echo "=== AC-7: append-only（既有位元組不變）==="
cp "$LOG" "$TMP/before"
before_lines="$(lines)"
run "$(payload PostToolUse "$WT")"; quiet
expect_lines $((before_lines + 1))
head -c "$(wc -c <"$TMP/before")" "$LOG" | cmp -s - "$TMP/before" || fail "既有內容被改寫"
echo "PASS"

echo "=== AC-8: 並行寫入不交錯（單筆 > 4KB，可抓出 stdio 分段寫入）==="
before_lines="$(lines)"
EMOJI="$(printf '😀%.0s' $(seq 1 2000))" # 截斷後仍約 8KB，逼出 stdio 的多次 write
P8="$(payload PostToolUse "$WT" | jq -c --arg b "$EMOJI" '.tool_response.stdout = $b')"
N=50; ROUNDS=4 # 交錯屬機率事件，多輪提高檢出率
for _ in $(seq 1 "$ROUNDS"); do
  for _ in $(seq 1 "$N"); do printf '%s' "$P8" | "$HOOK" & done
  wait
done
expect_lines $((before_lines + N * ROUNDS))
jq -Rn '[inputs | fromjson] | length' "$LOG" >/dev/null || fail "有列不是合法 JSON（並行交錯）"
echo "PASS"

echo "=== AC-9: fail-open ==="
run ""; quiet
run "not json"; quiet
# warned：寫入失敗須 exit 1（non-blocking，絕不 2）、stderr 告警、stdout 乾淨
warned() {
  [ "$CODE" -eq 1 ] || fail "寫入失敗應 exit 1，實得 $CODE"
  [[ "$ERR" == *"[WF-DEVLOG WARN]"* ]] || fail "stderr 缺告警：$ERR"
  [ -z "$OUT" ] || fail "stdout 應為空：$OUT"
}
before_lines="$(lines)"
chmod 444 "$LOG" # 既有 log 不可追加（對目錄 chmod 555 擋不住追加既有檔）
run "$(payload PostToolUse "$WT")"
chmod 644 "$LOG"
warned
expect_lines "$before_lines"
mkdir "$WT2/.claude" && chmod 555 "$WT2/.claude" # workflow-state/ 建不出來
run "$(payload PostToolUse "$WT2")"
warned
echo "PASS"

echo "=== AC-10: 位置、ignore 規則、*.json glob 不受影響 ==="
[[ "$LOG" != *.json ]] || fail "log 檔名不得以 .json 結尾"
git -C "$REPO_ROOT" -c core.excludesFile=/dev/null check-ignore -q --no-index -- .claude/workflow-state/dev-log.jsonl \
  || fail ".claude/workflow-state/dev-log.jsonl 未被 repo 規則忽略"
[ "$(cd "$DIR" && echo *.json)" = "fixture.json" ] || fail "*.json glob 結果改變：$(cd "$DIR" && echo *.json)"
echo "PASS"

echo "ALL TESTS PASSED!"
```

```bash
chmod +x .claude/hooks/tests/test_wf_dev_log.sh
bash .claude/hooks/tests/test_wf_dev_log.sh
```

**預期（紅）**：停在 AC-3，`FAIL: 預期 exit 0 且無輸出，實得 code=127 … No such file or directory`。

#### 步驟 1.2（綠）：建立 hook

建立 `.claude/hooks/wf-dev-log.sh`，完整內容（**不得**把 `perl` 那段「簡化」成 `printf >>` 或 `jq >>`，理由見 §2.1）：

```bash
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

input=$(cat) || exit 0

# 截斷以字元（codepoint）計，jq 字串切片保證不切斷多位元組字元。
# 失敗事件的 exit code 只信 error 首行 `Exit code N`；解析不到（或荒謬的 0）記 null，絕不記 0。
line=$(jq -c '
  select((.agent_id // "") != "" and (.cwd | type) == "string" and (.tool_input.command | type) == "string")
  | (.hook_event_name != "PostToolUse") as $failed
  | (if $failed then (.error // "" | tostring)
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
```

```bash
chmod +x .claude/hooks/wf-dev-log.sh
bash .claude/hooks/tests/test_wf_dev_log.sh
```

**預期（綠）**：10 個 `=== AC-… ===` 區段皆 `PASS`，結尾 `ALL TESTS PASSED!`（本機約 2 秒）。

#### 步驟 1.3（紅）：settings 測試鎖定新條目

修改 `.claude/hooks/tests/test_project_settings_hooks.sh`，共 4 處：

1. `DELEGATE_CWD_REL=…` 之下新增：
   ```bash
   DEV_LOG_REL='.claude/hooks/wf-dev-log.sh'
   ```
2. `DELEGATE_CWD='"$CLAUDE_PROJECT_DIR"/'"$DELEGATE_CWD_REL"` 之下新增：
   ```bash
   DEV_LOG='"$CLAUDE_PROJECT_DIR"/'"$DEV_LOG_REL"
   ```
3. `check_guard PostToolUse mcp__gemini-cli__ask-gemini "$DELEGATE_CWD post"` 之下新增：
   ```bash
   # dev log 側錄：失敗的 Bash 只觸發 PostToolUseFailure，兩個事件都要掛（AC-11）
   check_guard PostToolUse Bash "$DEV_LOG"
   check_guard PostToolUseFailure Bash "$DEV_LOG"
   ```
   （`check_guard` 對非 `PreToolUse` 事件預期形狀不含 `onFailure`，`PostToolUseFailure` 自然落入該分支，函式本身不改。）
4. Test 3 的迴圈改為：
   ```bash
   for rel in "$STAGE_CHECK_REL" "$DELEGATE_CWD_REL" "$DEV_LOG_REL"; do
   ```

```bash
bash .claude/hooks/tests/test_project_settings_hooks.sh
```

**預期（紅）**：`FAIL: PostToolUse / Bash / "$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-dev-log.sh handlers: [] (expected exactly …)`。

#### 步驟 1.4（綠）：註冊 hook

`.claude/settings.json` 改為下列完整內容（`PreToolUse` 與既有 `PostToolUse` 條目逐字不變；只在 `PostToolUse` 末尾追加一個物件、新增 `PostToolUseFailure` 鍵；**不設 `onFailure`、不設 `timeout`、不設 `async`**——async 會讓 verifier 讀 log 時 canary 可能尚未寫入）：

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-guard-stage-check.sh",
            "onFailure": "block"
          }
        ]
      },
      {
        "matcher": "mcp__gemini-cli__ask-gemini",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-guard-delegate-cwd.sh pre",
            "onFailure": "block"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__gemini-cli__ask-gemini",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-guard-delegate-cwd.sh post"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-dev-log.sh"
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-dev-log.sh"
          }
        ]
      }
    ]
  }
}
```

Test 3 讀的是 **git index** 的 mode，hook 腳本須先進 index：

```bash
git add .claude/hooks/wf-dev-log.sh .claude/hooks/tests/test_wf_dev_log.sh
git ls-files -s -- .claude/hooks/wf-dev-log.sh .claude/hooks/tests/test_wf_dev_log.sh   # 兩檔皆 100755
bash .claude/hooks/tests/test_project_settings_hooks.sh
```

**預期（綠）**：Test 2 多出 `PASS: PostToolUse / Bash / …wf-dev-log.sh` 與 `PASS: PostToolUseFailure / Bash / …wf-dev-log.sh`；Test 3 多出 `PASS: .claude/hooks/wf-dev-log.sh exists, executable, index mode 100755`；結尾 `ALL TESTS PASSED!`。

#### 步驟 1.5：回歸與範圍

```bash
for t in .claude/hooks/tests/test_*.sh; do bash "$t" >/dev/null 2>&1 && echo "ok   $t" || echo "FAIL $t"; done
python3 .claude/hooks/tests/test_delegate_cwd_logic.py >/dev/null && echo "ok   test_delegate_cwd_logic.py"
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- .claude/hooks/ .claude/settings.json; git ls-files --others --exclude-standard -- .claude/hooks/ .claude/settings.json; } | sort -u
```

**T1 驗收**：
- `test_wf_dev_log.sh` 全綠（AC-1～AC-10，區段標題即 AC 編號）。
- `test_project_settings_hooks.sh` 全綠，且含上述 3 行新 `PASS`（AC-11）。
- 回歸迴圈全 `ok`、`test_delegate_cwd_logic.py` ok（AC-12）。迴圈以 glob 取檔：#255（`test_wf_state_rework_verdict.sh`）已 merge 進 base 時自動涵蓋，未 merge 時不存在亦不報錯。
- `<base>` 比對輸出**恰為** 4 檔：`.claude/hooks/tests/test_project_settings_hooks.sh`、`.claude/hooks/tests/test_wf_dev_log.sh`、`.claude/hooks/wf-dev-log.sh`、`.claude/settings.json`（`cbm-reindex-*.sh`、`wf-guard-*.sh` 不得出現，AC-12）。
- `jq -se 'length == 1' .claude/settings.json` 為 `true`（已含於 settings 測試 Test 1）。
- 人工確認 hook 內仍是 `perl … syswrite`、無 `exit 2`。

---

### Task 2：agent 定義（verifier 對照規則、implementer 宣稱標示）

**寫入**：`.claude/agents/verifier.md`、`.agents/agents/verifier.yaml`、`.claude/agents/implementer.md`、`.agents/agents/implementer.yaml`

#### 步驟 2.1：`verifier.md`（2 處）

1. 在「## 行為準則 (Behavioral Mindset)」段落之後、「## 兩階段驗收 (Two-Stage Verification)」之前插入整節：

````markdown
## Dev log 對照（STAGE 2 任務驗收的前置關卡）

實作方回報的「跑過 X、結果 Y」是宣稱，不是證據。subagent 在 linked worktree 內的每一次 `Bash` 都會由 `.claude/hooks/wf-dev-log.sh` 自動側錄到 dev log（JSONL，一列一筆：`ts`、`agent_type`、`agent_id`、`cwd`、`command`、`exit_code`、`background`、`output_tail`）。你以側錄核對宣稱。

**適用**：僅 STAGE 2 任務驗收模式，且派發 prompt 附有 `DEV_LOG`（dev log 絕對路徑）、`SINCE`（UTC `YYYY-MM-DDTHH:MM:SSZ`）與 implementer 完整回報。未附 `DEV_LOG` → 本節不適用，報告註明「dev log 對照：未啟用（派發未附 DEV_LOG）」後照常執行兩階段驗收。

1. **Canary（先確認側錄在運作）**。hook 在一次 Bash 呼叫**結束後**才寫入，且每次 Bash 都是新 shell、變數不保留，所以：
   - 下列 `<…>` 一律代入派發 prompt 附的**字面值**（`<WORKTREE>` = `DEV_LOG` 去掉結尾的 `/.claude/workflow-state/dev-log.jsonl`），不要寫成 `$DEV_LOG` 這類 shell 變數；
   - canary 字串**每次驗收自訂一個字面字串**（`devlog-canary-` 接任務編號與你當場想的幾個字元），不可用 `$RANDOM`、`$(date)` 等展開式（log 記的是未展開的指令原文，查不回來），也不可照抄任何範例值（舊驗收留下的同名紀錄會讓壞掉的側錄看似正常）；
   - echo 與查詢必須是**兩次獨立的 Bash 呼叫**。

   第 1 次 Bash：
   ```bash
   cd '<WORKTREE>' && echo devlog-canary-<自訂>
   ```
   第 2 次 Bash（`first` 只取最早一筆——查詢指令本身也含 canary 字串，重查時會多命中）：
   ```bash
   jq -rn --arg n 'devlog-canary-<自訂>' 'first(inputs | select(.command | contains($n))) | .agent_type' '<DEV_LOG>'
   ```
   log 不存在、`jq` 解析失敗、或輸出為空 → 首行 `FAIL: INFRA: dev log 側錄失效`，停止對照（側錄沒在運作不是代碼問題，不得改判 `FAIL: CODE`）。
2. **比對範圍**：第 2 次 Bash 輸出的 `agent_type` 即 `<ME>`。第 3 次 Bash 以字面值代入，排除所有驗收方紀錄，只看本次派發之後的被稽核者紀錄（`jq` 解析失敗同樣判 `FAIL: INFRA: dev log 側錄失效`）：
   ```bash
   jq -c --arg s '<SINCE>' --arg me '<ME>' 'select(.ts >= $s and .agent_type != $me) | {ts, cwd, command, exit_code, background, output_tail}' '<DEV_LOG>'
   ```
3. **逐條判定**回報中標示「（自行執行）」或未標示來源的測試／分析宣稱：

   | 情境 | 判定 |
   |---|---|
   | 範圍內剔除 `background == true` 啟動列後，無對應指令的紀錄（背景啟動列尚無結果，不是證據；前台失敗後的背景重試不得蓋掉那筆失敗） | `FAIL: CODE: 宣稱的 <指令> 無側錄紀錄` |
   | 測試類指令（剔除背景啟動列後）最後一筆對應紀錄 `exit_code != 0`（含 `null`：失敗但取不到 exit code） | `FAIL: CODE: 宣稱通過的 <指令> 最後一次執行失敗` |
   | `exit_code == 0` 但 `output_tail` 顯示失敗或數字對不上（如 `\| tail` 遮蔽 exit code、宣稱 981 passed 但尾段為 `+975 -6`） | `FAIL: CODE`，以 `output_tail` 為準 |
   | 分析類指令（`flutter analyze` 有任何 issue，含既有 7 info，即 exit 1） | 不看 exit code，以 `output_tail` 的 `N issues found` 核對宣稱；不符即 `FAIL: CODE` |
   | 中途失敗、最後一筆成功（TDD red → green） | 不是 FAIL；屬正常過程，可在報告中引述 |
   | 標示「（委派端回報）」的宣稱 | 不以 log 判定；報告註明「未側錄、不採信」，通過與否以你自己的執行結果為準 |

   「對應指令」為語意比對：忽略 `cd <path> &&` 前綴、`rtk` 前綴、環境變數賦值、輸出重導，比對工具與目標範圍（如 `flutter test test/ui/console_tab_test.dart`）。**位置限定**：紀錄的 `cwd` 須位於 `<WORKTREE>` 內，指令中 `cd` 的目標（若有）也須位於 `<WORKTREE>` 內；`cd` 到主 repo、其他 worktree 或任何 worktree 外路徑的紀錄不採計（視同無對應紀錄）——在別棵樹跑的結果不能為本 worktree 背書。
4. 報告的實證引述段落列出所比對的 log 紀錄（`ts` + `command` + `exit_code`）。
5. 本節是**額外**關卡：通過後仍須執行下方兩階段驗收，親自跑 `flutter test` / `flutter analyze` 並引述。
````

2. 「狀態值與判定標準」表：
   - `FAIL: CODE` 列的「觸發與判定標準」欄，把 `4. **報告格式**：…` 改編號為 `5.`，並在其前插入：
     `4. **宣稱與側錄不符**：dev log 對照（見「Dev log 對照」節）查無對應紀錄、最後一筆執行失敗或尾段與宣稱不符。<br>`
   - `FAIL: INFRA` 列的「觸發與判定標準」欄，同樣把 `4. **報告格式**` 改為 `5.`，並在其前插入：
     `4. **側錄失效**：派發附有 `DEV_LOG`，但 log 不存在、無法解析或查無本次 canary 紀錄。<br>`

#### 步驟 2.2：`verifier.yaml`

同 2.1 兩處，鏡像進 `system_prompt: |` 區塊：新節插在 `## 行為準則` 段落之後、`## 兩階段驗收` 之前，**每行前加 2 個空白**（含程式碼區塊與表格內的行，空行保持空行）；表格兩欄同步修改。

#### 步驟 2.3：`implementer.md`

「## 工作原則」中，「**回報不等於事實與證據形狀複核：**」那一條之後新增：

```markdown
- **測試／分析宣稱標示來源：** 回報中每一項「跑過 X、結果 Y」前標註 `（自行執行）` 或 `（委派端回報）`。自行執行＝你自己的 `Bash`，會被 dev log 側錄、由 verifier 逐條對照，引述的必須是**最後一次**執行的結果；委派端回報＝gemini 委派端執行、不經 Claude `Bash`、未側錄，verifier 不以 log 判定、以自己的執行為準。未標示者一律視為自行執行。
```

#### 步驟 2.4：`implementer.yaml`

同 2.3，插在 `system_prompt` 中「**回報不等於事實：**」那一條之後（yaml 版該條措辭較短，已實查；縮排 2 空白）。

#### 步驟 2.5：驗收

```bash
grep -c "devlog-canary" .claude/agents/verifier.md .agents/agents/verifier.yaml
grep -c "dev log 側錄失效" .claude/agents/verifier.md .agents/agents/verifier.yaml
grep -c "N issues found" .claude/agents/verifier.md .agents/agents/verifier.yaml
grep -c "未啟用" .claude/agents/verifier.md .agents/agents/verifier.yaml
grep -c "兩次獨立的 Bash 呼叫" .claude/agents/verifier.md .agents/agents/verifier.yaml
grep -c "first(inputs" .claude/agents/verifier.md .agents/agents/verifier.yaml
grep -c "位置限定" .claude/agents/verifier.md .agents/agents/verifier.yaml
grep -c "（委派端回報）" .claude/agents/implementer.md .agents/agents/implementer.yaml .claude/agents/verifier.md .agents/agents/verifier.yaml
ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }; puts "yaml ok"' .agents/agents/verifier.yaml .agents/agents/implementer.yaml
ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["system_prompt"].include?("devlog-canary")' .agents/agents/verifier.yaml
head -8 .claude/agents/verifier.md .claude/agents/implementer.md   # frontmatter 未被動到
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- .claude/agents/ .agents/agents/; git ls-files --others --exclude-standard -- .claude/agents/ .agents/agents/; } | sort -u
```

**T2 驗收**：各 `grep -c` ≥ 1；`yaml ok` 且第二個 ruby 輸出 `true`（新節確實落在 `system_prompt` 內，不是縮排錯位成別的 key）；frontmatter 不變；`<base>` 比對輸出恰為本任務 4 檔；越界檢查依 §7「範圍驗收規則」；人工檢視 §3.5 全部規則（canary → INFRA、兩次獨立 Bash／字面值代入／自訂字面 canary／`first` 取一筆、三種 CODE、分析類以尾段核對、位置限定、red→green、委派端、背景列、排除驗收方、僅 STAGE 2、未附 `DEV_LOG` 不適用）皆在兩檔中，且兩檔都**不含**可照抄的具體 canary 值（AC-13）。

---

### Task 3：workflow 文件同步

**寫入**：`.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`、`.claude/skills/gen-dev-workflow/SKILL.md`、`.claude/skills/gen-dev-workflow/references/workflow-parallel.md`

#### 步驟 3.1：`delegation-and-parallel.md`（3 處）

1. 「### STAGE 2 驗收的 model（與實作 model 分離）」中，`> 落地方式：…` 引言區塊之後、`> **微任務驗收例外…**` 之前插入：

```markdown
> **派發 verifier 必附 dev log 三件**（僅 Claude Code runtime：側錄 hook 只掛在 `.claude/settings.json`，`.agents/` 不鏡像；微任務原地驗收不適用）：
> 1. implementer 的**完整回報**（原文照貼，不摘要）。
> 2. `DEV_LOG=<worktree 絕對路徑>/.claude/workflow-state/dev-log.jsonl`。
> 3. `SINCE=<UTC>`：主對話**每次**派發 implementer 前以 `date -u +%Y-%m-%dT%H:%M:%SZ` 記下（`FAIL: CODE` 重派時重記），verifier 只看此後的紀錄。
>
> subagent 在 linked worktree 內的 `Bash` 由 `.claude/hooks/wf-dev-log.sh`（`PostToolUse` + `PostToolUseFailure`）自動側錄；verifier 先以 canary 確認側錄在運作，再逐條核對 implementer「（自行執行）」的宣稱（規則見 `.claude/agents/verifier.md`「Dev log 對照」）。同批並行任務共用同一份 log：他任務在同一 worktree 跑過的相同指令也會被採計——同一棵樹的結果，屬可接受的已知行為。
```

2. 「#### 階層式驗收契約與狀態解析」表的 `FAIL: CODE` 列，「觸發標準」欄改為：
   `規格偏離、過度工程、測試失敗、靜態分析新增警告/錯誤，或 implementer 宣稱自行執行的指令與 dev log 側錄不符；附帶具體反駁證據與重現步驟。`
3. 同表 `FAIL: INFRA` 列，「觸發標準」欄改為：
   `客觀環境異常、指令執行逾時、前置外部依賴未就緒、dev log 側錄失效（附了 `DEV_LOG` 但 canary 查無紀錄）等非程式代碼缺陷所致之阻礙。`

#### 步驟 3.2：`SKILL.md`（1 處）

STAGE 2 流程圖中，`│      見 references/delegation-and-parallel.md） │` 那一行之後插入一行（右框線依相鄰行對齊）：

```text
    │     （派發附回報＋DEV_LOG＋SINCE，對照 dev log 側錄）│
```

#### 步驟 3.3：`workflow-parallel.md`（1 處）

「## 適用點 2：STAGE 2 同批獨立任務」中，`> 邊界：**批與批之間的暫停由主指揮控制**…` 那段引言之後新增：

```markdown
> **Dev log 對照未接線**：本適用點的 verify 步驟不附 `DEV_LOG` / `SINCE`——`isolation: 'worktree'` 下 implementer 的 `Bash` 側錄落在隔離 worktree，路徑未經實測。verifier 會在報告註明「dev log 對照：未啟用」。需要對照時改走主檔的 `Task(...)` 路徑（附件見 [`delegation-and-parallel.md`](delegation-and-parallel.md)「STAGE 2 驗收的 model」）。
```

#### 步驟 3.4：驗收

```bash
D=.claude/skills/gen-dev-workflow
grep -c "DEV_LOG" $D/references/delegation-and-parallel.md $D/SKILL.md $D/references/workflow-parallel.md
grep -c "SINCE" $D/references/delegation-and-parallel.md $D/SKILL.md
grep -c "dev log 側錄失效" $D/references/delegation-and-parallel.md
grep -c "未接線" $D/references/workflow-parallel.md
bash .claude/hooks/tests/test_retro_skill.sh    # 會 grep SKILL.md，確認沒被誤刪
BASE="$(git merge-base HEAD origin/main)"
{ git diff --name-only "$BASE" -- $D/; git ls-files --others --exclude-standard -- $D/; } | sort -u
```

**T3 驗收**：各 `grep -c` ≥ 1；`test_retro_skill.sh` exit 0；`<base>` 比對輸出恰為本任務 3 檔（`$D/` 下其餘檔不得出現）；越界檢查依 §7「範圍驗收規則」；人工目視 SKILL.md 流程圖框線未錯位（AC-15）。

---

## 8. 整體驗收（STAGE 2 收尾，非獨立任務）

### 8.1 自動化

| AC | 覆蓋 |
|:---|:---|
| AC-1～AC-10 | `test_wf_dev_log.sh` 各 `===` 區段（標題即 AC 編號） |
| AC-11 | `test_project_settings_hooks.sh` 的 3 行新 `PASS` |
| AC-12 | 下方回歸迴圈全 `ok`；T1 範圍檢查不含 `cbm-reindex-*.sh` |
| AC-16 | `git diff --name-only "$(git merge-base HEAD origin/main)" \| grep -E '^(lib\|test)/'` 無輸出 |

```bash
for t in .claude/hooks/tests/test_*.sh; do bash "$t" >/dev/null 2>&1 && echo "ok   $t" || echo "FAIL $t"; done
python3 .claude/hooks/tests/test_delegate_cwd_logic.py >/dev/null && echo "ok   test_delegate_cwd_logic.py"
git diff --name-only "$(git merge-base HEAD origin/main)" | grep -E '^(lib|test)/' || echo "AC-16 ok"
```

> scratchpad 複本實跑結果：新測試對無 hook 為紅（AC-3，code 127）、對 hook 為綠（`/bin/bash` 3.2 亦綠）。突變皆被抓到：寫入改 `printf >>`（AC-8，3/3）、改 `jq >>`（AC-8，4 輪 × 50 下 6/6）、拿掉 linked worktree 判斷（AC-4）、`// null` 改 `// 0`（AC-2）、拿掉 `agent_id` 判斷（AC-3）。settings 測試對「缺 `PostToolUseFailure` 條目」與「條目多 `onFailure: block`」皆紅。verifier 的 canary／範圍 `jq` 指令以 hook 產出的 log 實跑，輸出符合預期。

### 8.2 人工、一次性（AC-14，結果記入 PR 描述）

hook 與新 verifier 只在「session 從載有新設定的目錄啟動」時生效（§3.4），所以這一步**必須由使用者在 worktree 根目錄開新的 Claude Code session**（`cd <worktree> && claude`），不能在原 session 做：

1. `/hooks`：確認 `PostToolUse` / `PostToolUseFailure` 的 `Bash` 下各有 `wf-dev-log.sh`。
2. 派一個一般 subagent 依序執行 `cat README.md | head -1`、`false`、`cd /tmp && echo cwd-probe`，再看 `<worktree>/.claude/workflow-state/dev-log.jsonl`：
   - 應有 `exit_code` 為 `0`、`1` 的列（H2 實測）；
   - `cat` 那列的 `command` 是否為 `rtk read …`（**H6 實測**，結果寫回規格 §9）；
   - `cwd-probe` 那列是否出現、`cwd` 為何（**H3 subagent cwd 重設語意實測**）。
3. 派發 verifier，附一份假回報「（自行執行）`flutter test test/nonexistent_test.dart` 通過」+ 真實 `DEV_LOG` + 剛記下的 `SINCE` → 首行應為 `FAIL: CODE: 宣稱的 … 無側錄紀錄`。
4. 同上，但 `DEV_LOG` 給不存在的路徑 → 首行應為 `FAIL: INFRA: dev log 側錄失效`。

**失敗處置**：第 2 步的 `cat`／`false` 兩列沒有寫進 worktree log，或紀錄的 `cwd` 不在 worktree 內（**cwd 行為不符**）→ **不 merge，退回 0b**，改走規格 H3 備案（解析指令開頭 `cd <絕對路徑> &&`，或由 workflow state 反推 worktree）。第 3、4 步首行不符 → 屬 T2 文字缺陷，退回 T2 修正後重測。

**與正式佈局的差異**：這個 session 從 worktree 啟動，`$CLAUDE_PROJECT_DIR` 與 subagent 的起始 cwd 都是 worktree；正式佈局是 session 從主 checkout 啟動（`$CLAUDE_PROJECT_DIR` = 主 checkout）、主對話在 STAGE 1 後才 `cd` 進 worktree。後者「subagent 的起始 cwd 是否跟著進 worktree」AC-14 驗不到，canary 自帶 `cd` 也驗不到；起始 cwd 不在 worktree 時症狀為不帶 `cd` 的指令無紀錄（或被位置限定剔除）→ `FAIL: CODE: 無側錄紀錄`，不會默默放行，首次正式使用若出現此 FAIL 先人工確認起始 cwd；屆時同樣依上述失敗處置退回 0b。

AC-13、AC-15 為 T2、T3 的 `git diff` 人工檢視。

---

## 9. 風險、已知限制與回退

| # | 風險 | 處置 |
|:-:|:---|:---|
| R1 | `settings.json` 改壞（多一個頂層值、事件被改成物件）會讓整份專案 hooks 拒載，連帶 `onFailure: block` 的流程守衛失效 | settings 測試 Test 1（strict 單一 JSON 物件）+ Test 2 形狀鎖定；AC-14 第 1 步 `/hooks` 目視 |
| R2 | 每次 Bash 多一個 hook 程序 | 實測主對話 9 ms/次、subagent 30 ms/次；成功路徑零輸出；不設 `async`（canary 需同步寫入） |
| R3 | 依賴 jq、perl、git ≥ 2.31 | macOS 26 皆內建（`/usr/bin/jq` 1.7.1、`/usr/bin/perl`、git 2.50）；缺任一 → canary 查無 → `FAIL: INFRA`，不默默放行 |
| R4 | STAGE 2 進行中更新主 checkout（`git pull`）：hook 註冊與 agent 定義的生效時點不明，該任務之前的 Bash 也沒被側錄 | 視 hook 設定為 **session 啟動時的快照**：主 checkout 更新後**須重啟 session** 再續行（官方 hooks 文件未保證熱載入，重啟是確定生效的作法）；重啟後重派該任務的 implementer 並重記 `SINCE` |
| R5 | H6：`command` 可能是 rtk 改寫後的指令；implementer 若主動用 `rtk flutter test`，`output_tail` 是 rtk 壓縮後的摘要、exit code 由 rtk 轉傳 | verifier 比對忽略 `rtk` 前綴、以 `output_tail` 為準；AC-14 第 2 步實測 |
| R6 | `flutter analyze` 在基線下恆 exit 1（F1） | 對照表分析類以尾段核對（T2）；規格 §3.5 / §3.7 同步修（§5） |
| R7 | Workflow 適用點 2（opt-in）未接線：verify 步驟不附 `DEV_LOG` | 文件明載「未啟用」，verifier 報告可見；需要對照時走 `Task(...)` 路徑。升級路徑：TASK_SCHEMA 加 `worktree`（implementer 以 `git rev-parse --show-toplevel` 填）並在 verify prompt 帶 `DEV_LOG=${impl.worktree}/.claude/workflow-state/dev-log.jsonl`，待 isolation 語意實測後另案 |
| R8 | 同批並行任務互相背書 | 同一 worktree 的結果屬實（§2.6），接受 |
| R9 | 竄改：subagent 有 `Write` / `Edit` 權限可改 log | 規格 §5 已列範圍外 |
| R10 | 若 subagent 把 Bash cwd 停在**他 repo** 的 linked worktree，會在該處建立 `.claude/workflow-state/dev-log.jsonl`（他 repo 未必 ignore） | 機率極低、後果為一個未追蹤檔；不加白名單（YAGNI），發生時刪檔 |
| R11 | log 無輪替 | 每列約 2–3 KB，隨 worktree 刪除（規格 §5） |
| R12 | 與 #255（`chore/202611/255-stage3-rework-verdict`，尚未 merge）同改 `SKILL.md`、`delegation-and-parallel.md` | **不阻擋**：本分支自 origin/main 開。兩案修改段落不重疊（本案 SKILL.md STAGE 2 區塊第 113–115 行附近、delegation 第 53–73 行；#255 為 SKILL.md STAGE 3 區塊與暫停表、delegation 第 157 行），衝突若有，由後 merge 者 rebase 時處理。回歸迴圈以 glob 取檔，有無 `test_wf_state_rework_verdict.sh` 皆可 |
| R13 | 既有 `verifier.md` 寫「analyze 因代碼問題非零退出 → FAIL: CODE」，與 F1 的基線 exit 1 相衝 | 屬既有措辭問題、本案範圍外不改；本案新節已明載分析類不看 exit code。建議另開 issue 釐清 |

**回退**：
- **零改碼緊急停用**：主對話派發 verifier 時**不附 `DEV_LOG`** → verifier 走「未啟用」分支，行為等同現狀；hook 仍側錄但無人讀，無副作用。
- **完整回退**：`git revert -m 1 <merge commit>`。**不可只拿掉 settings 條目**而保留 `delegation-and-parallel.md` 的派發附件——那會讓每次驗收 canary 查無 → 永遠 `FAIL: INFRA`。
- 已產生的 `dev-log.jsonl` 位於 gitignored 目錄，隨 worktree 刪除，無需清理。

未處理（YAGNI）：`agent_id` 精確過濾（§2.6）；`duration_ms` / `is_interrupt` / `tool_use_id` 欄位；log 輪替；`.agents/hooks.json` 鏡像；Workflow 路徑接線（R7）。

---

## 10. 執行方式

1. **Subagent-driven（建議）**：同一 session 依 SKILL.md STAGE 2 **序列**派發 T1 → T2 → T3（`total_tasks=3`；T1 標準、T2／T3 快/便宜），每個任務由 verifier 依該任務「驗收」段落（含 §7 範圍驗收規則）做兩階段驗收、`PASS` 後經 `gen-commit` commit 才派發下一個——**本 feature 自己的驗收不附 `DEV_LOG`**（§7 末段）。全部完成後主對話跑 §8.1 回歸；§8.2 交使用者在 worktree 開新 session 執行，結果帶進 PR。
2. **Parallel session**：另開一個獨立 session 載入本計畫，同樣依序執行 T1 → T2 → T3 與 §8.1（只是把執行移出主對話，任務本身仍序列）。適合想讓主對話保持乾淨、或要人工盯每一步時採用。
