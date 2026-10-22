# D3 · Verifier 驗收契約標準化為三態（CONFIRMED / REFUTED / INCONCLUSIVE）

> **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` 第七部分 §3.3 與 §5 建議借鏡表（D3）
> **狀態**：功能規格（What & Why）· 2026-10-23
> **借鏡來源**：Nanako0129 / pilotfish 微觀派發策略體系（https://github.com/Nanako0129/pilotfish）

---

## 1. 🔴 痛點與設計批判（Linus-Style Critique）

### 1.1 現況痛點：二值契約的假象與結論模糊

在 `gen-dev-workflow` 中，STAGE 2 實作完成後會委派獨立的 `verifier` agent 執行兩階段驗收（`spec compliance` → `code quality`），且 STAGE 3 的多 angle 審查亦包含平行 verifier。現行 `.claude/agents/verifier.md:35` 規定：

> 「結論二值：PASS，或 FAIL + 問題清單。不給『大致可以』。」

這看似斯巴達式嚴格，實務上卻存在兩個根本性的結構缺陷：

1. **二值狀態無法誠實反映「環境中斷與資訊不足」**：
   當驗收過程中發生命令逾時（Timeout）、本機 pub 快取鎖死、Flutter SDK 工具鏈瞬態異常，或是依賴前置外部資源而無法完整跑完測試時，現行二值制會逼迫 Verifier 做出虛假裁決：
   - **逼出假 PASS**：「雖然測試中途逾時，但看代碼應該沒問題」→ 漏放嚴重回歸缺陷；
   - **或誤判 FAIL**：將暫時性的環境抖動歸咎於實作代碼錯誤，打回實作端無效重做。
   真實的軟體工程驗證存在第三態——**客觀條件不足以證實或反駁**。缺乏第三態，就是逼模型說謊。

2. **長篇 Markdown 散文導致結論模糊（Rubber Stamp 橡皮圖章）**：
   Verifier 產出長篇分析報告時，最終結論常隱含在段落深處或註腳中。主調度進程（Orchestrator）或人類審查者必須依賴自然語言語意解析才能提取判定，極易產生心證誤判或隨手放行。

3. **「球員兼裁判」的越權風險**：
   Verifier 的唯一使命是對抗式驗收（嘗試反駁實作）。若 Verifier 具備寫檔或順手修正的權限與心態，驗收者就會退化成第二個實作端，失去獨立把關強度。

---

## 2. 規格細節（What & Why）

### 2.1 三態契約的嚴格定義與解釋意義

規範 Verifier 報告的**第 1 行必須嚴格頂格輸出三態標籤之一**（不可有額外前綴或包裹符），各狀態代表的具體含義與觸發條件如下：

#### 🟢 1. `CONFIRMED`（證實 · 驗收合格）
* **核心定義**：Verifier 盡力挑刺後，**確認實作完全符合規格，且所有客觀證據皆成立**。
* **觸發條件**：
  * **Spec compliance**：逐項核對實作計畫與規格驗收條件，全部明確滿足，且無任何計畫外加料（無多餘依賴、無過度工程抽象）。
  * **Code quality**：`flutter test` 跑完整套測試並引述實際通過數（達到或超過既有基準，如 606 tests）；`flutter analyze lib/ test/` 完整引述輸出，且嚴格吻合既有 7 個 info 基準，無新增 warning 或 error。
* **主流程行為**：判定任務合格，記錄狀態並推進至下一個任務。

#### 🔴 2. `REFUTED`（反駁 · 發現缺陷）
* **核心定義**：Verifier 成功找到破綻，**證明該實作存在缺陷、未達標或存在回歸風險**。
* **觸發條件**：
  * **測試失敗**：單元測試、widget 測試或整合測試出現 failure 或 exception。
  * **靜態分析回歸**：出現任何新增 info（>7）、warning、error，或命令返回非零狀態。
  * **規格偏離**：存在規格缺漏、邏輯邊界未防守、或引入計畫未要求的複雜抽象與外部依賴。
  * **必須附帶反駁證據**：報告中必須指出具體出錯位置、複現情境與終端報錯內容。
* **主流程行為**：判定驗收不通過，將反駁證據與問題清單打回給實作端（implementer）修正，不推進流程。

#### 🟡 3. `INCONCLUSIVE`（未定 · 環境或資訊不足）
* **核心定義**：**並非代碼有 Bug，而是當下客觀條件無法做出「對」或「錯」的確定性判斷**。
* **觸發條件**：
  * **基礎設施或環境異常**：本地套件快取異常、模擬器崩潰、記憶體耗盡等非代碼因素。
  * **命令執行逾時**：測試指令因外力中斷或超時，未能完整跑完。
  * **資訊或依賴缺失**：驗收所需的外部資源尚未就緒，使得 Verifier 既無法證實它正確、也無法提出具體反駁證據。
* **主流程行為**：
  * 主流程判定為非代碼缺陷，自動原樣（同 tier）重試 1 次。
  * 若重試後依然為 `INCONCLUSIVE`，則立即暫停流程，主動提示人類開發者排除環境問題，絕不強行放行。

---

### 2.2 報告格式契約

Verifier 產出的報告必須遵循以下結構：

```markdown
CONFIRMED (或 REFUTED: <簡述> / INCONCLUSIVE: <簡述>)

## 1. 兩階段驗收結果摘要
- Spec Compliance: 符合 / 偏離
- Code Quality: 測試通過 (引述數字) / 靜態分析合格 (引述基線)

## 2. 實證引述 (Evidence Quotation)
- flutter test 輸出片段
- flutter analyze 輸出片段

## 3. 具體問題與反駁 (僅在 REFUTED 或 INCONCLUSIVE 時)
- 問題描述、位置、嚴重度與建議 (或環境受阻具體原因)
```

---

### 2.3 嚴格禁止修改代碼（Immutable Role）

* Verifier **嚴禁修改任何業務代碼與測試代碼**。
* 工具層約束：`.agents/agents/verifier.yaml` 維持 `enable_write_tools: false`，僅保留唯讀與執行測試權限（`Bash, Read, Glob, Grep`）。
* 職責邊界：Verifier 的工作是「驗證與反駁」，修正代碼的責任完全歸屬於 implementer。

---

## 3. 適用範圍與邊界（Scope）

1. **適用範圍**：
   - STAGE 2 實作完成後，逐任務由主流程委派的獨立 `verifier` subagent。
   - STAGE 3 多 angle 對抗審查中，由 Claude Workflow 或序列派發的平行 verifier。
2. **不變的既有規則**：
   - 兩階段驗收流程不變（`Spec compliance` → `Code quality`）。
   - 證據形狀（Evidence Shape）硬性引述契約不變（必須引述終端實際輸出與 606 測試基準）。
   - STAGE 2 派發煞車規則不變：微任務（單檔 ≤ 20 行且無公共 API 變更）仍由主進程原地測驗，不派發 verifier。

---

## 4. 影響範圍檔案（Where）

1. [`.claude/agents/verifier.md`](file:///Users/yomiry/StudioWorkspace/flutter_inspector/.claude/agents/verifier.md)：
   - 將二值規則改寫為三態契約定義，明確記錄 `CONFIRMED / REFUTED / INCONCLUSIVE` 的意圖、判定準則與首行輸出格式。
2. [`.agents/agents/verifier.yaml`](file:///Users/yomiry/StudioWorkspace/flutter_inspector/.agents/agents/verifier.yaml)：
   - 同步更新 `system_prompt`，與 `verifier.md` 保持完全一致。
3. [`.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`](file:///Users/yomiry/StudioWorkspace/flutter_inspector/.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md)：
   - 更新 STAGE 2 驗收契約章節，載明三態契約標準與主流程對 `INCONCLUSIVE` 的重試機制。
4. [`.claude/skills/gen-dev-workflow/SKILL.md`](file:///Users/yomiry/StudioWorkspace/flutter_inspector/.claude/skills/gen-dev-workflow/SKILL.md)：
   - STAGE 2 實作章節註記三態驗收契約。
5. [`docs/brainstorm/2026-09-17-workflow-brainstorm.md`](file:///Users/yomiry/StudioWorkspace/flutter_inspector/docs/brainstorm/2026-09-17-workflow-brainstorm.md)：
   - 將第七部分 §3.3 與 §5 建議借鏡表之 D3 項目狀態同步更新。
