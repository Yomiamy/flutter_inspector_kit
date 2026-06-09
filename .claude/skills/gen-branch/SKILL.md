---
name: gen-branch
description: |
  依據 GitHub Issue 編號建立以 main 為 base 的「純本地分支」（不追蹤任何 remote），
  命名格式對齊 <category>/YYYYMM/<ISSUE-NUMBER>-<kebab-case-summary>。
  觸發條件：gen branch <ISSUE-NUMBER>
allow-tools:
  - Bash
---

# Generate Branch From GitHub Issue

## 解析輸入

從觸發指令解析 GitHub Issue 編號。
- 輸入格式：`gen branch <ISSUE-NUMBER>`
- 編號為純數字，可接受 `#` 前綴（會自動去除）
- 範例：`gen branch 1702`、`gen branch #1718`、`gen branch 42`
- 若未提供，詢問使用者。

將編號記為 `$ISSUE`（純數字，無 `#` 前綴）。

若需指定 repo（不在 git 工作目錄、或要查跨 repo 的 issue），可帶 `--repo <owner>/<name>`。

---

## 執行步驟

### 1. 取得 Issue 資訊

使用 GitHub CLI 取得 issue 詳情：

```bash
gh issue view "$ISSUE" --json number,title,body,labels,state,url
```

關注：
- `title`：作為 slug 來源
- `body`：協助判斷本質是修正/優化/重構/新增
- `labels`：輔助判斷（例如 `bug`、`enhancement`、`refactor`、`chore`、`documentation` 等）
- `state`：若為 `CLOSED`，提示使用者再確認是否仍要建立分支

若找不到 issue（gh 回 404 或非 0 退出碼），報錯並停止。

> 若環境未安裝 `gh` 或未登入，提示使用者先執行 `gh auth login`。

---

### 2. 決定 category（分支前綴）

**不要只看 labels**。labels 只是輔助；最終依 **issue 內容本質**決定：

| category | 判準：issue 本質是要… |
|:---------|:-----------------------|
| `fix` | **修正** 既有功能的 bug / 行為錯誤 / 顯示錯誤 |
| `feature` | **新增** 功能、頁面、API 串接、流程 |
| `refactor` | **重構** 既有程式碼結構（行為不變，架構/可讀性改善） |
| `chore` | **優化** 雜項（建置/設定/文件/依賴升版/CI 等不影響產品功能） |

判斷線索（由強到弱）：
1. issue title/body 動詞——「修正」「錯誤」「顯示不正確」「無法」→ `fix`；「新增」「建立」「增加」「支援」→ `feature`；「重構」「整理」「抽出」→ `refactor`；「調整設定」「升級套件」「文件」→ `chore`。
2. labels（`bug` 幾乎必為 `fix`；`enhancement`/`feature` 多為 `feature`；`documentation`/`dependencies`/`ci` 多為 `chore`，但仍要看 title）。
3. 其他 labels 或 milestone 線索。

對不確定的 case，列出候選並請使用者確認再繼續。

---

### 3. 組出分支名稱

格式：`<category>/<YYYYMM>/<ISSUE-NUMBER>-<slug>`

- `<category>`：步驟 2 決定
- `<YYYYMM>`：當前年月（`date +%Y%m`）
- `<ISSUE-NUMBER>`：純數字（無 `#` 前綴）
- `<slug>`：title 轉出的英文 kebab-case
  - 去除 `[STG][iOS/Android][APP V3/XXX]` 等方括號前綴
  - 中文語意轉譯成簡短英文（3–7 個單字）
  - 全小寫，`-` 連字，不含中文或特殊字元

**範例**：

| 編號 | 本質 | title 節選 | 結果 |
|:-----|:-----|:-----------|:-----|
| `1700` | 修正 | 我的收藏貨到通知按鈕狀態重置 | `fix/202604/1700-wishlist-arrival-notify-button-state-reset` |
| `1702` | 修正 | 點擊貨到通知按鈕提示訊息顯示不正確 | `fix/202604/1702-wishlist-arrival-notify-toast-message` |
| `1699` | 修正 | 未根據商品銷售狀態顯示相應功能按鈕 | `fix/202604/1699-wishlist-button-state-by-sale-status` |
| `1718` | 新增 | Member card badge 功能 | `feature/202604/1718-member-card-badge` |
| `1751` | 重構 | Refactor app coupon detail page | `refactor/202604/1751-app-coupon-detail-page` |
| `42` | 優化 | 升級 Dart SDK 至 3.4 | `chore/202604/42-bump-dart-sdk-3-4` |

將結果記為 `$BRANCH`，**請使用者確認後**再建立分支。

---

### 4. 處理本地未提交變更

```bash
git status --short
```

- 若工作區乾淨：直接進下一步
- 若只有少量未追蹤或變更檔案擋住 checkout：
  - `git stash push -m "gen-branch switch: $ISSUE" -- <files>` 暫存
  - 切換完成後 `git stash pop`
- 若變更龐雜：提示使用者先自行 commit 或 stash 再重跑，不自動決斷。

---

### 5. 從 main 建立「純本地分支」（不追蹤任何 remote）

```bash
git fetch origin main
git checkout --no-track -b "$BRANCH" origin/main
```

**重點**：必須使用 `--no-track`，確保新分支為**純本地分支**，不自動關聯任何 remote tracking branch。

- 即使 `git config branch.autoSetupMerge` 被設為 `always`，`--no-track` 也會強制覆蓋此行為。
- 建立後執行 `git branch -vv` 驗證：新分支該行**不應**出現 `[origin/...]` 之類的 upstream 標記，只會顯示 commit hash 與 message。

若本地已有同名分支，報錯並中止（不強制覆蓋）。

---

### 6. 還原 stash（如果有）

```bash
git stash pop
```

若 pop 發生衝突：提示使用者，不自動解決。

---

### 7. 輸出結果與停止

輸出摘要：
- Base：`origin/main`
- Branch：`$BRANCH`（**local only, no upstream tracking**）
- Issue URL（步驟 1 取得的 `url`）
- 目前 `git status` 摘要
- `git branch -vv` 結果（用以確認未追蹤 remote）

**執行完畢後立即停止**，等待使用者下達開發指令。**嚴禁主動進入研究（Research）或開發階段**。

---

## 規則

- **永遠從 `origin/main` 起頭**，不是當前 HEAD。
- **新分支必為純本地分支**：建立時必加 `--no-track`，不自動追蹤任何 remote branch。
- **絕不自動 push**：本技能完成後不執行 `git push`，由使用者自行決定 remote 與 upstream。
- **category 依 issue 內容本質決定**，不要只看 labels。
- **絕不 force push、絕不 reset --hard**。
- **stash 還原衝突時停下來**，交給使用者。
- GitHub issue 編號為純數字，分支名中不含 `#`。
- slug 英文化要忠於 issue 本意，能從名字一眼看出修的是哪個功能面向。
- **僅限建立分支**：此技能的職責僅止於建立分支。完成後必須停止，不得自動開始程式碼調查、重構或修復。
