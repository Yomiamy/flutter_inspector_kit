# B3 專案層 settings.json 掛載流程守衛：實作計畫

依據 [`docs/features/2026-10-15-project-settings-hook-guards.md`](../features/2026-10-15-project-settings-hook-guards.md)（已確認）制定。

> 狀態：實作計畫（STAGE 0b，plan-verifier 初審後修正第 1 次）｜日期：2026-10-15
> 前置裁決（不可再議）：
> - **§3.1**：搬 3 條守衛到 `settings.json`，`cbm-reindex-on-pr.sh` 留在 local；指令字串對 `$CLAUDE_PROJECT_DIR` 加雙引號（PR #203 review 後修正；原為原文照搬不加引號）。
> - **U-1**：採納 `$schema`，放在 `settings.json` 第一個欄位。
> - **U-2**：場景 (b) 措辭定為「依 CLI 版本與平台而定」（已回寫規格 §1.3、§6）。
>
> **任務編號約定**：STAGE 2 只有 **T1、T2**（`total_tasks=2`）。local 檔的修改編為 **PM-1（合併後待辦）**，刻意不用 `T` 前綴，避免編排者把它算進 STAGE 2 的任務總數。

---

## 1. 實作方向的 trade-off 分析

整體改動很小：1 支新測試、1 個新設定檔、3 行註解，外加 1 次本機 JSON 編輯。真正需要設計判斷的只有三件事：**local 檔什麼時候改**、**測試怎麼斷言才不會形同虛設**、**local 檔怎麼改才不誤傷**。

### 1.1 核心難題：`settings.local.json` 的修改時機

#### 決定時機的事實（官方文件，2026-10-15 取得）

| # | 事實 | 出處 |
|:-:|:---|:---|
| F-1 | Claude 在 session 中進入 worktree 後，`${CLAUDE_PROJECT_DIR}` **仍指向 session 起始的主 checkout** | [hooks — Reference scripts by path](https://code.claude.com/docs/en/hooks)（"`${CLAUDE_PROJECT_DIR}` stays put"） |
| F-2 | 共享的 `.claude/settings.json` 從 session 的 **primary working directory** 讀取；只有 `/cd` 才會改讀新目錄的設定（v2.1.246+） | [settings](https://code.claude.com/docs/en/settings)（"reads the shared `.claude/settings.json` from the session's primary working directory"） |
| F-3 | 在 worktree 內，`settings.local.json` 用的是**主 checkout 根目錄那一份**；worktree 自己沒有 | 同上（"In a worktree, it uses the file at the main checkout's root"） |
| F-4 | 直接修改設定檔裡的 hooks，**file watcher 通常會即時套用到執行中的 session** | [hooks — Disable or remove hooks](https://code.claude.com/docs/en/hooks)（"normally picked up automatically by the file watcher"） |
| F-5 | 完全相同的 handler 出現在多個設定檔時**僅執行一次**（字串須完全相等） | [hooks](https://code.claude.com/docs/en/hooks)（"it runs once"） |

推論：

- local 檔**只有一份**，路徑是 `/Users/yomiry/StudioWorkspace/flutter_inspector/.claude/settings.local.json`（F-3）。worktree 裡沒有可改的副本，所以 PM-1 **只能在主 checkout 路徑執行**。
- 目前這個 workflow session 從主 checkout 啟動。STAGE 1 之後雖然 `cd` 進 worktree，讀的仍是**主 checkout 的** `settings.json`（F-2）。合併前主 checkout 沒有這個檔，**守衛完全靠 local 檔撐著**。
- 只要動到 local 檔，執行中的 session 就可能立即失去守衛（F-4）。測試只讀 worktree 裡進版控的 `settings.json`，**偵測不到這個空窗**。

#### 三個時機選項

| 方案 | 何時改 local | 優點 | 缺點 | 判定 |
|:---|:---|:---|:---|:-:|
| **A：PR 合併、主 checkout 同步之後** | STAGE 6 開頭（PM-1） | 合併前守衛完全不受影響。PM-1 執行時主 checkout 已有 `settings.json`。兩邊字串不同（`settings.json` 加引號、local 為舊的未加引號），F-5 不會去重，兩份都會執行；這是過渡狀態，PM-1 後恢復單一來源（影響見 PM-1 段） | AC-5/AC-6 要到合併後才能確認（規格 §4 已同步改寫）；PM-1 不計入 STAGE 2 的 `total_tasks` | **採用** |
| B：STAGE 2 內，和 T1、T2 同批 | 實作期間 | AC-5/AC-6 能在 STAGE 2/3 確認 | 從改檔那一刻到合併並 pull 之前，主 checkout **完全沒有守衛**。受影響的正好是本 PR 自己會走的路徑：STAGE 2 剩下的 gemini 委派（`delegate-cwd pre/post`），以及 STAGE 5 回覆 PR review 時派發 responder（`stage-check`） | 否決 |
| C：STAGE 4 建立 PR 後、合併前 | review 期間 | 空窗比 B 短 | STAGE 5 就在這段空窗裡，而 `stage-check` 是 STAGE 5 唯一的防線 | 否決 |

**採用 A。** 決定性理由：B、C 在合併前拿掉的守衛，正是本 PR 在 STAGE 2 與 STAGE 5 要靠的那幾條。A 的代價只是把兩條手動 AC 延後確認，交付物不變。

**空窗的精確範圍**：

- 對 PM-1 之後才開的 session：沒有空窗。這些 session 啟動時就從主 checkout 的 `settings.json` 讀到 3 條守衛。
- 對 `git pull` 當下已在執行的 session：能不能即時讀到新出現的 `settings.json`，要看 file watcher（F-4 的措辭是 "normally"），不保證。
- 實務上沒有影響。STAGE 6 不派發 Agent，也不呼叫 gemini；兩支守衛在非 responder、stage 不是 2 的情況下本來就直接放行。

### 1.2 測試斷言的設計

| 方向 | 作法 | 問題 | 判定 |
|:---|:---|:---|:-:|
| 甲：golden file | 把整份 `settings.json` 拿去和期望檔做 diff | 之後在檔案裡加任何無關內容（例如另一條 hook）測試就紅，太脆 | 否決 |
| 乙：只檢查存在 | `jq` 找得到該指令即算通過 | 抓不到重複註冊，也抓不到 matcher 或事件放錯 | 否決 |
| **丙：逐組恰好一次，handler 整個物件比對** | 每組「事件 / matcher」下，用 `jq` 收集 command 相同的**所有** handler（不看其他欄位），整份必須**等於** `[{"type":"command","command":<指令>}]`（事件與內層 `hooks` 須為 array） | 無 | **採用**（AC-2 的定義，再加上鎖住多出來的欄位） |

handler 整個物件比對：重複註冊、多出任何欄位（例如 `timeout`、`onFailure`）、`type` 被改掉，或事件被改成物件，收集結果都不等於預期而 FAIL。目前 local 檔的 3 條條目都只有 `type` 與 `command` 兩個欄位，T1 的 `settings.json` 也一樣，所以不會誤判（§1.4 GREEN 實測）。

AC-1 的兩個細節，都已實測：

- **`git check-ignore` 必須加 `--no-index`。** 已追蹤的檔案預設不受 ignore 規則檢查，不加這個旗標的話，對已追蹤的檔永遠沒有輸出，AC-1 的這半條就形同虛設。
- **不能加 `-v`。** verbose 模式連 `!` 否定規則的命中也會輸出。在 `.claude/*` 加 `!.claude/settings.json` 這種合法的「重新納入」寫法下，帶 `-v` 會誤判成 FAIL（M-2 實測，見 §1.4）。

另外兩個細節：

- AC-1 的 JSON 驗證用 `jq -se 'length == 1 and (.[0] | type == "object")'`：`-s` 讓多個頂層 JSON 值（Claude Code 的 strict parser 會拒絕）與 top-level array 都判 FAIL；stderr 不吞，jq 缺失或解析錯誤的真正原因會印出來。
- AC-3 的腳本路徑直接取自 AC-2 的同一組常數，不另外解析整份 JSON。AC-2 已經保證這些指令完全相等地存在。

### 1.3 local 檔的修改手法

| 方向 | 問題 | 判定 |
|:---|:---|:-:|
| 手動編輯 | 容易漏刪或連 cbm 一起刪（規格 R-3），而且無法重現 | 否決 |
| 依 matcher 刪整個群組 | 同一個 matcher 下若有使用者另加的 handler，會被一起刪掉 | 否決 |
| **依 command 字串刪 handler，再清掉空群組與空事件** | 精準、冪等，`.hooks` 以外的 key 一律不碰 | **採用** |

寫回的方式是「從**目前的原檔**讀 → 寫到暫存檔 → 成功後才 `cat` 回原檔」。原檔的權限與 inode 都保留，`jq` 失敗時原檔也不會被清空。

備份只在**不存在時**才建立。重跑 PM-1 時不會用已經改過的版本覆蓋原始備份；而且因為 jq 讀的是原檔而非備份，就算留下過期的備份也不會把舊內容寫回原檔。

### 1.4 計畫撰寫時已做的實測（scratch clone，不影響 repo）

T1 測試在 scratch clone 中的紅綠燈與變異矩陣（修正版測試，2026-10-15）：

| 情境 | 期望 | 實測 |
|:---|:-:|:---|
| 沒有 `settings.json` | FAIL | `not tracked by git` |
| 檔案存在但未 `git add` | FAIL | `not tracked by git` |
| `git add` 之後 | PASS | exit 0 |
| Agent 條目重複註冊 | FAIL | `registered 2 times` |
| 缺 PostToolUse | FAIL | `registered 0 times` |
| 指令多一個尾端空白 | FAIL | `registered 0 times` |
| handler 多一個 `timeout` 欄位 | FAIL | `registered 0 times` |
| handler `type` 改成 `http` | FAIL | `registered 0 times` |
| matcher 改錯 | FAIL | `registered 0 times` |
| 條目放錯事件 | FAIL | `registered 0 times` |
| 拿掉 `$schema` | PASS | exit 0（測試不檢查此欄位） |
| 非法 JSON | FAIL | jq 的 parse error 照常印出，再接 `not valid JSON` |
| **`.gitignore` 加 `.claude/*` 與 `!.claude/settings.json`（M-2 對照組）** | **PASS** | exit 0。帶 `-v` 的舊寫法會輸出 `.gitignore:141:!.claude/settings.json`，因而誤判 FAIL；不帶 `-v` 輸出為空 |
| `.gitignore` 加 `.claude/` | FAIL | `matched by an ignore rule` |
| `.gitignore` 加 `.claude/settings.json` | FAIL | `matched by an ignore rule` |
| 腳本 index mode 改成 `100644` | FAIL | `index mode is '100644'` |
| 工作區拿掉 x 權限 | FAIL | `is not executable` |

PM-1 與 AC-5（用目前 local 檔的副本，`TMPDIR` 指向 scratch 目錄）：

- 第一次執行：輸出只剩 cbm 一條，`alwaysThinkingEnabled` 保留，檔案權限維持 `644`，AC-5 通過。
- 重跑：備份仍是原始版本（4 條 handler 都在），AC-5 照樣通過。
- 若在 AC-5 之前先移除 `alwaysThinkingEnabled`（模擬 STAGE 6 的環境清理），AC-5 的 diff 會 FAIL。這就是 AC-5 必須緊接在 PM-1 之後的原因（§5.3）。

AC-8 的 5 個情境已在主 checkout 實測：全部 exit 0，沒有 stderr。

---

## 2. 檔案異動清單

| 檔案路徑 | 類型 | 異動說明 | 任務 |
|:---|:-:|:---|:-:|
| `tests/test_project_settings_hooks.sh` | 新增（`100755`） | AC-1 到 AC-4 的 shell 測試 | T1 |
| `.claude/settings.json` | 新增 | `$schema` 加上 3 條守衛 | T1 |
| `.claude/hooks/wf-guard-delegate-cwd.sh` | 修改掛載說明註解（`:16`、`:18-27`） | 修正掛載註解（AC-9） | T2 |
| `/Users/yomiry/StudioWorkspace/flutter_inspector/.claude/settings.local.json` | **僅本機修改，沒有 git diff** | 移除 3 條守衛（AC-5） | PM-1（**合併後，不計入 `total_tasks`**） |
| `docs/features/2026-10-15-project-settings-hook-guards.md` | 已於 STAGE 0b 修改 | 狀態改為「已確認」、U-1/U-2 已決、§4 手動 AC 時機與 §5 In scope 第 2 項改為合併後 | — |

**明確不動**：`wf-guard-stage-check.sh`（整支）、`wf-guard-delegate-cwd.sh` 開頭掛載說明註解以外的部分（`:18-27` 的 JSON 片段須與 T1 的條目一致，含雙引號）、`.agents/hooks.json`、`SKILL.md` 中 `alwaysThinkingEnabled` 的寫入邏輯，以及規格 §5 列出的歷史文件。

---

## 3. 任務拆分

STAGE 2 的範圍是 **T1、T2，`total_tasks=2`**。PM-1 在合併後執行，**不計入**任務數，否則 STAGE 3 的完成度閘門會永遠卡住。

T1、T2 都在 **STAGE 1 建立的 worktree**（`.claude/worktrees/<slug>/`）裡執行，以下相對路徑都以 worktree 根目錄為準。

---

### T1：新增 shell 測試（紅）→ 新增 `.claude/settings.json`（綠）

- **等級**：機械性 → 快/便宜（2 個檔案，內容完整給定）
- **寫入檔案**：`tests/test_project_settings_hooks.sh`、`.claude/settings.json`
- **步驟 1（紅）**：（下方測試腳本為初版；PR #203 review 後改為依 事件+matcher+command 收集 handler 並比對唯一形狀、`jq -s` 驗單一 JSON object、指令字串含雙引號，最終版以 `tests/test_project_settings_hooks.sh` 為準。）建立測試檔，執行 `chmod +x tests/test_project_settings_hooks.sh`。`core.fileMode=true`，所以 `git add` 時會記成 `100755`。

```bash
#!/usr/bin/env bash
set -euo pipefail

# 鎖住「流程守衛掛載在進版控的 .claude/settings.json」。
# 刻意不讀 settings.local.json：它不進版控，clone 環境裡不存在。
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS=".claude/settings.json"
STAGE_CHECK='$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-stage-check.sh'
DELEGATE_CWD='$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-delegate-cwd.sh'

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "=== Test 1 (AC-1): settings.json tracked, not ignored, valid JSON ==="
git -C "$REPO_ROOT" ls-files --error-unmatch -- "$SETTINGS" >/dev/null 2>&1 \
  || fail "$SETTINGS is not tracked by git"
# --no-index：已追蹤的檔案預設不受 ignore 規則檢查，不加此旗標斷言永遠成立。
# 不加 -v：verbose 連「!」否定規則的命中也會輸出，會讓合法的重新納入誤判為 FAIL。
# core.excludesFile=/dev/null：只看 repo 內規則，不讓個人全域 ignore 左右結果（S-3）。
IGNORED="$(git -C "$REPO_ROOT" -c core.excludesFile=/dev/null check-ignore --no-index -- "$SETTINGS" || true)"
[ -z "$IGNORED" ] || fail "$SETTINGS is matched by a repo ignore rule"
jq -e . "$REPO_ROOT/$SETTINGS" >/dev/null || fail "$SETTINGS is not valid JSON"
echo "PASS: $SETTINGS tracked, not ignored, valid JSON"

echo "=== Test 2 (AC-2): each guard registered exactly once ==="
check_guard() {
  local n
  n="$(jq --arg e "$1" --arg m "$2" --arg c "$3" \
    '[.hooks[$e][]? | select(.matcher == $m) | .hooks[]?
      | select(. == {"type": "command", "command": $c})] | length' \
    "$REPO_ROOT/$SETTINGS")"
  [ "$n" = "1" ] || fail "$1 / $2 / $3 registered $n times (expected 1)"
  echo "PASS: $1 / $2 / $3"
}
check_guard PreToolUse Agent "$STAGE_CHECK"
check_guard PreToolUse mcp__gemini-cli__ask-gemini "$DELEGATE_CWD pre"
check_guard PostToolUse mcp__gemini-cli__ask-gemini "$DELEGATE_CWD post"

echo "=== Test 3 (AC-3): guard scripts exist, executable, index mode 100755 ==="
for cmd in "$STAGE_CHECK" "$DELEGATE_CWD"; do
  rel="${cmd#\$CLAUDE_PROJECT_DIR/}"
  [ -f "$REPO_ROOT/$rel" ] || fail "$rel does not exist"
  [ -x "$REPO_ROOT/$rel" ] || fail "$rel is not executable"
  mode="$(git -C "$REPO_ROOT" ls-files -s -- "$rel" | cut -d' ' -f1)"
  [ "$mode" = "100755" ] || fail "$rel index mode is '${mode:-untracked}' (expected 100755)"
  echo "PASS: $rel exists, executable, index mode 100755"
done

echo "ALL TESTS PASSED!"
```

  確認紅燈：

```bash
bash tests/test_project_settings_hooks.sh; echo "exit=$?"
# 期望：印出 "FAIL: .claude/settings.json is not tracked by git"，exit=1
grep -c "settings.local" tests/test_project_settings_hooks.sh
# 期望：1（只有註解那一行；AC-4：測試不讀 local 檔）
```

- **步驟 2（綠）**：建立 `.claude/settings.json`。`$schema` 放第一個欄位（U-1）；3 條指令字串與規格 §3.1 完全相等；縮排 2 格，格式比照 local 檔。

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
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-guard-stage-check.sh"
          }
        ]
      },
      {
        "matcher": "mcp__gemini-cli__ask-gemini",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wf-guard-delegate-cwd.sh pre"
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
      }
    ]
  }
}
```

  執行 `git add .claude/settings.json tests/test_project_settings_hooks.sh`，再用 `gen-commit` 提交成一個 commit。紅燈只存在於工作區，不會在歷史裡留下紅燈 commit。

- **對應 AC**：AC-1、AC-2、AC-3、AC-4（先紅後綠）。
- **驗證指令**：

```bash
bash tests/test_project_settings_hooks.sh; echo "exit=$?"
# 期望：6 行 PASS + "ALL TESTS PASSED!"，exit=0
git ls-files -s tests/test_project_settings_hooks.sh .claude/settings.json
# 期望：test 檔為 100755、settings.json 為 100644
jq -r 'keys_unsorted[0]' .claude/settings.json
# 期望：$schema
```

---

### T2：修正 `wf-guard-delegate-cwd.sh` 的掛載註解（`:16`、`:21`、`:26`） `[原地修改]`（接在 T1 之後）

- **等級**：`[原地修改]`（派發煞車：單檔 3 行註解、沒有公開 API 變更，由主進程直接改）
- **依賴**：必須在 T1 之後。AC-9 的驗證會讀 T1 產生的 `.claude/settings.json`。
- **寫入檔案**：`.claude/hooks/wf-guard-delegate-cwd.sh`
- **具體改動**：初版只替換第 16 行。PR #203 review 後，`:21`、`:26` 註解中的 command 也改為加引號（`\"$CLAUDE_PROJECT_DIR\"/...`），共 3 行，總行數不變，規格引用的其他行號仍然正確。其餘一字不動。（下方 diff 與驗證指令為最終版；與實檔不一致時以實檔為準。）

```diff
-# 掛載方式（.claude/settings.local.json，本地設定不進版控——沿用既有三個 hook 的慣例）：
+# 掛載於 .claude/settings.json（進版控；條目由 tests/test_project_settings_hooks.sh 鎖定）：
```

  （`:21`、`:26` 兩行僅把 `"$CLAUDE_PROJECT_DIR/...` 改為 `"\"$CLAUDE_PROJECT_DIR\"/...`。）

  用 `gen-commit` 獨立提交一個 commit。

- **對應 AC**：AC-9；AC-7（除這三行註解外不得有其他改動）。
- **驗證指令**（commit 之後執行，以 bash 執行，因為用到 process substitution）：

```bash
git diff -U0 main...HEAD -- .claude/hooks/ | sed -n '/^@@/p;/^[-+][^-+]/p'
# 期望：只有 "@@ -16 +16 @@"、"@@ -21 +21 @@"、"@@ -26 +26 @@" 三個 hunk，各一行 - 一行 +（AC-7）
# sed 擷取的是帶 JSON 跳脫的字串，jq -r . 解碼後才與 settings.json 的 command 比對
diff <(sed -n '18,27s/.*"command": \(".*"\) }.*/\1/p' .claude/hooks/wf-guard-delegate-cwd.sh | jq -r .) \
     <(jq -r '.hooks[][] | select(.matcher == "mcp__gemini-cli__ask-gemini") | .hooks[].command' .claude/settings.json) \
  && echo "AC-9 fragment consistent"
# 期望：印出 "AC-9 fragment consistent"
```

---

### PM-1（合併後待辦）：從主 checkout 的 `settings.local.json` 移除 3 條守衛

- **等級**：`[原地修改]`。由主對話在主 checkout 親自執行，不派發 subagent：這是個人的本機檔，不屬於 worktree，也沒有 git diff 可交給 verifier 驗收。
- **寫入檔案**：`/Users/yomiry/StudioWorkspace/flutter_inspector/.claude/settings.local.json`（**僅本機，沒有 git diff**）
- **執行時機**（理由見 §1.1）：
  1. PR 已實際合併。
  2. 主 checkout 已同步到包含本 PR 的 `main`。這一步是 git 同步操作，**由使用者自己執行 `git pull`，或在使用者明確授權後才執行**。
  3. 放在 STAGE 6 開頭：推進狀態之後、同步文件之前。**AC-5 的檢查（§5.3）必須緊接在 PM-1 之後，而且要在 STAGE 6 的環境清理（移除 `alwaysThinkingEnabled`）之前完成**。否則 AC-5 的「非 hooks key 未變」比對會因為清理動作而誤判 FAIL。
  4. PM-1 本身與 `alwaysThinkingEnabled` 互不干涉：filter 只動 `.hooks`，該 key 當下是否存在都會原樣保留。
- **前置檢查**：執行 `git worktree list`。若存在其他 worktree，且其 branch 早於本變更（沒有 `.claude/settings.json`），PM-1 之後在那些 worktree 內新開的 session 會失去守衛（規格 R-4）。遇到這種情況，先讓那些 branch 同步 `main`，或確認接受這個風險。
- **具體改動**：以 bash 在單一呼叫內執行整段。
  - 下方 `--argjson cmds` 比對的是 **local 現存的未加引號舊字串**，刻意不隨 `settings.json` 加引號。
  - 過渡期影響：`settings.json` 的指令加了引號、`settings.local.json` 仍是未加引號的舊字串，兩者字串不同，不會被去重，三條守衛各會跑兩次，直到 PM-1 移除 local 的副本。這不只發生在合併後到 PM-1 之間：合併前在 worktree 根目錄啟動的 session，會同時讀到 worktree 的 `settings.json` 與主 checkout 的 local，現在就已各跑兩次。兩份都 fail-open。`stage-check` 唯讀、結果一致，無副作用。`delegate-cwd pre` 兩份並行、非原子地寫同一個 snapshot，交錯時可能寫壞檔，`post` 的 `json.load` 失敗就放行，因此極少數情況可能漏報（sensor 只告警，不阻斷）；`post` 另可能重複告警、`cwd-violations.log` 多寫一行。PM-1 緊接合併後執行即可，不需額外處理。
  - 各步驟用 `&&` 串接，步驟 0 失敗則後面全部不執行，什麼都不改。

```bash
MAIN=/Users/yomiry/StudioWorkspace/flutter_inspector
F="$MAIN/.claude/settings.local.json"
# 固定路徑：Bash 工具的 shell 變數不跨呼叫保留，§5.3 要能找回同一份備份。
# 放在 $TMPDIR 而不是 .claude/ 下，避免留下可能被誤 commit 的檔。
BAK="${TMPDIR:-/tmp}/b3-settings.local.json.bak"

# 步驟 0（閘門）：主 checkout 必須已含本 PR，否則改了就是製造空窗
# 步驟 1：備份只在不存在時建立（重跑不會用已改版本覆蓋原始備份），並印出實際路徑
# 步驟 2：從原檔讀 → 依 command 字串精準移除 → 成功後才寫回原檔（保留權限與 inode）
bash "$MAIN/tests/test_project_settings_hooks.sh" >/dev/null \
&& { [ -e "$BAK" ] || cp "$F" "$BAK"; } \
&& echo "backup: $BAK" \
&& NEW="$(mktemp -t b3-settings-local-new)" \
&& jq --argjson cmds '[
  "$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-stage-check.sh",
  "$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-delegate-cwd.sh pre",
  "$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-delegate-cwd.sh post"
]' '
  .hooks |= (
    map_values(
      map(.hooks |= map(select(.command | IN($cmds[]) | not)))
      | map(select(.hooks | length > 0))
    )
    | with_entries(select(.value | length > 0))
  )' "$F" > "$NEW" \
&& cat "$NEW" > "$F" && rm -f -- "$NEW" && echo "local updated"
```

- **對應 AC**：AC-5、AC-6（步驟見 §5.3）。
- **還原**：`cp "${TMPDIR:-/tmp}/b3-settings.local.json.bak" /Users/yomiry/StudioWorkspace/flutter_inspector/.claude/settings.local.json`

---

## 4. 並行判定與 commit 切分

```
STAGE 2:  T1（紅→綠，commit）──→ T2（3 行，commit）
STAGE 3:  §5.1 / §5.2 驗證 + §5.4 /hooks 冒煙檢查（必做）
STAGE 4–5: PR、review
合併 → 主 checkout 同步（使用者執行或授權）
STAGE 6 開頭:  PM-1 ──→ AC-5（緊接著）──→ AC-6 ──→ STAGE 6 其餘步驟（含環境清理）
```

| 分組 | 任務 | 並行性 | 理由 |
|:---|:---|:---|:---|
| STAGE 2 | T1 → T2 | **必須序列** | T1 內部是 TDD 的先紅後綠；T2 的 AC-9 驗證要讀 T1 產生的 `settings.json` |
| 合併後 | PM-1 → AC-5 → AC-6 | 序列 | 前提是主 checkout 已有 `settings.json`（§1.1）；AC-5 要搶在環境清理之前 |

**`/Users/yomiry/StudioWorkspace/flutter_inspector/.claude/settings.local.json` 只有 PM-1 一個 owner。** STAGE 2 的任何任務（包括 implementer 與 verifier）都不得碰它。worktree 裡本來也沒有這個檔，在 worktree 內新建一份會造成第二個真相來源。

---

## 5. 驗證

### 5.1 STAGE 2 收尾與 STAGE 3 的整體驗證（在 worktree 根目錄執行）

```bash
bash tests/test_project_settings_hooks.sh                # AC-1~4：ALL TESTS PASSED!，exit 0
bash tests/test_wf_state_total_tasks.sh                  # 既有 shell 測試回歸：ALL TESTS PASSED!
python3 .claude/hooks/tests/test_delegate_cwd_logic.py   # AC-7：印 OK，exit 0
```

`test_delegate_cwd_logic.py` 已實查：這支檔案是 `100755`，直接以 python3 執行、不依賴任何框架，目前印 `OK`、exit 0。

不需要跑 `flutter test` 或 `flutter analyze`：本次沒有改到任何 Dart 檔。

### 5.2 回歸 AC-7 / AC-8 / AC-9

- **AC-7**：執行 T2 的 `git diff -U0 main...HEAD -- .claude/hooks/`，期望只有 `:16`、`:21`、`:26` 三個 hunk（掛載說明註解）；再加上 §5.1 的 python 測試通過。
- **AC-8**：在 worktree 根目錄以 **bash** 執行下列片段（不要用 zsh，兩者的 word-splitting 行為不同）：

```bash
H="$PWD/.claude/hooks"; D="$(mktemp -d)"; cd "$D"
A='{"tool_name":"Agent","tool_input":{"subagent_type":"%s"}}'
G='{"tool_name":"mcp__gemini-cli__ask-gemini","tool_input":{"prompt":"x"}}'
for t in responder planner; do printf "$A" "$t" | "$H/wf-guard-stage-check.sh"; echo "stage-check $t exit=$?"; done
printf '' | "$H/wf-guard-stage-check.sh"; echo "stage-check empty exit=$?"
for m in pre post; do printf '%s' "$G" | "$H/wf-guard-delegate-cwd.sh" "$m"; echo "delegate-cwd $m exit=$?"; done
cd - >/dev/null; rmdir "$D"
```

  期望：恰好 5 行，全部是 `exit=0`，中間沒有任何 stderr 輸出。

- **AC-9**：執行 T2 的 `diff` 指令，期望印出 `AC-9 fragment consistent`。

### 5.3 合併後確認 AC-5 / AC-6（PM-1 之後，在主 checkout）

**AC-5**：緊接在 PM-1 之後、STAGE 6 環境清理之前執行。該檔沒有 git diff，所以用 jq 檢視。

```bash
F=/Users/yomiry/StudioWorkspace/flutter_inspector/.claude/settings.local.json
BAK="${TMPDIR:-/tmp}/b3-settings.local.json.bak"
jq -e '(.hooks | keys) == ["PostToolUse"]
  and [.hooks.PostToolUse[] | .matcher, .hooks[].command]
      == ["Bash", "$CLAUDE_PROJECT_DIR/.claude/hooks/cbm-reindex-on-pr.sh"]' "$F"
# 期望：true（hooks 只剩 PostToolUse/Bash → cbm 一條）
diff <(jq -S 'del(.hooks)' "$BAK") <(jq -S 'del(.hooks)' "$F") && echo "非 hooks 的 key 未變"
# 期望：印出「非 hooks 的 key 未變」（alwaysThinkingEnabled 等當時存在的 key 原樣保留）
```

**AC-6**（需要人工操作）：

1. 在 `/Users/yomiry/StudioWorkspace/flutter_inspector` 開一個**新的** Claude Code session。不要沿用舊 session，避免看到 file watcher 熱更新前後混雜的狀態。
2. 執行 `/hooks`，逐項確認：
   - `PreToolUse` / `Agent` → `wf-guard-stage-check.sh`，來源為 **Project settings**
   - `PreToolUse` / `mcp__gemini-cli__ask-gemini` → `wf-guard-delegate-cwd.sh pre`，來源為 **Project settings**
   - `PostToolUse` / `mcp__gemini-cli__ask-gemini` → `wf-guard-delegate-cwd.sh post`，來源為 **Project settings**
   - `PostToolUse` / `Bash` → `cbm-reindex-on-pr.sh`，來源為 **Local settings**
   - 沒有任何一支守衛同時出現兩個來源，也沒有 Settings Error。
3. 全部符合後刪除備份：`rm -f -- "${TMPDIR:-/tmp}/b3-settings.local.json.bak"`。

### 5.4 STAGE 3 必做：CLI 接受度冒煙檢查

`jq` 只能證明 `settings.json` 是合法 JSON，不能證明 CLI 接受它。STAGE 3 期間必須做一次：

1. 在 worktree 根目錄開一個新的 Claude Code session。
2. 執行 `/hooks`，確認 3 條守衛以 **Project settings** 來源出現，而且沒有 Settings Error。

此時 local 還沒改，同一支守衛可能同時顯示 Project 與 Local 兩個來源。這是預期中的過渡狀態（兩份字串不同，F-5 不去重，兩份都會執行），不算 AC-6 失敗。順帶也能觀察 U-2：worktree 內的 session 是否讀到主 checkout 的 local 檔。

---

## 6. 與規格的一致化、合併後待辦與待決事項

### 6.1 規格已同步改寫（採方案 A）

方案 A（PM-1 在 PR 合併、主 checkout 同步後執行）會在 STAGE 0b 暫停點交由使用者裁決。為避免計畫與規格不一致，規格已先按方案 A 改寫：

| 規格位置 | 原文 | 改為 |
|:---|:---|:---|
| §4 手動 AC 小標 | 「手動（無法自動化，於 STAGE 2/3 確認）」 | 「手動（無法自動化，於 PR 合併、主 checkout 同步後確認：計畫 PM-1 + §5.3）」 |
| §5 In scope 第 2 項 | 「從 `.claude/settings.local.json` 移除這 3 條。」 | 加註「**合併後執行**」與理由 |

若使用者否決 A、改採 B，上述兩處要改回「STAGE 2/3」；PM-1 改編為 T3 併入 STAGE 2（`total_tasks=3`），並明確接受「合併前主 checkout 沒有守衛」的空窗。

### 6.2 合併後待辦寫入 Issue

PM-1、AC-5、AC-6 不在 STAGE 2–4 的流程內，PR 合併後很容易被遺忘。因此 **STAGE 1 建立 Issue 時，要把這三項寫進 Issue 的 Verification 區段，標成「合併後待辦」**，內容指向本計畫 PM-1 與 §5.3。實際寫入由 STAGE 1（gen-gh-issue）負責，本計畫只交代需求。

### 6.3 已決：AC-1 只看 repo 內的 ignore 規則（S-3）

**使用者裁決（2026-10-15）：採「改成 `-c core.excludesFile=/dev/null`」**，T1 測試已依此撰寫，規格 AC-1 措辭同步改為「repo 內的 ignore 規則」。原始取捨保留如下：

| 選項 | 優點 | 缺點 |
|:---|:---|:---|
| **維持現狀**（含全域 excludes） | 符合 AC-1「沒有被**任何** ignore 規則排除」的字面；全域忽略了 `.claude/` 的機器會被提醒：在那台機器上新增 `.claude/` 下的檔案時會被 `git add` 擋下 | 結果依賴各自機器的設定。若某位貢獻者全域忽略 `.claude/`，在他機器上測試會 FAIL，但 repo 本身沒有問題（已追蹤的檔案不受 ignore 影響） |
| 改成 `git -c core.excludesFile=/dev/null check-ignore --no-index` | 結果只取決於 repo 內的規則（各層 `.gitignore` 與 `.git/info/exclude`），在任何機器上都能重現 | 偏離 AC-1「任何」的字面，規格措辭要同步改成「repo 內的 ignore 規則」；也失去對個人機器設定的提醒 |

實測（scratch clone）：用一份含 `.claude/` 的檔案模擬全域 excludes 時，現行寫法會輸出 `.claude/settings.json`（判 FAIL）；改成 `-c core.excludesFile=/dev/null` 後輸出為空（判 PASS）。本機目前的全域 ignore 只有 `**/.claude/settings.local.json`，兩種寫法結果相同。

---

## 7. Ponytail 紀律檢查表

本次刻意**不做**的事：

| 不做的事 | 依據 |
|:---|:---|
| golden file 全文比對 | §1.2：太脆，任何無關新增都會讓測試變紅 |
| 通用解析 `settings.json` 內所有 hook 的腳本路徑 | §1.2：AC-3 只要求 AC-2 那 3 條；需要時再擴充 |
| 測試檢查 `$schema` | 規格 §3.4：不影響任何 AC（§1.4 已確認拿掉後測試仍 PASS） |
| 把 AC-8 的 5 個情境寫成 repo 內的測試檔 | 規格只要求 AC-1~4 自動化；AC-8 是一次性的回歸確認，計畫內附可直接貼上的片段即可 |
| 改動 hook 腳本的掛載說明註解以外的部分 | AC-7 限制只能改註解；`:18-27` 的 JSON 片段已隨 PR #203 review 同步為加引號版本 |
| 把指令改成 exec form | PR #203 review 後改為 shell form 加雙引號（`"$CLAUDE_PROJECT_DIR"/...`），已滿足官方「shell form 須為佔位符加雙引號」；exec form 需改 `args` 結構，收益相同，不做 |
| 在 worktree 內建立 `settings.local.json` | F-3：CLI 會改讀主 checkout 那份，建了只會多一個真相來源 |
| 跑 `flutter test` / `flutter analyze` | 沒有改到任何 Dart 檔 |
| 回寫 brainstorm §8.2 B3 / §8.5 的狀態 | 規格 §5：留到 STAGE 6 |

---

## 8. 執行方式選項

| 方式 | 適用 | 說明 |
|:---|:---|:---|
| **subagent-driven（建議）** | 本計畫 | T1 派發 implementer（快/便宜），由 verifier 驗收；T2 接在 T1 之後，命中派發煞車，由主進程原地修改；PM-1 在合併後由主對話於主 checkout 親自執行 |
| parallel session | 不建議 | STAGE 2 只有兩個必須序列的任務，沒有可並行的部分 |

**建議：subagent-driven，單一 session，STAGE 2 設 `total_tasks=2`。**
