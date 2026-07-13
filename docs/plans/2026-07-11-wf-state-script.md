# 實作計畫：workflow 狀態機腳本（wf-state.sh）

> **功能規格**：[docs/features/2026-07-11-wf-state-script.md](../features/2026-07-11-wf-state-script.md)
> **Issue**：[#78](https://github.com/Yomiamy/flutter_inspector_kit/issues/78) ｜ **PR**：[#79](https://github.com/Yomiamy/flutter_inspector_kit/pull/79)
> **日期**：2026-07-11
> **狀態**：Done — 已合併（文件為事後補齊，內容依實際實作回填）

---

## 任務總覽

| # | 任務 | 複雜度 | 檔案 | 依賴 |
|---|------|--------|------|------|
| 1 | `wf-state.sh` 核心：schema 校驗 + 原子寫入 + 指令骨架 | Medium | `.claude/skills/gen-dev-workflow/scripts/wf-state.sh` | 無 |
| 2 | 三道 guard：轉移表 / 棘輪 / `set` 白名單 | Medium | 同上 | Task 1 |
| 3 | SKILL.md 改寫：唯一存取入口章節 + 全流程改用腳本指令 | Medium | `.claude/skills/gen-dev-workflow/SKILL.md` | Task 2 |
| 4 | 分析報告狀態回填 | Low | `docs/features/2026-07-11-gen-dev-workflow-analysis.md` | Task 2 |

**並行判定**：Task 1 → Task 2（序列，同一檔案）。Task 3 與 Task 4 都依賴 Task 2 的最終介面，但**寫入路徑不重疊**，可並行。

```
Task 1 ──→ Task 2 ──┬──→ Task 3（SKILL.md）
                    └──→ Task 4（分析報告）   ← 兩者可並行
```

---

## Task 1：核心（schema 校驗 + 原子寫入 + 指令骨架）

**檔案**：`.claude/skills/gen-dev-workflow/scripts/wf-state.sh`（新增）
**複雜度**：Medium

### 內容

#### 1a. 環境與前置

- `set -euo pipefail`
- `STATE_DIR="${WF_STATE_DIR:-.claude/workflow-state}"`、`SCHEMA_VERSION=1`
- 啟動即檢查 `jq` 存在，缺少直接 `die`

#### 1b. `validate()` — schema 校驗

用單一 `jq -e` 表達式檢查全部欄位型別，任一不符即 `die`：

```
schema_version == 1
workflow_id / stage : string
mode                : "sequence" | "jump" | "quick"
completed_tasks     : array of number
total_tasks         : null | number
awaiting_confirmation : boolean
```

#### 1c. `atomic_write()` — 原子寫入

`jq . > tmp` → `validate tmp` → `mv tmp target`。

**關鍵細節**：`validate` 放在**子 shell** 內執行（`( validate "$tmp" ) || { rm -f "$tmp"; exit 1; }`），否則 `validate` 的 `die` 會直接終止整支腳本、tmp 檔留在磁碟上。

#### 1d. `claim_new()` — 排他佔位

`( set -C; : >"$1" )`——檔案已存在即失敗，消滅「檢查存在 → mv」之間的並發窗口。搭配 `trap 'rm -f "$f"' EXIT`，`atomic_write` 失敗時清掉 0-byte 佔位檔，避免卡死 branch 名。

#### 1e. 指令骨架

`init` / `promote` / `get` / `set` / `stage-done` / `task-done` / `confirm` / `advance` / `upgrade`，`resolve()` 支援「路徑」或「相對 `$STATE_DIR` 的檔名」兩種寫法。

---

## Task 2：三道 guard

**檔案**：同 Task 1
**複雜度**：Medium

### 2a. stage 轉移合法性表（`legal_transition()`）

```
0a→0b | 0b→1 | 1→2 | 2→3 | 3→4 | 3→2 | 4→done   → 合法
其餘                                              → exit 1
```

**只在 `mode == "sequence"` 時套用**。quick / jump 的 stage 是自由標籤（如 `review`），套轉移表會綁死彈性。

### 2b. 暫停點棘輪

- `stage-done <檔> <stage>` → `awaiting_confirmation = true`
  - sequence 模式下 `<stage>` 必須等於目前 stage——不讓 `stage-done` 替 `advance` 代勞改 stage 值
- `task-done <檔> <n>` → 記入 `completed_tasks`（`unique`）+ `awaiting_confirmation = true`
  - sequence 模式僅能在 STAGE 2 執行
- `advance <檔> <next> --confirmed`：`awaiting_confirmation == true` 且未帶 `--confirmed` → **拒絕**
- `confirm <檔>`：清旗標、stage 不變（STAGE 2 任務間用）

### 2c. `set` 白名單（`apply_sets()`）

僅允許 `spec` / `plan` / `branch` / `issue` / `pr` / `total_tasks` / `interrupted_by`。
試圖 `set stage=...` 或 `set awaiting_confirmation=false` → `die`——**堵死繞過棘輪的側門**。

搭配 `jq_val()` 做值型別解析：`null`/`true`/`false`/數字原樣，前導零（如 `007`）不是合法 JSON 數值，當字串處理。

### 2d. `upgrade` 單向

`quick` → `sequence`（`stage` 落在 `2`）。其他 mode 一律拒絕。等待確認中且未帶 `--confirmed` 同樣拒絕。

---

## Task 3：SKILL.md 改寫

**檔案**：`.claude/skills/gen-dev-workflow/SKILL.md`
**複雜度**：Medium

| 改動 | 內容 |
|------|------|
| 新增章節 | 「狀態機腳本（唯一存取入口，強制）」——三道 guard 說明 + 時機／指令對照表 |
| 明文禁令 | **絕不手寫或手改 state JSON** |
| 生命週期表 | 全部改為腳本指令（`init` / `promote` / `set` / `stage-done` / `advance`…） |
| 暫停點段落 | 補上「棘輪」說明：每個暫停點對應一次 `stage-done`／`task-done`，確認後才 `advance --confirmed` |
| Token Gate | 中斷／續接改用腳本指令 |
| quick 升級路徑 | 改為 `wf-state.sh upgrade` |
| JSON 範例 | 補上 `schema_version` / `awaiting_confirmation` 欄位 |

---

## Task 4：分析報告狀態回填

**檔案**：`docs/features/2026-07-11-gen-dev-workflow-analysis.md`
**複雜度**：Low

| 條目 | 改動 |
|------|------|
| 「狀態檔脆弱」 | ~~JSON 手動管理無校驗~~ → ✅ **已解決**（schema 校驗 + 原子寫入 + `get` 讀取即校驗） |
| 「文件 vs 執行」 | 🔴 高 → 🟡 **中**，並記錄殘餘風險：LLM 仍可能根本不呼叫腳本；context 用量估算無程式解 |
| 「已修掉的問題」 | 補入第 (3) 點：可程式化的 guard 已進 `wf-state.sh` |
| 「最危險的假設」 | 更新為：從「markdown 指令 = 程式碼保證」縮小為「LLM 會記得呼叫腳本」 |

---

## 驗證計畫

**沒有測試框架可用**（bash 腳本 + skill 文件，不在 Dart 測試範圍內），驗證方式為**手動路徑實測**，於 `/bin/bash` 3.2（darwin 預設）逐條執行：

| # | 路徑 | 預期 |
|---|------|------|
| V-1 | `init` 正常建檔 | 產出合法 state，輸出檔路徑 |
| V-2 | `init` 撞到既有檔 | exit 1，不覆蓋 |
| V-3 | `init --mode sequence --stage 1` | 拒絕（sequence 只能從 0a 起） |
| V-4 | `promote` pending → branch 檔 | 搬到目標 dir，pending 檔移除 |
| V-5 | `get` 讀合法檔 | 輸出 JSON |
| V-6 | `get` 讀壞檔 | exit 1（不靜默續接） |
| V-7 | `set spec=...` | 成功 |
| V-8 | `set stage=3` | 拒絕（白名單） |
| V-9 | `set awaiting_confirmation=false` | 拒絕（白名單） |
| V-10 | `stage-done` 後直接 `advance`（無 `--confirmed`） | **拒絕**（棘輪） |
| V-11 | `stage-done` → `advance --confirmed` 合法轉移（如 `2→3`） | 成功 |
| V-12 | `advance --confirmed` 非法轉移（如 `1→3`） | 拒絕（轉移表） |
| V-13 | `advance` 審查退回 `3→2` | 成功（合法路徑） |
| V-14 | `task-done` + `confirm`（STAGE 2 任務間） | `completed_tasks` 累加，stage 不變 |
| V-15 | `task-done` 於非 STAGE 2（sequence） | 拒絕 |
| V-16 | quick 模式任意 stage 轉移 | 通過（不套轉移表），但棘輪照常 |
| V-17 | `upgrade` from quick | mode→sequence、stage→2 |
| V-18 | `upgrade` from sequence | 拒絕（單向） |
| V-19 | 原子寫入失敗後 | 零 `.wf-tmp.*` 殘留 |

---

## 檔案異動彙整

| 操作 | 檔案路徑 | 動幅 |
|------|---------|------|
| **新增** | `.claude/skills/gen-dev-workflow/scripts/wf-state.sh` | 239 行 |
| **修改** | `.claude/skills/gen-dev-workflow/SKILL.md` | 新增狀態機章節；生命週期表／Token Gate／quick 升級改為腳本指令 |
| **修改** | `docs/features/2026-07-11-gen-dev-workflow-analysis.md` | 兩項缺點狀態回填 |
| **不動** | `lib/`、`test/`、`pubspec.yaml`、所有套件程式碼 | — |

**總計**：1 個新檔（bash 腳本）、2 個文件修改，**零 Dart 程式碼異動、零新 pub 依賴**。

---

## 實作後記（PR review 修正）

原始實作在 review 中被抓出兩批問題，已於後續 commit 修正：

| Commit | 問題 | 修正 |
|--------|------|------|
| `e9ddde4` | **Critical**：bash 3.2 下 `$var` 直接接 CJK 字元會展開炸裂，導致四條 guard 的錯誤訊息變亂碼 | 全數改為 `${var}` 大括號包覆；重驗四條 guard 拒絕路徑 |
| `e9ddde4` | `atomic_write` 失敗時 tmp 檔外洩 | `validate` 移入子 shell，確保 tmp 必被清掉 |
| `1967880` | state machine 繞過與可攜性缺口 | 補上 `claim_new` 排他佔位、`trap` 清 0-byte 佔位檔、`set` 白名單收緊 |
