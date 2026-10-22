# D3 · Verifier 驗收契約標準化為三態（CONFIRMED / REFUTED / INCONCLUSIVE）— 實作計畫

> **規格**：[`docs/features/2026-10-23-verifier-three-state-contract.md`](../features/2026-10-23-verifier-three-state-contract.md)
> **日期**：2026-10-23 ｜ **優先序**：P2 ｜ **預估 Effort**：低（規格清晰、純規則與契約更新、零核心業務程式碼改動）

---

## 1. 核心判斷與設計原則 (Linus-Style Mindset)

**消滅假二值，確立不可變的反駁角色。**

* **誠實反映第三態（Good Taste）**：
  軟體驗收不是非黑即白。當指令逾時、環境晃動或依賴缺失時，現行二值制會逼迫 Verifier 說謊（猜 PASS 或盲目打回 FAIL）。引進 `INCONCLUSIVE` 承認「當下客觀資訊不足以證實或反駁」，並透過主流程自動同 tier 重試 1 次機制，消滅偶發性環境假警報。
* **第一行頂格輸出，消除橡皮圖章**：
  報告首行必須直接以 `CONFIRMED`、`REFUTED` 或 `INCONCLUSIVE` 開頭，後續段落再展開證據。杜絕散文報告中把結論藏在長篇大論裡的模糊空間。
* **不可變的角色分工（Never break boundaries）**：
  Verifier 的天職是「驗證與反駁」，嚴禁動手改代碼。維持 `.agents/agents/verifier.yaml` 的 `enable_write_tools: false`，避免驗收端球員兼裁判。

---

## 2. 驗收契約與資料流向

```text
       Implementer 完成實作任務
                 │
                 ▼
       委派 Verifier 執行兩階段驗收
                 │
                 ▼
   ┌─────────────────────────────────────────────────────────────┐
   │ Verifier 三態驗收報告（首行必須頂格輸出狀態）                  │
   │                                                             │
   │ 🟢 CONFIRMED                                                │
   │    • 規格逐項符合，無多餘依賴/過度工程抽象                  │
   │    • 引述 flutter test（基準 ≥606 tests 全綠）             │
   │    • 引述 flutter analyze（嚴格符合 7-info 基線）           │
   │                                                             │
   │ 🔴 REFUTED: <簡述>                                          │
   │    • 測試失敗 / analyze 報錯 / 規格偏離                     │
   │    • 附帶具體反駁證據（出錯位置、複現情境、報錯文字）        │
   │                                                             │
   │ 🟡 INCONCLUSIVE: <簡述>                                     │
   │    • 環境異常 / 命令逾時 / 依賴未就緒                       │
   │    • 說明無法斷定的客觀受阻原因                             │
   └──────────────────────────────┬──────────────────────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
     CONFIRMED                 REFUTED                INCONCLUSIVE
   推進下個任務             打回實作端修正          同 tier 自動重試 1 次
                                                 （仍未定則暫停問人）
```

---

## 3. 檔案異動清單

| # | 檔案 | 動作 | 說明 |
|:-:|:---|:---|:---|
| 1 | `.claude/agents/verifier.md` | 修改 | 將二值規則改寫為三態契約，完整載明 `CONFIRMED / REFUTED / INCONCLUSIVE` 各自代表的意義、觸發標準與首行格式規範；明訂嚴禁修改代碼 |
| 2 | `.agents/agents/verifier.yaml` | 修改 | 同步更新 `system_prompt`，保持與 `verifier.md` 規則一致，維持 `enable_write_tools: false` |
| 3 | `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改 | 在 STAGE 2 實作驗收章節增補三態契約要求，並明載主流程收到 `INCONCLUSIVE` 時的重試機制 |
| 4 | `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 | STAGE 2 流程說明中補註三態驗收契約 |
| 5 | `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新第七部分 §3.3 與 §5 表格之 D3 狀態為已完成 |

---

## 4. 任務拆分與執行規劃

### Task 1: 更新 Verifier Agent 定義（.claude/agents/verifier.md 與 .agents/agents/verifier.yaml）
- **實作內容**：
  1. 將原本的規則「結論二值：PASS，或 FAIL + 問題清單」改為三態契約：
     - 首行頂格格式：`CONFIRMED` / `REFUTED: <簡述>` / `INCONCLUSIVE: <簡述>`。
     - 完整解釋三態的語意與判定標準：
       - `CONFIRMED`：規格完全滿足、測試全綠（引述實際通過數 ≥606）、靜態分析無新增警告/錯誤（吻合 7-info 基線）。
       - `REFUTED`：測試失敗、analyze 出錯、規格偏離或存在過度工程；必須附帶具體反駁證據。
       - `INCONCLUSIVE`：環境受阻、指令逾時、資訊不足以斷定對錯；說明受阻原因。
     - 明訂硬性紀律：「只驗收、不修代碼，嚴禁修改任何業務與測試檔案」。
  2. 同步更新 `.agents/agents/verifier.yaml` 的 `system_prompt`。

### Task 2: 更新工作流編排指引（delegation-and-parallel.md 與 SKILL.md）
- **實作內容**：
  1. 在 `references/delegation-and-parallel.md` 的「STAGE 2 實作」與「兩階段驗收」段落：
     - 加入三態契約要求，說明 Verifier 首行輸出之解析。
     - 明載主調度進程對 `INCONCLUSIVE` 的處理邏輯：自動原樣（同 tier）重試 1 次；若重試後依然未定，立即暫停流程向人類開發者求助。
  2. 在 `SKILL.md` STAGE 2 流程圖中標註三態驗收契約。

### Task 3: 同步更新頭腦風暴文件（docs/brainstorm/2026-09-17-workflow-brainstorm.md）
- **實作內容**：
  - 在第七部分 §3.3 標題更新為 `✅ 已完成`。
  - 在第七部分 §5 建議借鏡表將 D3 狀態更新為 `✅ 已完成`，並同步附註。

### Task 4: 完整驗證
- **驗證命令**：
  1. `git diff` 審查所有文件修改，確保無語法損壞或誤傷。
  2. 執行 `flutter test`，確認既有 606 tests 全數通過。
  3. 執行 `flutter analyze lib/ test/`，確認吻合 7 個既有 info 基線。
