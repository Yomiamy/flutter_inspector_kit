# 功能規格：STAGE 3 退回迴圈上限與三值審查裁決（Rework Loop Cap & Review Verdict）

> **建立日期**：2026-11-20
> **關聯提案**：[`docs/brainstorm/2026-11-09-workflow-brainstorm.md`](../brainstorm/2026-11-09-workflow-brainstorm.md) R8（退回邊一等公民、三值裁決）、R12(a)（迴圈偵測）
> **狀態**：草案（What & Why，待 STAGE 0a 確認）
> **模式**：Sequence
> **需求來源**：gen-grill brief（Q1–Q5 已與使用者確認）

---

## 1. 背景與痛點（Why）

### 1.1 現況實查（以程式碼為準）

| 位置 | 現況 |
|:---|:---|
| [`wf-state.sh:95`](../../.claude/skills/gen-dev-workflow/scripts/wf-state.sh#L95) `legal_transition` | 只有 `3->2` 這條邊本身，沒有任何附帶條件 |
| `wf-state.sh:305-338` `advance` | 參數只認位置 `$3 == --confirmed`；STAGE 3 相關的閘門只有「進 3 前 `total_tasks` 完成度」 |
| `wf-state.sh:160-181` `apply_sets` | 白名單 `spec\|plan\|branch\|issue\|pr\|total_tasks\|interrupted_by` + `pause_level`；無裁決、無退回欄位 |
| `wf-state.sh:50-62` `validate` | schema v1，無 reason / verdict / rework 欄位 |
| `wf-state.sh:389-408` | `--note` 只存在於批次佇列（`batch-fail`），workflow state 無理由欄位 |
| [`SKILL.md:234`](../../.claude/skills/gen-dev-workflow/SKILL.md) | 「STAGE 3 審查失敗退回 STAGE 2」列為**不應暫停**的情況 |

### 1.2 三個缺陷

1. **迴圈無上限、無人看**：`3→2→3` 可無限打轉。`balanced` 只停 `0b/2/4`、`autonomous` 全不停，STAGE 3 本身不暫停，退回又被列為「不應暫停」——批次模式（最常用 `balanced`）下這個迴圈完全沒有人類視線。機制 1（轉移合法性）管「能不能轉」、機制 2（棘輪）管「人有沒有確認」，**兩者都沒管「同一段反覆修不好」**。
2. **二值裁決逼出假 PASS**：reviewer 的結論只有「通過 / 不通過」。「可以發，但有件事要留案」這一級問題只能假裝 PASS（問題從紀錄中消失）或判 FAIL（流程停擺）。
3. **退回沒有理由留存**：`advance <檔> 2` 不帶任何資訊，state 檔看不出退回過幾次、為什麼退回；續接的新 session 與事後 `/retro` 都無從追溯。

### 1.3 借鏡什麼、不借鏡什麼

- **借 R8 的拓樸**：退回是具名的一條邊（帶理由）、裁決三值 `PASS / CONCERNS / FAIL`。**不借它的執行方式**——BMAD 的狀態機寫在 markdown 裡、靠指令自律，已有實證失敗；本案一律落在 `wf-state.sh` 的 exit code。
- **R12(a) 用計數取代 `issues_hash`**：hash 比對要先把 issue 集合正規化，對 LLM 產出的散文報告是假精確；「已退回 2 次」是零推論成本的純機械判定，且與 Rel(AI)Build「2–3 次後修復效力急降」的實證一致。

---

## 2. 使用者故事

- **身為流程編排者（主對話）**：reviewer 不通過時，我執行 `advance <檔> 2 --reason "<摘要>"` 退回；不寫理由就退不回去，理由與時間自動寫進 state。
- **身為使用者（`balanced` / 批次模式）**：前兩次退回自動跑完不打擾我；第三次要退回時流程一定停下來，把歷次退回理由攤給我看，由我決定再修、改判留案發布，或放棄。
- **身為 reviewer**：除了通過與不通過，我可以裁決 `CONCERNS`——可以發布，但未結案項必須跟著 PR 走，不會在流程裡蒸發。
- **身為 PR 讀者**：PR 描述裡能看到審查留下的未結案項，不必翻 session 紀錄。

---

## 3. 行為規格（What）

### 3.1 state schema 新增欄位（schema_version 維持 1）

| 欄位 | 型別 | `init` 初值 | 唯一寫入者 | 說明 |
|:---|:---|:---|:---|:---|
| `review_verdict` | `null` \| `"PASS"` \| `"CONCERNS"` \| `"FAIL"` | `null` | `set`（enum 校驗）；`advance … 3` 清空 | 本輪 STAGE 3 裁決 |
| `review_concerns` | `null` \| string | `null` | `set`；`advance … 3` 清空 | 未結案項，markdown 文字（多項一行一項） |
| `rework_history` | array of `{reason: string, at: string}` | `[]` | **僅** `advance` 的 `3→2` 追加 | 退回歷史；`at` 為 UTC ISO 8601（`YYYY-MM-DDTHH:MM:SSZ`） |

- **舊檔相容**：三欄缺席一律等同初值（`null` / `null` / `[]`）。`validate()` 對三欄採「缺席或為 null 即合法，有值才檢查型別」，與既有 `total_tasks` / `pause_level` 的寫法同構。**不升 schema_version**——升版會讓 `validate` 的 `schema_version == 1` 把所有進行中的 state 判為腐壞。
- **`rework_history` 不進 `set` 白名單**：可被 `set` 清空的計數器等於沒有上限（同 `stage` / `awaiting_confirmation` 不可 `set` 的理由）。

### 3.2 `advance` 參數

`advance <檔> <next> [--confirmed] [--reason <s>]`——旗標順序不拘；未知參數 `die`（與 `init` / `promote` 一致）。

### 3.3 STAGE 3→2 退回（所有模式）

以下規則在 **`cur == 3` 且 `next == 2`** 時生效，不分 mode（下稱「退回」）：

1. **理由必填**：未帶 `--reason`，或理由去頭尾空白後為空 → `die`，提示用法。
2. **上限併入既有棘輪**：`rework_history` 長度 **≥ 2** 時，本次退回視同暫停點——未帶 `--confirmed` 即拒絕，**不看 `pause_level`**。拒絕訊息須列出既往每筆 `at` + `reason`，供主對話原樣展示給使用者。`--confirmed` 的語意與既有棘輪完全相同（只能在使用者真的在對話中確認後帶上），不新增覆寫旗標。
3. **追加歷史**：通過上述檢查後，在同一次原子寫入中把 `{reason, at}` 追加到 `rework_history`，並推進 stage。
4. **`--reason` 用於退回以外的轉移** → `die`（避免使用者以為理由已被記錄，實際被丟棄）。
5. 任何 `die` 路徑 state 檔一律不變。

> 上限常數為 2（腳本內具名常數，不開放設定）。`strict` 下 STAGE 3 本來就停，每次退回都已帶 `--confirmed`，上限自然滿足；本規則的實質作用對象是 `balanced` / `autonomous`。jump 亦適用：jump 雖不套轉移表，`3→2` 仍是同一條退回邊，理由與上限只看 `cur`/`next` 與 `rework_history`，不依賴轉移表（見 D5）。但 jump 下上限只是**軟約束**：jump 的 `stage-done` 可直接改 stage 標籤、且無轉移表可走 `3→4→2`，都能繞過 `3→2`；腳本強制僅在 sequence 完整成立。

### 3.4 STAGE 3→4 裁決閘門（sequence 模式）

`mode == sequence` 且 `cur == 3` 且 `next == 4` 時：

| `review_verdict` | `review_concerns` | 結果 |
|:---|:---|:---|
| `null`（含舊檔缺席） | — | `die`：提示 `set <檔> review_verdict=PASS\|CONCERNS\|FAIL` |
| `FAIL` | — | `die`：提示修正請走 `advance <檔> 2 --reason` |
| `PASS` | 空 | 放行 |
| `PASS` | 非空 | `die`：裁決與未結案項矛盾 |
| `CONCERNS` | 非空 | 放行，`review_concerns` 保留至 STAGE 4 供 publisher 使用 |
| `CONCERNS` | 空 | `die`：`CONCERNS` 須附未結案項 |

不變式只有一條：**放行 ⇔ `review_verdict ∈ {PASS, CONCERNS}` 且 `(verdict == CONCERNS) == (concerns 非空)`**。`--confirmed` 不能覆寫 `FAIL`。

jump / quick 不套用本閘門：jump 可 `init --stage 4` 或從任意 stage 直接 `advance 4`，只擋 3→4 形同虛設，且會破壞進行中 jump state 停在 3 直接 `advance 4` 的既有路徑（見 D5）。jump 下主對話仍照 §3.6 寫入裁決，供 publisher 使用。

### 3.5 進入 STAGE 3 清空裁決（所有模式）

任何 `advance <檔> 3` 一律把 `review_verdict` 與 `review_concerns` 設回 `null`；`rework_history` 不動。

- 裁決只屬於「本輪」審查。退回期間（stage 2）舊裁決保留可見，說明為何在修；重新進 3 才清掉，杜絕上一輪的 `PASS` 被帶進下一輪。
- 清空不限 sequence：這是資料正確性，不是閘門；jump 模式重跑審查同樣不該留著舊結論。

### 3.6 裁決語意與 agent 契約

> 下表 `advance` 為簡寫：`stage-done 3` 依 `pause_level` 標了等待確認時（strict 恆是），須先取得使用者確認並加 `--confirmed`，否則被既有棘輪拒絕；`balanced`／`autonomous` 未暫停時不需要。

| 裁決 | 判定依據（對齊 reviewer.md 既有分級） | 主對話動作 |
|:---|:---|:---|
| `PASS` | 無 Critical / Important，無需留案項 | `set review_verdict=PASS` → `stage-done 3` → `advance 4` |
| `CONCERNS` | 無 Critical / Important（不阻擋），但有須在 PR 揭露、留待後續的未結案項 | `set review_verdict=CONCERNS review_concerns="<項目>"`（單次 `set`，原子寫入）→ `stage-done 3` → `advance 4` |
| `FAIL` | 有 Critical / Important（含 reviewer.md 兩種阻擋型 simplification） | `set review_verdict=FAIL` → `stage-done 3` → `advance 2 --reason "<摘要>"` |

- **reviewer**：報告首行輸出固定格式裁決（建議 `REVIEW: PASS|CONCERNS|FAIL`，前綴刻意不同於 Verifier 的 `PASS` / `FAIL: CODE` / `FAIL: INFRA`，避免混淆）；`CONCERNS` 時報告須有「未結案項」區段。reviewer 不寫 state，state 一律由主對話寫入。
- **publisher**：**建立新 PR 時（STAGE 4，或 quick 模式步驟④）**以 `wf-state.sh get` 讀 state（不依賴派發 prompt 轉述）；`review_verdict == CONCERNS` 時，PR 描述必須含「未結案項（Review CONCERNS）」區段，原樣列出 `review_concerns`。state 檔不存在視為無裁決、照常發布；存在但校驗失敗才停下回報。STAGE 5 更新 PR 描述時不依 state 增刪未結案區段（STAGE 5 不寫裁決，state 中的值已非最新）。
- **quick 模式**：快掃不經 `advance 3`，裁決不會自動清空；reviewer 首行為 `REVIEW: CONCERNS` 時主對話 `set review_verdict=CONCERNS review_concerns=…`，重掃結論改變時以同法覆寫。
- **使用者覆寫路徑**：使用者看過 `FAIL` 或上限停下後決定「就這樣發」→ 主對話把剩餘問題寫成 `review_concerns`、改判 `CONCERNS` 再推進。覆寫一定留下書面未結案項，並一路帶進 PR——不存在「無聲放行」。

### 3.7 典型流程（`balanced`，sequence）

```text
[2] 實作完成 ──advance 3──▶ [3] reviewer: FAIL
    set review_verdict=FAIL → advance 2 --reason "R1"            (history=1，自動)
[2] 修正 ──advance 3（清空裁決）──▶ [3] reviewer: FAIL
    set review_verdict=FAIL → advance 2 --reason "R2"            (history=2，自動)
[2] 修正 ──advance 3──▶ [3] reviewer: FAIL
    set review_verdict=FAIL → advance 2 --reason "R3"            ✗ 拒絕，列出 R1/R2
    ⏸ 主對話停下展示歷史，使用者擇一：
       ├─ 再修  → advance 2 --reason "R3" --confirmed           (history=3)
       ├─ 留案發布 → set review_verdict=CONCERNS review_concerns="…" → advance 4
       └─ 放棄  → 依 state-machine.md 刪檔規則
```

---

## 4. 設計判斷與 Trade-off

| # | 決策 | 選擇 | 捨棄方案與理由 |
|:---|:---|:---|:---|
| D1 | 欄位形狀 | 頂層平鋪三欄，schema_version 不升 | 巢狀 `review:{…}`：`set` 的 `.[$k] = $v` 只寫頂層，巢狀要改 `apply_sets`；升版會讓所有進行中 state 校驗失敗 |
| D2 | 上限的強制點 | 在 `advance` 退回當下要求 `--confirmed`，與 awaiting 共用同一條拒絕條件 | (a) 獨立 die 分支＋新旗標：多一個覆寫概念；(b) 讓 `should_pause` 在 history≥2 時強制停 `stage-done 3`：主對話跳過 `stage-done` 直接 `advance` 就繞過了，且會連 `3→4` 一起擋，超出需求 |
| D3 | 裁決清空時機 | 進入 stage 3 時清空 | 在 `3→2` 清空：stage 2 期間看不到為何退回，且 stage 2 期間預先 `set PASS` 會被帶進下一輪 |
| D4 | 未結案項形狀 | string，經既有 `set k=v` 寫入（與裁決同一次 `set`） | 新子指令 `review-verdict <檔> <V> --concern <s>…` 存陣列：寫入當下即可擋矛盾，但多一個子指令；目前沒有任何機器消費者需要逐項處理，publisher 只需原樣貼出 markdown。陣列的價值不足以付這個成本 |
| D5 | 規則適用模式 | 退回規則（理由／歷史／上限）不分模式；3→4 閘門僅 sequence | 退回邊在 jump 同樣存在、同樣會打轉，理由與上限只看 `cur`/`next` 與歷史，套用不需特例；3→4 閘門在 jump 形同虛設（可 `init --stage 4` 或任意 stage 直接 `advance 4`），硬套只會破壞進行中 jump state 停在 3 直接推進 4 的既有路徑；quick 的 stage 是自由標籤，實務上不命中 `3→2`。jump/quick 下上限為軟約束（`stage-done` 改標籤或 `3→4→2` 可繞過），只有 sequence 是腳本完整強制。（0b 初審修正：原案退回規則亦限 sequence，導致 jump 帶 `--reason` 被拒、文件須寫模式特例） |
| D6 | `FAIL` 能否 `--confirmed` 推進 | 不能；覆寫走改判 `CONCERNS` | 允許 `--confirmed` 覆寫會讓「帶著已知問題發布」不留書面紀錄 |
| D7 | 計數依據 | `rework_history` 長度，永不重置 | issues_hash（見 §1.3）；按輪重置會讓上限失效 |

---

## 5. 範圍邊界

### 包含（In Scope）
1. `wf-state.sh`：三欄 schema（`init` 初值、`validate` 相容校驗）、`apply_sets` 白名單加 `review_verdict`（enum）與 `review_concerns`、`advance` 參數解析與 §3.3–3.5 行為、`usage()` 文字。
2. 新 bash 測試 `.claude/hooks/tests/test_wf_state_rework_verdict.sh`。
3. 既有測試 `test_wf_state_done_reentry.sh` 的 helper 於 `3→4` 前補 `set review_verdict=PASS`（唯一允許的既有測試改動，見 §6）。
4. 文件同步（§8）。

### 不包含（Out of Scope）
- STAGE 2 內部 retry（`delegation-and-parallel.md` §退回路徑既有規則不變）。
- STAGE 0b plan-verifier `REVISE` 迴圈、STAGE 5 `5→5`。
- `issues_hash` 或任何報告內容比對。
- 退回時要求產出更新後的 plan（R8 的 BMAD 作法）。
- Verifier `PASS / FAIL: CODE / FAIL: INFRA` 契約。
- jump / quick 模式的 3→4 裁決閘門（退回規則不分模式，見 D5）。
- STAGE 5 reviewer 重審時寫入 `review_verdict`。
- 機械驗證 PR 描述確實含未結案項（如 `gh pr view --json body` 比對）。
- `gen-pr` skill 本身的格式；未結案項區段由 publisher 校對時補上。
- brainstorm / architecture 文件回寫（交 STAGE 6 `gen-sync-docs-by-branchs`）。

---

## 6. 破壞性分析

| 受影響對象 | 影響 | 處置 |
|:---|:---|:---|
| 進行中、停在 stage 3 的 sequence state | `advance 4` 會因裁決為空被拒 | 已接受：補一次 `set review_verdict=…` 即可；拒絕訊息直接給出指令 |
| 進行中、曾多次退回的 state | 舊檔無 `rework_history`，計數從 0 起算 | 已接受，不做回溯推算 |
| `test_wf_state_done_reentry.sh` 的 `new_done_state` | 直接 `advance 3 → 4`，會被新閘門擋下而整檔失敗 | 於 `4` 之前補 `set review_verdict=PASS` |
| `advance` 帶多餘參數的呼叫者 | 原本靜默忽略，改為 `die` | repo 內實查無此類呼叫（`.claude/` 下所有 `advance` 呼叫皆只帶 `--confirmed`） |
| 進行中、停在 stage 3 的 jump state | `advance 2` 改為須帶 `--reason`，且計入上限 | 屬 D5 本意；錯誤訊息直接給出用法 |
| `autonomous` 的「全不停」承諾 | 第 3 次起的退回成為例外暫停點 | 屬需求本意；SKILL.md 暫停粒度章節須明載此例外 |
| `strict` 模式 | 無行為差異（退回本就帶 `--confirmed`），僅多了必填 `--reason` 與 3→4 須先 `set` 裁決 | 文件同步 |
| `wf-guard-stage-check.sh` | 只看 `stage` 欄位，不受影響 | 無 |

---

## 7. 驗收條件（Acceptance Criteria）

以下除 AC-13 外，皆由 `test_wf_state_rework_verdict.sh` 以 bash 斷言覆蓋（AC-12 為 jump，其餘為 sequence 模式，經 `init → 0b → 1 → promote → 2 → 3` 建立 fixture）。

1. **AC-1 理由必填**：stage 3 執行 `advance <檔> 2`（無 `--reason`）→ exit 1，stderr 含 `--reason`；state 不變（stage 仍為 `"3"`）。
2. **AC-2 空理由拒絕**：`--reason ""` 與 `--reason "   "` → 同 AC-1。
3. **AC-3 退回記錄**：`advance <檔> 2 --reason "R1"` → exit 0；`.stage == "2"`；`.rework_history | length == 1`；`.rework_history[0].reason == "R1"`；`.rework_history[0].at` 符合 `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`。
4. **AC-4 退回上限（不看 pause_level）**：`pause_level=autonomous` 下完成 2 次退回後，第 3 次 `advance <檔> 2 --reason "R3"` → exit 1，stderr 含 `R1`、`R2` 與 `--confirmed`，`rework_history` 長度仍為 2；改為 `advance <檔> 2 --confirmed --reason "R3"`（旗標順序對調）→ exit 0，長度 3；第 4 次不帶 `--confirmed` 仍被拒。
5. **AC-5 理由誤用**：`--reason` 用於退回以外的轉移（如 stage 2 的 `advance <檔> 3 --reason x`）→ exit 1。
6. **AC-6 set 白名單**：`set review_verdict=PASS|CONCERNS|FAIL` 皆成功；`review_verdict=pass`、`review_verdict=OK` → exit 1；`set rework_history=x` → exit 1。
7. **AC-7 3→4 閘門**：依 §3.4 表逐列驗證——`null`、`FAIL`、`PASS`+非空 concerns、`CONCERNS`+空 concerns 皆 exit 1 且 stage 仍為 `"3"`；`null` 的 stderr 含 `review_verdict=`；`PASS` 放行至 `"4"`；`CONCERNS`+`review_concerns="X"` 放行，且 stage 4 時 `.review_concerns == "X"`。
8. **AC-8 進 3 清空**：`FAIL` → 退回 → `advance 3` 後，`.review_verdict == null`、`.review_concerns == null`，`rework_history` 長度不變。
9. **AC-9 init 初值**：新 `init` 的 state 含 `review_verdict: null`、`review_concerns: null`、`rework_history: []`。
10. **AC-10 舊檔相容**：以 `jq 'del(.review_verdict, .review_concerns, .rework_history)'` 產生的 v1 舊檔，`get` exit 0；在 stage 3 可 `advance 2 --reason` 成功（歷史從 1 筆起算）；`set review_verdict=PASS` 後 `advance 4` 成功。
11. **AC-11 壞值擋下**：直接寫入 `review_verdict: "MAYBE"`，或 `rework_history: [{"at": "…"}]`（缺 `reason`）的檔案 → `get` exit 1。
12. **AC-12 jump：退回規則適用、3→4 閘門不適用**：`init --mode jump --stage 3 --branch <b>` 後 `advance 4`（未設裁決）exit 0；`init --mode jump --stage 4` 直接建立仍成功。另一個 jump state 在 stage 3 `advance 2`（無 `--reason`）→ exit 1、stderr 含 `--reason`；`set review_verdict=FAIL` 後 `advance 2 --reason R1` → exit 0、`rework_history` 長度 1；`advance 3` 後 `.review_verdict == null`（jump 進 3 同樣清空）；再完成第 2 次退回後，第 3 次不帶 `--confirmed` → exit 1、stderr 含 `--confirmed`、長度仍為 2。
13. **AC-13 既有測試全綠**：`test_wf_state_total_tasks.sh`、`test_wf_state_done_reentry.sh`（僅 §5 第 3 點的改動）、`test_project_settings_hooks.sh`、`test_retro_skill.sh`、`python3 test_delegate_cwd_logic.py` 皆 exit 0。
14. **AC-14 文件鏈路閉環**：§8 所列文件皆已更新，人工檢視確認。

---

## 8. 需同步的文件

| 檔案 | 改動 |
|:---|:---|
| `.claude/skills/gen-dev-workflow/SKILL.md` | 編排流程圖 STAGE 3 區塊（`set` 裁決、`--reason`、第 3 次強制暫停、`CONCERNS` 留案）；暫停點規則表「審查報告完成後」列；「不應該暫停的情況」改為「前 2 次自動退回，第 3 次起任何 `pause_level` 都停」；暫停粒度章節註明 `autonomous` 的此一例外 |
| `references/state-machine.md` | 腳本 guard 說明補退回理由／上限／3→4 閘門；指令表加 `set review_verdict=…`、`advance 2 --reason`；JSON 範例加三欄並說明（比照 `interrupted_by` 段） |
| `references/command-cheatsheet.md` | 第 31、50 行「[若不通過] 退回 STAGE 2」改寫為帶 `set review_verdict` 與 `advance <檔> 2 --reason`（兩處相同，不分模式） |
| `references/delegation-and-parallel.md` | 第 157 行「與 STAGE 3 退回的關係」補一句上限規則（指向 SKILL.md） |
| `.claude/agents/reviewer.md` | 首行裁決格式、三值判定依據（§3.6）、`CONCERNS` 未結案項區段；完成條件改寫；註明不寫 state |
| `.claude/agents/publisher.md` | 建立新 PR 時（STAGE 4 / quick 步驟④）以 `wf-state.sh get` 讀裁決（無 state 檔照常、校驗失敗才停）；`CONCERNS` 時 PR 描述必含未結案項區段；STAGE 5 不依 state 增刪該區段 |
| `.agents/agents/reviewer.yaml`、`.agents/agents/publisher.yaml` | 鏡像定義，同步上兩列的新增段落 |
| `references/execution-modes.md` | quick 步驟③補 `CONCERNS` 裁決寫入與重掃覆寫；批次失敗條件改為「STAGE 3 退回達上限後使用者選擇放棄」 |
| `scripts/wf-state.sh` `usage()` | `advance` 用法加 `--reason`；`set` 說明加 `review_verdict` / `review_concerns` |

---

## 9. 開放問題（待使用者或 0b 決定）

1. **同輪改判是否需確認**：裁決由主對話寫入，閘門只防「忘了」，不防「改判 FAIL→CONCERNS 繞過」（與 `task-done` / `total_tasks` 相同的信任模型）。本規格不擋；若要擋，需讓 `set` 在 `FAIL` → 非 `FAIL` 時要求 `--confirmed`，這會替 `set` 引入它目前沒有的旗標。建議：不做，靠 §3.6 的覆寫路徑把改判留成書面 concerns。
2. **reviewer「建議精簡」是否自動構成 `CONCERNS`**：reviewer.md 現行的非阻擋 simplification 只列在報告尾段。建議不自動升級（否則幾乎每次都是 `CONCERNS`，稀釋語意），由 reviewer 判斷是否值得進 PR。
3. **reviewer 首行格式字面**：建議 `REVIEW: PASS|CONCERNS|FAIL`，0b 可改，但須與 Verifier 前綴可區分。
4. **`review_concerns` 純數字值**：`apply_sets` 對 `review_concerns` 一律以 `--arg` 存成字串（`null` 字面仍為清空），純數字不再被 `validate` 擋下。
