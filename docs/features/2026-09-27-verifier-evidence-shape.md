# A2 · Verifier 增加「證據形狀」驗收契約規範（Verifier Evidence Shape）

> **來源**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §8.2 A2
> **狀態**：功能規格（What & Why）· 2026-09-27

---

## 1. 🔴 痛點與設計批判（Linus-Style Critique）

### 1.1 現況痛點：態度嚴格，但缺乏客觀可驗證的「證據形狀」

在 `gen-dev-workflow` 中，STAGE 2 實作完成後會委派 `verifier` agent 執行兩階段驗收（`spec compliance` → `code quality`）。現行 `verifier.md` 與 `verifier.yaml` 建立了良好的態度基調：
* 「測試失敗一律 FAIL，不得以『應該是環境問題』放行」
* 「結論二值：PASS，或 FAIL + 問題清單。不給『大致可以』」

然而，**「態度嚴格」不等於「結果可查」**。
在現行規範下，verifier 驗收時僅回報主觀判定結論，未被強制要求提供客觀、可證偽的「證物形狀」（Evidence Shape）：
1. **「Tests pass」不可證偽**：
   回報「測試全部通過」無法證明到底跑了單一測試檔案、少數檔案，還是整個 repo 的測試套件。跑 1 個測試檔通過與跑 606 個全套測試通過，在文字描述上都是「Tests pass」。
2. **靜態分析雜訊基線脫鉤**：
   `CLAUDE.md` §3 明文記載 `flutter analyze lib/ test/` 存在 **7 個既有 info** 基線。最危險的情境是：靜態分析吐出 9 個 info 時，verifier 主觀判定「看起來都是既有分析雜訊」而給予 PASS；或者既有 7 個 info 中有 2 個被修復但同時引入 2 個新 warning，總數仍為 7，但實質上引入了回歸缺陷。

### 1.2 設計原則：證據形狀（Evidence Shape）大於宣稱

> 「爛程式員宣稱測試通過，好程式員交出終端輸出與基線比對。」

* **驗收項不寫結論，寫必須交出什麼證物才算數**：
  * ❌ `Tests pass` → ✅ `以 flutter test 跑完整套，引述實際通過數（基準 606 tests）與耗時`
  * ❌ `No analyze errors` → ✅ `以 flutter analyze lib/ test/ 檢查，引述完整輸出，並逐一指認是否完全吻合 7 個既有 info`
* **關鍵在「引述」（Quotation）**：
  要求 verifier 必須在驗收報告中貼出實際執行的終端輸出片段，而非僅做二度詮釋。缺乏引述文字的報告視同未驗收。

---

## 2. 規格細節（What）

### 2.1 Verifier 兩階段驗收中的「Code Quality 證據形狀契約」

在 `verifier.md` 與 `verifier.yaml` 的「兩階段驗收」第二階段（Code Quality）中，追加明確的證據形狀交付要求：

1. **單元測試證據**：
   - 必須執行 `flutter test`。
   - 必須引述實際通過測試數，比對是否達到或超過基準（目前為 `606 tests`）。
   - 若有特定任務新增測試，必須引述新測試檔案的執行結果與通過數量。
2. **靜態分析證據**：
   - 必須執行 `flutter analyze lib/ test/`。
   - 必須完整引述終端輸出。
   - 必須對照 `CLAUDE.md` §3 的 7 個既有 info 基準：
     - 若 info 數 > 7：多出的項目一律視為新增回歸，直接判定 FAIL。
     - 若 info 數 ≤ 7：必須逐一核對是否均為已知的 7 個項目（6 個 `deprecated_member_use` + 1 個 `share_text_web.dart:15`）。若有舊 info 消失但出現新 warning/info，必須指認並判定 FAIL。
3. **拒絕無效證物**：
   - 禁止僅回傳「測試通過，analyze 無異常」等抽象摘要。
   - 未附帶命令完整輸出與數字比對者，視為未滿足驗收契約。

### 2.2 Implementer 複核契約對齊

在 `.claude/agents/implementer.md` 中，補充要求 implementer 在複核 verifier 結論時，必須親自檢查 verifier 報告中的**終端引述與數字比對**，不得盲信 PASS 結論。

---

## 3. 影響範圍（Where）

1. `.claude/agents/verifier.md`：
   更新「兩階段驗收」之 Code quality 規範與「規則」段落，加入證據形狀與引述要求。
2. `.agents/agents/verifier.yaml`：
   同步更新 `system_prompt`，保持與 `verifier.md` 一致。
3. `.claude/agents/implementer.md`：
   更新驗收複核準則，要求檢驗 verifier 附帶的實際證物。
4. `docs/brainstorm/2026-09-17-workflow-brainstorm.md`：
   同步將 §8.2 A2 標註為推進中/已對齊。

---

## 4. 驗收條件（Acceptance Criteria）

* [ ] `.claude/agents/verifier.md` 明確載入 `flutter test`（引述通過數、對照 606 基線）與 `flutter analyze`（引述完整輸出、對照 7-info 基線）的證據形狀要求。
* [ ] `.agents/agents/verifier.yaml` 的 `system_prompt` 完整同步該項契約變更。
* [ ] `.claude/agents/implementer.md` 明確註記複核 verifier 時須審查引述證物。
* [ ] 無引入多餘繁複模板，文字簡潔直指核心。
