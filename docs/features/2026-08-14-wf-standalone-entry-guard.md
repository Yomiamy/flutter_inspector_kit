# 獨立入口狀態機防護與 PreToolUse Hook 守衛 (Gap 2.6)

## 1. 背景與問題 (Background & Problem)

在 `gen-dev-workflow` 的狀態機設計中，所有安全檢查（轉移表 `legal_transition`、暫停棘輪、任務完成度校驗）均位於 `wf-state.sh` 腳本內部。

在主鏈流程（`0a → 0b → 1 → 2 → 3 → 4`）中，因為有連續推進的慣性，狀態機能如實記錄進度。然而在獨立入口（**STAGE 5：回覆 PR Review** 與 **STAGE 6：清理 Worktree**）中，由於是手動跳入，LLM 容易因任務心智直接派發 `responder` 處理 review 意見，**全程未呼叫 `wf-state.sh`**。

這導致了以下嚴重問題：
1. **狀態檔假死（State Blindness）**：遠端已推 commit，但本地狀態檔永久停在 `stage: "4"`，破壞單一真理來源。
2. **步驟遺漏（Step Omission）**：因無狀態機推進引導，LLM 容易在 reviewer 複審通過後漏掉最後更新 PR 描述與留言的 `publisher` 步驟。
3. **跨 Session 續接崩潰**：新對話讀取狀態檔時誤判 STAGE 5 未執行，引發重複派發或流程衝突。

---

## 2. 使用者故事 (User Stories)

### US-1：獨立入口首步硬性化指引
身為開發者／編排器，當進入 STAGE 5（回覆 PR）或 STAGE 6（清理 Worktree）時，流程規範應明確要求第一步必須先推進狀態機至對應階段，避免流程違規。

### US-2：Hook 底層實體阻擋違規派發
身為系統管理員，當 LLM 忘記執行狀態推進而直接試圖派發 `responder` 時，系統底層的 `PreToolUse` Hook 必須主動阻擋該次調用，並輸出可直接複製執行的修復指令。

### US-3：防誤殺保護（嚴格分支綁定）
身為開發者，當在主倉庫（`main`）或其他非 workflow 分支上進行日常開發或單點調用 `responder`/`reviewer` 時，Hook 必須自動判定當前分支未綁定 workflow 狀態，直接放行，絕不造成誤殺（Never break userspace）。

### US-4：狀態機轉移表支援
身為狀態機使用者，當從 STAGE 4（已建 PR）推進至 STAGE 5 或 STAGE 6 時，`wf-state.sh advance` 應能依轉移表順暢通過，不拋出非法轉移錯誤。

---

## 3. 驗收條件 (Acceptance Criteria)

- [x] **AC-1**：`SKILL.md` 的 STAGE 5 與 STAGE 6 區塊明訂「🔴 第一步（不可跳過）：推進狀態至 STAGE 5/6」。
- [x] **AC-2**：建立 `.claude/hooks/wf-guard-stage-check.sh`，在 `PreToolUse` 攔截 `Agent` / `invoke_subagent`。
- [x] **AC-3**：當目錄存在 active workflow 且當前分支狀態非 STAGE 5 時，派發 `responder` 必被 Hook 阻擋（Exit code 1），並於 stderr 輸出修復命令。
- [x] **AC-4**：當目錄無 active workflow 或當前分支無對應狀態檔時，派發 `responder` 必被 Hook 放行（Exit code 0）。
- [x] **AC-5**：任何時候派發非 `responder` 之 Agent（如 `reviewer`, `verifier`），Hook 必直接放行（Exit code 0）。
- [x] **AC-6**：`wf-state.sh` 的 `legal_transition()` 補齊 `4->5`、`5->4`、`5->5`、`4->6`、`5->6`、`6->done` 之轉移規則。

---

## 4. 邊界與排除 (Out of Scope)

- 不針對 STAGE 6 設置專用 Agent Hook（STAGE 6 為 skill / bash 操作，由文件規範 A 與狀態機覆蓋）。
- 不破壞或修改既有主鏈 `0a` 至 `4` 的狀態轉移規則與校驗。
