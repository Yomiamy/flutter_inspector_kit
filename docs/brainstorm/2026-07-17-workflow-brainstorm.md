# Gen-Dev-Workflow 改進評估：借鑑 Pilotfish 動態 Model/Effort 編排

> **來源**：[Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish) — Multi-model orchestration layer for Claude Code
> **日期**：2026-07-17
> **狀態**：brainstorm（尚未進入實作規劃）

---

## 背景

Pilotfish 是一個 Claude Code 的多 model 編排層，核心哲學：**frontier model 負責規劃與判斷，便宜 model 執行量產工作，fresh-context verifier 守護品質**。它定義了 8 個角色（scout / Explore / plan-verifier / security-reviewer / mech-executor / executor / verifier / security-executor），每個角色綁定不同的 model tier 與 effort level。

Anthropic 官方數據佐證了這個方向的可行性：
- Fable 5 orchestrator + Sonnet workers = **96% 全 Fable 的品質，46% 的成本**
- 社群實測 12-worker audit：Fable 5 + Haiku workers 節省 **74%** 成本

本文評估 4 個從 Pilotfish 借鑑的改進方向，逐一對照 gen-dev-workflow 目前的設計，給出核心判斷。

---

## 改進方向評估

### ① STAGE 0a context 收集降級

#### Pilotfish 做法
- 定義 `scout` 角色：`model: haiku, effort: low`，專做唯讀搜尋（grep、讀檔、git log、symbol lookup）
- 主 session（frontier model）只負責收斂 scout 回報的結果，撰寫規格

#### 目前 gen-dev-workflow 的做法
- STAGE 0a 的兩條並行 context 收集（A. 專案 context 讀檔 / B. 相似功能調查）都交給 `planner`（opus-level, effort: xhigh）
- 用最貴的 model 做唯讀搜尋，是純粹的浪費

#### 【核心判斷】✅ 值得做

**【關鍵洞察】**
- **資料結構**：STAGE 0a 的兩條線本質上是「唯讀資料收集」→「有判斷力的收斂」，兩個操作的認知需求天差地別
- **可消除的複雜度**：目前讓 planner 既當搜尋引擎又當分析師，混合了兩個不同推論等級的工作
- **風險點**：sonnet 搜尋品質足以覆蓋日常收集需求；偶爾漏報靠 STAGE 3 reviewer 看 diff 時自然能抓到（例如重複造輪）

**【方案】**

不新增角色。直接把 STAGE 0a 兩條收集線的派發參數從 opus 降到 sonnet：

```
現行：
  parallel([
    agent('收集專案 context', {agentType: 'Explore'})   // 繼承主 session opus ← 太貴
    agent('調查相似功能', {agentType: 'Explore'})        // 繼承主 session opus ← 太貴
  ]) → planner 收斂 → 撰寫規格

改為：
  parallel([
    agent('收集專案 context', {model: 'sonnet', effort: 'high'})   // sonnet, effort: high
    agent('調查相似功能', {model: 'sonnet', effort: 'high'})        // sonnet, effort: high
  ]) → planner 收斂並驗證 → 撰寫規格  // opus, effort: xhigh（只在這步）
```

**需要的配套：**
1. 修改 STAGE 0a 的 Workflow `agent()` 呼叫，加上 `model: 'sonnet', effort: 'high'` 參數
2. 推論等級表新增一行「偵察」等級

**預估效益**：STAGE 0a 的 token 消耗降低約 50-60%（兩條收集線從 opus→sonnet）

---

### ② 兩次失敗才升級（Tiered Retry Escalation）

#### Pilotfish 做法
- 失敗後先升一個 tier 再試，不是直接放棄
- 漸進式：haiku 失敗 → sonnet 重試 → opus 重試 → 才停

#### 目前 gen-dev-workflow 的做法
```
失敗單元 → 分析原因
  ├─ context 不足  → 補 context，重派同 model（最多 1 次）
  ├─ 任務過大      → 拆成更小單元，重新並行/序列
  ├─ 計畫本身有誤  → 退回 planner（STAGE 0b）
  └─ 重派仍失敗 2 次 → 停止，回報使用者
```
問題：重派用同 model 重試 2 次，不升級就放棄。

#### 【核心判斷】✅ 值得做，但要限縮範圍

**【關鍵洞察】**
- **資料結構**：目前的 retry 路徑是「同 tier 重試 → 放棄」，缺少「升級 tier」這個中間態
- **可消除的複雜度**：不需要完整的 haiku→sonnet→opus 三級鏈（我們的最低 tier 是 sonnet，不像 Pilotfish 從 haiku 起步）
- **風險點**：無限升級鏈會燒掉預算。必須有硬上限。
- **實用性**：真正會從「升級 tier」受益的場景是：機械性任務（快/便宜 model）因為推論能力不足而失敗，升到標準 model 就能過。設計判斷類的任務本來就在最強 tier，沒有升級空間。

**【方案】**

修改退回路徑，在「停止」之前插入一步「升級 tier」：

```
失敗單元 → 分析原因
  ├─ context 不足  → 補 context，重派同 model（最多 1 次）
  ├─ 任務過大      → 拆成更小單元
  ├─ 計畫本身有誤  → 退回 planner
  └─ 同 tier 重派失敗 2 次 → 升一級 tier 再試 1 次
       ├─ 成功 → 繼續（日誌記錄「任務 X 從 tier A 升級到 tier B 才成功」供未來參考）
       └─ 仍失敗 → 停止，回報使用者
```

| 原始 tier | 升級目標 | 說明 |
|---|---|---|
| 快/便宜（agy fast） | 標準（sonnet, effort: max） | 機械性任務推論不足 |
| 標準（sonnet, effort: max） | 最強推論（opus, effort: xhigh） | 整合任務推論不足 |
| 最強推論（opus, effort: xhigh） | — 無升級空間 | 直接停止回報 |

**硬規則**：升級最多發生一次。不搞 3 級串聯，避免失控燒錢。

---

### ~~③ 低 tier 收集結果信任等級聲明~~ — 已刪除

> Pilotfish 建議 planner 對低 tier 偵察結果做抽樣驗證。但我們的收集線用 sonnet（不是 haiku），搜尋品質已經足夠；且「planner 抽樣驗證」在實作上等於讓 planner 重做收集線的工作，省下的 token 又燒回去。偶爾的漏報靠 STAGE 3 reviewer 看 diff 時自然能抓到。不值得做。

---

### ④ Explore 覆蓋（全域設定層）

#### Pilotfish 做法
- Claude Code v2.1.198 起，內建 `Explore` subagent 繼承主 session 的 model
- 如果主 session 跑 Opus/Fable，每次背景搜尋都燒最貴的 token
- Pilotfish 透過 `~/.claude/agents/Explore.md` 把 Explore 鎖回 Haiku
- 代價：自訂 Explore 會載入 user memory（內建的不會），但 Pilotfish 在 subagent 角色下自動停用 policy block 來降低 overhead

#### 目前 gen-dev-workflow 的做法
- STAGE 0a 的 Workflow `agent()` 呼叫用 `agentType: 'Explore'`，會繼承主 session model
- 沒有全域 Explore 覆蓋

#### 【核心判斷】🟡 值得知道，但暫不納入 skill 層

**【關鍵洞察】**
- **資料結構**：這是全域 config 層（`~/.claude/agents/`）的設定，不是 skill 層的流程變更
- **可消除的複雜度**：如果 ① 落地（STAGE 0a 收集線降級至 sonnet），STAGE 0a 就不再依賴 Explore 的繼承行為，問題自然消失
- **風險點**：全域覆蓋 Explore 會影響所有專案的所有 session（包括非 workflow 的日常使用），副作用範圍太大
- **實用性**：對 Antigravity CLI (`agy`) 的使用場景，Explore 的行為可能與 Claude Code 不完全一致，需要驗證

**【方案】**

暫不在 gen-dev-workflow skill 裡處理。如果要做，屬於全域配置層的獨立改動：

```markdown
# 獨立議題：Explore Agent 全域 Model 覆蓋
- 範圍：~/.claude/agents/Explore.md（全域，非專案級）
- 前置：確認 Antigravity CLI 的 Explore 行為是否與 Claude Code 一致
- 如果 ① 落地，此項優先序自動降低
```

---

## 開發優先序

### P0：STAGE 0a 收集線降級至 Sonnet（①）

> **前置條件**：無
> **預估成本**：30 分鐘
> **預估效益**：STAGE 0a token 消耗降低 50–60%
> **狀態**：✅ 已於 `9d3de40` 落地（採最小改動：僅在 STAGE 0a `agent()` 呼叫層級加上 `model: 'sonnet', effort: 'high'` 覆蓋，未動任何 agent 定義檔）

**異動檔案：**
- `.agents/skills/gen-dev-workflow/SKILL.md` — 三處修改：
  1. STAGE 0a 並行收集的 `agent()` 呼叫加上 `model: 'sonnet', effort: 'high'`
  2. 推論等級表新增「偵察」行
  3. Stage 層級基準分配表中 STAGE 0a 的 agent 欄更新

**具體步驟：**
1. 修改 STAGE 0a Workflow `parallel()` 範例，將兩條 `agent()` 呼叫加上 `model: 'sonnet', effort: 'high'` 參數（不改 `agentType`，不新增 agent 定義）
2. 推論等級表新增一行：`偵察 | model: sonnet | effort: high | STAGE 0a 收集線`
3. Stage 層級基準分配表 STAGE 0a 行改為：`sonnet（收集）→ planner（收斂）`

**驗收條件：**
- [x] STAGE 0a 的兩條收集線派發參數為 sonnet + effort: high（`9d3de40`）
- [x] 不新增任何 agent 定義檔（僅參數覆蓋，`agentType: 'Explore'` 維持）
- [x] planner 仍為 opus-level，只負責收斂與撰寫規格（未變動）
- [ ] 推論等級表與 Stage 基準分配表已同步更新 — **未同步**：`9d3de40` 採最小改動只動 `agent()` 參數；Stage 基準分配表 `0a/0b` 行描述的是 planner 的收斂角色（仍為 Opus），未新增「偵察」行。若需表格層級文件一致性，列為後續 follow-up。

---

### P1：Tiered Retry Escalation（②）

> **前置條件**：無（可與 P0 平行進行）
> **預估成本**：1 小時
> **預估效益**：減少機械性任務失敗時的不必要人工介入
> **狀態**：✅ 已於 `b73d08f` 落地（退回路徑加入「同 tier 失敗 2 次 → 升一級 tier 再試 1 次」，硬性限制最多升級一次，並要求進度行註記 tier 升級）

**異動檔案：**
- `.agents/skills/gen-dev-workflow/SKILL.md` — 「退回路徑」段落

**具體步驟：**
1. 修改「退回路徑（失敗 retry 迴圈）」段落，在最後一條「重派仍失敗 2 次 → 停止」前插入升級步驟：
   ```
   └─ 同 tier 重派失敗 2 次 → 升一級 tier 再試 1 次
        ├─ 成功 → 繼續（日誌記錄升級事實）
        └─ 仍失敗 → 停止，回報使用者
   ```
2. 新增 tier 升級對照表：
   | 原始 tier | 升級目標 |
   |---|---|
   | 快/便宜 | 標準（sonnet, effort: max） |
   | 標準 | 最強推論（opus, effort: xhigh） |
   | 最強推論 | 無升級空間，直接停止 |
3. 明確硬規則：升級最多發生**一次**，不搞多級串聯

**驗收條件：**
- [x] 退回路徑包含「升一級 tier」步驟
- [x] tier 升級對照表存在且有硬上限
- [x] 升級成功時有日誌記錄的要求

---

### P2：Explore 覆蓋（④）— 條件性

> **前置條件**：P0 落地後重新評估是否仍有必要
> **預估成本**：低，但副作用範圍大（全域 config）
> **預估效益**：如果 P0 已落地，效益趨近於零

**異動檔案：**
- `~/.claude/agents/Explore.md`（全域，非專案級）

**具體步驟：**
1. P0 落地後，確認 STAGE 0a 是否仍有任何路徑使用內建 Explore
2. 若有 → 評估建立全域 `Explore.md` 覆蓋（`model: haiku`）
3. 若無 → 關閉此項，標記「P0 已解決，不再需要」

**驗收條件：**
- [x] P0 落地後重新評估，記錄結論：由於 P0 已在 workflow 呼叫 `Explore` 時明確指定 `model: 'sonnet'` 與 `effort: 'high'` 覆蓋，不再依賴 Explore 的預設繼承行為，故不需全域覆蓋。
- [ ] 若決定實施：Explore.md 存在且 model 為 haiku
- [x] 若決定不實施：本項標記關閉並附理由（P0 已於參數層級解決，全域修改副作用太大，不再需要）

---

### 依賴關係圖

```
P0（收集線降 Sonnet）──→ P2（Explore 覆蓋，條件性）
                            ↑ P0 落地後重新評估

P1（Tiered Retry）── 獨立，可平行
```

---

## 與 Pilotfish 的關鍵差異（不應照搬的部分）

| Pilotfish 設計 | 我們的情況 | 不照搬的原因 |
|---|---|---|
| 8 個角色（含 security-reviewer / security-executor） | 目前不需要 security 專職角色 | YAGNI — 本專案是 Flutter 套件，不是安全敏感的後端服務 |
| plan-verifier（唯讀挑戰 plan） | STAGE 3 reviewer 已涵蓋 | 我們的 reviewer 在 STAGE 3 已做多 angle 對抗式審查，加 plan-verifier 是重複 |
| 全域 CLAUDE.md policy | 我們用 per-project skill | 全域 policy 會影響所有專案，我們偏好專案級控制 |
| `best` alias 作為 orchestrator | 我們直接指定 `opus` | `best` alias 的解析行為可能隨 CLI 版本變動，不夠穩定 |
