# 功能規格：B3 專案層 settings.json 掛載流程守衛 (Project Settings Hook Guards)

> **建立日期**：2026-10-15
> **狀態**：已確認
> **來源**：[`docs/brainstorm/2026-09-17-workflow-brainstorm.md`](../brainstorm/2026-09-17-workflow-brainstorm.md) §8.2 B3、§8.5 順位 3；[`docs/architecture/2026-08-12-gen-dev-workflow-analysis.md`](../architecture/2026-08-12-gen-dev-workflow-analysis.md) 「Hook 層脆弱」缺口 (1)
> **取代**：[`docs/features/2026-08-19-delegation-cwd-sensor.md`](2026-08-19-delegation-cwd-sensor.md) §6 U-8「掛載設定不進版控」（理由見 §3.3）

---

## 1. 問題陳述

### 1.1 一句話

兩支 exit 2 守衛的腳本已進版控，**掛載它們的設定卻沒有**。換一台機器 clone，腳本都在，但沒有任何東西會呼叫它們；守衛失效時**不會有任何錯誤訊息**。

### 1.2 現況（2026-10-15 實查）

| 項目 | 事實 | 證據 |
|:---|:---|:---|
| 專案層共享設定 | `.claude/settings.json` **不存在** | `git ls-files .claude/settings.json` 無輸出 |
| 唯一掛載點 | `.claude/settings.local.json`，未被 git 追蹤 | `git check-ignore -v` → `~/.config/git/ignore:1: **/.claude/settings.local.json` |
| local 檔內容 | 只有 `hooks` 與 `alwaysThinkingEnabled` 兩個 key（brainstorm 說的權限清單／skillOverrides 已經不在） | `.claude/settings.local.json` 全文 |
| `alwaysThinkingEnabled` | workflow 執行期間暫時寫入、結束時移除的流程設定，**不屬於本需求** | `.claude/skills/gen-dev-workflow/SKILL.md:22,169,185` |
| local 內的 hook | 4 條：PreToolUse/`Agent`、PreToolUse/`mcp__gemini-cli__ask-gemini`、PostToolUse/`Bash`、PostToolUse/`mcp__gemini-cli__ask-gemini` | 同上 |
| hook 腳本 | 5 支都已追蹤，git index mode 都是 `100755` | `git ls-files -s .claude/hooks/` |
| Antigravity 側 | `.agents/hooks.json` **已進版控**，並已掛上 `wf-guard-stage-check.sh` | `git ls-files .agents/` |

最後一列說明兩側不對稱：Antigravity 的掛載跟著 repo 走，**只有 Claude Code 這一側缺掛載**。

### 1.3 觸發場景

- **(a) clone 到新機器**：拿不到 `settings.local.json`，3 條守衛全部沒有掛上。其中 `wf-guard-stage-check.sh`（防止未推進到 STAGE 5 就派 responder）與 `wf-guard-delegate-cwd.sh pre`（防止派發 prompt 缺工作目錄）是 exit 2 阻擋型守衛，這兩道防線會一起消失。
- **(b) 在 STAGE 1 建立的 worktree 內開新 session**（例如 STAGE 5 用新對話回覆 PR；**是否失效依 CLI 版本與平台而定**）：Claude Code 從 session 的工作目錄讀取專案設定，而 worktree 是重新 checkout 的，不會有未追蹤的 local 檔。
  - **事實校正（給 (b) 的前提加上條件）**：官方文件指出，CLI **v2.1.211 起**在 worktree 內會改用主 checkout 根目錄的 `settings.local.json`（[settings — Where Claude Code keeps the local file](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository)）；本機版本是 `2.1.300`。例外情況有：Windows、repo 根目錄或其 `.git`/`.claude` 的擁有者不是目前使用者、CLI 版本早於 v2.1.211。
  - 結論：(b) 是否失效**依 CLI 版本與平台而定**，沒有保證。目前**還沒有在本機實測**（見 §6 U-2）。不論 (b) 實際會不會發生，本需求的交付物都不變：守衛改由進版控的 `settings.json` 掛載後，(a) 與 (b) 都不再受上述條件影響。

### 1.4 為何是「靜默」失效

hook 有掛載但壞掉時，Claude Code 會在 transcript 顯示 `<event>:<matcher> hook error`。**根本沒掛載的腳本則完全不會被執行**，harness 不知道它存在，也就不會出現任何訊號。所以這個缺陷無法從日常使用中察覺，只能靠讀設定檔才發現。

---

## 2. 使用者故事

- **US-1（clone 即生效）**：身為 clone 本 repo 的開發者，我在 repo 根目錄開 session 時，3 條流程守衛就自動生效，不需要從 hook 腳本的註解手動複製掛載片段。
- **US-2（worktree 內同樣生效）**：身為在 STAGE 1 worktree 內開新 session 的開發者（例如 STAGE 5 回覆 PR），守衛照樣掛載，不依賴主 checkout 的本地檔、CLI 版本或平台。
- **US-3（不打擾一般貢獻者）**：身為不跑 gen-dev-workflow 的貢獻者，這些守衛對我的日常開發完全透明：不阻擋、沒有輸出、感覺不到延遲。
- **US-4（不讓失效再次靜默）**：身為維護者，我要一支自動化測試鎖住「3 條守衛註冊在進版控的設定裡，且腳本存在、可執行」。日後有人誤刪、改名，或把條目搬回 local，測試會立即失敗，而不是再度靜默失效。
- **US-5（個人設定留在本地）**：身為本機開發者，我的個人設定（`cbm-reindex-on-pr.sh` 掛載、workflow 暫時寫入的 `alwaysThinkingEnabled`）仍留在 `settings.local.json`，不進版控，也不會被共享設定覆蓋。

---

## 3. 決策與論證

### 3.1 搬哪幾條（沿用 brainstorm 原表，使用者已確認）

| # | 事件 | matcher | 指令 | 去向 |
|:-:|:---|:---|:---|:---|
| 1 | PreToolUse | `Agent` | `"$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-guard-stage-check.sh` | → `settings.json` |
| 2 | PreToolUse | `mcp__gemini-cli__ask-gemini` | `"$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-guard-delegate-cwd.sh pre` | → `settings.json` |
| 3 | PostToolUse | `Bash` | `$CLAUDE_PROJECT_DIR/.claude/hooks/cbm-reindex-on-pr.sh` | 留在 local |
| 4 | PostToolUse | `mcp__gemini-cli__ask-gemini` | `"$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-guard-delegate-cwd.sh post` | → `settings.json` |

第 3 條負責 codebase-memory 重建索引，不是守衛，而且依賴個人環境裡的 cbm MCP server。留在 local，`settings.json` 的語意才乾淨：只放「本 repo 的流程守衛」。

指令字串在 `settings.json` 中對 `$CLAUDE_PROJECT_DIR` 加雙引號（`"$CLAUDE_PROJECT_DIR"/.claude/hooks/...`）：[hooks 文件](https://code.claude.com/docs/en/hooks#reference-scripts-by-path)規定 shell form 須為路徑佔位符加雙引號，否則 repo 路徑含空白時 hook 無法啟動。其餘部分原文照搬。（PR #203 review 後由「原文照搬、不加引號」修正。）

### 3.2 是「搬」不是「複製」（論證校正）

brainstorm 寫的理由是「兩邊都註冊會雙掛載、每次觸發跑兩次」。這**跟目前的官方行為不符**：[hooks 文件](https://code.claude.com/docs/en/hooks)寫明「If you define the same handler in more than one settings file, it runs once」，完全相同的 handler 會被去重。

**重複執行（過渡狀態，範圍不只合併後）**：`settings.json` 的指令加了引號、`settings.local.json` 仍是未加引號的舊字串，兩者字串不同，不會被去重，三條守衛各會跑兩次，直到 PM-1 移除 local 的副本。這不只發生在合併後到 PM-1 之間：合併前在 worktree 根目錄啟動的 session，會同時讀到 worktree 的 `settings.json` 與主 checkout 的 local，現在就已各跑兩次。兩份都 fail-open。`stage-check` 唯讀、結果一致，無副作用。`delegate-cwd pre` 兩份並行、非原子地寫同一個 snapshot，交錯時可能寫壞檔，`post` 的 `json.load` 失敗就放行，因此極少數情況可能漏報（sensor 只告警，不阻斷）；`post` 另可能重複告警、`cwd-violations.log` 多寫一行。PM-1 緊接合併後執行即可，不需額外處理。

不過「搬」這個決策本身依然正確，理由改為：

1. **單一真相來源**：兩份副本一旦漂移（例如其中一邊改了參數或路徑），就會變成兩個**不同**的 handler，各跑一次。
2. **local 的副本別人看不到**：漂移發生在個人的未追蹤檔裡，review 抓不到。

### 3.3 為何推翻 U-8「掛載設定不進版控」

U-8 列了三個理由。逐條對照後，三個理由反對的都是「**把 `settings.local.json` 整份進版控**」，並不反對「**另外建一個只放 3 條守衛的 `settings.json`**」：

| U-8 理由 | 對本方案是否成立 |
|:---|:---|
| (1) 單一 JSON 物件，進版控會讓開發者互相覆蓋，永久衝突 | 不成立。個人設定留在 local；Claude Code 會合併兩檔，local 優先（[settings](https://code.claude.com/docs/en/settings)：「Each teammate can still override it for themselves in their own `.claude/settings.local.json`」）。shared 檔只有 3 條靜態守衛，沒有理由被個人修改。 |
| (2) public repo，225 條 permissions 中有 29 條含絕對路徑，會洩漏機器佈局 | 不成立。`settings.json` 不含 permissions，指令一律以 `$CLAUDE_PROJECT_DIR` 開頭，沒有絕對路徑。 |
| (3) 協作者真正需要的只有那 8 行掛載 | **正是本方案要 commit 的內容。** |

U-8 當時選的替代方案是「掛載片段寫在 hook 腳本的註解裡，需要的人自己複製」。這本質上仍是 Guide：沒人複製就不生效，而且不會出聲。這也是 §1.4 靜默失效的根源。

### 3.4 `$schema` 欄位：採納（U-1 已決）

- 官方範例把 `"$schema": "https://json.schemastore.org/claude-code-settings.json"` 放在設定檔第一行，用途是讓編輯器提供自動完成與即時驗證；文件也註明 schema 可能落後最新 CLI，**驗證警告不代表設定無效**（[settings](https://code.claude.com/docs/en/settings)）。
- 實查已發布的 schema：`$schema` 是合法屬性，`hooks.PreToolUse` / `hooks.PostToolUse` 都有定義，頂層 `additionalProperties: true`。本需求的 3 條條目都在 schema 涵蓋範圍內。
- 成本是一行，執行期零影響；好處是之後在編輯器手改這個檔時（strict JSON，`//` 註解或尾逗號都會造成 Settings Error）能即時抓錯。
- **使用者已採納（U-1）：`settings.json` 的第一個欄位放 `"$schema": "https://json.schemastore.org/claude-code-settings.json"`。測試不檢查此欄位，不影響任何 AC。**

### 3.5 開放問題實查結論

#### Q-A：沒有 workflow state 時是否 exit 0（不打擾一般貢獻者）

**結論：是。** 兩支守衛在沒有 state 檔時都會直接 exit 0，沒有 stderr 輸出。另外，`.claude/workflow-state/` 被 repo 的 `.gitignore:5` 排除，所以 **fresh clone 天生沒有 state 檔**，一般貢獻者永遠走放行路徑。

| 守衛 | 放行路徑（任一條命中即 exit 0） | 證據 |
|:---|:---|:---|
| `wf-guard-stage-check.sh` | payload 為空或解析失敗 | `:17-22` |
| | 派發對象不是 `responder` | `:57-60` |
| | 找不到 state 檔 | `:80-82` |
| | 目前 branch 沒有對應的 state 檔 | `:97-100` |
| `wf-guard-delegate-cwd.sh` | mode 不是 `pre`/`post` | `:131-132` |
| | 工具不是 `mcp__gemini-cli__ask-gemini` | `:143-146` |
| | 不在 worktree 內（`--git-dir == --git-common-dir`） | `:148-157` |
| | 找不到 state 檔 | `:175-176` |
| | 任何未預期例外（P-11 fail-open） | `:381-387` |

實測（2026-10-15，在無 git、無 state 的暫存目錄）：

| 情境 | exit |
|:---|:-:|
| stage-check，派發 `responder` | 0 |
| stage-check，派發 `planner` | 0 |
| stage-check，空 stdin | 0 |
| delegate-cwd `pre` | 0 |
| delegate-cwd `post` | 0 |

延遲：stage-check 每次約 36 ms，只在 `Agent` 呼叫時觸發；delegate-cwd 每次約 56 ms，只在 `mcp__gemini-cli__ask-gemini` 呼叫時觸發。兩者都感覺不到。

#### Q-B：缺 python3 時的行為

**結論：fail-open（不阻擋），但不靜默。** 守衛會失去作用，不會擋任何人的工具呼叫，而且每次觸發都會留下一行可見的 notice。

- 兩支腳本都以 bash 包 `python3 -c '...'`（stage-check `:13`、delegate-cwd `:35`），最後 `exit $?`（`:131`、`:390`）。
- 實測 `PATH=/bin`（沒有 python3）：兩支都印出 `python3: command not found`，並以 **exit 127** 結束。
- 依官方 [hooks — Other exit codes](https://code.claude.com/docs/en/hooks#other-exit-codes)：0 與 2 以外的 exit code 屬 **non-blocking error**，動作照常執行，transcript 顯示 `PreToolUse:Agent hook error`，並帶出 stderr 第一行。
- 對使用者的影響：沒裝 python3 的貢獻者，每次派發 Agent 或呼叫 gemini 時會看到一行 hook error notice，但不會被阻擋。
- 實務盤點：macOS 內建 `/usr/bin/python3`（本機確認存在）；Flutter 的 iOS/macOS 開發本來就需要 Xcode CLT。缺 python3 的情境實際上很少。

**對 AC 的影響**：這是既有行為，本需求**不改變**它，也不新增 AC 去改它。明確**不做**的兩件事：

- 不設 `onFailure: "block"`：會讓沒裝 python3 的人無法派發任何 Agent。（**註：此決策已於 2026-10-23 被 Issue #220 / PR #221 取代**——為落實 fail-closed 確定性防禦，所有 PreToolUse 守衛均已配置 `"onFailure": "block"`，當 hook 因直譯器異常非零退出時強制阻斷，杜絕安全穿透）。
- 不在腳本加 `command -v python3 || exit 0` 靜默短路：那等於把「會出聲的失效」改回「靜默失效」，正好違背本需求要解決的問題。

---

## 4. 驗收條件

### 自動化（新增 shell 測試涵蓋）

- **AC-1 設定檔進版控且合法**：`.claude/settings.json` 存在、被 git 追蹤（`git ls-files` 列得出來），沒有被 repo 內的 ignore 規則（各層 `.gitignore` 與 `.git/info/exclude`，不含個人全域 `core.excludesFile`）排除（`git -c core.excludesFile=/dev/null check-ignore --no-index` 無輸出），而且是可解析的 strict JSON。
- **AC-2 3 條守衛註冊正確**：`settings.json` 裡以下 3 組「事件 / matcher / 指令」**各恰好出現一次**，指令字串與 §3.1 表格完全相等：
  1. `PreToolUse` / `Agent` / `"$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-guard-stage-check.sh`
  2. `PreToolUse` / `mcp__gemini-cli__ask-gemini` / `"$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-guard-delegate-cwd.sh pre`
  3. `PostToolUse` / `mcp__gemini-cli__ask-gemini` / `"$CLAUDE_PROJECT_DIR"/.claude/hooks/wf-guard-delegate-cwd.sh post`
- **AC-3 腳本存在且可執行**：AC-2 指令引用的每支腳本（剝掉 `"$CLAUDE_PROJECT_DIR"/` 前綴，以 repo 根目錄為基準解析相對路徑）都存在、工作區有執行權限，而且 git index mode 是 `100755`。fresh clone 的執行權限來自 index mode，不是來自本機檔案屬性。
- **AC-4 測試的形式**：
  - 放在 `tests/` 下的 shell 腳本，風格比照 `tests/test_wf_state_total_tasks.sh`：`set -euo pipefail`、以腳本位置推出 `REPO_ROOT`、逐條印 PASS/FAIL、失敗時 exit 1、最後印出全數通過的訊息。
  - 測試**不得讀取或依賴 `settings.local.json`**，因為它不進版控，在 clone 環境裡不存在。
  - 在目前（`settings.json` 不存在）的狀態下執行必須 **FAIL**（TDD 紅燈），落地後才 PASS。

### 手動（無法自動化，於 PR 合併、主 checkout 同步後確認：計畫 PM-1 + §5.3）

- **AC-5 local 已移除 3 條**：`settings.local.json` 的 `hooks` 只剩 PostToolUse/`Bash` → `cbm-reindex-on-pr.sh` 一條。其他 key（例如當時存在的 `alwaysThinkingEnabled`）保持原樣，不動。該檔不進版控，所以這條只能在本機以 `jq` 檢視確認。
- **AC-6 實際掛載生效**：在 repo 根目錄開新 session，`/hooks` 顯示 3 條守衛的來源是 Project settings、`cbm-reindex-on-pr.sh` 的來源是 Local settings，沒有同一支守衛出現兩個來源。

### 回歸（Never break userspace）

- **AC-7 守衛行為不變**：兩支守衛腳本除了 `wf-guard-delegate-cwd.sh` 開頭的掛載說明註解（`:16-27`），沒有其他改動；既有的 `.claude/hooks/tests/test_delegate_cwd_logic.py` 照常通過。
- **AC-8 一般貢獻者無感**：在無 workflow state 的環境下，§3.5 Q-A 實測表的 5 個情境仍然全部 exit 0，沒有 stderr。
- **AC-9 註解與事實一致**：`wf-guard-delegate-cwd.sh:16` 的掛載說明改為「掛載於 `.claude/settings.json`（進版控）」，不再寫本地設定或「沿用既有三個 hook 的慣例」；`:18-27` 的 JSON 片段與 `settings.json` 的實際條目一致。

---

## 5. 範圍邊界

### In scope

1. 新增 `.claude/settings.json`，只含 §3.4 的 `$schema`（第一個欄位）與 §3.1 的 3 條守衛。
2. 從 `.claude/settings.local.json` 移除這 3 條（**合併後執行**：PR 合併、主 checkout 同步後才改，避免合併前主 checkout 失去守衛；見計畫 §1.1）。
3. 在 `tests/` 新增 shell 測試（AC-1 至 AC-4）。
4. 修正 `.claude/hooks/wf-guard-delegate-cwd.sh` 開頭的掛載說明註解（`:16` 說明句，以及 `:21`、`:26` 的 command 引號）。

### Out of scope

- **歷史文件**：以下文件中關於 `settings.local.json` 掛載的描述**不改**，它們是當時的決策紀錄：
  - `docs/plans/2026-08-14-wf-standalone-entry-guard.md`
  - `docs/plans/2026-08-19-delegation-cwd-sensor.md`
  - `docs/plans/2026-08-30-w2-redefine.md`
  - `docs/features/2026-08-19-delegation-cwd-sensor.md`（U-8 由本規格宣告取代，原文不動）
  - `docs/architecture/2026-08-12-gen-dev-workflow-analysis.md`
  - `docs/architecture/2026-09-22-gen-dev-workflow-architecture.html` 與同名的 `.architecture.json`（同一份產物，計為一份）
- **`alwaysThinkingEnabled` 的寫入位置**：仍然是 `settings.local.json`（`SKILL.md:22,169,185`），不動。
- **`cbm-reindex-on-pr.sh`**：留在 local。
- **`cbm-reindex-on-sync.sh`**：已追蹤，但 Claude Code 側沒有掛載，本次不處理。
- **`.agents/hooks.json`**（Antigravity 側）：已進版控，不動。
- **缺 python3 時的行為**：不加 `onFailure`，也不改腳本（§3.5 Q-B）。
- **matcher 寫死委派通道名稱**的問題（architecture analysis「Hook 層脆弱」缺口 (2)）：另案處理。
- **`settings.json` 的其他用途**（permissions、env、plugins 等）：YAGNI，本次只放守衛。
- **brainstorm §8.2 B3 與 §8.5 的狀態回寫**：留到 STAGE 6。

---

## 6. 風險與未決事項

### 風險

| # | 風險 | 影響 | 緩解 |
|:-:|:---|:---|:---|
| R-1 | 進版控後所有 clone 者都會執行這些守衛 | 低 | §3.5 Q-A：fresh clone 沒有 state 檔，一律 exit 0；延遲在 60 ms 以內，而且只在特定 matcher 觸發 |
| R-2 | 沒裝 python3 的貢獻者每次觸發都看到 hook error notice | 低 | 不阻擋任何動作；接受這個噪音，換取「缺依賴會出聲」（§3.5 Q-B） |
| R-3 | 從 local 搬出時手誤（漏刪造成兩個不同 handler 雙跑，或連 cbm 一起刪掉） | 中 | AC-5、AC-6 手動確認 |
| R-4 | 分支早於本變更的 worktree，其 checkout 沒有 `settings.json` | 低 | 目前 `git worktree list` 只有主 checkout；STAGE 1 的 worktree 從 main 分出，合併後新建的 worktree 都會有 |
| R-5 | 有人把條目搬回 local，或改名、刪除腳本 | 中 | AC-1 至 AC-4 的測試立即失敗 |

### 未決事項（皆已決，2026-10-15）

- **U-1｜`$schema`**：**已決，採納。** `settings.json` 第一個欄位放 `"$schema": "https://json.schemastore.org/claude-code-settings.json"`（§3.4）。
- **U-2｜場景 (b) 在本機的實際狀況**：**已決，採納措辭修正。** 場景 (b) 定為「依 CLI 版本與平台而定」（§1.3）。官方文件顯示 CLI ≥ v2.1.211 在 worktree 內會讀主 checkout 的 local 檔，本機版本是 v2.1.300，但**尚未實測**；這不影響任何交付物或 AC。若要確認，可在 worktree 內開 session 執行 `/hooks` 檢視來源。

---

## 7. 成功的定義

一句話：**流程守衛從「只在作者本機、靠手動複製才存在」，變成「跟著 repo 走，clone 就有」；之後若再被拿掉，會有一支測試出聲。**
