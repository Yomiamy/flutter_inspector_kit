# 功能規格：workflow 狀態機腳本（wf-state.sh）

> **來源**：[gen-dev-workflow 全階段分析報告](2026-07-11-gen-dev-workflow-analysis.md) — 🔴「文件 vs 執行」與 🟡「狀態檔脆弱」兩項缺點
> **Issue**：[#78](https://github.com/Yomiamy/flutter_inspector_kit/issues/78)
> **PR**：[#79](https://github.com/Yomiamy/flutter_inspector_kit/pull/79)
> **日期**：2026-07-11
> **狀態**：Done — 已合併（文件為事後補齊）

---

## 問題

`gen-dev-workflow` skill 的整條流程控制是**純 markdown 文件**，靠 LLM「讀懂後遵守」。實際運行時三個層面同時失守：

| 失守點 | 現象 |
|--------|------|
| **狀態檔脆弱** | state 檔由 LLM 手寫 JSON。無 schema 校驗、無版本號；寫到一半中斷即腐壞，下次續接**靜默出錯**而非報錯 |
| **stage 轉移無強制** | SKILL.md 寫了 `0a→0b→1→2→3→4` 的 state machine，但沒有任何可執行的 guard——sequence 模式可被**無聲跳段** |
| **暫停點靠自律** | 使用者確認點只是文件裡的一句話。LLM 可能直接跳過確認往下跑，違規不留任何訊號 |

**核心矛盾**：文件描述了一台 state machine，卻沒有任何程式碼實作它。這等於寫一份「請不要碰記憶體」的備忘錄給 C 程式員，然後期待 segfault 不會發生。

---

## 解決方案（一句話）

新增 `scripts/wf-state.sh` 作為 workflow state 的**唯一存取入口**，把「可程式化的規則」從文件搬進程式：schema 校驗 + 原子寫入、stage 轉移合法性表、暫停點棘輪。

---

## 使用者故事

### US-1：壞掉的 state 檔應該立刻失敗，不該靜默續接
> 身為使用這條 workflow 的開發者，
> 當 state 檔因中斷而寫壞、或欄位被寫成非預期型別時，
> 我希望下次讀取時**立即報錯**而不是被當成合法 state 續接，
> 好讓我知道要重來，而不是在錯誤基礎上跑完整條流程。

### US-2：跳段必須是不可能的，不是不建議的
> 身為使用這條 workflow 的開發者，
> 當流程試圖從 STAGE 1 直接跳到 STAGE 3（跳過實作），
> 我希望腳本直接拒絕（exit 1），
> 好讓「文件說不可以」變成「程式上做不到」。

### US-3：跳過暫停點必須留下痕跡
> 身為使用這條 workflow 的開發者，
> 當 LLM 想在我還沒確認時就推進 stage，
> 我希望它必須**蓄意加上 `--confirmed` 旗標**才做得到，
> 好讓「無聲遺忘暫停點」變成一個會留在 Bash 歷史裡、可稽核的動作。

---

## 驗收條件

| # | 條件 | 驗證方式 |
|---|------|---------|
| AC-1 | state 檔含 `schema_version` 欄位，讀取（`get`）時即校驗，不合法直接 exit 1 | 手動路徑測試（壞檔拒讀） |
| AC-2 | 所有寫入為原子操作（tmp → `jq` 驗證 → `mv`），失敗時零 tmp 殘留 | 手動路徑測試（原子寫入 + tmp 清理） |
| AC-3 | sequence 模式僅接受 `0a→0b→1→2→3→4`、`3→2`（審查退回）、`4→done`，其餘轉移 exit 1 | 手動路徑測試（合法與非法轉移各一組） |
| AC-4 | `stage-done` / `task-done` 後 `awaiting_confirmation=true`；未帶 `--confirmed` 的 `advance` 一律拒絕 | 手動路徑測試（棘輪拒絕） |
| AC-5 | `set` 白名單僅允許 `spec`/`plan`/`branch`/`issue`/`pr`/`total_tasks`/`interrupted_by`，禁改 `stage` 與確認旗標 | 手動路徑測試（set 白名單） |
| AC-6 | `upgrade` 單向：僅 `quick` → `sequence`（stage 落在 2），其他 mode 拒絕 | 手動路徑測試（upgrade 單向） |
| AC-7 | quick / jump 模式不套用轉移表（保留彈性），但 schema 校驗與棘輪照常生效 | 手動路徑測試（quick 轉移表豁免） |
| AC-8 | `init` 撞到既有 state 檔時拒絕（不覆蓋既有流程） | 手動路徑測試（init 撞檔拒絕） |
| AC-9 | 在 `/bin/bash` 3.2（darwin 預設）可正常執行，含 CJK 錯誤訊息 | 於 bash 3.2 實測全部路徑 |
| AC-10 | SKILL.md 明文禁止手寫 state JSON，生命週期表全部改為腳本指令 | 文件對比 |

---

## 設計摘要

### state 檔 schema

```
{
  schema_version: 1,            // 校驗必檢
  workflow_id: string,          // wf-<epoch>-<random>
  stage: string,                // "0a" | "0b" | "1" | "2" | "3" | "4" | "done"（quick/jump 為自由標籤）
  mode: "sequence" | "jump" | "quick",
  spec: string?, plan: string?, branch: string?, issue: ?, pr: ?,
  completed_tasks: number[],    // STAGE 2 已完成任務編號
  total_tasks: number?,
  interrupted_by: string?,
  awaiting_confirmation: boolean // 暫停點棘輪旗標
}
```

### 三道 guard

1. **schema 校驗 + 原子寫入**
   寫入路徑一律 `jq` 產生 tmp → `validate` 驗過 → `mv` 就位。壞資料**進不了磁碟**；寫到一半中斷不留半套 state。`get` 讀取即校驗——腐壞檔立即失敗而非靜默續接。

2. **stage 轉移合法性表**（sequence 模式）
   ```
   0a → 0b → 1 → 2 → 3 → 4 → done
                    ↑    │
                    └────┘  （3→2：審查退回重做）
   ```
   非法轉移直接 exit 1。**強制性跟著 `mode` 走**：quick / jump 不套轉移表（quick 的階段本來就非正式、jump 是使用者明示跳段），但校驗與棘輪照常生效。

3. **暫停點棘輪**
   `stage-done` / `task-done` → `awaiting_confirmation = true`。此後未帶 `--confirmed` 的 `advance` 一律拒絕。`set` 白名單禁改 `stage` 與確認旗標——沒有繞過的側門。

### 指令介面

| 指令 | 用途 |
|------|------|
| `init [--mode] [--stage] [--branch] [--set k=v]` | 建新 state（無 branch → pending 檔） |
| `promote <pending> --branch <b> [--dest <dir>]` | pending → 正式 state（STAGE 1 建好 worktree 後） |
| `get <檔>` | 校驗後輸出 JSON |
| `set <檔> k=v ...` | 更新白名單欄位 |
| `stage-done <檔> <stage>` | 標記 stage 完成，進入等待確認 |
| `task-done <檔> <n>` | STAGE 2 單一任務完成，進入等待確認 |
| `confirm <檔>` | 使用者已確認（stage 不變） |
| `advance <檔> <next> --confirmed` | 確認並推進 stage |
| `upgrade <檔> [--confirmed]` | quick → sequence（單向，stage 落在 2） |

---

## 範圍邊界

### 在範圍內

- `scripts/wf-state.sh`：state 檔唯一存取入口（schema 校驗、原子寫入、轉移表、棘輪、白名單）
- `SKILL.md`：新增「狀態機腳本（唯一存取入口，強制）」章節與指令對照表；生命週期表、Token Gate、quick 升級路徑全部改為腳本指令
- 分析報告狀態更新：「狀態檔脆弱」→ ✅ 已解決；「文件 vs 執行」🔴 高 → 🟡 中

### 明確排除

| 排除項 | 理由 |
|--------|------|
| 「LLM 根本不呼叫腳本」的強制 | 腳本無法強制自己被呼叫。這層仍是文件約束——**這正是缺點降為 🟡 而非消除的原因** |
| Token Budget Gate 的 context 用量估算 | LLM 無法精確測量自己的 context 用量，無程式解，維持啟發式 |
| 暫停點密度優化 | 分析報告指出的下一個待修項，獨立議題 |
| hooks 層面的強制 | 更強的攔截層，本次不做 |
| 自動 rollback / `git revert` | 3→2 退回只是「重做」，壞 commit 留在歷史中，不在本次範圍 |

---

## 破壞性分析

| 面向 | 風險 | 緩解 |
|------|------|------|
| 既有 workflow state 檔 | 舊檔無 `schema_version` → 校驗失敗 | 舊 state 為短生命週期的 in-flight 檔案，無長期保存需求；失敗即報錯是預期行為（勝過靜默續接） |
| quick / jump 模式彈性 | 套上轉移表會綁死非正式階段 | 強制性跟著 `mode` 走：quick/jump 豁免轉移表，只保留校驗與棘輪 |
| bash 3.2（darwin 預設） | `$var` 直接接 CJK 會展開炸裂 | 全數改用 `${var}` 大括號包覆；15+ 條路徑於 bash 3.2 實測通過 |
| 並發啟動 | 「檢查存在 → mv」中間有窗口 | `claim_new` 用 `set -C` 排他建檔，撞檔直接失敗 |
| 依賴 | 新增 `jq` 依賴 | `jq` 是開發機標配；腳本啟動即檢查，缺少時明確報錯 |

---

## 核心判斷

✅ **值得做**。

理由：這不是把文件寫得更詳細——那只是同一個錯誤的更長版本。**規則要能被機器拒絕，才叫規則。** 把可程式化的 guard 搬進 `wf-state.sh` 之後，最危險的假設從「markdown 指令 = 程式碼保證」縮小為「LLM 會記得呼叫腳本」——違規面從『整條流程的每一條規則』縮到『一個入口點』。縮小攻擊面就是進步。

---

## 相關文件

- 分析報告（問題來源）：[2026-07-11-gen-dev-workflow-analysis.md](2026-07-11-gen-dev-workflow-analysis.md)
- 實作計畫：[../plans/2026-07-11-wf-state-script.md](../plans/2026-07-11-wf-state-script.md)
- 腳本本體：`.claude/skills/gen-dev-workflow/scripts/wf-state.sh`
- Skill 文件：`.claude/skills/gen-dev-workflow/SKILL.md`
