# 委派工作目錄強制：Guide → Sensor 實作計畫

依據 [`docs/features/2026-08-19-delegation-cwd-sensor.md`](../features/2026-08-19-delegation-cwd-sensor.md) 之需求規格制定。

> 狀態：實作計畫（STAGE 0b）｜日期：2026-08-19
> 前置裁決（不可再議）：
> - **U-1**：路 B 僅 stderr 告警 + 稽核紀錄，**不阻斷**流程。不做「標記 workflow 需人工確認」，不做環境變數升級開關。
> - **U-7**：路 A 與路 B **同批實作、同一個 PR** 落地。兩者阻擋語意刻意不同：路 A `sys.exit(2)` 阻斷；路 B 只告警。

---

## 1. 實作方向的 trade-off 分析

### 1.1 核心難題：PostToolUse 拿不到「委派前」的狀態

規格 P-9 要求 **before/after 差集判定**（用絕對值判定必定誤殺使用者自己未 commit 的工作）。但 PostToolUse hook 只在工具**執行後**觸發，此時「之前」的快照在物理上已不可得。這是本次實作唯一的真正技術難點，三個候選方向：

| 方向 | 作法 | 優點 | 缺點 | 判定 |
|:---|:---|:---|:---|:---:|
| **甲：單 hook + 快取檔** | 只掛 PostToolUse，第一次跑時把 `git status` 存起來當基準，之後每次比對上一次的紀錄 | 只需一個 hook | 基準是「上一次委派結束時」而非「本次委派開始前」；兩次委派之間使用者自己改的檔案會被算進下一次委派的帳上。**假告警來源** | ❌ |
| **乙：PreToolUse 存快照 + PostToolUse 比對（配對）** | 掛兩個 hook 到同一個 matcher。Pre 存 before 快照到暫存檔，Post 讀出來做差集後刪除 | 差集語意精確符合 P-9；Pre hook 本來就要為路 A 掛上去，**邊際成本趨近於零** | 需處理快照檔的並行覆蓋與洩漏清理 | ✅ **採用** |
| **丙：不做差集，改比對 commit** | 只看主 repo 的 `HEAD` 有沒有前進 | 極簡 | 抓不到「改了檔案但沒 commit」的越界（規格 AC-B1 的主情境）；且 HEAD 也需要 before 值，並沒有省掉配對 | ❌ |

**採用方向乙。** 決定性理由：路 A 本來就必須掛一個 PreToolUse hook 在 `mcp__gemini-cli__ask-gemini` 上（AC-A1~A6），在那個已存在的 hook 裡多寫一次 `git status --porcelain` 到暫存檔，是**零額外掛載點、零額外進程**的搭便車。方向甲省下的那個 hook 根本不存在可省。

### 1.2 快照配對的具體設計

**Key 的選擇**：payload 裡沒有 `tool_use_id`（實查 `.claude/hooks/` 既有兩個 hook 皆未使用該欄位，且不保證存在）。改用**主 repo 的 git common dir 路徑 hash** 作為 key：

```
<TMPDIR>/wf-cwd-sensor-<sha1(git_common_dir)[:12]>.json
```

- **為何不用 PID**：Pre 與 Post 是兩個獨立進程，PID 不同，無法配對。
- **為何不用 session_id**：payload 未保證提供該欄位（既有 hook 皆未依賴）。
- **為何 repo path 夠用**：同一個 repo 內的並行委派，主 repo 的 dirty 狀態本來就是共享的單一事實，用同一個 key 覆蓋不會產生錯誤結論——後寫的快照只會讓基準更接近「當下」，差集只會**更保守**（更不容易告警），符合 R-1「寧可漏報不可誤殺」的方向。

**並行覆蓋處理**：
- 快照檔存 `{"ts": <epoch>, "entries": [...]}`。
- Post 端讀取時檢查 `ts`：若 `now - ts > 3600`（一小時）視為過期孤兒 → 忽略並刪除，**不告警**（fail-open）。
- Post 端比對完畢後**無條件刪除**快照檔（`try/except pass`）。

**異常清理**：
- Pre hook 阻擋（路 A `exit 2`）時**不寫快照**——因為委派根本沒發生，寫了就是孤兒。
- Pre 寫了但 Post 從未觸發（委派中斷、hook 被停用）→ 檔案留在 `$TMPDIR`，靠上述 1 小時 TTL 自然作廢；`$TMPDIR` 本身由 OS 定期清理，不需自建清理排程。

> `// ponytail:` 用 repo-path 當 key、TTL 一小時、後寫覆蓋先寫。升級路徑：若日後 payload 穩定提供 `tool_use_id`，改用它當 key 即可精確配對。

### 1.3 單檔 vs 雙檔

| 方向 | 檔案數 | 判定 |
|:---|:---|:---:|
| 路 A 與路 B 各一個腳本 | 2 | ❌ 白名單與 state 檔比對邏輯（P-2~P-6）兩邊完全重複 |
| **單一腳本 `wf-guard-delegate-cwd.sh`，靠參數分岔 pre/post** | 1 | ✅ 採用 |

單檔以 `$1` 為 `pre` / `post` 分岔，共用 payload 解析、state 檔比對、白名單解析。settings 掛載時分別傳入 `... pre` 與 `... post`。**這不是「為未來預留擴充」的抽象，是消除兩份必然同步修改的重複程式碼。**

### 1.4 白名單的表達位置

遵守 U-5 與 Ponytail：**寫死在腳本內的一個 Python list**，不抽設定檔、不抽 module、不做 loader。目前只有一個消費者。

---

## 2. 檔案異動清單

| 檔案路徑 | 類型 | 異動說明 | Owner 任務 |
|:---|:---:|:---|:---:|
| `.claude/hooks/wf-guard-delegate-cwd.sh` | 新增 | 本次核心：路 A（pre）+ 路 B（post）單一腳本 | T2 / T3 / T4 |
| `.claude/hooks/tests/test_delegate_cwd_logic.py` | 新增 | 純函式邏輯的自我檢查（見 §5） | T5 |
| `.claude/settings.local.json` | 修改 | 於既有 `PreToolUse` / `PostToolUse` **陣列中追加**新項目 | **T6（唯一 owner）** |
| `docs/features/2026-08-19-delegation-cwd-sensor.md` | 修改 | 回寫 U-6（worktree `.git` 實測結果）與 U-2（稽核紀錄位置定案） | T7 |

**明確不動**（規格 §5 Out of scope + 本次邊界）：
- `.claude/skills/gen-dev-workflow/scripts/wf-state.sh`
- `.claude/agents/implementer.md`（那段〈工作目錄與邊界〉正是路 A 要檢查的對象，動了等於自我作弊）
- `.agents/hooks.json`（Antigravity 側；本次委派管道是 Claude 側的 MCP，不擴大範圍）

---

## 3. 任務拆分

每個任務 2–5 分鐘粒度，TDD-first（有純函式邏輯者先寫檢查）。

---

### T1：建立測試骨架與白名單解析的失敗測試
- **複雜度**：快/便宜
- **寫入 scope**：`.claude/hooks/tests/test_delegate_cwd_logic.py`
- **內容**：
  - 建立檔案，`#!/usr/bin/env python3`，以 `assert` 為唯一斷言手段，`if __name__ == "__main__":` 執行全部檢查後印 `OK`。
  - 從腳本抽出的邏輯尚不存在 → 先寫 import 失敗的骨架與 `test_whitelist_roots()`、`test_is_allowed_path()` 兩個空殼，執行應失敗。
- **驗收**：`python3 .claude/hooks/tests/test_delegate_cwd_logic.py` 以非零離開（紅燈）。

---

### T2：實作共用骨架 + 白名單動態解析
- **複雜度**：標準
- **寫入 scope**：`.claude/hooks/wf-guard-delegate-cwd.sh`
- **內容**：沿用 `wf-guard-stage-check.sh` 的骨架風格（bash wrapper 讀 stdin → inline `python3 -c` → `exit $?`），加上 `mode="$1"` 分岔。
  - **payload 解析**（P-1）：非 JSON / 空輸入 → `sys.exit(0)`。
  - **工具名比對**（P-2）：`tool_name` 不是 `mcp__gemini-cli__ask-gemini` → `sys.exit(0)`。
  - **state 檔搜尋**（P-3）：沿用既有 hook 的 `WF_STATE_DIR` → 逐層往上找 `.claude/workflow-state/*.json` 邏輯，排除 `.batch-` 前綴；找不到 → `sys.exit(0)`。
  - **branch 比對**（P-4）：`git branch --show-current` → `<slug>.json`；對不上 → `sys.exit(0)`。
  - **stage 比對**（P-5）：`stage` 不是 `"2"` → `sys.exit(0)`。
  - **worktree 存在性**（P-6）：`git rev-parse --git-dir` == `git rev-parse --git-common-dir` 表示不在 worktree 中（主 repo）→ 路 A 與路 B 皆 `sys.exit(0)`。**一律用 `git rev-parse` 動態取得，禁止解析 `.git` 檔內容**（R-6 / U-6）。
  - **白名單解析函式** `whitelist_roots()`：
    - `git rev-parse --git-common-dir`（主 repo `.git`）與 `git rev-parse --git-dir`（worktree gitdir），皆取 `os.path.realpath`。
    - `os.environ.get("PUB_CACHE") or os.path.expanduser("~/.pub-cache")`。
    - SDK 根：`shutil.which("flutter")` → `os.path.realpath()` → `dirname(dirname(...))`；另納入 `os.environ.get("FLUTTER_ROOT")` 與 `~/fvm`。三者取聯集，任一取不到就跳過不報錯。
    - 固定項：`~/.gitconfig`、`~/.config/git`、`~/.ssh/known_hosts`、`~/.dart-tool`、`~/.flutter`、`~/.dartServer`、`~/.config/gh`、`~/.npm`、`~/.cache`。
    - 暫存：`os.environ.get("TMPDIR")`、`/tmp`、`/private/tmp`。
  - **路徑比對函式** `is_allowed(path, roots)`：兩側都先 `os.path.realpath`，比對 `path == root or path.startswith(root + os.sep)`。
  - **fail-open 總包裝**（P-11）：整段主邏輯包在 `try/except BaseException: sys.exit(0)` 外層。
  - `chmod +x`。
- **驗收**：AC-B6、AC-B7、AC-A4、AC-A5、AC-A6、AC-C2（白名單各類路徑各有一個 `is_allowed` 為 True 的檢查）。

---

### T3：實作路 A（pre 模式）
- **複雜度**：標準
- **寫入 scope**：`.claude/hooks/wf-guard-delegate-cwd.sh`（同 T2，**必須序列**）
- **內容**：`mode == "pre"` 分支，接在 T2 的共用前置判斷之後。
  1. 從 payload 取出 prompt 字串：`tool_input.prompt`（缺失或非字串 → `sys.exit(0)`，P-1 精神）。
  2. 從 state 檔算出目標 worktree 絕對路徑。**取得方式**：state 檔的 `branch` 欄位 → `git worktree list --porcelain` 解析出對應 branch 的 worktree 路徑。取不到 → `sys.exit(0)`（P-6 延伸）。
  3. **比對**（R-4：只比對「prompt 是否含目標 worktree 絕對路徑字串」，**不比對整段格式**）：
     - prompt 不含該絕對路徑 → 阻擋。
     - stderr 需分辨兩種情況：prompt 完全沒有任何 `工作目錄` 字樣 → AC-A1 訊息（列出缺少的段落與正確格式）；有 `工作目錄` 字樣但路徑不符 → AC-A2 訊息（同時列出「prompt 中的路徑」與「應為的路徑」）。
  4. 阻擋時 `sys.exit(2)`（BUG-1 教訓：PreToolUse 只有 exit 2 有阻擋力）。
  5. 放行前（且僅在放行時）呼叫 T4 的 `save_snapshot()`。
- **驗收**：AC-A1、AC-A2、AC-A3。

---

### T4：實作路 B（快照 + post 模式差集告警）
- **複雜度**：最強推論
- **寫入 scope**：`.claude/hooks/wf-guard-delegate-cwd.sh`（同 T2/T3，**必須序列**）
- **內容**：
  1. **`snapshot_path()`**：`os.path.join(tmpdir, "wf-cwd-sensor-" + sha1(git_common_dir).hexdigest()[:12] + ".json")`。
  2. **`take_status()`**：對主 repo 與 `git worktree list --porcelain` 列出的**所有非目標 worktree**，各跑一次
     `git -C <path> status --porcelain --untracked-files=normal`
     （R-3：只跑 `git status --porcelain`，**不做全檔案系統遍歷**；實測主 repo 耗時 38ms。`--untracked-files=normal` 天然滿足 P-10——`.gitignore` 內的檔案不會出現在輸出）。
     另記錄各 repo 的 `git rev-parse HEAD`，用於偵測「越界 commit」（規格 §1.2 的失效路徑明列此情境）。
     回傳 `{"<repo path>": {"entries": [...], "head": "<sha>"}}`。
  3. **`save_snapshot()`**（pre 端）：寫入 `{"ts": time.time(), "repos": <take_status()>}`。
  4. **post 端差集**：
     - 讀快照；檔案不存在 → `sys.exit(0)`（未配對，fail-open）。
     - `now - ts > 3600` → 刪檔並 `sys.exit(0)`（孤兒快照）。
     - 對每個 repo：`after_entries - before_entries` 取集合差集（P-9）；`before.head != after.head` 記為新增 commit。
     - 差集中的每個路徑組成絕對路徑，套 `is_allowed()` 過濾（P-7/P-8：`git status` 只回報工作區檔案，讀取行為天然不入列）。
     - **無條件刪除快照檔**（`try/except pass`）。
  5. **告警輸出**（U-1：只告警，**不阻斷**）：
     - 有越界 → stderr 印高可見度區塊，列出**具體越界檔案路徑清單** + 新增 commit sha + 目標 worktree 路徑 + 修復建議 + R-2 要求的免責句「若這是你自己的改動請忽略」。
     - **`sys.exit(0)`**（PostToolUse 動作已完成，回捲無意義）。
  6. **稽核紀錄**（AC-B5）：append 一行 JSON 到 `.claude/workflow-state/cwd-violations.log`（**U-2 定案**：與 state 檔同目錄，跟著 workflow 生命週期走，不另建目錄、不做輪替）。欄位：`ts`（ISO8601）、`branch`、`worktree`、`paths`（清單）、`new_commits`。寫入失敗一律吞掉不影響流程。
- **驗收**：AC-B1、AC-B2、AC-B3、AC-B4、AC-B5。

---

### T5：補齊純函式自我檢查
- **複雜度**：標準
- **寫入 scope**：`.claude/hooks/tests/test_delegate_cwd_logic.py`
- **內容**：見 §5。針對 `is_allowed()`、`whitelist_roots()`、差集函式三者寫 assert 檢查。
- **驗收**：`python3 .claude/hooks/tests/test_delegate_cwd_logic.py` 印 `OK` 且離開碼 0。

---

### T6：掛載 hook 到 settings.local.json
- **複雜度**：快/便宜
- **寫入 scope**：`.claude/settings.local.json`（**共享檔，本任務為唯一 owner**）
- **內容**：**追加**而非取代（AC-C1）。既有的 `PreToolUse[matcher=Agent]` 與 `PostToolUse[matcher=Bash]` 兩項一字不動，於各自陣列末端新增：
  ```json
  { "matcher": "mcp__gemini-cli__ask-gemini",
    "hooks": [{ "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/wf-guard-delegate-cwd.sh pre" }] }
  ```
  PostToolUse 同結構，命令結尾改 `post`。
  改完以 `python3 -m json.tool .claude/settings.local.json` 驗證 JSON 合法。
- **驗收**：AC-C1（既有兩個 hook 項目仍存在且內容未變）。

---

### T7：回寫規格未決事項 + 手動驗證
- **複雜度**：標準
- **寫入 scope**：`docs/features/2026-08-19-delegation-cwd-sensor.md`
- **內容**：
  1. 於 STAGE 1 建立的 worktree 中實測 `.git` 型態（檔案 vs 目錄）與 `git rev-parse --git-dir` / `--git-common-dir` 的實際輸出，回寫 U-6 / R-6。
  2. 標記 U-2 為已定案（稽核紀錄 = `.claude/workflow-state/cwd-violations.log`，隨 workflow 生命週期，不輪替）。
  3. 標記 U-5 為已定案（白名單寫死在腳本內）。
  4. 執行 §5.2 的手動驗證清單，把結果記入。
- **驗收**：AC-B1~B7、AC-A1~A3、AC-C1 的手動情境全數通過。

---

## 4. 並行判定

```
T1 ──┬──────────────────────────────────────┐
     │                                      │
     ├─→ T2 ─→ T3 ─→ T4 ─→ T5 ──┐           │
     │   (同一檔案，必須序列)      │           │
     └─→ T6（獨立檔案，可與 T2~T5 並行）──┴──→ T7
```

| 分組 | 任務 | 並行性 | 理由 |
|:---|:---|:---|:---|
| 第 1 批 | **T1** | 單獨 | 建立測試骨架，是後續紅燈基準 |
| 第 2 批 | **T2 → T3 → T4 → T5** | **必須序列** | T2/T3/T4 全部寫入同一個檔案 `wf-guard-delegate-cwd.sh`，且 T3/T4 依賴 T2 的共用前置判斷函式；T5 依賴 T2~T4 的函式簽名 |
| 第 2 批（並行支線） | **T6** | **可與第 2 批並行** | 唯一寫入 `.claude/settings.local.json`，與 hook 腳本路徑不重疊。掛載的是尚未存在的腳本路徑——不會出錯，hook 檔不存在時 Claude Code 靜默略過 |
| 第 3 批 | **T7** | 序列（最後） | 手動驗證需要 T2~T6 全部落地 |

**🔴 `.claude/settings.local.json` 是共享檔，只有 T6 一個 owner。** 任何其他任務都不得觸碰它。

---

## 5. 測試策略

### 5.1 現實：本專案沒有任何 hook / bash 測試可沿用

實查確認：
- `.claude/skills/gen-dev-workflow/scripts/` 底下只有 `wf-state.sh`，無 test 檔。
- 全 repo 找不到任何 hook 相關測試（`*hook*test*`、`*test*hook*` 皆零命中）。
- `test/` 是純 Dart 產品測試（`*_test.dart`），bash/python hook 放不進 Dart test runner。
- 既有 hook（`wf-guard-stage-check.sh`，BUG-1 修復）是以「四情境手動實測」驗證的。

**因此不能寫成「沿用既有測試位置與風格」——沒有既有的可沿用。**

### 5.2 決策：採混合策略（方向 c）

**選擇：核心純函式邏輯寫可獨立執行的自我檢查，端到端情境走手動驗證。**

理由（三點，逐一對應考量）：

1. **白名單比對不是 trivial 邏輯，且會被反覆修改。** 規格 §3.2 明訂「白名單只增不減」——這保證了它會持續變動。R-1 又把「白名單漏列導致誤殺」列為**最高風險**。一個會反覆改、改錯代價最高的純函式，正是 Ponytail「非 trivial 邏輯留一個可跑的檢查」所指的對象。全手動（方向 a）意味著每次動白名單都得手跑 15 條，實務上不會發生，等於零回歸保護。
2. **不引入框架，所以不構成第二套測試體系。** 檔案是**單一 Python 檔、只用 `assert`、`python3 <file>` 直接跑**——沒有 bats、沒有 pytest、沒有 fixture、沒有 runner 設定、不進 CI。它在形式上更接近「腳本的 `__main__` 自我檢查」而非「測試套件」。維護成本 = 一個檔案。相對地，bats（方向 b 的常見選擇）是實打實的新依賴 + 新慣例，違反 Ponytail 階梯第 5 級。
3. **端到端情境在物理上無法自動化。** AC-B1~B4 需要「真的觸發一次 MCP 委派並讓子進程寫錯目錄」，AC-A1~A3 需要「真的送出一次帶特定 prompt 的 MCP 呼叫」。要自動化就得偽造整個 Claude Code hook 執行環境——那個 harness 本身的複雜度會遠超被測的腳本，是典型的過度工程。

> `// ponytail:` 純 assert 自我檢查，無框架、不進 CI。升級路徑：若日後 hook 數量增加到 5 個以上、或誤判事故重複發生，再考慮引入 bats 與 CI。

### 5.3 自動化涵蓋（`.claude/hooks/tests/test_delegate_cwd_logic.py`）

| AC | 檢查內容 |
|:---|:---|
| **AC-C2** | `whitelist_roots()` 回傳的清單中，§3.2 表格每一類路徑各有一個對應 root；`is_allowed()` 對每類各一個代表性路徑回傳 True |
| AC-B3 的邏輯層 | `is_allowed("<PUB_CACHE>/hosted/pub.dev/foo/x.dart")` == True；`is_allowed("<flutter SDK 根>/bin/cache/x")` == True |
| AC-B1 的邏輯層 | `is_allowed("<主repo>/lib/foo.dart")` == False；`is_allowed("<主repo>/.git/index")` == True（`.git/` 白名單但工作區黑名單） |
| AC-B4 的邏輯層 | 差集函式：before 已含 `M lib/a.dart`，after 相同 → 差集為空 |
| AC-B1 的差集層 | before 為空、after 含 `?? lib/b.dart` → 差集含該項 |
| SDK 反解 | `PUB_CACHE` 有設定時採用環境變數值、未設定時回退 `~/.pub-cache` |

**做法**：把 T2 抽出的三個純函式放進腳本內以 `# --- pure logic ---` 區塊標示，測試檔用 `re` 抽出該區塊 `exec()` 之——避免為了可測性把腳本拆成 module（那才是不必要的抽象）。

> `// ponytail:` 用 exec 抽區塊而非拆 module。升級路徑：若第二個 hook 也要共用白名單，再抽成 `.claude/hooks/lib/`。

### 5.4 手動驗證清單（T7 執行，逐條記錄結果）

| AC | 情境 | 期望 |
|:---|:---|:---|
| AC-A1 | STAGE 2，派發 prompt 不含工作目錄段 | 阻擋（exit 2），stderr 列出缺少段落與正確格式 |
| AC-A2 | prompt 含工作目錄但路徑錯誤 | 阻擋，stderr 同時列出 prompt 路徑與應為路徑 |
| AC-A3 | prompt 含正確工作目錄路徑 | 放行 |
| AC-B1 | 主 repo clean，子進程在主 repo 工作區寫檔 | 告警，列出具體越界檔案路徑 |
| AC-B2 | 子進程完全在 worktree 內動手（含 add/commit） | 不告警 |
| AC-B3 | 子進程僅跑 `flutter pub get` + `flutter --version` | 不告警 |
| AC-B4 | 委派前主 repo 已 dirty，委派期間無新增變動 | 不告警（P-9 差集驗證） |
| AC-B5 | AC-B1 觸發後 | `.claude/workflow-state/cwd-violations.log` 有對應紀錄 |
| AC-B6 | 無 state 檔時委派 | 無輸出、無可感知延遲 |
| AC-B7 | 手動在腳本內注入 `raise` | 委派結果不受影響（fail-open） |
| AC-C1 | 派發 responder（stage != 5） | `wf-guard-stage-check.sh` 仍照常阻擋 |
| AC-C1 | 跑 `gh pr create` | `cbm-reindex-on-pr.sh` 仍照常觸發背景索引 |

---

## 6. Ponytail 紀律檢查表

本次刻意**不做**的事，逐條對應規格與裁決：

| 不做的事 | 依據 |
|:---|:---|
| 白名單抽外部設定檔 / loader | U-5：先寫死，出現第二個消費者再抽 |
| 「標記 workflow 需人工確認」機制 | U-1 使用者裁決：僅告警 |
| 環境變數升級開關（告警 → 阻斷） | U-1 使用者裁決：不做兩階段版本 |
| 稽核 log 輪替 / 清理排程 | AC-B5 只要求「可稽核」，`$TMPDIR` 由 OS 清、log 隨 workflow 走 |
| 為 pre/post 各寫一個腳本 | 會產生兩份必然同步修改的重複邏輯（§1.3） |
| 把純函式拆成獨立 module 以利測試 | 為可測性而做的抽象；`exec` 抽區塊已足夠（§5.3） |
| Antigravity `.agents/hooks.json` 同步掛載 | 本次委派管道是 Claude 側 MCP，不擴大範圍 |
| 引入 bats / pytest / CI 整合 | §5.2 理由 2 |
| 涵蓋 Fallback 模式（U-3） | 規格未決事項，本次不處理；Fallback 無 MCP 呼叫，路 A/B 皆天然不觸發 |

---

## 7. 執行方式選項

| 方式 | 適用 | 說明 |
|:---|:---|:---|
| **subagent-driven（建議）** | 本計畫 | T1 → (T2→T3→T4→T5 序列 ‖ T6 並行) → T7。第 2 批的兩條支線可用 Workflow `pipeline()` 並行；主線內部必須序列。T4 標為最強推論、T2/T3/T5/T7 標準、T1/T6 快/便宜 |
| **parallel session** | 不建議 | 主線 4 個任務全部寫入同一個檔案，並行度只有 T6 一個任務，開第二個 session 的協調成本大於收益 |

**建議：subagent-driven，單一 session。** 真正可並行的只有 T6（一個 2 分鐘的 JSON 編輯），不值得為它拆 session。
