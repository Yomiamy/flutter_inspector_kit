# 實作計畫：B5 effort 分層表機制修正（確認 Frontmatter 覆蓋機制）

- **日期**：2026-10-01
- **狀態**：STAGE 0b — 待確認
- **規格參考**：[`docs/features/2026-10-01-align-model-tiers-remove-effort.md`](../features/2026-10-01-align-model-tiers-remove-effort.md)
- **模式**：Sequence（Batch Item 2）

---

## 1. 摘要與架構設計

### 背景
先前曾計畫移除各 Agent frontmatter 中的 `effort`，並交由主 session 全域繼承。然而實務上，為確保 `planner`、`reviewer` 等核心環節擁有足夠推論深度，我們已在 frontmatter 中明確加回了 `effort: xhigh` 與 `effort: max` 的設定。舊有的文件與此實務現況存在矛盾，被 CodeRabbit 於 PR #189 中指出。

### 核心改動
- 更新相關文件，確立**各 Agent frontmatter 的 `effort` 設定為權威，且會自動覆蓋主 session 的 effort 設定**。
- 修正 `delegation-and-parallel.md` 的「推論等級表」，明確標示各等級對應的 `model` 與 `effort` 設定。
- 清理 `workflow-parallel.md` 中宣稱「effort 繼承 session」的註解，改為「依 frontmatter 覆蓋」。
- 回寫 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`，記錄 B5 的最終決策（採用 frontmatter 覆蓋機制）已完成。

---

## 2. 檔案異動清單

| 檔案 | 變更性質 | 說明 |
|---|---|---|
| `.claude/skills/gen-dev-workflow/references/delegation-and-parallel.md` | 修改 | 推論等級表保留並更新 effort 欄位；內文確立 frontmatter effort 覆蓋 session 的機制 |
| `.claude/skills/gen-dev-workflow/references/workflow-parallel.md` | 修改 | 更新範例程式碼中的註解，指明 effort 依 frontmatter 設定覆蓋 |
| `docs/features/2026-10-01-align-model-tiers-remove-effort.md` | 修改 | 修正規格書，將目標從「移除 effort」改為「確認 frontmatter 覆蓋機制」 |
| `docs/plans/2026-10-01-align-model-tiers-remove-effort.md` | 修改 | 修正實作計畫，對齊 CodeRabbit 審查意見 |
| `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新 B5 條目與 §8.5 表格，標記為已修正並說明決策 |

---

## 3. 具體任務拆分 (Tasks)

### Task 1: 修正 `delegation-and-parallel.md`（確立 Frontmatter 覆蓋）
- **操作**：
  1. 將「推論等級表」更新為包含 `model` 與 `effort` 綁定的表格。
  2. 內文確立單一事實：各 Agent 依其職責於 frontmatter 綁定 `model` 與 `effort`，啟動時優先採用 frontmatter 設定以覆蓋 session。
- **驗收**：表格與內文真實反映 codebase 中的設定。

### Task 2: 修正 `workflow-parallel.md` 註解
- **操作**：
  1. 在範例代碼中，將「effort 繼承主對話 session」的說法修正為「effort 依 frontmatter 設定覆蓋 session」。
- **驗收**：代碼註解正確傳達覆蓋機制。

### Task 3: 修正 Feature 與 Plan 文件
- **操作**：
  1. 改寫 `docs/features/2026-10-01-align-model-tiers-remove-effort.md`，將目標修正為確認 frontmatter 覆蓋機制。
  2. 改寫本計畫文件。
- **驗收**：文件不再自相矛盾。

### Task 4: 更新 Brainstorm 文件追蹤狀態
- **操作**：
  1. 更新 B5 條目：說明最終決策為保留並規範 frontmatter 的 effort 覆蓋機制。
  2. 更新 §8.5 建議動工順序表。
- **驗收**：記錄與 PR #189 討論結果一致。

---

## 4. 風險評估與防禦

- **向後相容性（Never break userspace）**：
  - 各 Agent frontmatter 的 `model:` 與 `effort:` 綁定維持 codebase 現況不變。
  - 此改動是將文件與實況對齊，確保開發者不會對 effort 的生效機制產生誤解。
