# 用 Claude Workflow 執行並行（gen-dev-workflow 可選加速層）

> 本檔是 `gen-dev-workflow` 主 skill 的並行加速層參考。主檔（`../SKILL.md`）在使用者 opt-in 多 agent 編排時指向這裡。
> 未 opt-in 時完全用不到本檔——三處適用點一律退回主檔原本的 `Task(...)` / 序列作法，功能相同，只是不 fan-out。

**僅在使用者已 opt-in 多 agent 編排時啟用**（見主檔 [`../SKILL.md`](../SKILL.md) 的「Claude Workflow 編排（可選加速層）」章節）。未 opt-in → 三處全部退回原本的 `Task(...)` / 序列作法。

共通鐵則（與 [`delegation-and-parallel.md`](delegation-and-parallel.md) 的「並行三規則」一致，違反即退回序列）：
- 一個 `Workflow` 呼叫 = **一段不可中斷的 fan-out**，跑完才回到主對話。**暫停點永遠在 Workflow 呼叫之外**，由主指揮掌控。
- Workflow 回傳結構化結果後，主指揮負責**聚合、套用 model 策略、寫 state 檔、在既有暫停點展示**。Workflow 內部不碰 state 檔、不問使用者。
- 用 `pipeline()` 為預設；只有「下一步需要前一步全部結果」時才用 `parallel()` barrier。
- 共享檔（`pubspec.yaml`、DI 註冊、generated files）只能有唯一 owner；多任務搶同一檔 → 不可並行，退回序列。

## 適用點 1：STAGE 0a 雙線 context 收集

兩條唯讀調查（A. 專案 context 讀檔/git log｜B. 相似功能代碼調查），無依賴、不寫檔 → 天然安全的 `parallel()` barrier，收斂後才交給 planner 撰寫規格。

```js
// meta 省略；agentType 用 Explore（唯讀搜尋）但強制指定 model 與 effort 覆蓋
const [projCtx, similarCode] = await parallel([
  () => agent('收集專案 context：讀 README / pubspec / 近期 git log，回報架構與慣例', {agentType: 'Explore', model: 'sonnet', effort: 'high', schema: CTX_SCHEMA}),
  () => agent('調查與「<需求>」相似的既有實作，回報可參考的檔案與模式', {agentType: 'Explore', model: 'sonnet', effort: 'high', schema: CTX_SCHEMA}),
])
// 回到主對話：planner 收斂 projCtx + similarCode → 撰寫 docs/features/...md → 暫停確認（不在 Workflow 內）
```

## 適用點 2：STAGE 2 同批獨立任務

planner 已在計畫中標好各任務的**寫入檔案 scope** 與**複雜度等級**。同一批內「寫入路徑不重疊」的任務 → `pipeline()` 並行，**每個任務沿用原本的逐任務 model 分級**（`opts.model` 帶入計畫標註的等級）；**effort 需另外依推論等級表帶入**（`opts.model` 只管 model，不會連帶設定 effort）。

```js
// batch = 當前批次中路徑不重疊的任務；model/effort 來自計畫的複雜度標註（等級 → 綁定見 delegation-and-parallel.md 的「推論等級表」）
// 驗收固定走 verifier agent + effort: 'xhigh'（frontmatter 只綁 model，effort 不隨實作任務浮動，需顯式帶）
const results = await pipeline(
  batch,
  task => agent(task.prompt, {label: task.id, agentType: 'implementer', model: task.model, effort: task.effort, isolation: 'worktree', schema: TASK_SCHEMA}),
  (impl, task) => agent(`驗收任務 ${task.id}：跑測試、檢查 diff`, {label: `verify:${task.id}`, agentType: 'verifier', effort: 'xhigh', schema: VERIFY_SCHEMA}),
)
// 回到主對話：聚合 results → 寫 state（completed_tasks）→ 在「每批完成」暫停點展示 → 問使用者確認下一批
```

> ⚠️ **`agentType` 不可省略**：省略時 agent 不會套用該角色 `.claude/agents/*.md` 的 frontmatter（implementer 的 `model: sonnet`、verifier 的 `model: opus`），等於放棄角色綁定。`opts.model` 只覆寫 model，不會補上 agentType。
>
> ⚠️ **「快/便宜」是委派後端的內部等級，不是 Claude model 名**——`task.model` 帶的必須是 `sonnet`/`opus` 這類真實別名。計畫標「機械性」時對應 `model: 'sonnet'`，不要把「快/便宜」四個字直接傳進 `opts.model`。
>
> 邊界：**批與批之間的暫停由主指揮控制**，不可把多批塞進同一個 Workflow 連續跑完（那會跳過暫停點）。並行任務改檔時用 `isolation: 'worktree'` 避免互踩工作區。

## 適用點 3：STAGE 3 多 angle 對抗式審查

**reviewer 仍是主導者、最終判斷者**（不違反「審查報告 reviewer 親自判斷」）。Workflow 的 verifier 只是平行找 bug 的助手：依據**改動特徵驅動（Feature-driven Guard Clause）**決定派發哪些專門 lens，對抗式地嘗試挑出問題，reviewer 收斂所有 verdict 後親自寫審查報告。

### 1. Lens 派發判準矩陣（特徵驅動衛語句）

**省略專門 Lens 的正當理由，不是「行數少」，而是「改動在物理上不具備產生該類缺陷的條件」。**

| Lens | 派發條件（滿足任一即開獨立子 Agent） | 略過條件（滿足時免除獨立 Lens，由主審兜底） |
|:---|:---|:---|
| **`correctness`** | **核心基線：永遠必開**，檢查邏輯正確性與邊界。 | （不可略過） |
| **`過度工程`** | **核心基線：永遠必開**，挑出計畫外抽象與多餘代碼。 | （不可略過） |
| **`security`** | • 涉及網路傳輸、Dio/HTTP 攔截、外部 API<br>• 涉及金鑰、Token、認證、敏感資料遮罩<br>• 涉及反序列化、外部資料解析、條件匯出 | • 純內部 UI 樣式、排版常數<br>• 純離線腳本、Markdown 文件更動<br>• 改動範圍物理上無外部輸入與權限邊界 |
| **`回歸風險`** | • 涉及核心緩衝區（`RingBuffer`、`mergedTimeline`）<br>• 涉及生命週期（observer、dispose、listener 註銷）<br>• 涉及全域狀態、公共 API 簽章更動 | • 獨立新檔案且無現有呼叫端<br>• 純局部無狀態 Helper/Extension<br>• 純樣式或純展示 UI 微調 |
| **`測試覆蓋`** | • 新增業務邏輯、分支條件、演算法<br>• 重構核心路徑或修復特定 Bug | • 純文字/註解更新、純樣式微調<br>• 僅修改 workflow 規範文件或輔助腳本 |

> ⚠️ **Context 警戒收斂**：若 `100k ≤ context ≤ 150k`（依 Token Budget Gate 警戒區間；`context > 150k` 則強制切 session），為防中斷，一律收斂為僅派發 `correctness` + `過度工程`，其餘維度改由主 Reviewer 親自速審。

### 2. 動態派發腳本範例

```js
// 依據 diff 觸及檔案與特徵動態建構專門 lens
// （各 diffTouches* 特徵布林值由 Agent 於 STAGE 3 檢驗 git diff 時，依據上方「Lens 派發判準矩陣」對照判定）
// 若 context 處於 100k ~ 150k 警戒區間，收斂為空（只派發基線 2 個，其餘主審速審）
const activeSpecialLenses = []
if (!isNearTokenBudgetLimit) {
  if (diffTouchesNetworkOrAuthOrSerialization ||
      diffTouchesSensitiveDataMasking ||
      diffTouchesConditionalExports) {
    activeSpecialLenses.push('security')
  }
  if (diffTouchesCoreBufferOrLifecycleOrState ||
      diffTouchesPublicApiSignature) {
    activeSpecialLenses.push('回歸風險')
  }
  if (diffAddsLogicOrBranching || diffRefactorsCorePath || diffFixesSpecificBug) {
    activeSpecialLenses.push('測試覆蓋')
  }
}

// 每個 lens effort 對齊 STAGE 3 最強推論——不是任意選填
const findings = (await parallel([
  // 1. 核心基線：correctness 必開
  () => agent('以 correctness 視角審查 <branch> 的 diff，盡力挑出真實問題',
    {label: 'review:correctness', agentType: 'verifier', effort: 'xhigh', schema: FINDING_SCHEMA}),
  
  // 2. 特徵驅動的專門 lens
  ...activeSpecialLenses.map(lens => () =>
    agent(`以 ${lens} 視角審查 <branch> 的 diff，盡力挑出真實問題`,
      {label: `review:${lens}`, agentType: 'verifier', effort: 'xhigh', schema: FINDING_SCHEMA})),

  // 3. 核心基線：過度工程（Ponytail）必開。verifier 子進程看不到 ponytail hook，判準必須明文內嵌。
  () => agent(`以「過度工程/可簡化」視角審查 <branch> 的 diff 對照已確認的 plan：挑出計畫沒要求卻新增的抽象（單一實作的 interface、單一產品的 factory、永不變的 config、留給未來的 scaffolding、可用既有 helper/stdlib 取代的自製輪子）。每條 finding 必附刪除方案（刪哪些行、刪後 diff 是否更小、既有測試是否仍過）。絕不把信任邊界輸入驗證、防資料遺失、security、a11y 列為可簡化項。`,
    {label: 'review:過度工程', agentType: 'verifier', effort: 'xhigh', schema: FINDING_SCHEMA}),
])).filter(Boolean).flatMap(r => r.findings)

// 回到主對話：reviewer 親自收斂 findings、去重、判定真偽 → 寫審查報告 → 暫停展示（不委派）
```

> 不變式：審查報告由 reviewer（最強推論）親自產出，**不委派**。多 angle 只是提高召回率的輸入，不取代 reviewer 的最終判斷。退回 STAGE 2 的條件與層級不變。
>
> **主審兜底契約（Guard Clause Record）**：專門 Lens 未派發不等於放棄該維度。未派發專門 Lens 的維度，主 Reviewer 必須在審查報告中明載前置免除理由（如：無網路傳輸攻擊面、無跨組件共享狀態），親自覆核兜底，不得假裝該維度不存在。
>
> 「過度工程/可簡化」lens 的 finding 屬獨立類別：僅「plan 未要求的新抽象」或「刪除即嚴格更小 diff 且測試仍過」兩種情況可列 Important 並觸發退回 STAGE 2；其餘列為非阻擋建議。與 correctness/security 衝突時後者勝出。（reviewer 收斂判準詳見 `reviewer.md`。）

