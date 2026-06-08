---
name: gen-pr-reply
description: 讀取 GitHub PR 的 review inline comments，核對每項意見是否已在程式碼或 git history 中修正，並以中文在對應 comment thread 回覆修正 commit SHA。觸發時機：使用者說「回覆 PR comment」、「針對 review 回覆修正」、「gen-pr-reply PR {number}」，或要針對 code review 的每個 inline comment 回覆修正 commit。
---

# gen-pr-reply

讀取 PR inline comments → 驗證修正狀態 → 以中文在 GitHub thread 回覆對應 commit SHA。

## 流程

### 1. 取得必要資訊

同時執行：

```bash
# repo 名稱（不可假設）
gh repo view --json nameWithOwner

# PR inline comments（含 comment id、diff_hunk、body）
gh api repos/{owner}/{repo}/pulls/{pr}/comments

# 近期 commits
git log --oneline -20
```

### 2. 對每則 comment 驗證修正狀態

- **讀取被評論的檔案目前狀態**（`Read` 工具）
- 比對 git log，找出對應修正的 commit

| 狀況 | 行動 |
|------|------|
| 已修正（code 或 commit 可驗證） | 回覆修正 commit SHA |
| 設計已改變（建議本身已過時） | 說明實際採用的設計與原因 |
| 尚未修正 | 告知使用者，不發回覆 |

### 3. 以中文回覆每則 comment（inline thread）

**必須 reply 到 comment thread**，不可發頂層 PR comment：

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies \
  -X POST \
  -f body="{中文內容}"
```

回覆格式：

- **已修正**：`已修正，對應 commit \`{sha7}\`。{一句話說明修正內容}`
- **設計改變**：`已於 commit \`{sha7}\` 重構處理。{說明實際設計決策與原因}`

## 規則

- 逐一回覆，每則 comment 對應一個 reply，不合併
- SHA 用 7 位短碼（`git log --oneline` 格式）
- 找不到明確 commit 時，告知使用者，不亂填
- 回覆聚焦技術事實，不寫感謝語
