# 順位 5 (R3/R4) · 確立 Hook Fail-Closed 防禦與退出碼校驗（否決 SubagentStart 阻斷）

> **規格狀態**：Draft ｜ **優先序**：P1 ｜ **關聯**：R3、R4、BUG-1、Issue #202

---

## 1. 背景與核心判斷 (Context & Problem Statement)

### 1.1 歷史背景與原提案假設
在 2026-08-16 的工作流頭腦風暴（`docs/brainstorm/2026-09-17-workflow-brainstorm.md` §3.5）中，記錄了兩項關於 Hook 行為的查證結論：
- **R3**：發現 Claude Code hooks 只有 `exit 2` 是 blocking；`exit 1` 被視為非阻斷錯誤（non-blocking error，動作照跑）。該問題已於 BUG-1 修復 `wf-guard-stage-check.sh` 兩處退出碼。
- **R4**：提出了「改用 `SubagentStart` 依 agent type 過濾攔截，比在 `PreToolUse` 手刻 Task payload 解析更短、更不易失效」的待落地提案（即修訂動工順序中的「順位 5」）。

### 1.2 實證查證與否決分析 (Empirical Verification & Invalidation)
在準備落地順位 5 時，經查證官方 Claude Code Hooks 生命週期規範與實作行為，發現一項致命事實：
1. **`SubagentStart` 是純觀察型（Informational）事件**：
   - 其觸發時機在 subagent 已經被建立並啟動的當下。
   - 官方 runtime 在 `SubagentStart` 事件中**不支援 blocking**——即使 hook 腳本返回 `exit 2` 或 JSON deny 決策，該退出碼與決策亦會被忽略，subagent 依然會繼續生成並執行！
   - **破壞性推論**：若將現有守衛 `wf-guard-stage-check.sh` 改掛為 `SubagentStart`，現行在未推進狀態機時阻止 `responder` 啟動的防線將**全面崩潰，完全失去阻擋力**。
2. **`PreToolUse` 是唯一的確定性阻斷點**：
   - 只有 `PreToolUse` 能夠在工具（`Agent` / `invoke_subagent` / `Task`）實際呼叫前進行確定性攔截與 `exit 2` 阻斷。
   - **核心決策**：**正式否決「將阻斷守衛改掛 SubagentStart」的提案**，堅守 `PreToolUse`；並將此查證事實登錄於 brainstorm 文件之「刻意不學與否決提案」。

### 1.3 真實痛點：預設 Fail-Open 的安全漏洞
雖然 `wf-guard-stage-check.sh` 內部已使用 `exit 2`，但存在嚴重的防禦缺口：
- **Hook 腳本異常 crash 會 fail-open**：若 hook 腳本因直譯器缺少套件、語法例外、或 Bash 腳本未預期錯誤而以 `exit 1` 退出，Claude Code 的預設策略是 `"onFailure": "continue"`（fail-open）。結果是**守衛崩潰了，危險操作卻依然被放行**。
- **缺少 fail-closed 宣告**：`.claude/settings.json` 未替 `PreToolUse` 守衛配置 `"onFailure": "block"`。

---

## 2. 規格要求 (Requirements)

### 2.1 規格一：設定檔導入 `"onFailure": "block"` (Fail-Closed)
- 於 `.claude/settings.json` 的所有 `PreToolUse` 阻擋型守衛中，明確設定 `"onFailure": "block"`：
  1. `matcher: "Agent"` 的 `wf-guard-stage-check.sh`。
  2. `matcher: "mcp__gemini-cli__ask-gemini"` 的 `wf-guard-delegate-cwd.sh pre`。
- 一旦 hook 腳本發生未預期 crash、逾時或非 0/2 異常退出碼時，runtime 必須強制視為阻斷（fail-closed），杜絕穿透風險。

### 2.2 規格二：守衛腳本退出碼與例外安全加固
- 全面盤點 `.claude/hooks/wf-guard-stage-check.sh` 與 `.claude/hooks/wf-guard-delegate-cwd.sh`：
  - 確保所有阻斷情境均使用 `sys.exit(2)` / `exit 2`。
  - 在 Python 腳本的最外層增加結構化例外捕捉，當遭遇解析失敗或未知例外時，若屬需要防護的上下文，輸出清晰的 `[WF-GUARD ERROR]` 至 stderr 並回傳 `exit 2`。

### 2.3 規格三：自動化測試鎖定契約
- 更新 `.claude/hooks/tests/test_project_settings_hooks.sh`：
  - 強化 `check_guard` 斷言：驗證 `PreToolUse` 守衛配置均明確包含 `"onFailure": "block"`。
  - 確保新進工程師或自動化工具修改 settings.json 時，若誤刪 `"onFailure": "block"` 會立即被測試阻擋。

### 2.4 規格四：回寫頭腦風暴與決策紀錄
- 於 `docs/brainstorm/2026-09-17-workflow-brainstorm.md`：
  - 更新 §3.5 順位 5 表格狀態為 `✅ 已完成`。
  - 在 §3.5 R3/R4 節點與 §6 刻意不學表中詳細記錄：
    - 查證證實 `SubagentStart` exit 2 無法 blocking，正式否決改掛 SubagentStart。
    - 堅守 `PreToolUse`，並透過 `"onFailure": "block"` 與 `exit 2` 建立真正的 fail-closed 確定性防禦。

---

## 3. 驗收條件 (Acceptance Criteria)

1. [ ] `.claude/settings.json` 中 `PreToolUse` 的 `Agent` 與 `mcp__gemini-cli__ask-gemini` 守衛均帶有 `"onFailure": "block"`。
2. [ ] `.claude/hooks/tests/test_project_settings_hooks.sh` 執行全綠，且能正確校驗 `"onFailure": "block"`。
3. [ ] `.claude/hooks/tests/test_delegate_cwd_logic.py` 與 `test_wf_state_total_tasks.sh` 測試全綠。
4. [ ] `docs/brainstorm/2026-09-17-workflow-brainstorm.md` 完成相關記錄與決策回寫。
5. [ ] `flutter test` 維持 ≥606 tests 全數通過；`flutter analyze lib/ test/` 維持 7-info 基線。
