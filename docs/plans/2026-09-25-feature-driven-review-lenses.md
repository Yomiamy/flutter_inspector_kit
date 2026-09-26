# A3 · STAGE 3 審查 Lens 規模特徵裁決規範 — 實作計畫

> **規格**：[`docs/features/2026-09-25-feature-driven-review-lenses.md`](../features/2026-09-25-feature-driven-review-lenses.md)
> **日期**：2026-09-25 ｜ **優先序**：P2 ｜ **預估 Effort**：極低（改動小、規範精確）

---

## 1. 核心判斷與設計原則 (Linus-Style Mindset)

**消滅以「行數大小」一刀切的偽安全機制，代之以「改動特徵驅動的衛語句（Guard Clause）」。**

- **拒絕無意義分工**：在不具備特定缺陷物理條件的純樣式改動上派發 5 個最高推論 Agent，是純粹的同義反覆與 Token 浪費。
- **拒絕以行數偷懶**：3 行代碼足以改壞整個認證系統或全域單例。絕不可因「行數少」而省略安全與回歸審查。
- **主審兜底契約**：專門 Lens 未派發，不代表放棄該維度。主 Reviewer（Opus）自身具備最高推論能力，必須在最終報告中記錄前置判定理由（Guard Clause Record），負全責兜底。

---

## 2. 裁決架構與資料流

```text
                           Git Diff 變更特徵掃描
                                    │
           ┌────────────────────────┴────────────────────────┐
           ▼                                                 ▼
      【核心基線 (必開)】                             【專門 Lens 條件判定】
   1. correctness (邏輯)                             • security (碰網路/認證/序列化)
   2. 過度工程 (Ponytail)                            • 回歸風險 (碰核心緩衝/生命週期/狀態)
           │                                         • 測試覆蓋 (新增邏輯/分支)
           │                                                 │
           └────────────────────────┬────────────────────────┘
                                    ▼
                         動態組裝 LENSES 陣列
                                    │
                       Workflow parallel fan-out
                     (每個選定 Lens 派發 verifier)
                                    │
                                    ▼
                         主 Reviewer 親自收斂
                                    │
                 ┌──────────────────┴──────────────────┐
                 ▼                                     ▼
        彙整子 Agent findings                 覆核未派發維度並記錄
                                              前置判定理由 (Guard Clause)
                                                       │
                                                       ▼
                                             完整審查報告輸出
```

---

## 3. 檔案異動清單

| # | 檔案 | 動作 | 說明 |
|:-:|:---|:---|:---|
| 1 | `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` | 修改 | 更新適用點 3：重構多 angle 審查規格，替換原固定陣列為特徵驅動過濾範例代碼，明訂特徵判準 |
| 2 | `.claude/agents/reviewer.md` | 修改 | 增補 Reviewer 工作原則：載明未派發 Lens 時的兜底義務與審查報告中的免除判定紀錄（Guard Clause Record） |
| 3 | `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新 §8.2 A3 段落：由純行數一刀切修正為特徵驅動裁決，記錄批判與實作結論，標記為完成 |

---

## 4. 任務拆分與執行規劃

### Task 1: 更新 `workflow-parallel.md` 適用點 3 規格
- **檔案**：`.claude/skills/gen-dev-workflow/references/workflow-parallel.md`
- **實作內容**：
  1. 重寫「適用點 3：STAGE 3 多 angle 對抗式審查」章節。
  2. 刪除原固定 `['correctness', 'security', '回歸風險', '測試覆蓋']` 寫死陣列。
  3. 引入特徵判準矩陣：
     - 基線：`correctness` + `過度工程` 永遠啟用。
     - `security`：更動網路、Dio/HTTP、認證 Token、序列化、敏感資料、條件匯出時啟用。
     - `回歸風險`：更動全域狀態、生命週期、核心緩衝區（`RingBuffer` / `mergedTimeline`）、公共 API 簽章時啟用。
     - `測試覆蓋`：新增邏輯或分支、重構核心路徑或修復特定 Bug 時啟用；純文檔/樣式微調跳過。
  4. 提供 JavaScript 動態過濾與派發之範例代碼。

### Task 2: 更新 `.claude/agents/reviewer.md` 職責與兜底契約
- **檔案**：`.claude/agents/reviewer.md`
- **實作內容**：
  1. 在「職責」增補：對未派發專門 Lens 的維度進行覆核兜底。
  2. 在「工作原則」增補第 4 點：**特徵免除判定紀錄（Guard Clause Record）**：
     - 若審查未派發某專門 Lens，Reviewer 必須在最終報告中簡要標註前置免除理由（如無外部攻擊面、無跨組件共享狀態）。

### Task 3: 更新 `docs/brainstorm/2026-09-17-workflow-brainstorm.md` §8.2 A3 內容
- **檔案**：`docs/brainstorm/2026-09-17-workflow-brainstorm.md`
- **實作內容**：
  1. 更新 line 2522 附近之 A3 標題與內文，說明為何捨棄「diff < 200 行一刀切」，改採「變更特徵驅動」。
  2. 同步更新 line 2561 的建議動工順序表（A3 標記為 ✅ 已完成）。

### Task 4: 交叉核對與驗證
- **實作內容**：
  1. 確認各檔案間術語統一（`correctness`, `security`, `回歸風險`, `測試覆蓋`, `過度工程`）。
  2. 檢查 markdown 格式與連結有效性。

---

## 5. 驗證方式

1. 檢查 `workflow-parallel.md`，確認其 JavaScript 範例代碼語意清晰、無語法漏洞。
2. 檢查 `reviewer.md`，確認主審職責與報告格式契約明確。
3. 檢查 `workflow-brainstorm.md`，確認 A3 描述已正確更新且無狀態漂移。
