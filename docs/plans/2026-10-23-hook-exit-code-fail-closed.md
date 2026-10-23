# 順位 5 (R3/R4) · 確立 Hook Fail-Closed 防禦與退出碼校驗（否決 SubagentStart 阻斷）— 實作計畫

> **規格**：[`docs/features/2026-10-23-hook-exit-code-fail-closed.md`](../features/2026-10-23-hook-exit-code-fail-closed.md)
> **日期**：2026-10-23 ｜ **優先序**：P1 ｜ **預估 Effort**：低（配置強化、測試斷言補充、決策回寫、零業務邏輯侵入）

---

## 1. 核心判斷與設計原則 (Linus-Style Mindset)

**實證否定偽假設，確定性取代機率放行。**

* **絕不破壞既有防線（Never break userspace）**：
  查證顯示官方 `SubagentStart` 是純觀察型事件，exit 2 或 deny 決策不會阻擋 subagent 啟動。若強行將 `wf-guard-stage-check.sh` 改掛 `SubagentStart`，現有在 STAGE 5 前攔截 `responder` 的防線將直接死滅。因此**正式否決改掛 SubagentStart**，維持 `PreToolUse` 唯一阻斷地位。
* **Fail-Closed 消除非預期放行（Good Taste）**：
  當守衛腳本遭遇直譯器例外、未捕捉語法錯誤或逾時（以 exit 1 退出）時，Claude Code 預設 `"onFailure": "continue"`（fail-open）會導致危險操作被放行。設定 `"onFailure": "block"` 能在作業系統層強制 fail-closed，杜絕任何例外漏網之魚。
* **測試即契約（Test as Contract）**：
  在 `test_project_settings_hooks.sh` 補上對 `"onFailure": "block"` 的硬性斷言，確保未來任何維護或 refactor 都不會誤刪該安全配置。

---

## 2. 檔案異動清單

| # | 檔案 | 動作 | 說明 |
|:-:|:---|:---|:---|
| 1 | `.claude/settings.json` | 修改 | 為 `PreToolUse` 的 `Agent` 與 `mcp__gemini-cli__ask-gemini pre` 守衛配置 `"onFailure": "block"` |
| 2 | `.claude/hooks/tests/test_project_settings_hooks.sh` | 修改 | 強化 `check_guard` 斷言：驗證 `PreToolUse` 守衛明確包含 `"onFailure": "block"` |
| 3 | `.claude/hooks/wf-guard-stage-check.sh` | 檢查/微調 | 確保例外捕捉與退出碼皆為 `exit 2`，排除 fail-open 隱患 |
| 4 | `docs/brainstorm/2026-09-17-workflow-brainstorm.md` | 修改 | 更新 §3.5 順位 5 狀態為已完成；於 §3.5 R3/R4 及 §6 刻意不學表中詳細記錄查證事實與否決原因 |

---

## 3. 任務拆分與執行規劃

### Task 1: 配置 PreToolUse 守衛之 `"onFailure": "block"`（.claude/settings.json）
- **實作內容**：
  1. 在 `PreToolUse` 下的 `Agent` hook 項目加入 `"onFailure": "block"`。
  2. 在 `PreToolUse` 下的 `mcp__gemini-cli__ask-gemini pre` hook 項目加入 `"onFailure": "block"`。
  3. 維持 `PostToolUse` 項目不變（Post 事件屬執行後，非阻斷用途）。

### Task 2: 強化 Hook 設定檔回歸測試（.claude/hooks/tests/test_project_settings_hooks.sh）
- **實作內容**：
  1. 更新 `check_guard` 函式：支援接收預期物件（或依事件自動校驗 `PreToolUse` 必須包含 `"onFailure": "block"`）。
  2. 執行 `./.claude/hooks/tests/test_project_settings_hooks.sh`，確保 3 個 AC 測試全數 PASS。

### Task 3: 守衛腳本退出碼與例外安全審查（wf-guard-stage-check.sh）
- **實作內容**：
  1. 審查 `wf-guard-stage-check.sh` 與 `wf-guard-delegate-cwd.sh`，確認頂層 exception 處理皆正確回傳 `exit 2`。
  2. 執行 `./.claude/hooks/tests/test_delegate_cwd_logic.py` 與 `./.claude/hooks/tests/test_wf_state_total_tasks.sh` 確保既有測試全數 PASS。

### Task 4: 更新頭腦風暴文件與刻意不學記錄（docs/brainstorm/2026-09-17-workflow-brainstorm.md）
- **實作內容**：
  1. 於第 1547 行順位 5 表格將狀態更新為 `✅ 已完成（2026-10-23 · Issue #<id>）`，並更新說明。
  2. 於 §3.5 R3/R4 段落補充說明：經 2026-10-23 官方規範查證，`SubagentStart` 是純觀察型事件，exit 2 不具阻擋力，因此否決改掛 SubagentStart，堅守 `PreToolUse`。
  3. 於 §6 刻意不學表格增列：「將阻斷守衛改掛 SubagentStart」之否決記錄與技術理由。

### Task 5: 完整回歸驗證
- **實作內容**：
  1. 執行 `./.claude/hooks/tests/test_project_settings_hooks.sh`。
  2. 執行 `./.claude/hooks/tests/test_delegate_cwd_logic.py`。
  3. 執行 `./.claude/hooks/tests/test_wf_state_total_tasks.sh`。
  4. 執行 `flutter test`，確認 750 tests 全數通過（基準 ≥606 tests）。
  5. 執行 `flutter analyze lib/ test/`，確認嚴格符合 7-info 基線。
