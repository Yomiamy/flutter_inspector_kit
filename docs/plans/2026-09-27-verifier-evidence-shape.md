# A2 · Verifier 增加「證據形狀」驗收契約規範 — 實作計畫

> **規格**：[`docs/features/2026-09-27-verifier-evidence-shape.md`](../features/2026-09-27-verifier-evidence-shape.md)
> **日期**：2026-09-27 ｜ **優先序**：P2 ｜ **預估 Effort**：極低（規則精確、檔案少、不改核心代碼）

---

## 1. 核心判斷與設計原則 (Linus-Style Mindset)

**驗收項不寫結論，寫必須交出什麼證物才算數。**

* **消滅主觀模糊（Good Taste）**：
  「測試通過」是一句不可證偽的廢話（跑 1 個檔或跑 606 個檔都叫通過）。唯有要求**引述實際命令輸出**並核對明確基準數字，做沒做才一眼可辨。
* **鎖定靜態分析 7-info 基線**：
  `CLAUDE.md` §3 明文界定目前有 7 個既有 info（6 個 deprecated_member_use + 1 個 share_text_web.dart:15）。verifier 必須完整引述終端輸出並對照清單。多出第 8 個直接判定 FAIL，總數 ≤ 7 時也必須確認是既有的 7 個，防止新警告被舊修正掩蓋。
* **簡潔不冗長（YAGNI）**：
  改法僅在 verifier 與 implementer 的契約中加入明確的證物形狀要求（約 4–6 行），不抄上游冗長的 Rationalizations / Red Flags 三件套。

---

## 2. 驗收契約與資料流向

```text
       Implementer 完成實作任務
                 │
                 ▼
       委派 Verifier 執行兩階段驗收
                 │
                 ▼
   ┌───────────────────────────────────────────────┐
   │ Verifier 兩階段驗收契約                        │
   │                                               │
   │ 1. Spec compliance：                          │
   │    • 逐條對照任務規格與驗收條件               │
   │    • 揪出計畫外加料（抽象/依賴/防禦分支）     │
   │                                               │
   │ 2. Code quality【本次增訂證據形狀】：         │
   │    • 執行 `flutter test`，引述通過數 (基準 606)│
   │    • 執行 `flutter analyze lib/ test/`，      │
   │      完整引述輸出，核對 7-info 基線           │
   │    • 引述實際終端輸出，禁止僅給抽象摘要       │
   └──────────────────────┬────────────────────────┘
                          │ 產出附帶真實引述之報告
                          ▼
           Implementer 複核驗收報告
         （核對終端引述文字與數字是否真實）
                          │
            ┌─────────────┴─────────────┐
            ▼                           ▼
          PASS                        FAIL
       推進下個任務               退回子進程修正
```

---

## 3. 檔案異動清單

| # | 檔案 | 動作 | 說明 |
|:-:|:---|:---|:---|
| 1 | `.claude/agents/verifier.md` | 修改 | 在「兩階段驗收」Code quality 與「規則」段落增補證據形狀：要求引述 `flutter test`（核對 606 tests）與 `flutter analyze lib/ test/`（核對 7-info 基線） |
| 2 | `.agents/agents/verifier.yaml` | 修改 | 同步更新 `system_prompt`，保持與 `verifier.md` 規則一致 |
| 3 | `.claude/agents/implementer.md` | 修改 | 在驗收複核原則中載明：Implementer 必須核對 verifier 回報中的終端引述與基準數字，未附證物視同無效 |
| 4 | `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新 §8.2 A2 段落狀態為已完成，同步更新建議動工順序表（A2 標註 ✅ 已完成） |

---

## 4. 任務拆分與執行規劃

### Task 1: 更新 Verifier Agent 定義檔
- **目標檔案**：
  - `.claude/agents/verifier.md`
  - `.agents/agents/verifier.yaml`
- **實作內容**：
  1. 在 `## 兩階段驗收 (Two-Stage Verification)` 的第 2 點 `Code quality` 增訂具體證物交付規範：
     - **測試證據**：必須以 `flutter test` 跑完整套，引述實際通過數（基準 606 tests）與耗時；若有特定任務新增測試檔案，亦須一併引述該測試檔案的執行結果與通過數量。
     - **靜態分析證據**：以 `flutter analyze lib/ test/` 檢查並引述完整終端輸出；嚴格對照 `CLAUDE.md` §3 的 7 個既有 info，多於 7 個直接判 FAIL，≤ 7 個需指認完全符合既有清單，任何新增 warning/error 或非零 exit status 均直接判 FAIL。
  2. 在 `## 規則 (Rules)` 增補：
     - 報告中必須附帶命令之實際輸出引述，未附帶證物或僅給予抽象總結者一律視為無效驗收。

### Task 2: 更新 Implementer Agent 複核契約
- **目標檔案**：
  - `.claude/agents/implementer.md`
- **實作內容**：
  1. 在「驗收」與「回報不等於事實」工作原則段落中，補充要求 Implementer 複核 Verifier 報告時，必須親自檢查 Verifier 是否如實引述終端輸出與基準數字（606 tests, 7-info baseline）。

### Task 3: 更新 Brainstorm 文件追蹤狀態
- **目標檔案**：
  - `docs/brainstorm/2026-09-17-workflow-brainstorm.md`
- **實作內容**：
  1. 將 §8.2 標題 `##### 🟢 A2. verifier 加「證據形狀」（P2）` 更新為 `##### 🟢 A2. verifier 加「證據形狀」（P2）— ✅ 已完成（2026-09-27）`。
  2. 更新 §8.5 建議動工順序表中的 A2 狀態為 `✅ 已完成（2026-09-27）`。

### Task 4: 驗證與基準回歸檢查
- **執行驗證**：
  1. 執行 `flutter test`，確認全套 606 tests 通過。
  2. 執行 `flutter analyze lib/ test/`，確認既有 7 個 info 保持不變。
  3. 檢視修改的 agent 文件與 markdown 文件格式。

---

## 5. 驗證方式

1. 檢查 `.claude/agents/verifier.md` 與 `.agents/agents/verifier.yaml` 的改動，確認內容對齊且無語法錯誤。
2. 檢查 `.claude/agents/implementer.md`，確認責任邊界清晰。
3. 執行 `flutter test` 與 `flutter analyze lib/ test/` 確認 codebase 本身未受任何負面影響。
