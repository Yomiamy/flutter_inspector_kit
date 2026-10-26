# D3 · Verifier 階層式驗收契約（PASS / FAIL: CODE / FAIL: INFRA）

> **來源**：`docs/brainstorm/2026-10-25-workflow-brainstorm.md` 第七部分 §3.3 與 §5 建議借鏡表（D3）
> **狀態**：功能規格（What & Why）· 2026-10-23（2026-10-27 重構優化）
> **借鏡來源**：Nanako0129 / pilotfish 微觀派發策略體系（https://github.com/Nanako0129/pilotfish）與 HTTP 狀態碼架構

---

## 1. 🔴 痛點與設計批判（Linus-Style Critique）

### 1.1 現況痛點：二值契約的假象、學術名詞的晦澀與狀態爆炸

在 `gen-dev-workflow` 中，STAGE 2 實作完成後會委派獨立的 `verifier` agent 執行兩階段驗收（`spec compliance` → `code quality`），且 STAGE 3 的多 angle 審查亦包含平行 verifier。現行架構存在以下核心缺陷：

1. **二值契約的制度性困境（逼良為娼）**：
   原有的純二值制（PASS / FAIL）只有兩條下游路由：PASS 往前走，FAIL 打回給實作端改代碼。
   當遇到命令逾時（Timeout）、本機 pub 快取鎖死或 Flutter SDK 工具鏈抖動等非代碼因素時，Verifier 被逼入囚徒困境：
   - **若判 FAIL**：環境異常被當成代碼錯誤打回，實作端開始胡亂修改根本沒錯的業務邏輯，引發代碼退化；
   - **若為了避免冤枉實作端**：全系統缺乏合法的例外通道，逼出假 PASS（「雖然逾時，但看代碼應該沒問題」）。

2. **學術名詞的晦澀與扁平狀態爆炸（Flat State Explosion）**：
   若採用科學假說驗證名詞（`CONFIRMED` / `REFUTED` / `INCONCLUSIVE`）：
   - **違背工程直覺**：開發者第一眼無法分辨「到底算成功還是失敗？能 Merge 嗎？」；`INCONCLUSIVE` 在流程上本質就是「沒通過」，模稜兩可的名詞徒增心智負擔。
   - **狀態爆炸風險**：扁平列舉無法應對真實工程複雜度。若未來出現規格矛盾、前置依賴未就緒或設定錯誤，難道要一路追加第四態、第五態（如 `INVALID_SPEC`、`BLOCKED`、`UNAUTHORIZED`）？這會徹底拖垮調度器。

3. **「長篇散文」與「空口無憑」的橡皮圖章（Rubber Stamp）**：
   若 Verifier 僅在長篇 Markdown 結尾寫下主觀結論，而缺乏客觀證據的硬約束，主調度進程（Orchestrator）或人類審查者極易漏看缺陷。

4. **「球員兼裁判」的越權風險**：
   Verifier 的唯一使命是對抗式驗收（嘗試反駁實作）。若 Verifier 具備寫檔或順手修正的權限，驗收者就會退化成第二個實作端，失去獨立把關強度。

---

## 2. 規格細節（What & Why）

### 2.1 階層式契約：對齊 HTTP 狀態碼心智模型

將驗收契約重構成兩層結構：
* **第一層（Gate 閘門）**：眼球 0.01 秒即可辨識的二值結果 —— **`PASS`** vs **`FAIL`**。
* **第二層（Category 處置路由）**：以冒號標籤對齊 HTTP 狀態碼責任模型（2xx / 4xx / 5xx）：

| 狀態輸出 | 等同 HTTP | 狀態意義 (Meaning) | 觸發與判定標準 (Trigger & Criteria) | 後續處理 (Action) |
|---|---|---|---|---|
| **`PASS`** | `200 OK` | **驗收確認通過**<br>實作成果經客觀檢驗完全符合預期。 | 1. **規格逐項吻合**：逐條核對 Spec 與 Plan 之驗收條件，無遺漏或偏離，且無未經計畫的過度工程抽象與多餘依賴。<br>2. **測試全數通過**：執行 `flutter test`，引述終端實際通過數（基準 ≥606 tests 全綠）與執行耗時。<br>3. **靜態分析合規**：執行 `flutter analyze lib/ test/`，終端完整輸出嚴格符合 7 個既有 info 基準，無新增 warning 或 error。 | 推進至下一個任務，或完成階段驗收。 |
| **`FAIL: CODE`** | `4xx Client Error` | **實作缺陷（代碼問題）**<br>實作端責任：代碼存在瑕疵、規格不符或品質不達標。 | 1. **規格偏離**：未滿足驗收條件，或存在多餘抽象、未授權相依、不符設計哲學的邏輯。<br>2. **測試失敗**：`flutter test` 出現任何 failure、error 或因代碼錯誤導致非零退出。<br>3. **靜態分析不合規**：`flutter analyze` 出現新增 info、warning、error，或由代碼變更導致非零退出。<br>4. **反駁證據**：首行必須為 `FAIL: CODE: <簡述>`，並在內文列出結構化反駁證據（出錯位置、複現情境、終端報錯文字、修復建議）。 | **打回 Implementer**，依反駁證據修復代碼後重新提請驗收。 |
| **`FAIL: INFRA`** | `5xx Server Error` | **環境故障（非代碼問題）**<br>基礎設施責任：因客觀阻礙無法產出完整測試結果。 | 1. **環境異常**：非代碼引起的網路抖動、相依服務不可用、CI 或沙箱資源短缺。<br>2. **指令逾時**：測試或構建指令因環境鎖死或資源搶佔逾時，無法產出完整終端結果。<br>3. **前置未就緒**：依賴的前置產物或外部系統未就緒，導致無法執行驗收驗證步驟。<br>4. **受阻說明**：首行必須為 `FAIL: INFRA: <簡述>`，並在內文詳述無法斷定的客觀受阻原因與終端輸出。 | **同 tier 自動重試 1 次**；若重試後依然失敗，立即暫停流程向人類開發者求助，**嚴禁打回改代碼**。 |
| *(未來擴展)* **`FAIL: BLOCKED`** | `424 Failed Dep` | **相依受阻**<br>前置任務或外部資源未滿足。 | 任務拓撲依賴尚未就緒。 | 由調度器重新排程或等待相依單元。 |

### 2.2 杜絕假 PASS 的真實機制：客觀證據形狀（Evidence Shape）硬契約

狀態分類消滅了系統逼迫模型說謊的制度動機，而**真正杜絕假 PASS 的是證據形狀的機械式校驗**：
* `PASS` **絕非主觀心證**，它的充要條件是**必須引述實際終端輸出**，且明確標出通過數字（例如 `All 606 tests passed!`）與靜態分析 7-info 基線。
* **無證據即違約**：任何僅寫下「看代碼應該沒問題」而缺乏終端 exit 0 證物引述的 `PASS` 報告，主調度進程與審查者一律判定為**契約違規（Contract Violation）**，直接作廢打回。

---

### 2.3 報告格式契約

Verifier 產出的報告第一行必須頂格輸出狀態前綴，結構如下：

```markdown
PASS

## 1. 兩階段驗收結果摘要
- Spec Compliance: 符合 / 偏離
- Code Quality: 測試通過 (引述數字) / 靜態分析合格 (引述基線)

## 2. 實證引述 (Evidence Quotation)
- flutter test 輸出片段
- flutter analyze 輸出片段

## 3. 具體問題與反駁 (僅在 FAIL: CODE 或 FAIL: INFRA 時)
- 問題描述、位置、嚴重度與建議 (或環境受阻具體原因)
```

若驗收未通過，首行改為 `FAIL: CODE: <簡述>` 或 `FAIL: INFRA: <簡述>`。

---

### 2.4 嚴格禁止修改代碼（Immutable Role）

* Verifier **嚴禁修改任何業務代碼與測試代碼**。
* 工具層約束：`.agents/agents/verifier.yaml` 維持 `enable_write_tools: false`，僅保留唯讀與執行測試權限（`Bash, Read, Glob, Grep`）。
* 職責邊界：Verifier 的工作是「驗證與反駁」，修正代碼的責任完全歸屬於 implementer。

---

## 3. 適用範圍與邊界（Scope）

1. **適用範圍**：
   - **STAGE 2 任務驗收（核心適用）**：實作完成後，逐任務委派獨立 `verifier` 執行兩階段驗收，首行輸出階層式狀態（`PASS` / `FAIL: CODE` / `FAIL: INFRA`）。
   - **STAGE 3 多 Angle 審查相容**：當 STAGE 3 委派 verifier 作為特定 lens 審查時，若指定了 `schema: FINDING_SCHEMA`，則依 schema 回傳結構化 findings；若該 lens 因環境異常（如逾時）受阻，回報包含環境受阻說明的 finding，供 Reviewer 識別並處理，絕不把環境中斷誤判為零缺陷通過。
2. **不變的既有規則**：
   - 兩階段驗收流程不變（`Spec compliance` → `Code quality`）。
   - 證據形狀（Evidence Shape）硬性引述契約不變（必須引述終端實際輸出與 606 測試基準）。
   - STAGE 2 派發煞車規則不變：微任務（單檔 ≤ 20 行且無公共 API 變更）仍由主進程原地測驗，不派發 verifier。

---

## 4. 影響範圍檔案（Where）

1. [`.claude/agents/verifier.md`](../../.claude/agents/verifier.md)：
   - 將二值規則改寫為階層式契約定義，明確記錄 `PASS / FAIL: CODE / FAIL: INFRA` 的意圖、判定準則與首行輸出格式。
2. [`.agents/agents/verifier.yaml`](../../.agents/agents/verifier.yaml)：
   - 同步更新 `system_prompt`，與 `verifier.md` 保持完全一致。
3. [`.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md`](../../.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md)：
   - 更新 STAGE 2 驗收契約章節，載明階層式契約標準與主流程對 `FAIL: INFRA` 的重試機制。
4. [`.claude/skills/gen-dev-workflow/SKILL.md`](../../.claude/skills/gen-dev-workflow/SKILL.md)：
   - STAGE 2 實作章節註記階層式驗收契約。
5. [`docs/brainstorm/2026-10-25-workflow-brainstorm.md`](../brainstorm/2026-10-25-workflow-brainstorm.md)：
   - 將第七部分 §3.3 與 §5 建議借鏡表之 D3 項目狀態同步更新。
