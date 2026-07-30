# 功能規格：修復 promote 後 stage-done 1 恆遭拒（STAGE 1 happy path 斷裂）

- **日期**：2026-07-30
- **狀態**：STAGE 0a — 已確認
- **來源**：`docs/brainstorm/2026-07-30-workflow-brainstorm.md` §6（Bug 1.6）
- **類型**：**開發工具流程缺陷修復（bug fix）**，非新功能
- **Issue**：#108

---

## 1. 問題陳述（What & Why）

### 一句話本質

`gen-dev-workflow` 的 sequence 模式在 STAGE 1 建好 worktree 後，照 SKILL.md 指示依序執行 `promote` → `stage-done 1`，後者必被腳本拒絕（`0a ≠ 1`），導致 STAGE 1 收尾流程在 happy path 上斷裂。

### 現況行為 vs 期望行為

| | 現況（bug） | 期望 |
|---|---|---|
| `promote` 後的 `stage` 欄位 | 維持 `0a`（promote 不碰 stage） | 維持 `0a`（promote 是共用工具，不應改） |
| SKILL.md 指示的收尾動作 | 直接 `stage-done 1` → 被 guard 擋 ❌ | 先 `advance 0b` → `advance 1` → 再 `stage-done 1` ✅ |
| 整體 STAGE 1 happy path | 斷裂，需 fallback 到 jump 模式繞過 | 順暢完成，不觸發 jump fallback |

### 根因鏈

1. **`promote` 設計為共用的純搬移工具**：同時服務 sequence-from-0a 與 quick→sequence 升級路徑，刻意不碰 `stage` 欄位。
2. **SKILL.md 的指示遺漏中間步驟**：原版 SKILL.md 要求 promote 後直接 `stage-done 1`，但 stage 仍是 `0a`。
3. **`stage-done` 的 sequence guard**：`stage-done <N>` 要求 `N == 目前 stage`，`0a ≠ 1` → 拒絕。

### 為何不修改腳本

- `promote` 若無條件寫死 `stage=1`，會破壞 quick→sequence 升級路徑（upgrade 後 stage 為 `2`，promote 會打回 `1`）。
- `wf-state.sh` 是流程心臟，動核心邏輯需對全部四種啟動模式做回歸測試，風險/收益比不划算。
- **Never break userspace** 原則：底層轉移表邏輯正確，只是上層手冊的操作順序有誤。

### 為何值得修

此缺陷讓**每一個** sequence 流程到 STAGE 1 都必須 fallback 到 jump 模式，喪失 sequence 模式的轉移表保護。jump 模式雖然能繼續，但繞過了 sequence 的合法性檢查——這是「繞過」不是「修好」。

---

## 2. 使用者故事

### US-1：AI agent 按手冊操作 sequence 流程不中斷

> 身為 gen-dev-workflow 的 AI 操作者，我在 STAGE 1 建好 worktree 執行 promote 後，按照 SKILL.md 的指示完成收尾，流程不應斷裂也不需降級到 jump 模式。

### US-2：Workflow 開發者能信任 SKILL.md 的操作序列

> 身為維護 gen-dev-workflow 的開發者，我希望 SKILL.md 文件中記載的狀態機操作序列在所有模式下都能正確執行，不存在「照做會失敗」的死路。

---

## 3. 驗收條件

### AC-1：sequence 模式 STAGE 1 promote 後能正確收尾

- [ ] 執行 `wf-state.sh init` → `promote` → `advance 0b --confirmed` → `advance 1 --confirmed` → `stage-done 1` 全程無報錯。
- [ ] 最終 state JSON 的 `stage` 值為 `1`，`awaiting_confirmation` 為 `true`。

### AC-2：其他模式不受影響

- [ ] quick 模式：`init --mode quick` 流程不受本次修改影響。
- [ ] jump 模式：`init --mode jump --stage 2` 流程不受影響。
- [ ] upgrade 路徑：`upgrade` 後 `promote` 仍維持原 stage，不被覆蓋。

### AC-3：SKILL.md 的 Bug 1.6 Workaround 清楚可執行

- [ ] SKILL.md 的狀態機腳本表格（promote 行）有醒目的 Bug 1.6 Workaround 註記。
- [ ] State 檔生命週期表（STAGE 1 建好 worktree 後）有完整三步操作指引。

### AC-4：Brainstorm 文件如實記錄分析過程

- [ ] brainstorm 文件標記 Bug 1.6 為已修。
- [ ] 記錄「放棄修改腳本」的 Linus 哲學評估（向後相容 > 便利性）。
- [ ] 記錄曾經被否決的錯誤修復方向（promote 寫死 stage=1）。

---

## 4. 範圍邊界（Scope）

### In-Scope

- 修改 SKILL.md 新增 Bug 1.6 Workaround 註記（兩處：狀態機腳本表格 + State 檔生命週期表）。
- 更新 brainstorm 文件標記已修 + 記錄決策 rationale。
- 同步 architecture analysis 文件（重命名對齊日期）。

### Out-of-Scope

- **不修改 `wf-state.sh` 腳本**：底層轉移表正確，不為省兩行操作指令破壞核心。
- **不新增自動化測試**：文件修改無對應的可自動化測試目標。
- **不修改任何 Dart/Flutter 程式碼**：本次為純工具鏈文件修復。

---

## 5. 破壞性分析

| 風險項 | 評估 | 緩解 |
|---|---|---|
| `wf-state.sh` 行為變化 | 🟢 無（不動腳本） | — |
| 既有 workflow session 中斷 | 🟢 無（文件修改不影響執行中的 state 檔） | — |
| SKILL.md 操作指引變更 | 🟡 低（新增操作步驟，不刪除既有內容） | Workaround 區塊清楚標記 `🔴` 醒目前綴 |

---

## 6. 規格出口條件

- [x] 問題陳述與根因鏈已確認（promote 不碰 stage 是設計正確，SKILL.md 操作序列有誤）。
- [x] AC-1～AC-4 已確認為可驗收。
- [x] 範圍邊界已確認：不改腳本、不改 Dart 程式碼、不新增自動化測試。
- [x] 破壞性分析已確認：零破壞風險。
