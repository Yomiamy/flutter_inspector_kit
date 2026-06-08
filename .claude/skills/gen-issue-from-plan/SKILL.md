---
name: gen-issue-from-plan
description: |
  讀取一份 execute plan 文件，理解內容後在 GitHub 建立一個英文標題的 issue，
  接著呼叫 gen-branch 以該 issue 編號建立分支並 checkout。
  觸發條件：gen issue-from-plan <plan-file-path>
allow-tools:
  - Bash
  - Read
---

# Generate GitHub Issue From Execute Plan & Branch

此技能將「執行計畫文件」轉換為一個可追蹤的 GitHub issue，並立即依該 issue 建立工作分支。
分為三個階段：**理解計畫 → 建立 issue → 建立分支**。

---

## 解析輸入

從觸發指令解析 plan 文件路徑。

- 輸入格式：`gen issue-from-plan <plan-file-path>`
- 範例：
  - `gen issue-from-plan docs/plans/2026-04-27-member-card-badge.md`
  - `gen issue-from-plan /abs/path/to/plan.md`
- 若未提供路徑，詢問使用者。
- 路徑為相對路徑時，以當前工作目錄為基準解析。

將路徑記為 `$PLAN_FILE`。

確認檔案存在且可讀取：

```bash
test -f "$PLAN_FILE" && test -r "$PLAN_FILE"
```

若檔案不存在或無法讀取，報錯並停止。

若需指定 repo（不在 git 工作目錄、或要在跨 repo 建立 issue），可帶 `--repo <owner>/<name>`，後續所有 `gh` 指令一併套用。

---

## 執行步驟

### 1. 讀取並理解 plan 文件

使用 `Read` 工具讀取 `$PLAN_FILE` 完整內容。

從中萃取以下要點（用以撰寫 issue）：

- **Goal / 目標**：plan 開頭的一句話目標（常見於 `**Goal:**` 區塊）。
- **Architecture / 設計概念**：實作方式、架構選擇（常見於 `**Architecture:**` 區塊）。
- **Tech Stack**：關鍵技術、套件（常見於 `**Tech Stack:**` 區塊）。
- **Tasks / 步驟概觀**：列出 plan 中的主要任務標題（不需細節步驟），讓 issue reader 能掌握範圍。
- **本質判斷**：這份 plan 是要修 bug、加 feature、重構、還是雜項優化？（用於 labels 與後續分支 category）

若 plan 文件結構不符預期（例如沒有明顯目標段落），仍盡力從整體內容歸納；不要捏造原文沒有的資訊。

---

### 2. 草擬 GitHub issue 內容

#### Title（**必須英文**）

- 短句、祈使句或名詞片語，能一眼看出這份 plan 要做什麼。
- 不超過 ~70 字元。
- 不含中文、不含 ticket 前綴（例如不要 `[BUG-1234]`）。
- 範例：
  - `Add member card badge to profile page`
  - `Refactor app coupon detail page`
  - `Fix wishlist arrival notify button state reset`
  - `Bump Dart SDK to 3.4`

#### Body（Markdown）

固定使用以下骨架，內容用 `zh-tw` 撰寫，技術名詞保留 `en-us`：

```md
## Goal

<一句話總結要達成什麼>

## Background / Why

<為什麼要做這件事，從 plan 推導出的動機或現況問題>

## Scope

<這份 plan 涵蓋的範圍；條列主要任務標題，3–7 點為宜>

- ...
- ...

## Out of Scope

<明確不會在這次處理的事項；若 plan 沒提及則寫「N/A」>

## References

- Plan: `<$PLAN_FILE 的相對或絕對路徑>`
```

規則：

- 不要把 plan 的逐步指令（step 1 / step 2 / 測試指令）整段搬進 issue body；issue 是高層摘要，plan 才是執行細節。
- 若 plan 內含 ticket 連結（YouTrack / Jira），在 References 下加一行 `- Ticket: <link>`。
- 若 plan 提到驗收標準或測試重點，可額外補一個 `## Acceptance Criteria` 段落（條列）；無則略過。

#### Labels（可選）

依 plan 本質建議 label，使用前先確認 repo 已有該 label：

```bash
gh label list --json name --jq '.[].name'
```

對照建議：

| 本質 | 建議 label |
|:-----|:-----------|
| 修 bug | `bug` |
| 新增功能 | `enhancement` 或 `feature` |
| 重構 | `refactor`（若 repo 有此 label）|
| 雜項 | `chore`（若 repo 有此 label）|

只套用 repo 確實存在的 label；缺漏的就略過，不要新建 label。

---

### 3. 與使用者確認後再建立 issue

在呼叫 `gh issue create` 之前，先把擬好的 **title + body + labels** 印給使用者，並詢問：

> **「以上 issue 草稿可以嗎？確認後將建立 GitHub issue。」**

待使用者明確回覆同意（如「yes」「對」「建立」「ok」）後，才執行下一步。
若使用者要求修改，重擬後再次確認。

---

### 4. 建立 GitHub issue

使用 `gh issue create`，body 透過 HEREDOC 傳遞以保留格式：

```bash
gh issue create \
  --title "<English title>" \
  --body "$(cat <<'EOF'
## Goal
...

## Background / Why
...

## Scope
- ...

## Out of Scope
...

## References
- Plan: <$PLAN_FILE>
EOF
)" \
  $(printf -- '--label %s ' "${LABELS[@]}")
```

若使用了 `--repo <owner>/<name>` 參數，一併加入。

從輸出中擷取新建 issue 的 URL 與編號（`gh issue create` 預設會印出 issue URL）。將編號記為 `$ISSUE`（純數字，無 `#` 前綴）。

若 `gh` 未安裝或未登入：提示使用者先 `gh auth login`，並停止。
若建立失敗（網路、權限、label 不存在等）：報錯並停止，不繼續建立分支。

---

### 5. 呼叫 gen-branch 建立並 checkout 分支

成功取得 `$ISSUE` 後，**轉交 gen-branch 技能** 完成分支建立。

具體做法：呼叫 `gen-branch` 的流程，等同於使用者輸入 `gen branch $ISSUE`。
gen-branch 會：

1. 透過 `gh issue view "$ISSUE"` 取得剛建立的 issue 詳情。
2. 依 issue 本質決定 category（`fix` / `feature` / `refactor` / `chore`）。
3. 組出 `<category>/<YYYYMM>/<ISSUE>-<slug>` 分支名。
4. **與使用者確認分支名**。
5. 從 `origin/main` 以 `--no-track` 建立純本地分支並 checkout。

**重要**：本技能不要自行 reimplement 分支建立邏輯，務必委派給 `gen-branch` 以保持一致性（命名規則、`--no-track`、不自動 push 等都由 gen-branch 統一保證）。

若使用者帶了 `--repo` 旗標（亦即 issue 不在當前 git 工作目錄的 repo），則**不執行步驟 5**，僅輸出 issue URL 並提醒使用者 gen-branch 必須在對應 repo 的本地 worktree 內手動執行。

---

### 6. 輸出結果與停止

完成後輸出摘要：

- **Plan file**：`$PLAN_FILE`
- **Issue**：`#$ISSUE` — `<English title>` — `<issue URL>`
- **Branch**：`$BRANCH`（由 gen-branch 建立，pure local，no upstream）
- **目前 HEAD**：`git status` 摘要

**執行完畢後立即停止**，等待使用者下達後續開發指令。
**嚴禁在本技能內自動進入研究、設計、或實作階段**——這是後續流程，不屬於本技能職責。

---

## 規則

- **plan 文件是唯一輸入來源**：issue 內容必須能從 plan 推導，不憑空捏造功能、檔案、測試。
- **issue title 必為英文**；body 用 zh-tw + 必要英文技術名詞。
- **建立 issue 前必先讓使用者確認**草稿，不主動先 create。
- **建立 issue 後必呼叫 gen-branch**，不自行實作分支邏輯，避免雙份維護。
- **絕不自動 push 分支、絕不自動實作程式碼**：本技能止於「建立 issue + 切到新分支」。
- **gh 失敗時停下來**，不嘗試 fallback 用 web UI 等替代手段。
- **跨 repo 模式**（帶 `--repo`）只建立 issue，不建立分支；分支由使用者在對應 worktree 內自行 `gen branch`。
- **不修改 plan 文件本身**：plan 是輸入，不應因建立 issue 而被改動。
